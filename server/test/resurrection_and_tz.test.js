// Test Suite: Timezone Wall-Clock & Anti-Resurrection Invariants
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { parseClientTimestamp } = require('../cairoTime');

const PORT = 5500 + Math.floor(Math.random() * 500);
const BASE = `http://localhost:${PORT}`;
let proc, dataDir, adminToken, custToken, testVenueId;

const call = (method, url, { token, body, headers } = {}) =>
  fetch(BASE + url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  }).then(async r => ({ status: r.status, json: await r.json().catch(() => ({})) }));

test('UNIT: parseClientTimestamp handles explicit UTC, explicit offsets, and naive Cairo wall-clock', () => {
  // Explicit UTC
  const utc = parseClientTimestamp('2027-01-15T16:30:00.000Z');
  assert.equal(utc.toISOString(), '2027-01-15T16:30:00.000Z');

  // Explicit Offset (+02:00)
  const withOffset = parseClientTimestamp('2027-01-15T18:30:00.000+02:00');
  assert.equal(withOffset.toISOString(), '2027-01-15T16:30:00.000Z');

  // Naive winter timestamp (Cairo is UTC+2 in January)
  // 18:30 Cairo wall time must translate to 16:30 UTC
  const naiveWinter = parseClientTimestamp('2027-01-15T18:30:00.000');
  assert.equal(naiveWinter.toISOString(), '2027-01-15T16:30:00.000Z');

  // Naive space-separated timestamp
  const naiveSpace = parseClientTimestamp('2027-01-15 18:30:00');
  assert.equal(naiveSpace.toISOString(), '2027-01-15T16:30:00.000Z');

  // Naive summer timestamp (Egypt DST UTC+3 in July)
  // 18:30 Cairo wall time must translate to 15:30 UTC
  const naiveSummer = parseClientTimestamp('2027-07-15T18:30:00.000');
  assert.equal(naiveSummer.toISOString(), '2027-07-15T15:30:00.000Z');

  // Edge cases
  assert.ok(isNaN(parseClientTimestamp('').getTime()));
  assert.ok(isNaN(parseClientTimestamp('invalid-date').getTime()));
});

test('INTEGRATION SUITE: Server timezone parsing and booking anti-resurrection', async (t) => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hagzy-resurrect-'));
  proc = spawn('node', ['index.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      PORT,
      JWT_SECRET: 'test-resurrection-secret-32-chars!',
      ADMIN_EMAIL: 'admin@test.dev',
      ADMIN_PHONE: '01000000001',
      ADMIN_PASSWORD: 'correct-horse-password',
      PAYMENT_LISTENER_KEY: 'test-listener-secret-res',
      PAYMENT_WEBHOOK_SECRET: 'test-webhook-secret-res',
      HAGZY_DATA_DIR: dataDir,
    },
    stdio: 'ignore',
  });

  for (let i = 0; i < 50; i++) {
    try {
      if ((await fetch(BASE + '/api/health')).ok) break;
    } catch (_) {}
    await new Promise(r => setTimeout(r, 100));
  }

  // Obtain admin token
  const adminRes = await call('POST', '/api/auth/login', {
    body: { email: 'admin@test.dev', password: 'correct-horse-password' },
  });
  adminToken = adminRes.json.token;

  // Obtain customer token
  const otpRes = await call('POST', '/api/auth/customer-otp/request', { body: { phone: '01011223344' } });
  const custRes = await call('POST', '/api/auth/customer-otp/verify', {
    body: { phone: '01011223344', code: otpRes.json.testOtp, name: 'TZ Tester' },
  });
  custToken = custRes.json.token;

  // Create test venue
  testVenueId = 'tz-venue-1';
  await call('PUT', `/api/admin/venues/${testVenueId}`, {
    token: adminToken,
    body: {
      id: testVenueId,
      name: 'Cairo Padel Center',
      type: 'sports',
      depositPercent: 25,
      spaces: [{ id: 'court-1', name: 'Center Court', price: 200, hourlyRate: 200 }],
    },
  });

  await t.test('TIMEZONE: naive startsAt is parsed as Africa/Cairo wall time', async () => {
    // Naive winter timestamp for Cairo 18:30 (UTC+2) -> server must store 16:30Z
    const naiveDate = '2027-01-20T18:30:00.000';
    const bRes = await call('POST', '/api/bookings', {
      token: custToken,
      body: {
        venueId: testVenueId,
        itemId: 'court-1',
        startsAt: naiveDate,
        durationMinutes: 60,
        customer: 'Timezone User',
      },
    });
    assert.equal(bRes.status, 200);
    assert.equal(bRes.json.booking.startsAt, '2027-01-20T16:30:00.000Z');

    // With explicit offset (+02:00) -> exact same instant
    const offsetDate = '2027-01-20T18:30:00.000+02:00';
    // Clean up first booking to avoid slot collision
    await call('POST', `/api/bookings/${bRes.json.booking.id}/cancel`, { token: custToken });

    const bRes2 = await call('POST', '/api/bookings', {
      token: custToken,
      body: {
        venueId: testVenueId,
        itemId: 'court-1',
        startsAt: offsetDate,
        durationMinutes: 60,
        customer: 'Timezone User 2',
      },
    });
    assert.equal(bRes2.status, 200);
    assert.equal(bRes2.json.booking.startsAt, '2027-01-20T16:30:00.000Z');
  });

  await t.test('RESURRECTION: late payment cannot resurrect cancelled booking & queues to reviewQueue', async () => {
    // 1. Create a fresh booking
    const slotTime = '2027-02-10T14:00:00.000+02:00';
    const bRes = await call('POST', '/api/bookings', {
      token: custToken,
      body: {
        venueId: testVenueId,
        itemId: 'court-1',
        startsAt: slotTime,
        durationMinutes: 60,
        customer: 'Resurrection Target',
      },
    });
    assert.equal(bRes.status, 200);
    const bookingId = bRes.json.booking.id;
    const dueAmount = bRes.json.booking.dueNow || 50;

    // 2. Customer initiates payment intent
    const intentRes = await call('POST', '/api/payments/intent', {
      token: custToken,
      body: {
        bookingId,
        paymentMethod: 'MOBILE_WALLET',
        senderIdentifier: '01011223344',
      },
    });
    assert.equal(intentRes.status, 200);
    const payableAmount = intentRes.json.payableAmount || dueAmount;

    // 3. Customer cancels the booking BEFORE payment arrives
    const cancelRes = await call('POST', `/api/bookings/${bookingId}/cancel`, { token: custToken });
    assert.equal(cancelRes.status, 200);
    assert.equal(cancelRes.json.booking.status, 'cancelled');

    // 4. Late payment arrives via Android listener webhook
    const rawText = `تم استلام مبلغ ${payableAmount} جنيه من رقم 01011223344`;
    const listenerRes = await call('POST', '/api/payments/listener', {
      headers: { 'x-listener-key': 'test-listener-secret-res' },
      body: { text: rawText, sender: '01011223344' },
    });
    assert.equal(listenerRes.status, 200);

    // The payment matcher must NOT confirm the dead booking
    assert.equal(listenerRes.json.matched, false);
    assert.equal(listenerRes.json.status, 'BOOKING_INACTIVE');

    // 5. Verify the booking remains strictly CANCELLED in DB
    const bCheck = await call('GET', `/api/bookings/${bookingId}`, { token: custToken });
    assert.equal(bCheck.status, 200);
    assert.equal(bCheck.json.booking.status, 'cancelled', 'Booking must NOT be resurrected to confirmed');

    // 6. Verify an inactive review queue item was recorded
    const queueRes = await call('GET', '/api/admin/payments/review-queue', { token: adminToken });
    assert.equal(queueRes.status, 200);
    const queueItem = queueRes.json.items.find(i => i.bookingId === bookingId && i.status === 'BOOKING_INACTIVE');
    assert.ok(queueItem, 'Review queue must contain BOOKING_INACTIVE item');

    // 7. Verify admin cannot force-attach the payment to the dead booking
    const attachRes = await call('POST', `/api/admin/payments/review-queue/${queueItem.id}/attach`, {
      token: adminToken,
      body: { bookingId },
    });
    assert.equal(attachRes.status, 409, 'Attaching to cancelled booking must return 409 Conflict');
    assert.match(attachRes.json.error, /cancelled/i);
  });

  if (proc) proc.kill();
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true });
});

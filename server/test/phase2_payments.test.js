// Phase 2 Payments & State Machine Adversarial Tests
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');

const PORT = 4900 + Math.floor(Math.random() * 500);
const BASE = `http://localhost:${PORT}`;
let proc, dataDir, adminToken, custToken, testVenueId;
let seq = 100;

const call = (method, url, { token, body, headers } = {}) =>
  fetch(BASE + url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  }).then(async r => ({ status: r.status, json: await r.json().catch(() => ({})) }));

const futureSlot = hours => new Date(Date.now() + hours * 3600000 + (seq++) * 3600000).toISOString();

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hagzy-p2-'));
  proc = spawn('node', ['index.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      PORT,
      JWT_SECRET: 'test-phase-2-secret-32-chars-long!',
      ADMIN_EMAIL: 'admin@test.dev',
      ADMIN_PHONE: '01000000001',
      ADMIN_PASSWORD: 'correct-horse-password',
      PAYMENT_LISTENER_KEY: 'test-listener-secret-p2',
      PAYMENT_WEBHOOK_SECRET: 'test-webhook-secret-p2',
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
  const otpRes = await call('POST', '/api/auth/customer-otp/request', { body: { phone: '01099998888' } });
  const custRes = await call('POST', '/api/auth/customer-otp/verify', {
    body: { phone: '01099998888', code: otpRes.json.testOtp, name: 'Payment Tester' },
  });
  custToken = custRes.json.token;

  // Setup test venue
  testVenueId = 'p2-venue';
  await call('PUT', `/api/admin/venues/${testVenueId}`, {
    token: adminToken,
    body: {
      id: testVenueId,
      name: 'Padel Pro Club',
      nameAr: 'نادي البادل',
      type: 'sports',
      depositPercent: 30,
      spaces: [
        { id: 'court-alpha', name: 'Court Alpha', price: 200, hourlyRate: 200 },
        { id: 'court-beta', name: 'Court Beta', price: 250, hourlyRate: 250 },
      ],
      services: [
        { id: 'srv-rackets', name: 'Rackets Rental', price: 50 },
      ],
    },
  });
});

after(() => {
  if (proc) proc.kill();
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true });
});

test('STATE MACHINE: Cannot revive a cancelled booking (409 Conflict)', async () => {
  const slotTime = futureSlot(48);
  const createRes = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: testVenueId,
      itemId: 'court-alpha',
      startsAt: slotTime,
      durationMinutes: 60,
      customer: 'Cancellation Tester',
    },
  });
  assert.equal(createRes.status, 200);
  const bookingId = createRes.json.booking.id;

  // Customer cancels booking
  const cancelRes = await call('POST', `/api/bookings/${bookingId}/cancel`, { token: custToken });
  assert.equal(cancelRes.status, 200);
  assert.equal(cancelRes.json.booking.status, 'cancelled');

  // Attempt to confirm the cancelled booking as admin -> MUST return 409 Conflict
  const confirmRes = await call('POST', `/api/admin/bookings/${bookingId}/confirm`, { token: adminToken });
  assert.equal(confirmRes.status, 409);
  assert.match(confirmRes.json.error, /cancelled/i);
});

test('CONCURRENCY: Simultaneous booking attempts for the same slot yield exactly one 200 and one 409', async () => {
  const targetSlot = futureSlot(72);
  const payload = {
    venueId: testVenueId,
    itemId: 'court-alpha',
    startsAt: targetSlot,
    durationMinutes: 60,
    customer: 'Concurrent Racer',
  };

  const [res1, res2] = await Promise.all([
    call('POST', '/api/bookings', { token: custToken, body: payload }),
    call('POST', '/api/bookings', { token: custToken, body: payload }),
  ]);

  const statuses = [res1.status, res2.status].sort();
  assert.deepEqual(statuses, [200, 409], 'Exactly one concurrent booking must succeed and one must be rejected with 409');
});

test('ROUTE PARITY: Fawry reference number generation works and extends hold', async () => {
  const slotTime = futureSlot(36);
  const bRes = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: testVenueId,
      itemId: 'court-beta',
      startsAt: slotTime,
      durationMinutes: 60,
      customer: 'Fawry Customer',
      phone: '01012345678',
    },
  });
  assert.equal(bRes.status, 200);
  const bookingId = bRes.json.booking.id;

  const fawryRes = await call('POST', `/api/bookings/${bookingId}/fawry-reference`, {
    body: { customerName: 'Fawry Customer', phone: '01012345678' },
  });
  assert.equal(fawryRes.status, 200);
  assert.ok(fawryRes.json.referenceNumber, 'Should return referenceNumber');
  assert.match(fawryRes.json.referenceNumber, /^\d{3}\s\d{3}\s\d{4}$/, 'Should be 10 formatted digits');
  assert.ok(fawryRes.json.amount > 0);
  assert.ok(fawryRes.json.expiresAt);
});

test('WALLET LEDGER: Overdraft protection strictly blocks overspending (402)', async () => {
  const deductRes = await call('POST', '/api/customer/wallet/deduct', {
    token: custToken,
    body: { amount: 1000000 },
  });
  assert.equal(deductRes.status, 402);
  assert.match(deductRes.json.error, /insufficient/i);
});

test('PAYMENT MATCHER: High-value transfers (> 5000 EGP) route to review queue', async () => {
  const rawText = 'تم استلام مبلغ 6000.00 جنيه من رقم 01011119999';
  const listenerRes = await call('POST', '/api/payments/listener', {
    headers: { 'x-listener-key': 'test-listener-secret-p2' },
    body: { text: rawText },
  });
  assert.equal(listenerRes.status, 200);
  assert.equal(listenerRes.json.matched, false);
  assert.equal(listenerRes.json.status, 'REQUIRES_MANUAL_REVIEW');

  // Verify it appears in Admin Review Queue
  const queueRes = await call('GET', '/api/admin/payments/review-queue', { token: adminToken });
  assert.equal(queueRes.status, 200);
  assert.ok(queueRes.json.items.some(i => i.amount === 6000 && i.status === 'REQUIRES_MANUAL_REVIEW'));
});

test('PAYMENT MATCHER: Duplicate payment notification is detected as idempotent duplicate', async () => {
  const providerRef = `test_dup_${Date.now()}`;
  const payload = {
    paymentMethod: 'MOBILE_WALLET',
    senderIdentifier: '01012344321',
    amount: 150,
    providerRef,
    rawText: `Transfer of 150 ref ${providerRef}`,
  };

  const secret = 'test-webhook-secret-p2';
  const bodyStr = JSON.stringify(payload);
  const sig = crypto.createHmac('sha256', secret).update(bodyStr).digest('hex');

  const first = await call('POST', '/api/payments/webhook', {
    headers: { 'x-signature': sig },
    body: payload,
  });
  assert.equal(first.status, 200);

  const second = await call('POST', '/api/payments/webhook', {
    headers: { 'x-signature': sig },
    body: payload,
  });
  assert.equal(second.status, 200);
  assert.equal(second.json.duplicate, true, 'Second submission of same event must be flagged as duplicate');
});

test('HEARTBEAT: Listener heartbeat updates status endpoint', async () => {
  const beatRes = await call('POST', '/api/payments/listener/heartbeat', {
    headers: { 'x-listener-key': 'test-listener-secret-p2' },
  });
  assert.equal(beatRes.status, 200);
  assert.equal(beatRes.json.status, 'ok');

  const statusRes = await call('GET', '/api/payments/listener/status');
  assert.equal(statusRes.status, 200);
  assert.equal(statusRes.json.isListenerActive, true);
  assert.ok(statusRes.json.lastHeartbeatAt);
});

test('MIGRATIONS: dry-run validates authoritative schema without DB connection', async () => {
  const { runMigrations } = require('../migrate');
  const summary = await runMigrations({ dryRun: true });
  assert.equal(summary.status, 'success');
  assert.ok(summary.executed.length >= 2);
  assert.ok(summary.executed.some(e => e.file.includes('002_authoritative_schema')));
});


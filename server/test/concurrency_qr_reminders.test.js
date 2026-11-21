// Single-Wallet Payment Concurrency, Parser Hardening, Notifications, QR Check-In & Reminders Tests
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 5100 + Math.floor(Math.random() * 500);
const BASE = `http://localhost:${PORT}`;
const LISTENER_KEY = 'test-listener-concurrency-key';
const WEBHOOK_SECRET = 'test-webhook-concurrency-secret';

let proc, dataDir, adminToken, custToken, partnerToken;
let venueAId, venueBId;
let seq = 500;

const call = (method, url, { token, body, headers } = {}) =>
  fetch(BASE + url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  }).then(async r => ({ status: r.status, json: await r.json().catch(() => ({})) }));

const futureSlot = hours =>
  new Date(Date.now() + hours * 3600000 + (seq++) * 3600000).toISOString();

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hagzy-conc-'));
  proc = spawn('node', ['index.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      PORT,
      JWT_SECRET: 'test-conc-jwt-secret-32-chars-ok!',
      ADMIN_EMAIL: 'owner@test.dev',
      ADMIN_PHONE: '01015325250',
      ADMIN_PASSWORD: 'correct-horse-password',
      PAYMENT_LISTENER_KEY: LISTENER_KEY,
      PAYMENT_WEBHOOK_SECRET: WEBHOOK_SECRET,
      HAGZY_DATA_DIR: dataDir,
    },
    stdio: 'ignore',
  });

  for (let i = 0; i < 60; i++) {
    try {
      if ((await fetch(BASE + '/api/health')).ok) break;
    } catch (_) {}
    await new Promise(r => setTimeout(r, 100));
  }

  const adminRes = await call('POST', '/api/auth/login', {
    body: { email: 'owner@test.dev', password: 'correct-horse-password' },
  });
  adminToken = adminRes.json.token;

  const custOtp = await call('POST', '/api/auth/customer-otp/request', {
    body: { phone: '01099881122' },
  });
  const custVerify = await call('POST', '/api/auth/customer-otp/verify', {
    body: { phone: '01099881122', code: custOtp.json.testOtp, name: 'Main Customer' },
  });
  custToken = custVerify.json.token;

  // Create Venue A owned by a dedicated approved partner
  const pOtp = await call('POST', '/api/auth/customer-otp/request', {
    body: { phone: '01077776666' },
  });
  const pVerify = await call('POST', '/api/auth/customer-otp/verify', {
    body: { phone: '01077776666', code: pOtp.json.testOtp, name: 'Partner One' },
  });
  const pCustToken = pVerify.json.token;
  const reqRes = await call('POST', '/api/partner/requests', {
    token: pCustToken,
    body: { venueName: 'Arena One', venueType: 'padel', city: 'Cairo' },
  });
  const appRes = await call('POST', `/api/admin/partner-requests/${reqRes.json.request.id}/approve`, {
    token: adminToken,
  });
  venueAId = appRes.json.venue.id;
  const pLogin = await call('POST', '/api/auth/login', { body: { token: pCustToken } });
  partnerToken = pLogin.json.token;

  // Ensure Arena One has a 400 EGP/hr court (30% deposit -> 120 EGP dueNow)
  await call('PUT', `/api/admin/venues/${venueAId}`, {
    token: partnerToken,
    body: {
      id: venueAId,
      name: 'Arena One',
      type: 'sports',
      depositPercent: 25,
      spaces: [{ id: 'court-1', name: 'Court 1', price: 400, hourlyRate: 400 }],
    },
  });

  // Create Venue B owned purely by platform admin (for cross-tenant checks)
  venueBId = 'venue-b-other';
  await call('PUT', `/api/admin/venues/${venueBId}`, {
    token: adminToken,
    body: {
      id: venueBId,
      name: 'Other Arena',
      type: 'sports',
      depositPercent: 25,
      spaces: [{ id: 'court-b1', name: 'Court B1', price: 400, hourlyRate: 400 }],
    },
  });
});

after(() => {
  if (proc) proc.kill();
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true });
});

test('SINGLE-WALLET CONCURRENCY: 10 distinct customers pay the exact same round amount without piaster inflation & auto-confirm cleanly', async () => {
  const bookings = [];
  const intents = [];

  for (let i = 0; i < 10; i++) {
    const bRes = await call('POST', '/api/bookings', {
      body: {
        venueId: venueAId,
        itemId: 'court-1',
        startsAt: futureSlot(10 + i * 2),
        durationMinutes: 60,
        customer: `Customer ${i}`,
        phone: `0102000001${i}`,
        reminderOffsetMinutes: 60,
      },
    });
    assert.equal(bRes.status, 200);
    const bk = bRes.json.booking;
    assert.equal(bk.reminderOffsetMinutes, 60);
    assert.ok(bk.qrSignature, 'Created booking should include HMAC qrSignature');
    assert.ok(bk.qrCheckInUrl.includes('scanBooking='), 'Created booking should include qrCheckInUrl');
    bookings.push(bk);

    const method = i % 2 === 0 ? 'MOBILE_WALLET' : 'INSTAPAY';
    const sender = method === 'MOBILE_WALLET' ? `0102000001${i}` : `user_conc_${i}@instapay`;
    const iRes = await call('POST', '/api/payments/intent', {
      body: {
        bookingId: bk.id,
        paymentMethod: method,
        senderIdentifier: sender,
      },
    });
    assert.equal(iRes.status, 200);
    // Distinct senders hitting one central wallet get the exact clean base amount (100.00 EGP)
    assert.equal(iRes.json.expected_amount, 100);
    intents.push({ ...iRes.json, method, sender, bookingId: bk.id });
  }

  // Interleave interleaved Arabic/English/comma gateway notifications concurrently
  const notifications = intents.map((it, idx) => {
    const msg = it.method === 'MOBILE_WALLET'
      ? (idx === 0
          ? `تم استلام مبلغ ١٠٠٫٠٠ جنيه من رقم ${it.sender} خدمة فودافون كاش المرجع ref_${idx}_${Date.now()}`
          : `You have received 100.00 EGP from ${it.sender} via VF-Cash ref_${idx}_${Date.now()}`)
      : `حوالة لحظية عبر انستاباي بقيمة 100.00 EGP من حساب ${it.sender} مرجع ip_${idx}_${Date.now()}`;
    return call('POST', '/api/payments/listener', {
      headers: { 'x-listener-key': LISTENER_KEY },
      body: { text: msg },
    });
  });

  const results = await Promise.all(notifications);
  for (let i = 0; i < results.length; i++) {
    assert.equal(results[i].status, 200);
    assert.equal(results[i].json.matched, true, `Expected intent ${i} to auto-match`);
    assert.equal(results[i].json.bookingId, bookings[i].id);
  }
});

test('SAME-SENDER COLLISION & PARSE HARNESS: Same sender 2 simultaneous intents disambiguate with piasters & comma/unparsed texts handled safely', async () => {
  const b1 = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: venueAId,
      itemId: 'court-1',
      startsAt: futureSlot(40),
      durationMinutes: 60,
      customer: 'Same Sender 1',
      phone: '01099881122',
    },
  });
  const b2 = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: venueAId,
      itemId: 'court-1',
      startsAt: futureSlot(44),
      durationMinutes: 60,
      customer: 'Same Sender 2',
      phone: '01099881122',
    },
  });

  const i1 = await call('POST', '/api/payments/intent', {
    token: custToken,
    body: { bookingId: b1.json.booking.id, paymentMethod: 'MOBILE_WALLET', senderIdentifier: '01033445566' },
  });
  const i2 = await call('POST', '/api/payments/intent', {
    token: custToken,
    body: { bookingId: b2.json.booking.id, paymentMethod: 'MOBILE_WALLET', senderIdentifier: '01033445566' },
  });
  assert.equal(i1.json.expected_amount, 100);
  assert.notEqual(i2.json.expected_amount, i1.json.expected_amount, 'Second concurrent intent from same sender must receive unique piaster suffix');

  // Exact match on suffixed amount must confirm b2 unambiguously without colliding with 100.00 b1
  const paySecond = await call('POST', '/api/payments/listener', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: {
      text: `تم استلام مبلغ ${i2.json.expected_amount} جنيه من رقم 01033445566 فودافون كاش المرجع ref_p2_${Date.now()}`,
    },
  });
  assert.equal(paySecond.status, 200);
  assert.equal(paySecond.json.matched, true);
  assert.equal(paySecond.json.bookingId, b2.json.booking.id);

  // Comma thousands parsing: "1,250.00 جنيه" -> 1250
  const commaRes = await call('POST', '/api/payments/listener', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: { text: `تم استلام مبلغ 1,250.00 جنيه من رقم 01088776655 فودافون كاش مرجع comma_${Date.now()}` },
  });
  assert.equal(commaRes.status, 200);
  assert.equal(commaRes.json.amount, 1250);

  // Financial notification missing sender routes to PARSE_REVIEW (200) instead of being dropped (422)
  const unparsedFin = await call('POST', '/api/payments/listener', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: { text: 'فودافون كاش: تم استلام مبلغ 100.00 جنيه بنجاح' },
  });
  assert.equal(unparsedFin.status, 200);
  assert.equal(unparsedFin.json.matched, false);
  assert.equal(unparsedFin.json.status, 'PARSE_REVIEW');

  // Partner attaches queued review item -> confirms b1!
  const attachRes = await call('POST', `/api/admin/payments/review-queue/${unparsedFin.json.eventId}/attach`, {
    token: partnerToken,
    body: { bookingId: b1.json.booking.id },
  });
  assert.equal(attachRes.status, 200);
  assert.equal(attachRes.json.item.status, 'RESOLVED');

  // Non-financial junk text still returns 422
  const junkRes = await call('POST', '/api/payments/listener', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: { text: 'Battery is at 80 percent' },
  });
  assert.equal(junkRes.status, 422);
});

test('RETROACTIVE MATCH: Early transfer resolves stale UNMATCHED review item once intent is created', async () => {
  const earlyRes = await call('POST', '/api/payments/listener', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: { text: `You received 100.00 EGP from 01055443322 via VF-Cash ref_early_${Date.now()}` },
  });
  assert.equal(earlyRes.status, 200);
  assert.equal(earlyRes.json.status, 'UNMATCHED');

  const bkRes = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: venueAId,
      itemId: 'court-1',
      startsAt: futureSlot(60),
      durationMinutes: 60,
      customer: 'Retro Guest',
      phone: '01099881122',
    },
  });
  const intentRes = await call('POST', '/api/payments/intent', {
    token: custToken,
    body: { bookingId: bkRes.json.booking.id, paymentMethod: 'MOBILE_WALLET', senderIdentifier: '01055443322' },
  });
  assert.equal(intentRes.status, 200);
  assert.equal(intentRes.json.status, 'VERIFIED');

  const qRes = await call('GET', '/api/admin/payments/review-queue', { token: adminToken });
  const matchedItem = qRes.json.items.find(i => i.id === earlyRes.json.eventId);
  assert.equal(matchedItem.status, 'RESOLVED');
});

test('QR CHECK-IN & VENUE OWNER NOTIFICATIONS: Signed QR lookup, cross-tenant protection, and idempotent check-in', async () => {
  // Pending booking on Arena One (Venue A)
  const pendingRes = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: venueAId,
      itemId: 'court-1',
      startsAt: futureSlot(80),
      durationMinutes: 60,
      customer: 'QR Guest',
      phone: '01099881122',
    },
  });
  const bk = pendingRes.json.booking;
  const sig = bk.qrSignature;

  // Venue A partner received an in-app notification for booking_created
  const notifsRes = await call('GET', '/api/admin/notifications', { token: partnerToken });
  assert.equal(notifsRes.status, 200);
  const createdNotif = notifsRes.json.notifications.find(n => n.bookingId === bk.id);
  assert.ok(createdNotif, 'Venue owner should receive persistent notification on booking creation');

  // Mark notification read
  const readRes = await call('POST', `/api/admin/notifications/${createdNotif.id}/read`, { token: partnerToken });
  assert.equal(readRes.status, 200);

  // Check-in of unconfirmed pending_payment booking must return 409
  const unconfCheckIn = await call('POST', `/api/admin/bookings/${bk.id}/check-in`, {
    token: partnerToken,
    body: { sig },
  });
  assert.equal(unconfCheckIn.status, 409);

  // Tampered signature must return 403
  const badSigRes = await call('GET', `/api/admin/bookings/${bk.id}/qr-details?sig=tampered_sig`, {
    token: partnerToken,
  });
  assert.equal(badSigRes.status, 403);

  // Valid signature returns booking & financial breakdown
  const goodSigRes = await call('GET', `/api/admin/bookings/${bk.id}/qr-details?sig=${encodeURIComponent(sig)}`, {
    token: partnerToken,
  });
  assert.equal(goodSigRes.status, 200);
  assert.equal(goodSigRes.json.signatureVerified, true);
  assert.equal(goodSigRes.json.financialSummary.totalPrice, 400);

  // Admin confirms booking for Venue B -> Venue A partner must NOT see Venue B's QR details (403)
  const bkB = await call('POST', '/api/bookings', {
    token: custToken,
    body: {
      venueId: venueBId,
      itemId: 'court-b1',
      startsAt: futureSlot(90),
      durationMinutes: 60,
      customer: 'Other Guest',
      phone: '01099881122',
    },
  });
  const crossTenantQr = await call('GET', `/api/admin/bookings/${bkB.json.booking.id}/qr-details`, {
    token: partnerToken,
  });
  assert.equal(crossTenantQr.status, 403);

  // Partner confirms bk on Venue A, then checks guest in twice (2nd is idempotent)
  const confirmRes = await call('POST', `/api/admin/bookings/${bk.id}/confirm`, { token: partnerToken });
  assert.equal(confirmRes.status, 200);

  const checkIn1 = await call('POST', `/api/admin/bookings/${bk.id}/check-in`, {
    token: partnerToken,
    body: { sig },
  });
  assert.equal(checkIn1.status, 200);
  assert.equal(checkIn1.json.booking.status, 'checked_in');
  assert.equal(checkIn1.json.booking.checkedIn, true);

  const checkIn2 = await call('POST', `/api/admin/bookings/${bk.id}/check-in`, {
    token: partnerToken,
    body: { sig },
  });
  assert.equal(checkIn2.status, 200);
  assert.equal(checkIn2.json.alreadyCheckedIn, true);
});

test('WHATSAPP REMINDERS & BOT: Custom reminder timing, PUT update, WhatsApp bot commands, and idempotent runner', async () => {
  // Create a booking starting 90 minutes from now (so 120m reminder is already due!)
  const soonIso = new Date(Date.now() + 90 * 60 * 1000).toISOString();
  const cOtp = await call('POST', '/api/auth/customer-otp/request', { body: { phone: '01066554433' } });
  const cVer = await call('POST', '/api/auth/customer-otp/verify', {
    body: { phone: '01066554433', code: cOtp.json.testOtp, name: 'Bot Customer' },
  });
  const botCustToken = cVer.json.token;

  const bRes = await call('POST', '/api/bookings', {
    token: botCustToken,
    body: {
      venueId: venueAId,
      itemId: 'court-1',
      startsAt: soonIso,
      durationMinutes: 60,
      customer: 'Bot Customer',
      phone: '01066554433',
      reminderOffsetMinutes: 120,
    },
  });
  assert.equal(bRes.status, 200);
  const bkId = bRes.json.booking.id;
  await call('POST', `/api/admin/bookings/${bkId}/confirm`, { token: partnerToken });

  // Bot status shows booking details + QR URL + balance
  const statusBot = await call('POST', '/api/chatbot/message', {
    body: { phone: '01066554433', message: 'حجزي', language: 'AR' },
  });
  assert.equal(statusBot.status, 200);
  assert.match(statusBot.json.reply, /scanBooking=/);
  assert.match(statusBot.json.reply, /Arena One/);

  // Update via WhatsApp command: "تذكير 6" -> 360 mins
  const remindBot = await call('POST', '/api/chatbot/message', {
    body: { phone: '01066554433', message: 'تذكير 6', language: 'AR' },
  });
  assert.equal(remindBot.status, 200);
  assert.match(remindBot.json.reply, /6 ساعات/);

  // Update via REST PUT /api/bookings/:id/reminder back to 120m so it is due now
  const putRem = await call('PUT', `/api/bookings/${bkId}/reminder`, {
    token: botCustToken,
    body: { reminderOffsetMinutes: 120 },
  });
  assert.equal(putRem.status, 200);
  assert.equal(putRem.json.reminderOffsetMinutes, 120);

  // Reminder runner requires auth (401 without listener key or admin token)
  const unauthRun = await call('POST', '/api/internal/run-reminders', { body: {} });
  assert.equal(unauthRun.status, 401);

  // Run reminders once with forceMarkSent (since SMS/UltraMsg creds aren't active in offline test)
  const run1 = await call('POST', '/api/internal/run-reminders', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: { forceMarkSent: true },
  });
  assert.equal(run1.status, 200);
  assert.ok(run1.json.results.some(r => r.bookingId === bkId && r.sent === true));

  // Second run must be idempotent (booking no longer re-dispatched)
  const run2 = await call('POST', '/api/internal/run-reminders', {
    headers: { 'x-listener-key': LISTENER_KEY },
    body: { forceMarkSent: true },
  });
  assert.equal(run2.status, 200);
  assert.ok(!run2.json.results.some(r => r.bookingId === bkId));
});

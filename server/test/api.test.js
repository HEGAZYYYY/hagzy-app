// Run with: npm test   (Node >= 20; spawns the server on a free port)
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const PORT = 4600 + Math.floor(Math.random() * 300);
const B = `http://localhost:${PORT}`;
let proc, dataDir, admin, cust, venueId, seq = 0;

const call = (method, url, { token, body, headers } = {}) =>
  fetch(B + url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  }).then(async r => ({ status: r.status, json: await r.json().catch(() => ({})) }));

const slot = days => new Date(Date.now() + days * 864e5 + (seq++) * 36e5).toISOString();
const booking = (extra = {}) => ({
  venueId, itemId: 'court-1', customer: 'Ali', startsAt: slot(2), durationMinutes: 60,
  price: 100, phone: '01011112222', ...extra,
});

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hagzy-'));
  proc = spawn('node', ['index.js'], {
    cwd: path.join(__dirname, '..'),
    env: { ...process.env, NODE_ENV: 'test', PORT, JWT_SECRET: 'test-secret',
           ADMIN_EMAIL: 'admin@test.dev', ADMIN_PASSWORD: 'correct-horse', HAGZY_DATA_DIR: dataDir },
    stdio: 'ignore',
  });
  for (let i = 0; i < 50; i++) {
    try { if ((await fetch(B + '/api/health')).ok) break; } catch (_) {}
    await new Promise(r => setTimeout(r, 100));
  }
  admin = (await call('POST', '/api/auth/login', { body: { email: 'admin@test.dev', password: 'correct-horse' } })).json.token;
  const otp = (await call('POST', '/api/auth/customer-otp/request', { body: { phone: '01011112222' } })).json.testOtp;
  cust = (await call('POST', '/api/auth/customer-otp/verify', { body: { phone: '01011112222', code: otp } })).json.token;
  venueId = (await call('GET', '/api/venues')).json.venues[0].id;
});
after(() => { proc.kill(); fs.rmSync(dataDir, { recursive: true, force: true }); });

test('admin endpoints require an admin token', async () => {
  for (const [m, u] of [['GET', '/api/admin/bookings'], ['GET', '/api/admin/venues'],
                        ['PUT', '/api/admin/venues/x'], ['DELETE', '/api/admin/venues/x']]) {
    assert.equal((await call(m, u)).status, 401, `${m} ${u}`);
    assert.equal((await call(m, u, { token: cust })).status, 403, `${m} ${u} as customer`);
  }
  assert.equal((await call('GET', '/api/admin/bookings', { token: admin })).status, 200);
});

test('legacy admin backdoor and wrong passwords are rejected', async () => {
  const r = await call('POST', '/api/auth/login', { body: { email: 'admin@hagzy.app', password: 'admin123' } });
  assert.equal(r.status, 401);
});

test('OTP: no bypass header, lockout after repeated wrong codes', async () => {
  await call('POST', '/api/auth/customer-otp/request', { body: { email: 'victim@test.dev' } });
  const bypass = await call('POST', '/api/auth/customer-otp/verify',
    { body: { email: 'victim@test.dev', code: '000000' }, headers: { 'x-test-suite': 'true' } });
  assert.equal(bypass.status, 400);
  const statuses = [];
  for (let i = 0; i < 7; i++) {
    statuses.push((await call('POST', '/api/auth/customer-otp/verify', { body: { email: 'victim@test.dev', code: '111111' } })).status);
  }
  assert.ok(statuses.includes(429), `expected a lockout, got ${statuses}`);
  // after lockout the code is burned, so even the right code can no longer work
  assert.equal(statuses.at(-1), 400);
});

test('OTP login only resolves the identifier that was verified', async () => {
  // Attacker verifies their own phone but names the victim's email too.
  const otp = (await call('POST', '/api/auth/customer-otp/request', { body: { phone: '01099998888' } })).json.testOtp;
  const r = await call('POST', '/api/auth/customer-otp/verify', { body: { phone: '01099998888', email: 'victim@test.dev', code: otp } });
  assert.equal(r.json.customer.email, '');
});

test('profile and wallet require auth; customers cannot credit themselves', async () => {
  assert.equal((await call('GET', '/api/customer/profile?phone=01011112222')).status, 401);
  assert.equal((await call('POST', '/api/customer/wallet/add', { body: { amount: 999, phone: '01011112222' } })).status, 401);
  assert.equal((await call('POST', '/api/customer/wallet/add', { token: cust, body: { amount: 999 } })).status, 403);
  assert.equal((await call('POST', '/api/customer/wallet/deduct', { token: cust, body: { amount: -50 } })).status, 400);
  assert.equal((await call('GET', '/api/customer/profile', { token: cust })).status, 200);
});

test('customers cannot self-confirm; overlapping slots are rejected', async () => {
  const body = booking({ status: 'confirmed', paymentStatus: 'paid', dueNow: 0 });
  const first = await call('POST', '/api/bookings', { body });
  assert.equal(first.status, 200);
  assert.equal(first.json.booking.status, 'pending_payment');
  assert.equal(first.json.booking.paymentStatus, 'unpaid');
  const second = await call('POST', '/api/bookings', { body });
  assert.equal(second.status, 409);
});

test('payment proof records a reference but does not confirm the booking', async () => {
  const b = (await call('POST', '/api/bookings', { body: booking() })).json.booking;
  const r = await call('POST', `/api/bookings/${b.id}/payment-proof`, { body: { method: 'instapay', reference: 'REF123456' } });
  assert.equal(r.status, 200);
  assert.equal(r.json.booking.status, 'pending_payment');
  assert.equal((await call('POST', `/api/bookings/${b.id}/payment-proof`, { body: { method: 'instapay', reference: 'x' } })).status, 400);
  const pub = await call('GET', `/api/bookings/${b.id}`);
  assert.equal(pub.json.booking.phone, undefined, 'public status must not leak contact details');
});

test('wallet payment is charged server-side, needs sign-in, and cannot overdraw', async () => {
  const body = booking({ paymentMethod: 'wallet', price: 40 }); // venue deposit % of 40
  assert.equal((await call('POST', '/api/bookings', { body })).status, 401);
  const before = (await call('GET', '/api/customer/profile', { token: cust })).json.customer.walletBalance;
  const ok = await call('POST', '/api/bookings', { token: cust, body });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.booking.status, 'confirmed');
  assert.ok(ok.json.walletBalance < before);
  const huge = await call('POST', '/api/bookings', { token: cust, body: booking({ paymentMethod: 'wallet', price: 1e6 }) });
  assert.equal(huge.status, 402);
  const mine = await call('GET', '/api/bookings', { token: cust });
  assert.ok(mine.json.bookings.length >= 1);
});

test('Google sign-in without a verifiable id token is refused', async () => {
  const r = await call('POST', '/api/auth/social/google', { body: { email: 'victim@test.dev', googleId: '1' } });
  assert.equal(r.status, 400);
});

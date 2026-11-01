const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const jwt = require('jsonwebtoken');

const PORT = 4700 + Math.floor(Math.random() * 200);
const BASE = `http://localhost:${PORT}`;
const JWT_SECRET = 'phase3-partner-secret';

let proc, dataDir;
let ownerToken, partnerAToken, partnerBToken;

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

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'hagzy-p3-'));

  proc = spawn('node', ['index.js'], {
    cwd: path.join(__dirname, '..'),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      PORT,
      JWT_SECRET,
      ADMIN_EMAIL: 'owner@hagzy.app',
      ADMIN_PHONE: '01011110000',
      ADMIN_PASSWORD: 'owner-secure-password',
      PAYMENT_LISTENER_KEY: 'p3-listener-secret',
      PAYMENT_WEBHOOK_SECRET: 'p3-webhook-secret',
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

  // 1. Platform Super Owner Token
  const loginRes = await call('POST', '/api/auth/login', {
    body: { email: 'owner@hagzy.app', password: 'owner-secure-password' },
  });
  ownerToken = loginRes.json.token;

  // 2. Partner A Token (owns Venue A)
  partnerAToken = jwt.sign(
    { id: 'usr_partner_a', email: 'partner.a@venue.com', phone: '01011112233', role: 'partner', isAdmin: false },
    JWT_SECRET,
    { expiresIn: '2h' }
  );

  // 3. Partner B Token (owns Venue B)
  partnerBToken = jwt.sign(
    { id: 'usr_partner_b', email: 'partner.b@venue.com', phone: '01099998877', role: 'partner', isAdmin: false },
    JWT_SECRET,
    { expiresIn: '2h' }
  );
});

after(() => {
  if (proc) proc.kill();
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true });
});

test('MULTI-TENANCY: Partner venue isolation, cross-tenant update/delete rejection, and soft-delete', async () => {
  // 1. Partner A creates Venue A
  const createA = await call('PUT', '/api/admin/venues/ven_partner_a', {
    token: partnerAToken,
    body: {
      name: 'Padel Arena A',
      type: 'sports',
      depositPercent: 25,
      items: [{ id: 'court-a1', name: 'Court A1', price: 200 }],
    },
  });
  assert.equal(createA.status, 200);
  assert.equal(createA.json.venue.ownerId, 'usr_partner_a');

  // 2. Partner B creates Venue B
  const createB = await call('PUT', '/api/admin/venues/ven_partner_b', {
    token: partnerBToken,
    body: {
      name: 'Gaming Lounge B',
      type: 'lounge',
      depositPercent: 20,
      items: [{ id: 'ps5-b1', name: 'PS5 Room B1', price: 150 }],
    },
  });
  assert.equal(createB.status, 200);
  assert.equal(createB.json.venue.ownerId, 'usr_partner_b');

  // 3. Scoped GET /api/admin/venues: Partner A sees only Venue A
  const getVenuesA = await call('GET', '/api/admin/venues', { token: partnerAToken });
  assert.equal(getVenuesA.status, 200);
  const idsA = getVenuesA.json.venues.map(v => v.id);
  assert.ok(idsA.includes('ven_partner_a'));
  assert.ok(!idsA.includes('ven_partner_b'), 'Partner A must never see Venue B');

  // 4. Scoped GET /api/admin/venues: Partner B sees only Venue B
  const getVenuesB = await call('GET', '/api/admin/venues', { token: partnerBToken });
  assert.equal(getVenuesB.status, 200);
  const idsB = getVenuesB.json.venues.map(v => v.id);
  assert.ok(idsB.includes('ven_partner_b'));
  assert.ok(!idsB.includes('ven_partner_a'), 'Partner B must never see Venue A');

  // 5. Platform Owner sees both
  const getVenuesOwner = await call('GET', '/api/admin/venues', { token: ownerToken });
  assert.equal(getVenuesOwner.status, 200);
  const idsOwner = getVenuesOwner.json.venues.map(v => v.id);
  assert.ok(idsOwner.includes('ven_partner_a'));
  assert.ok(idsOwner.includes('ven_partner_b'));

  // 6. Cross-tenant update rejection (403): Partner A attempts to modify Venue B
  const crossUpdate = await call('PUT', '/api/admin/venues/ven_partner_b', {
    token: partnerAToken,
    body: { name: 'Hacked Venue B' },
  });
  assert.equal(crossUpdate.status, 403, 'Cross-tenant update must be rejected with 403');

  // 7. Cross-tenant delete rejection (403): Partner A attempts to delete Venue B
  const crossDelete = await call('DELETE', '/api/admin/venues/ven_partner_b', {
    token: partnerAToken,
  });
  assert.equal(crossDelete.status, 403, 'Cross-tenant delete must be rejected with 403');

  // 8. Soft Delete: Partner A deletes Venue A
  const softDelRes = await call('DELETE', '/api/admin/venues/ven_partner_a', {
    token: partnerAToken,
  });
  assert.equal(softDelRes.status, 200);

  // Check public customer API: Venue A is hidden
  const publicVenues = await call('GET', '/api/venues');
  const pubIds = publicVenues.json.venues.map(v => v.id);
  assert.ok(!pubIds.includes('ven_partner_a'), 'Archived venue must not appear in customer list');
});

test('MULTI-TENANCY: Booking isolation and cross-tenant action protection', async () => {
  // 1. Create a customer booking for Venue B
  const bookingTime = new Date(Date.now() + 864e5 * 3).toISOString();
  const bookRes = await call('POST', '/api/bookings', {
    body: {
      venueId: 'ven_partner_b',
      itemId: 'ps5-b1',
      customer: 'Mostafa',
      startsAt: bookingTime,
      durationMinutes: 60,
      phone: '01055554433',
    },
  });
  assert.equal(bookRes.status, 200);
  const bookingId = bookRes.json.booking.id;

  // 2. Partner A calls GET /api/admin/bookings: must NOT see Venue B\'s booking
  const partnerABookings = await call('GET', '/api/admin/bookings', { token: partnerAToken });
  assert.equal(partnerABookings.status, 200);
  const bIdsA = partnerABookings.json.bookings.map(b => b.id);
  assert.ok(!bIdsA.includes(bookingId), 'Partner A must not see bookings of other venues');

  // 3. Partner A attempts to confirm Venue B\'s booking (403)
  const crossConfirm = await call('POST', `/api/admin/bookings/${bookingId}/confirm`, {
    token: partnerAToken,
  });
  assert.equal(crossConfirm.status, 403, 'Partner A must not confirm bookings of other venues');

  // 4. Partner A attempts to cancel Venue B\'s booking (403)
  const crossCancel = await call('DELETE', `/api/admin/bookings/${bookingId}`, {
    token: partnerAToken,
  });
  assert.equal(crossCancel.status, 403, 'Partner A must not cancel bookings of other venues');

  // 5. Partner B confirms own booking (200)
  const partnerBConfirm = await call('POST', `/api/admin/bookings/${bookingId}/confirm`, {
    token: partnerBToken,
  });
  assert.equal(partnerBConfirm.status, 200);
  assert.equal(partnerBConfirm.json.booking.status, 'confirmed');

  // 6. Server-side analytics scoped to Partner B
  const analyticsRes = await call('GET', '/api/admin/analytics', { token: partnerBToken });
  assert.equal(analyticsRes.status, 200);
  assert.equal(analyticsRes.json.analytics.confirmedCount, 1);
  assert.equal(analyticsRes.json.analytics.totalRevenueEgp, 150);
});

test('VALIDATION: Venue creation requires valid name and bounded depositPercent', async () => {
  // Empty name -> 400
  const emptyName = await call('PUT', '/api/admin/venues/ven_bad_1', {
    token: partnerAToken,
    body: { name: '   ', depositPercent: 30 },
  });
  assert.equal(emptyName.status, 400);

  // Invalid depositPercent (> 100) -> 400
  const badDeposit = await call('PUT', '/api/admin/venues/ven_bad_2', {
    token: partnerAToken,
    body: { name: 'Valid Name', depositPercent: 120 },
  });
  assert.equal(badDeposit.status, 400);
});

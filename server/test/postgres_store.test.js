const test = require('node:test');
const assert = require('node:assert/strict');

const { runMigrations } = require('../migrate');
const {
  buildRelationalSnapshot,
  persistToPostgres,
  hydrateFromPostgres,
} = require('../postgresStore');

function buildEmptyState() {
  return {
    users: [],
    venues: [],
    bookings: [],
    otps: {},
    walletLedger: [],
    auditLog: [],
    reviewQueue: [],
    partnerRequests: [],
  };
}

test('POSTGRES MIGRATIONS: dry-run validates 001, 002, and 003 SQL files', async () => {
  const summary = await runMigrations({ dryRun: true });
  assert.equal(summary.status, 'success');
  assert.ok(summary.executed.some(e => e.file === '001_customer_accounts.sql'));
  assert.ok(summary.executed.some(e => e.file === '002_authoritative_schema.sql'));
  assert.ok(summary.executed.some(e => e.file === '003_moderation_views.sql'));
});

test('POSTGRES STORE: snapshot preserves relational links, handles multi-venue unit IDs, and sanitizes orphan FKs', () => {
  const state = {
    users: [
      {
        id: 'u_cust_1',
        name: 'Ahmed',
        email: 'Ahmed@Example.com ',
        phone: '01001112233',
        role: 'customer',
        walletBalance: 150,
        firebaseUid: '',
        emailVerified: true,
      },
      {
        id: 'u_partner_1',
        name: 'Karim',
        email: 'karim@club.com',
        role: 'partner',
        partnerStatus: 'approved',
        googleId: 'g_999',
      },
    ],
    venues: [
      {
        id: 'v_padel_1',
        name: 'Cairo Padel',
        ownerId: 'u_partner_1',
        pricePerHour: 300,
        depositPercent: 25,
        units: [{ id: 'court_1', name: 'Court 1', capacity: 4 }],
      },
      {
        id: 'v_gaming_2',
        name: 'Cyber Lounge',
        ownerId: 'admin', // Not in users table
        pricePerHour: 120,
        items: [{ id: 'court_1', name: 'PS5 Room 1' }], // Same unit ID on a different venue
      },
    ],
    bookings: [
      {
        id: 'bk_1',
        customerId: 'u_cust_1',
        ownerId: 'u_cust_1',
        venueId: 'v_padel_1',
        itemId: 'court_1',
        unitName: 'Court 1',
        venueName: 'Cairo Padel',
        customerName: 'Ahmed',
        phone: '01001112233',
        email: 'ahmed@example.com',
        startsAt: '2026-12-01T18:00:00.000Z',
        durationMinutes: 60,
        status: 'confirmed',
        price: 300,
        depositAmount: 75,
        dueNow: 0,
        confirmed: true,
        paymentMethod: 'INSTAPAY',
      },
      {
        id: 'bk_guest',
        venueId: 'v_gaming_2',
        itemId: 'missing_unit',
        startsAt: '2026-12-02T19:00:00.000Z',
        durationMinutes: 120,
        status: 'pending_payment',
        price: 240,
      },
    ],
    walletLedger: [
      {
        id: 'led_1',
        userId: 'u_cust_1',
        amount: 200,
        type: 'TOPUP',
        referenceId: 'pi_topup_1',
        description: 'Wallet top-up',
      },
      {
        id: 'led_2',
        userId: 'u_cust_1',
        amount: -50,
        type: 'BOOKING_DEPOSIT',
        referenceId: 'bk_1',
        description: 'Booking deposit',
      },
    ],
    otps: {
      'ahmed@example.com': {
        hashedCode: 'abc123',
        expiresAt: Date.now() + 60000,
        attempts: 1,
        name: 'Ahmed',
        isSignUp: true,
        isPartner: false,
      },
    },
    auditLog: [
      { bookingId: 'bk_1', fromStatus: 'pending_payment', toStatus: 'confirmed', actor: 'payment_oracle', reason: 'Exact match' },
    ],
    reviewQueue: [
      {
        id: 'rev_1',
        paymentMethod: 'MOBILE_WALLET',
        senderIdentifier: '01099988877',
        amount: 75,
        status: 'UNMATCHED',
        reason: 'No open intent',
      },
    ],
    partnerRequests: [
      {
        id: 'pr_1',
        userId: 'u_partner_1',
        approvedVenueId: 'v_padel_1',
        venueName: 'Cairo Padel',
        status: 'approved',
      },
    ],
  };

  const intents = new Map([
    ['pi_1', {
      intentId: 'pi_1',
      booking_id: 'bk_1',
      user_id: 'u_cust_1',
      payment_method: 'INSTAPAY',
      expected_sender_identifier: 'ahmed@instapay',
      expected_amount: 75,
      status: 'VERIFIED',
      expires_at: '2026-12-01T18:15:00.000Z',
    }],
    ['pi_topup_1', {
      intentId: 'pi_topup_1',
      booking_id: 'wallet_topup_u_cust_1',
      user_id: 'guest',
      payment_method: 'MOBILE_WALLET',
      expected_sender_identifier: '01001112233',
      expected_amount: 200,
      status: 'AWAITING_TRANSFER',
      expires_at: '2026-12-01T18:15:00.000Z',
    }],
  ]);

  const events = new Map([
    ['evt_1', {
      eventId: 'evt_1',
      matchedIntentId: 'pi_1',
      bookingId: 'bk_1',
      payment_method: 'INSTAPAY',
      sender_identifier: 'ahmed@instapay',
      amount: 75,
      is_claimed: true,
      received_at: '2026-12-01T17:50:00.000Z',
    }],
  ]);

  const snap = buildRelationalSnapshot(state, {
    localPaymentIntents: intents,
    localPaymentEvents: events,
  });

  // NULL unique identifiers when empty so UNIQUE constraints never collide
  assert.equal(snap.users[0].firebase_uid, null);
  assert.equal(snap.users[0].email, 'ahmed@example.com');

  // Owner FK is kept when user exists, nulled cleanly when ownerId='admin'
  assert.equal(snap.venues[0].owner_id, 'u_partner_1');
  assert.equal(snap.venues[1].owner_id, null);
  assert.equal(snap.venues[1].extra._rawOwnerId, 'admin');

  // Both venues retain distinct composite rows even with same unit id 'court_1'
  assert.equal(snap.units.length, 2);
  assert.deepEqual(
    snap.units.map(u => ({ venue_id: u.venue_id, id: u.id, source_key: u.source_key })),
    [
      { venue_id: 'v_padel_1', id: 'court_1', source_key: 'units' },
      { venue_id: 'v_gaming_2', id: 'court_1', source_key: 'items' },
    ],
  );

  // Valid booking links user + venue + unit; guest/orphan unit nulls FK safely
  assert.equal(snap.bookings[0].customer_id, 'u_cust_1');
  assert.equal(snap.bookings[0].unit_id, 'court_1');
  assert.equal(snap.bookings[1].customer_id, null);
  assert.equal(snap.bookings[1].unit_id, null);
  assert.equal(snap.bookings[1].extra._rawUnitId, 'missing_unit');

  // Ledger links booking_id only when matching a real booking
  assert.equal(snap.walletLedger[0].booking_id, null);
  assert.equal(snap.walletLedger[1].booking_id, 'bk_1');

  // Payment intents keep raw_booking_id for wallet_topup strings while avoiding FK violations
  assert.equal(snap.paymentIntents[0].booking_id, 'bk_1');
  assert.equal(snap.paymentIntents[1].booking_id, null);
  assert.equal(snap.paymentIntents[1].raw_booking_id, 'wallet_topup_u_cust_1');
  assert.equal(snap.paymentIntents[1].user_id, null);

  // Payment event & partner request retain FKs
  assert.equal(snap.paymentEvents[0].matched_intent_id, 'pi_1');
  assert.equal(snap.paymentEvents[0].booking_id, 'bk_1');
  assert.equal(snap.partnerRequests[0].user_id, 'u_partner_1');
  assert.equal(snap.partnerRequests[0].approved_venue_id, 'v_padel_1');
  assert.ok(snap.auditLog[0].id);
});

test('POSTGRES STORE: persistToPostgres -> hydrateFromPostgres transactional round-trip', async () => {
  const tables = {
    users: new Map(),
    venues: new Map(),
    bookable_units: new Map(),
    bookings: new Map(),
    wallet_ledger: new Map(),
    payment_intents: new Map(),
    payment_events: new Map(),
    payment_review_queue: new Map(),
    partner_requests: new Map(),
    audit_log: new Map(),
    otp_challenges: new Map(),
  };
  const executedSql = [];

  function runMockQuery(sql, params = []) {
    executedSql.push(sql.trim().split('\n')[0]);
    const trimmed = sql.trim();
    if (trimmed === 'BEGIN' || trimmed === 'COMMIT' || trimmed === 'ROLLBACK') {
      return { rows: [] };
    }
    if (trimmed.startsWith('DELETE FROM public.bookable_units')) {
      if (!params.length) tables.bookable_units.clear();
      else {
        const keep = new Set(JSON.parse(params[0]).map(k => `${k.venue_id}::${k.id}`));
        for (const k of Array.from(tables.bookable_units.keys())) {
          if (!keep.has(k)) tables.bookable_units.delete(k);
        }
      }
      return { rows: [] };
    }
    const delMatch = trimmed.match(/^DELETE FROM public\.([a-z_]+)/);
    if (delMatch) {
      const tbl = delMatch[1];
      if (!params.length) tables[tbl].clear();
      else {
        const keep = new Set(params[0]);
        for (const k of Array.from(tables[tbl].keys())) {
          if (!keep.has(k)) tables[tbl].delete(k);
        }
      }
      return { rows: [] };
    }
    const insMatch = trimmed.match(/^INSERT INTO public\.([a-z_]+)/);
    if (insMatch) {
      const tbl = insMatch[1];
      const rows = JSON.parse(params[0]);
      for (const r of rows) {
        const pk = tbl === 'otp_challenges'
          ? r.target
          : (tbl === 'bookable_units' ? `${r.venue_id}::${r.id}` : r.id);
        tables[tbl].set(pk, r);
      }
      return { rows: [] };
    }
    const selMatch = trimmed.match(/^SELECT \* FROM public\.([a-z_]+)/);
    if (selMatch) {
      const tbl = selMatch[1];
      return { rows: Array.from(tables[tbl].values()) };
    }
    return { rows: [] };
  }

  const mockPool = {
    query: async (sql, params) => runMockQuery(sql, params),
    connect: async () => ({
      query: async (sql, params) => runMockQuery(sql, params),
      release: () => {},
    }),
  };

  const otpExp = Date.now() + 300000;
  const sourceState = {
    users: [{ id: 'u1', name: 'Nour', email: 'nour@test.com', role: 'customer', walletBalance: 80 }],
    venues: [{
      id: 'v1',
      name: 'Nile Lounge',
      ownerId: 'u1',
      pricePerHour: 200,
      units: [{ id: 'unit_a', name: 'Table A' }],
      items: [{ id: 'unit_b', name: 'Table B' }],
    }],
    bookings: [{
      id: 'b1',
      customerId: 'u1',
      ownerId: 'u1',
      venueId: 'v1',
      itemId: 'unit_a',
      phone: '01012345678',
      email: 'nour@test.com',
      startsAt: '2026-12-05T15:00:00.000Z',
      durationMinutes: 90,
      status: 'confirmed',
      price: 300,
      holdExpiresAt: '2026-12-05T14:45:00.000Z',
      confirmed: true,
    }],
    walletLedger: [{ id: 'l1', userId: 'u1', amount: 80, type: 'TOPUP', referenceId: 'b1', description: 'Credit' }],
    reviewQueue: [{ id: 'r1', bookingId: 'b1', userId: 'u1', paymentMethod: 'INSTAPAY', amount: 50, status: 'PENDING_REVIEW' }],
    partnerRequests: [{ id: 'pr1', userId: 'u1', approvedVenueId: 'v1', venueName: 'Nile Lounge', status: 'approved' }],
    auditLog: [{ id: 'a1', bookingId: 'b1', fromStatus: 'pending_payment', toStatus: 'confirmed', actor: 'system' }],
    otps: { 'nour@test.com': { hashedCode: 'hash1', expiresAt: otpExp, attempts: 0, name: 'Nour', isSignUp: true, isPartner: false } },
  };
  const sourceIntents = new Map([
    ['i1', { intentId: 'i1', booking_id: 'b1', user_id: 'u1', payment_method: 'INSTAPAY', expected_amount: 50, status: 'VERIFIED', expires_at: '2026-12-05T14:30:00.000Z' }],
  ]);
  const sourceEvents = new Map([
    ['e1', { eventId: 'e1', matchedIntentId: 'i1', bookingId: 'b1', payment_method: 'INSTAPAY', amount: 50, is_claimed: true, received_at: '2026-12-05T14:15:00.000Z' }],
  ]);

  await persistToPostgres(mockPool, sourceState, {
    localPaymentIntents: sourceIntents,
    localPaymentEvents: sourceEvents,
  });
  assert.equal(executedSql[0], 'BEGIN');
  assert.equal(executedSql[executedSql.length - 1], 'COMMIT');
  assert.equal(tables.users.size, 1);
  assert.equal(tables.bookable_units.size, 2);

  const restored = buildEmptyState();
  const restoredIntents = new Map();
  const restoredEvents = new Map();

  const stats = await hydrateFromPostgres(mockPool, restored, {
    localPaymentIntents: restoredIntents,
    localPaymentEvents: restoredEvents,
  });

  assert.equal(stats.usersCount, 1);
  assert.equal(stats.venuesCount, 1);
  assert.equal(stats.unitsCount, 2);
  assert.equal(stats.bookingsCount, 1);
  assert.equal(restored.venues[0].units[0].id, 'unit_a');
  assert.equal(restored.venues[0].items[0].id, 'unit_b');
  assert.equal(restored.bookings[0].itemId, 'unit_a');
  assert.equal(restored.bookings[0].phone, '01012345678');
  assert.equal(restored.bookings[0].holdExpiresAt, '2026-12-05T14:45:00.000Z');
  assert.equal(restored.otps['nour@test.com'].expiresAt, otpExp);
  assert.equal(restoredIntents.get('i1').status, 'VERIFIED');
  assert.equal(restoredEvents.get('e1').matchedIntentId, 'i1');
});

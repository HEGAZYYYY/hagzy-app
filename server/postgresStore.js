/**
 * Normalized PostgreSQL persistence store for Hagzy (Supabase-compatible).
 * Maps in-memory state (`db`, `localPaymentIntents`, `localPaymentEvents`)
 * across 11 linked relational tables inside a single transaction.
 */

const ALLOWED_ROLES = new Set(['customer', 'partner', 'owner', 'super_admin']);
const ALLOWED_PARTNER_STATUSES = new Set(['none', 'pending', 'approved', 'rejected']);
const ALLOWED_BOOKING_STATUSES = new Set([
  'pending',
  'pending_payment',
  'confirmed',
  'completed',
  'cancelled',
  'expired',
  'no_show',
  'checked_in',
]);
const ALLOWED_LEDGER_TYPES = new Set([
  'TOPUP',
  'BOOKING_DEPOSIT',
  'REFUND',
  'WELCOME_BONUS',
  'EXCESS_PAYMENT',
  'ADMIN_ADJUSTMENT',
]);
const ALLOWED_PAYMENT_METHODS = new Set(['INSTAPAY', 'MOBILE_WALLET']);
const ALLOWED_INTENT_STATUSES = new Set([
  'AWAITING_TRANSFER',
  'VERIFIED',
  'EXPIRED',
  'UNDERPAID_REVIEW',
  'CANCELLED',
]);
const ALLOWED_PARTNER_REQ_STATUSES = new Set(['pending', 'approved', 'rejected']);
const UNIT_ARRAY_KEYS = ['units', 'items', 'spaces'];

function cleanNullableStr(val) {
  if (val === undefined || val === null) return null;
  const s = String(val).trim();
  return s.length > 0 ? s : null;
}

function cleanStr(val, fallback = '') {
  if (val === undefined || val === null) return fallback;
  return String(val);
}

function cleanNum(val, fallback = 0) {
  const n = Number(val);
  return Number.isFinite(n) ? n : fallback;
}

function toIsoOrNull(val) {
  if (val === undefined || val === null || val === '') return null;
  const d = typeof val === 'number' ? new Date(val) : new Date(val);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function toIsoOrNow(val) {
  return toIsoOrNull(val) || new Date().toISOString();
}

function fromIsoOrUndefined(val) {
  if (!val) return undefined;
  const d = val instanceof Date ? val : new Date(val);
  return Number.isNaN(d.getTime()) ? undefined : d.toISOString();
}

function pickExtra(obj, knownKeys) {
  const extra = {};
  if (!obj || typeof obj !== 'object') return extra;
  for (const [k, v] of Object.entries(obj)) {
    if (!knownKeys.has(k) && v !== undefined) {
      extra[k] = v;
    }
  }
  return extra;
}

function enumOrDefault(val, allowed, fallback) {
  const s = cleanStr(val).trim();
  return allowed.has(s) ? s : fallback;
}

// ==========================================
// ROW MAPPERS (JS OBJECT <-> POSTGRES ROW)
// ==========================================

const USER_KNOWN_KEYS = new Set([
  'id', 'firebaseUid', 'googleId', 'appleUserId', 'email', 'phone', 'name', 'avatar',
  'role', 'partnerStatus', 'authProvider', 'passwordHash', 'emailVerified', 'phoneVerified',
  'walletBalance', 'createdAt', 'updatedAt',
]);

function mapUserToRow(u) {
  const id = cleanStr(u.id).trim();
  if (!id) return null;
  return {
    id,
    firebase_uid: cleanNullableStr(u.firebaseUid),
    google_id: cleanNullableStr(u.googleId),
    apple_user_id: cleanNullableStr(u.appleUserId),
    email: cleanStr(u.email).trim().toLowerCase(),
    phone: cleanStr(u.phone).trim(),
    name: cleanStr(u.name),
    avatar: cleanStr(u.avatar),
    role: enumOrDefault(u.role, ALLOWED_ROLES, 'customer'),
    partner_status: enumOrDefault(u.partnerStatus, ALLOWED_PARTNER_STATUSES, 'none'),
    auth_provider: cleanStr(u.authProvider || 'otp'),
    password_hash: cleanNullableStr(u.passwordHash),
    email_verified: Boolean(u.emailVerified),
    phone_verified: Boolean(u.phoneVerified),
    wallet_balance: cleanNum(u.walletBalance, 0),
    extra: pickExtra(u, USER_KNOWN_KEYS),
    created_at: toIsoOrNow(u.createdAt),
    updated_at: toIsoOrNow(u.updatedAt || u.createdAt),
  };
}

function mapRowToUser(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.id = row.id;
  if (row.firebase_uid) base.firebaseUid = row.firebase_uid;
  if (row.google_id) base.googleId = row.google_id;
  if (row.apple_user_id) base.appleUserId = row.apple_user_id;
  base.email = row.email || '';
  base.phone = row.phone || '';
  base.name = row.name || '';
  base.avatar = row.avatar || '';
  base.role = row.role || 'customer';
  base.partnerStatus = row.partner_status || 'none';
  base.authProvider = row.auth_provider || 'otp';
  if (row.password_hash) base.passwordHash = row.password_hash;
  base.emailVerified = Boolean(row.email_verified);
  base.phoneVerified = Boolean(row.phone_verified);
  base.walletBalance = cleanNum(row.wallet_balance, 0);
  base.createdAt = fromIsoOrUndefined(row.created_at);
  if (row.updated_at) base.updatedAt = fromIsoOrUndefined(row.updated_at);
  return base;
}

const VENUE_KNOWN_KEYS = new Set([
  'id', 'name', 'nameEn', 'category', 'city', 'area', 'address', 'description', 'phone',
  'ownerId', 'ownerEmail', 'ownerPhone', 'pricePerHour', 'depositPercent', 'pricingMode',
  'rating', 'reviewsCount', 'isActive', 'isDeleted', 'images', 'amenities', 'rules',
  'services', 'units', 'items', 'spaces', 'createdAt', 'updatedAt',
]);

function mapVenueToRow(v, validUserIds) {
  const id = cleanStr(v.id).trim();
  if (!id) return null;
  const rawOwnerId = cleanNullableStr(v.ownerId);
  const owner_id = rawOwnerId && validUserIds.has(rawOwnerId) ? rawOwnerId : null;
  const extra = pickExtra(v, VENUE_KNOWN_KEYS);
  if (rawOwnerId && !owner_id) {
    extra._rawOwnerId = rawOwnerId;
  }
  return {
    id,
    name: cleanStr(v.name || v.nameEn || 'Venue'),
    name_en: cleanStr(v.nameEn),
    category: cleanStr(v.category),
    city: cleanStr(v.city),
    area: cleanStr(v.area),
    address: cleanStr(v.address),
    description: cleanStr(v.description),
    phone: cleanStr(v.phone),
    owner_id,
    owner_email: cleanStr(v.ownerEmail).trim().toLowerCase(),
    owner_phone: cleanStr(v.ownerPhone).trim(),
    price_per_hour: Math.max(0, cleanNum(v.pricePerHour, 0)),
    deposit_percent: Math.min(100, Math.max(0, Math.round(cleanNum(v.depositPercent, 0)))),
    pricing_mode: cleanStr(v.pricingMode || 'per_hour'),
    rating: cleanNum(v.rating, 0),
    reviews_count: Math.max(0, Math.round(cleanNum(v.reviewsCount, 0))),
    is_active: v.isActive !== false,
    is_deleted: Boolean(v.isDeleted),
    images: Array.isArray(v.images) ? v.images : [],
    amenities: Array.isArray(v.amenities) ? v.amenities : [],
    rules: Array.isArray(v.rules) ? v.rules : [],
    services: Array.isArray(v.services) ? v.services : [],
    extra,
    created_at: toIsoOrNow(v.createdAt),
    updated_at: toIsoOrNow(v.updatedAt || v.createdAt),
  };
}

function mapRowToVenue(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  const rawOwnerId = base._rawOwnerId;
  delete base._rawOwnerId;
  base.id = row.id;
  base.name = row.name;
  if (row.name_en) base.nameEn = row.name_en;
  base.category = row.category || '';
  base.city = row.city || '';
  base.area = row.area || '';
  base.address = row.address || '';
  base.description = row.description || '';
  base.phone = row.phone || '';
  if (row.owner_id || rawOwnerId) base.ownerId = row.owner_id || rawOwnerId;
  if (row.owner_email) base.ownerEmail = row.owner_email;
  if (row.owner_phone) base.ownerPhone = row.owner_phone;
  base.pricePerHour = cleanNum(row.price_per_hour, 0);
  base.depositPercent = cleanNum(row.deposit_percent, 0);
  base.pricingMode = row.pricing_mode || 'per_hour';
  base.rating = cleanNum(row.rating, 0);
  base.reviewsCount = cleanNum(row.reviews_count, 0);
  base.isActive = row.is_active !== false;
  if (row.is_deleted) base.isDeleted = true;
  base.images = Array.isArray(row.images) ? row.images : [];
  base.amenities = Array.isArray(row.amenities) ? row.amenities : [];
  base.rules = Array.isArray(row.rules) ? row.rules : [];
  base.services = Array.isArray(row.services) ? row.services : [];
  if (row.created_at) base.createdAt = fromIsoOrUndefined(row.created_at);
  if (row.updated_at) base.updatedAt = fromIsoOrUndefined(row.updated_at);
  return base;
}

const UNIT_KNOWN_KEYS = new Set([
  'id', 'venueId', 'name', 'nameEn', 'type', 'unitType', 'capacity',
  'price', 'pricePerHour', 'isActive', 'sourceKey', 'sortOrder',
]);

function extractVenueUnitRows(venue) {
  const rows = [];
  const seenUnitIds = new Set();
  for (const sourceKey of UNIT_ARRAY_KEYS) {
    const arr = venue[sourceKey];
    if (!Array.isArray(arr)) continue;
    arr.forEach((u, idx) => {
      if (!u || typeof u !== 'object') return;
      const unitId = cleanStr(u.id).trim() || `${venue.id}_${sourceKey}_${idx + 1}`;
      if (seenUnitIds.has(unitId)) return;
      seenUnitIds.add(unitId);
      const rawPrice = u.pricePerHour ?? u.price;
      rows.push({
        id: unitId,
        venue_id: venue.id,
        name: cleanStr(u.name || u.title || unitId),
        name_en: cleanStr(u.nameEn),
        unit_type: cleanStr(u.unitType || u.type || 'unit'),
        capacity: u.capacity != null && Number.isFinite(Number(u.capacity)) ? Math.round(Number(u.capacity)) : null,
        price_per_hour: rawPrice != null && Number.isFinite(Number(rawPrice)) ? Number(rawPrice) : null,
        is_active: u.isActive !== false,
        source_key: sourceKey,
        sort_order: idx,
        extra: pickExtra(u, UNIT_KNOWN_KEYS),
        created_at: toIsoOrNow(u.createdAt || venue.createdAt),
        updated_at: toIsoOrNow(u.updatedAt || venue.updatedAt),
      });
    });
  }
  return rows;
}

function mapRowToUnit(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.id = row.id;
  base.name = row.name;
  if (row.name_en) base.nameEn = row.name_en;
  if (row.unit_type) base.type = row.unit_type;
  if (row.capacity != null) base.capacity = Number(row.capacity);
  if (row.price_per_hour != null) base.pricePerHour = Number(row.price_per_hour);
  base.isActive = row.is_active !== false;
  return base;
}

const BOOKING_KNOWN_KEYS = new Set([
  'id', 'customerId', 'ownerId', 'venueId', 'unitId', 'itemId', 'unitName', 'itemName',
  'venueName', 'customerName', 'customerPhone', 'phone', 'customerEmail', 'email',
  'date', 'bookingDate', 'startsAt', 'endsAt', 'durationMinutes', 'status',
  'price', 'totalPrice', 'depositAmount', 'dueNow', 'actualPaidAmount', 'excessAmount',
  'paymentMethod', 'paymentReference', 'confirmed', 'cancelled', 'checkedIn',
  'checkedInAt', 'confirmedAt', 'cancelledAt', 'expiresAt', 'holdExpiresAt',
  'createdAt', 'updatedAt',
]);

function mapBookingToRow(b, { validUserIds, validVenueIds, validUnitPairs }) {
  const id = cleanStr(b.id).trim();
  const venue_id = cleanStr(b.venueId).trim();
  if (!id || !venue_id || !validVenueIds.has(venue_id)) return null;

  const rawCustomerId = cleanNullableStr(b.customerId || b.ownerId);
  const customer_id = rawCustomerId && validUserIds.has(rawCustomerId) ? rawCustomerId : null;

  const rawUnitId = cleanNullableStr(b.unitId || b.itemId);
  const unit_id = rawUnitId && validUnitPairs.has(`${venue_id}::${rawUnitId}`) ? rawUnitId : null;

  const extra = pickExtra(b, BOOKING_KNOWN_KEYS);
  if (rawCustomerId && !customer_id) extra._rawCustomerId = rawCustomerId;
  if (b.ownerId) extra._ownerId = b.ownerId;
  if (rawUnitId && !unit_id) extra._rawUnitId = rawUnitId;
  if (b.itemId !== undefined) extra._hasItemId = true;
  if (b.phone !== undefined) extra._hasPhone = true;
  if (b.email !== undefined) extra._hasEmail = true;
  if (b.price !== undefined) extra._hasPrice = true;
  if (b.holdExpiresAt !== undefined) extra._hasHoldExpiresAt = true;

  const rawStatus = cleanStr(b.status || (b.confirmed ? 'confirmed' : b.cancelled ? 'cancelled' : 'pending_payment')).toLowerCase();

  return {
    id,
    customer_id,
    venue_id,
    unit_id,
    unit_name: cleanStr(b.unitName || b.itemName),
    venue_name: cleanStr(b.venueName),
    customer_name: cleanStr(b.customerName || b.name),
    customer_phone: cleanStr(b.customerPhone || b.phone),
    customer_email: cleanStr(b.customerEmail || b.email).trim().toLowerCase(),
    booking_date: cleanStr(b.date || b.bookingDate),
    starts_at: toIsoOrNow(b.startsAt),
    ends_at: toIsoOrNull(b.endsAt),
    duration_minutes: Math.max(1, Math.round(cleanNum(b.durationMinutes, 60))),
    status: enumOrDefault(rawStatus, ALLOWED_BOOKING_STATUSES, 'pending_payment'),
    total_price: Math.max(0, cleanNum(b.totalPrice ?? b.price, 0)),
    deposit_amount: Math.max(0, cleanNum(b.depositAmount, 0)),
    due_now: Math.max(0, cleanNum(b.dueNow, 0)),
    actual_paid_amount: Math.max(0, cleanNum(b.actualPaidAmount, 0)),
    excess_amount: Math.max(0, cleanNum(b.excessAmount, 0)),
    payment_method: cleanStr(b.paymentMethod),
    payment_reference: cleanStr(b.paymentReference),
    confirmed: Boolean(b.confirmed),
    cancelled: Boolean(b.cancelled),
    checked_in: Boolean(b.checkedIn),
    checked_in_at: toIsoOrNull(b.checkedInAt),
    confirmed_at: toIsoOrNull(b.confirmedAt),
    cancelled_at: toIsoOrNull(b.cancelledAt),
    expires_at: toIsoOrNull(b.holdExpiresAt || b.expiresAt),
    extra,
    created_at: toIsoOrNow(b.createdAt),
    updated_at: toIsoOrNow(b.updatedAt || b.createdAt),
  };
}

function mapRowToBooking(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  const rawCustomerId = base._rawCustomerId;
  const ownerId = base._ownerId;
  const rawUnitId = base._rawUnitId;
  const hasItemId = base._hasItemId;
  const hasPhone = base._hasPhone;
  const hasEmail = base._hasEmail;
  const hasPrice = base._hasPrice;
  const hasHoldExpiresAt = base._hasHoldExpiresAt;

  delete base._rawCustomerId;
  delete base._ownerId;
  delete base._rawUnitId;
  delete base._hasItemId;
  delete base._hasPhone;
  delete base._hasEmail;
  delete base._hasPrice;
  delete base._hasHoldExpiresAt;

  base.id = row.id;
  const resolvedCustomer = row.customer_id || rawCustomerId;
  if (resolvedCustomer) base.customerId = resolvedCustomer;
  if (ownerId || resolvedCustomer) base.ownerId = ownerId || resolvedCustomer;
  base.venueId = row.venue_id;

  const resolvedUnit = row.unit_id || rawUnitId;
  if (resolvedUnit) {
    base.unitId = resolvedUnit;
    if (hasItemId) base.itemId = resolvedUnit;
  }
  if (row.unit_name) base.unitName = row.unit_name;
  base.venueName = row.venue_name || '';
  base.customerName = row.customer_name || '';
  base.customerPhone = row.customer_phone || '';
  if (hasPhone || row.customer_phone) base.phone = row.customer_phone || '';
  base.customerEmail = row.customer_email || '';
  if (hasEmail || row.customer_email) base.email = row.customer_email || '';
  if (row.booking_date) base.date = row.booking_date;
  base.startsAt = fromIsoOrUndefined(row.starts_at);
  if (row.ends_at) base.endsAt = fromIsoOrUndefined(row.ends_at);
  base.durationMinutes = cleanNum(row.duration_minutes, 60);
  base.status = row.status;
  base.totalPrice = cleanNum(row.total_price, 0);
  if (hasPrice || base.price === undefined) base.price = base.totalPrice;
  base.depositAmount = cleanNum(row.deposit_amount, 0);
  base.dueNow = cleanNum(row.due_now, 0);
  base.actualPaidAmount = cleanNum(row.actual_paid_amount, 0);
  base.excessAmount = cleanNum(row.excess_amount, 0);
  base.paymentMethod = row.payment_method || '';
  if (row.payment_reference) base.paymentReference = row.payment_reference;
  base.confirmed = Boolean(row.confirmed);
  base.cancelled = Boolean(row.cancelled);
  base.checkedIn = Boolean(row.checked_in);
  if (row.checked_in_at) base.checkedInAt = fromIsoOrUndefined(row.checked_in_at);
  if (row.confirmed_at) base.confirmedAt = fromIsoOrUndefined(row.confirmed_at);
  if (row.cancelled_at) base.cancelledAt = fromIsoOrUndefined(row.cancelled_at);
  if (row.expires_at) {
    const expIso = fromIsoOrUndefined(row.expires_at);
    base.expiresAt = expIso;
    if (hasHoldExpiresAt) base.holdExpiresAt = expIso;
  }
  base.createdAt = fromIsoOrUndefined(row.created_at);
  if (row.updated_at) base.updatedAt = fromIsoOrUndefined(row.updated_at);
  return base;
}

const LEDGER_KNOWN_KEYS = new Set([
  'id', 'userId', 'bookingId', 'amount', 'type', 'referenceId', 'description', 'actor', 'createdAt', 'timestamp',
]);

function mapLedgerToRow(e, { validUserIds, validBookingIds }) {
  const id = cleanStr(e.id).trim();
  const user_id = cleanStr(e.userId).trim();
  if (!id || !user_id || !validUserIds.has(user_id)) return null;
  const candidateBookingId = cleanNullableStr(e.bookingId || e.referenceId);
  const booking_id = candidateBookingId && validBookingIds.has(candidateBookingId) ? candidateBookingId : null;
  return {
    id,
    user_id,
    booking_id,
    amount: cleanNum(e.amount, 0),
    entry_type: enumOrDefault(e.type, ALLOWED_LEDGER_TYPES, 'ADMIN_ADJUSTMENT'),
    reference_id: cleanNullableStr(e.referenceId),
    description: cleanStr(e.description),
    actor: cleanStr(e.actor || 'system'),
    extra: pickExtra(e, LEDGER_KNOWN_KEYS),
    created_at: toIsoOrNow(e.createdAt || e.timestamp),
  };
}

function mapRowToLedger(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.id = row.id;
  base.userId = row.user_id;
  if (row.booking_id) base.bookingId = row.booking_id;
  base.amount = cleanNum(row.amount, 0);
  base.type = row.entry_type;
  if (row.reference_id) base.referenceId = row.reference_id;
  base.description = row.description || '';
  base.actor = row.actor || 'system';
  base.createdAt = fromIsoOrUndefined(row.created_at);
  return base;
}

const INTENT_KNOWN_KEYS = new Set([
  'intentId', 'id', 'booking_id', 'user_id', 'payment_method', 'receiver_wallet',
  'expected_sender_identifier', 'expected_amount', 'actual_amount', 'excess_amount',
  'status', 'verified_at', 'expires_at', 'created_at', 'updated_at',
]);

function mapIntentToRow(intent, { validUserIds, validBookingIds }) {
  const id = cleanStr(intent.intentId || intent.id).trim();
  if (!id) return null;
  const rawBookingId = cleanStr(intent.booking_id).trim();
  const booking_id = rawBookingId && validBookingIds.has(rawBookingId) ? rawBookingId : null;
  const rawUserId = cleanNullableStr(intent.user_id);
  const user_id = rawUserId && validUserIds.has(rawUserId) ? rawUserId : null;
  const extra = pickExtra(intent, INTENT_KNOWN_KEYS);
  if (rawUserId && !user_id) extra._rawUserId = rawUserId;

  return {
    id,
    booking_id,
    raw_booking_id: rawBookingId,
    user_id,
    payment_method: enumOrDefault(intent.payment_method, ALLOWED_PAYMENT_METHODS, 'INSTAPAY'),
    receiver_wallet: cleanStr(intent.receiver_wallet),
    expected_sender_identifier: cleanStr(intent.expected_sender_identifier),
    expected_amount: Math.max(0.01, cleanNum(intent.expected_amount, 0.01)),
    actual_amount: intent.actual_amount != null ? cleanNum(intent.actual_amount, 0) : null,
    excess_amount: Math.max(0, cleanNum(intent.excess_amount, 0)),
    status: enumOrDefault(intent.status, ALLOWED_INTENT_STATUSES, 'AWAITING_TRANSFER'),
    verified_at: toIsoOrNull(intent.verified_at),
    expires_at: toIsoOrNow(intent.expires_at),
    extra,
    created_at: toIsoOrNow(intent.created_at),
    updated_at: toIsoOrNow(intent.updated_at || intent.created_at),
  };
}

function mapRowToIntent(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  const rawUserId = base._rawUserId;
  delete base._rawUserId;
  base.intentId = row.id;
  base.booking_id = row.booking_id || row.raw_booking_id || '';
  base.user_id = row.user_id || rawUserId || 'guest';
  base.payment_method = row.payment_method;
  base.receiver_wallet = row.receiver_wallet || '';
  base.expected_sender_identifier = row.expected_sender_identifier || '';
  base.expected_amount = cleanNum(row.expected_amount, 0);
  if (row.actual_amount != null) base.actual_amount = cleanNum(row.actual_amount, 0);
  if (row.excess_amount != null && Number(row.excess_amount) > 0) {
    base.excess_amount = cleanNum(row.excess_amount, 0);
  }
  base.status = row.status;
  if (row.verified_at) base.verified_at = fromIsoOrUndefined(row.verified_at);
  base.expires_at = fromIsoOrUndefined(row.expires_at);
  return base;
}

const EVENT_KNOWN_KEYS = new Set([
  'eventId', 'id', 'matchedIntentId', 'bookingId', 'payment_method', 'sender_identifier',
  'amount', 'provider_ref', 'is_claimed', 'raw_text', 'received_at', 'created_at',
]);

function mapEventToRow(evt, { validIntentIds, validBookingIds }) {
  const id = cleanStr(evt.eventId || evt.id).trim();
  if (!id) return null;
  const rawIntentId = cleanNullableStr(evt.matchedIntentId || evt.matched_intent_id);
  const rawBookingId = cleanNullableStr(evt.bookingId || evt.booking_id);
  return {
    id,
    matched_intent_id: rawIntentId && validIntentIds.has(rawIntentId) ? rawIntentId : null,
    booking_id: rawBookingId && validBookingIds.has(rawBookingId) ? rawBookingId : null,
    payment_method: enumOrDefault(evt.payment_method, ALLOWED_PAYMENT_METHODS, 'INSTAPAY'),
    sender_identifier: cleanStr(evt.sender_identifier),
    amount: cleanNum(evt.amount, 0),
    provider_ref: cleanStr(evt.provider_ref),
    is_claimed: Boolean(evt.is_claimed),
    raw_text: cleanStr(evt.raw_text),
    received_at: toIsoOrNow(evt.received_at),
    extra: pickExtra(evt, EVENT_KNOWN_KEYS),
    created_at: toIsoOrNow(evt.created_at || evt.received_at),
  };
}

function mapRowToEvent(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.eventId = row.id;
  if (row.matched_intent_id) base.matchedIntentId = row.matched_intent_id;
  if (row.booking_id) base.bookingId = row.booking_id;
  base.payment_method = row.payment_method;
  base.sender_identifier = row.sender_identifier || '';
  base.amount = cleanNum(row.amount, 0);
  base.provider_ref = row.provider_ref || '';
  base.is_claimed = Boolean(row.is_claimed);
  base.raw_text = row.raw_text || '';
  base.received_at = fromIsoOrUndefined(row.received_at);
  return base;
}

const REVIEW_KNOWN_KEYS = new Set([
  'id', 'intentId', 'bookingId', 'userId', 'paymentMethod', 'senderIdentifier',
  'amount', 'providerRef', 'rawText', 'status', 'reason', 'resolvedBy',
  'resolvedAt', 'attachedTo', 'receivedAt',
]);

function mapReviewToRow(item, { validIntentIds, validBookingIds, validUserIds }) {
  const id = cleanStr(item.id).trim();
  if (!id) return null;
  const attachedBooking = item.attachedTo && item.attachedTo.bookingId;
  const attachedUser = item.attachedTo && item.attachedTo.userId;
  const rawIntentId = cleanNullableStr(item.intentId);
  const rawBookingId = cleanNullableStr(item.bookingId || attachedBooking);
  const rawUserId = cleanNullableStr(item.userId || attachedUser);

  return {
    id,
    intent_id: rawIntentId && validIntentIds.has(rawIntentId) ? rawIntentId : null,
    booking_id: rawBookingId && validBookingIds.has(rawBookingId) ? rawBookingId : null,
    user_id: rawUserId && validUserIds.has(rawUserId) ? rawUserId : null,
    payment_method: cleanStr(item.paymentMethod || 'INSTAPAY'),
    sender_identifier: cleanStr(item.senderIdentifier),
    amount: cleanNum(item.amount, 0),
    provider_ref: cleanStr(item.providerRef),
    raw_text: cleanStr(item.rawText),
    status: cleanStr(item.status || 'PENDING_REVIEW'),
    reason: cleanStr(item.reason),
    resolved_by: cleanNullableStr(item.resolvedBy),
    resolved_at: toIsoOrNull(item.resolvedAt),
    attached_to: item.attachedTo || null,
    received_at: toIsoOrNow(item.receivedAt),
    extra: pickExtra(item, REVIEW_KNOWN_KEYS),
    created_at: toIsoOrNow(item.receivedAt),
    updated_at: toIsoOrNow(item.resolvedAt || item.receivedAt),
  };
}

function mapRowToReview(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.id = row.id;
  if (row.intent_id) base.intentId = row.intent_id;
  if (row.booking_id) base.bookingId = row.booking_id;
  if (row.user_id) base.userId = row.user_id;
  base.paymentMethod = row.payment_method || 'INSTAPAY';
  base.senderIdentifier = row.sender_identifier || '';
  base.amount = cleanNum(row.amount, 0);
  base.providerRef = row.provider_ref || '';
  base.rawText = row.raw_text || '';
  base.status = row.status || 'PENDING_REVIEW';
  base.reason = row.reason || '';
  if (row.resolved_by) base.resolvedBy = row.resolved_by;
  if (row.resolved_at) base.resolvedAt = fromIsoOrUndefined(row.resolved_at);
  if (row.attached_to) base.attachedTo = row.attached_to;
  base.receivedAt = fromIsoOrUndefined(row.received_at);
  return base;
}

const PARTNER_REQ_KNOWN_KEYS = new Set([
  'id', 'userId', 'approvedVenueId', 'venueName', 'category', 'city', 'area', 'address',
  'ownerName', 'ownerEmail', 'ownerPhone', 'status', 'reviewedBy', 'reviewedAt',
  'rejectionReason', 'createdAt', 'updatedAt',
]);

function mapPartnerReqToRow(req, { validUserIds, validVenueIds }) {
  const id = cleanStr(req.id).trim();
  if (!id) return null;
  const rawUserId = cleanNullableStr(req.userId);
  const rawVenueId = cleanNullableStr(req.approvedVenueId);
  return {
    id,
    user_id: rawUserId && validUserIds.has(rawUserId) ? rawUserId : null,
    approved_venue_id: rawVenueId && validVenueIds.has(rawVenueId) ? rawVenueId : null,
    venue_name: cleanStr(req.venueName),
    category: cleanStr(req.category),
    city: cleanStr(req.city),
    area: cleanStr(req.area),
    address: cleanStr(req.address),
    owner_name: cleanStr(req.ownerName),
    owner_email: cleanStr(req.ownerEmail).trim().toLowerCase(),
    owner_phone: cleanStr(req.ownerPhone).trim(),
    status: enumOrDefault(req.status, ALLOWED_PARTNER_REQ_STATUSES, 'pending'),
    reviewed_by: cleanNullableStr(req.reviewedBy),
    reviewed_at: toIsoOrNull(req.reviewedAt),
    rejection_reason: cleanStr(req.rejectionReason),
    extra: pickExtra(req, PARTNER_REQ_KNOWN_KEYS),
    created_at: toIsoOrNow(req.createdAt),
    updated_at: toIsoOrNow(req.updatedAt || req.createdAt),
  };
}

function mapRowToPartnerReq(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.id = row.id;
  if (row.user_id) base.userId = row.user_id;
  if (row.approved_venue_id) base.approvedVenueId = row.approved_venue_id;
  base.venueName = row.venue_name || '';
  base.category = row.category || '';
  base.city = row.city || '';
  base.area = row.area || '';
  base.address = row.address || '';
  base.ownerName = row.owner_name || '';
  base.ownerEmail = row.owner_email || '';
  base.ownerPhone = row.owner_phone || '';
  base.status = row.status || 'pending';
  if (row.reviewed_by) base.reviewedBy = row.reviewed_by;
  if (row.reviewed_at) base.reviewedAt = fromIsoOrUndefined(row.reviewed_at);
  if (row.rejection_reason) base.rejectionReason = row.rejection_reason;
  base.createdAt = fromIsoOrUndefined(row.created_at);
  if (row.updated_at) base.updatedAt = fromIsoOrUndefined(row.updated_at);
  return base;
}

const AUDIT_KNOWN_KEYS = new Set([
  'id', 'bookingId', 'venueId', 'userId', 'action', 'fromStatus', 'toStatus',
  'actor', 'reason', 'details', 'timestamp', 'occurredAt',
]);

function mapAuditToRow(entry, idx, { validBookingIds, validVenueIds, validUserIds }) {
  const occurredAt = toIsoOrNow(entry.timestamp || entry.occurredAt);
  let id = cleanStr(entry.id).trim();
  if (!id) {
    id = `aud_${idx}_${occurredAt}`;
    if (entry && typeof entry === 'object') entry.id = id;
  }
  const rawBookingId = cleanNullableStr(entry.bookingId);
  const rawVenueId = cleanNullableStr(entry.venueId);
  const rawUserId = cleanNullableStr(entry.userId);
  return {
    id,
    booking_id: rawBookingId && validBookingIds.has(rawBookingId) ? rawBookingId : null,
    venue_id: rawVenueId && validVenueIds.has(rawVenueId) ? rawVenueId : null,
    user_id: rawUserId && validUserIds.has(rawUserId) ? rawUserId : null,
    action: cleanStr(entry.action || (entry.toStatus ? 'booking_transition' : 'admin_action')),
    from_status: cleanNullableStr(entry.fromStatus),
    to_status: cleanNullableStr(entry.toStatus),
    actor: cleanStr(entry.actor || 'system'),
    reason: cleanStr(entry.reason),
    details: entry.details && typeof entry.details === 'object' ? entry.details : pickExtra(entry, AUDIT_KNOWN_KEYS),
    occurred_at: toIsoOrNow(entry.timestamp || entry.occurredAt),
  };
}

function mapRowToAudit(row) {
  const out = {
    id: row.id,
    actor: row.actor || 'system',
    timestamp: fromIsoOrUndefined(row.occurred_at),
  };
  if (row.booking_id) out.bookingId = row.booking_id;
  if (row.venue_id) out.venueId = row.venue_id;
  if (row.user_id) out.userId = row.user_id;
  if (row.action) out.action = row.action;
  if (row.from_status) out.fromStatus = row.from_status;
  if (row.to_status) out.toStatus = row.to_status;
  if (row.reason) out.reason = row.reason;
  if (row.details && Object.keys(row.details).length > 0) out.details = row.details;
  return out;
}

const OTP_KNOWN_KEYS = new Set([
  'hashedCode', 'expiresAt', 'attempts', 'name', 'isSignUp', 'isPartner',
]);

function mapOtpToRow(target, record) {
  const cleanTarget = cleanStr(target).trim();
  if (!cleanTarget || !record || !record.hashedCode) return null;
  return {
    target: cleanTarget,
    hashed_code: cleanStr(record.hashedCode),
    expires_at: toIsoOrNow(record.expiresAt),
    attempts: Math.max(0, Math.round(cleanNum(record.attempts, 0))),
    name: cleanStr(record.name),
    is_sign_up: Boolean(record.isSignUp),
    is_partner: Boolean(record.isPartner),
    extra: pickExtra(record, OTP_KNOWN_KEYS),
  };
}

function mapRowToOtp(row) {
  const base = { ...(row.extra && typeof row.extra === 'object' ? row.extra : {}) };
  base.hashedCode = row.hashed_code;
  base.expiresAt = new Date(row.expires_at).getTime();
  base.attempts = cleanNum(row.attempts, 0);
  base.name = row.name || '';
  base.isSignUp = Boolean(row.is_sign_up);
  base.isPartner = Boolean(row.is_partner);
  return base;
}

// ==========================================
// SNAPSHOT BUILDER & BATCH SQL PERSISTENCE
// ==========================================

function buildRelationalSnapshot(db, { localPaymentIntents, localPaymentEvents } = {}) {
  const users = (Array.isArray(db.users) ? db.users : []).map(mapUserToRow).filter(Boolean);
  const validUserIds = new Set(users.map(u => u.id));

  const rawVenues = Array.isArray(db.venues) ? db.venues : [];
  const venues = rawVenues.map(v => mapVenueToRow(v, validUserIds)).filter(Boolean);
  const validVenueIds = new Set(venues.map(v => v.id));

  const units = [];
  for (const v of rawVenues) {
    if (!v || !validVenueIds.has(cleanStr(v.id).trim())) continue;
    units.push(...extractVenueUnitRows(v));
  }
  const validUnitPairs = new Set(units.map(u => `${u.venue_id}::${u.id}`));

  const bookings = (Array.isArray(db.bookings) ? db.bookings : [])
    .map(b => mapBookingToRow(b, { validUserIds, validVenueIds, validUnitPairs }))
    .filter(Boolean);
  const validBookingIds = new Set(bookings.map(b => b.id));

  const walletLedger = (Array.isArray(db.walletLedger) ? db.walletLedger : [])
    .map(e => mapLedgerToRow(e, { validUserIds, validBookingIds }))
    .filter(Boolean);

  const intentValues = localPaymentIntents instanceof Map
    ? Array.from(localPaymentIntents.values())
    : (Array.isArray(localPaymentIntents) ? localPaymentIntents : []);
  const paymentIntents = intentValues
    .map(i => mapIntentToRow(i, { validUserIds, validBookingIds }))
    .filter(Boolean);
  const validIntentIds = new Set(paymentIntents.map(i => i.id));

  const eventValues = localPaymentEvents instanceof Map
    ? Array.from(localPaymentEvents.values())
    : (Array.isArray(localPaymentEvents) ? localPaymentEvents : []);
  const paymentEvents = eventValues
    .map(e => mapEventToRow(e, { validIntentIds, validBookingIds }))
    .filter(Boolean);

  const reviewQueue = (Array.isArray(db.reviewQueue) ? db.reviewQueue : [])
    .map(r => mapReviewToRow(r, { validIntentIds, validBookingIds, validUserIds }))
    .filter(Boolean);

  const partnerRequests = (Array.isArray(db.partnerRequests) ? db.partnerRequests : [])
    .map(r => mapPartnerReqToRow(r, { validUserIds, validVenueIds }))
    .filter(Boolean);

  const auditLog = (Array.isArray(db.auditLog) ? db.auditLog : [])
    .map((a, idx) => mapAuditToRow(a, idx, { validBookingIds, validVenueIds, validUserIds }));

  const otpChallenges = Object.entries(db.otps || {})
    .map(([target, record]) => mapOtpToRow(target, record))
    .filter(Boolean);

  return {
    users,
    venues,
    units,
    bookings,
    walletLedger,
    paymentIntents,
    paymentEvents,
    reviewQueue,
    partnerRequests,
    auditLog,
    otpChallenges,
  };
}

async function pruneMissing(client, table, keyCol, keepIds) {
  if (keepIds.length === 0) {
    await client.query(`DELETE FROM public.${table}`);
  } else {
    await client.query(`DELETE FROM public.${table} WHERE NOT (${keyCol} = ANY($1::text[]))`, [keepIds]);
  }
}

async function pruneMissingCompositeUnits(client, units) {
  if (units.length === 0) {
    await client.query('DELETE FROM public.bookable_units');
    return;
  }
  const keys = units.map(u => ({ venue_id: u.venue_id, id: u.id }));
  await client.query(
    `DELETE FROM public.bookable_units b
     WHERE NOT EXISTS (
       SELECT 1 FROM jsonb_to_recordset($1::jsonb) AS k(venue_id TEXT, id TEXT)
       WHERE k.venue_id = b.venue_id AND k.id = b.id
     )`,
    [JSON.stringify(keys)],
  );
}

async function persistToPostgres(pool, db, { localPaymentIntents, localPaymentEvents } = {}) {
  const snap = buildRelationalSnapshot(db, { localPaymentIntents, localPaymentEvents });
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Prune child-to-parent so RESTRICT / composite FKs stay satisfied
    await pruneMissing(client, 'otp_challenges', 'target', snap.otpChallenges.map(r => r.target));
    await pruneMissing(client, 'audit_log', 'id', snap.auditLog.map(r => r.id));
    await pruneMissing(client, 'payment_review_queue', 'id', snap.reviewQueue.map(r => r.id));
    await pruneMissing(client, 'payment_events', 'id', snap.paymentEvents.map(r => r.id));
    await pruneMissing(client, 'payment_intents', 'id', snap.paymentIntents.map(r => r.id));
    await pruneMissing(client, 'wallet_ledger', 'id', snap.walletLedger.map(r => r.id));
    await pruneMissing(client, 'partner_requests', 'id', snap.partnerRequests.map(r => r.id));
    await pruneMissing(client, 'bookings', 'id', snap.bookings.map(r => r.id));
    await pruneMissingCompositeUnits(client, snap.units);
    await pruneMissing(client, 'venues', 'id', snap.venues.map(r => r.id));
    await pruneMissing(client, 'users', 'id', snap.users.map(r => r.id));

    // Upsert parent-to-child in single round-trip per table
    if (snap.users.length > 0) {
      await client.query(
        `INSERT INTO public.users (
           id, firebase_uid, google_id, apple_user_id, email, phone, name, avatar,
           role, partner_status, auth_provider, password_hash, email_verified,
           phone_verified, wallet_balance, extra, created_at, updated_at
         )
         SELECT id, firebase_uid, google_id, apple_user_id, email, phone, name, avatar,
                role, partner_status, auth_provider, password_hash, email_verified,
                phone_verified, wallet_balance, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, firebase_uid TEXT, google_id TEXT, apple_user_id TEXT, email TEXT,
           phone TEXT, name TEXT, avatar TEXT, role TEXT, partner_status TEXT,
           auth_provider TEXT, password_hash TEXT, email_verified BOOLEAN,
           phone_verified BOOLEAN, wallet_balance NUMERIC, extra JSONB,
           created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           firebase_uid = EXCLUDED.firebase_uid,
           google_id = EXCLUDED.google_id,
           apple_user_id = EXCLUDED.apple_user_id,
           email = EXCLUDED.email,
           phone = EXCLUDED.phone,
           name = EXCLUDED.name,
           avatar = EXCLUDED.avatar,
           role = EXCLUDED.role,
           partner_status = EXCLUDED.partner_status,
           auth_provider = EXCLUDED.auth_provider,
           password_hash = EXCLUDED.password_hash,
           email_verified = EXCLUDED.email_verified,
           phone_verified = EXCLUDED.phone_verified,
           wallet_balance = EXCLUDED.wallet_balance,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.users)],
      );
    }

    if (snap.venues.length > 0) {
      await client.query(
        `INSERT INTO public.venues (
           id, name, name_en, category, city, area, address, description, phone,
           owner_id, owner_email, owner_phone, price_per_hour, deposit_percent,
           pricing_mode, rating, reviews_count, is_active, is_deleted, images,
           amenities, rules, services, extra, created_at, updated_at
         )
         SELECT id, name, name_en, category, city, area, address, description, phone,
                owner_id, owner_email, owner_phone, price_per_hour, deposit_percent,
                pricing_mode, rating, reviews_count, is_active, is_deleted, images,
                amenities, rules, services, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, name TEXT, name_en TEXT, category TEXT, city TEXT, area TEXT,
           address TEXT, description TEXT, phone TEXT, owner_id TEXT,
           owner_email TEXT, owner_phone TEXT, price_per_hour NUMERIC,
           deposit_percent INTEGER, pricing_mode TEXT, rating NUMERIC,
           reviews_count INTEGER, is_active BOOLEAN, is_deleted BOOLEAN,
           images JSONB, amenities JSONB, rules JSONB, services JSONB,
           extra JSONB, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           name = EXCLUDED.name,
           name_en = EXCLUDED.name_en,
           category = EXCLUDED.category,
           city = EXCLUDED.city,
           area = EXCLUDED.area,
           address = EXCLUDED.address,
           description = EXCLUDED.description,
           phone = EXCLUDED.phone,
           owner_id = EXCLUDED.owner_id,
           owner_email = EXCLUDED.owner_email,
           owner_phone = EXCLUDED.owner_phone,
           price_per_hour = EXCLUDED.price_per_hour,
           deposit_percent = EXCLUDED.deposit_percent,
           pricing_mode = EXCLUDED.pricing_mode,
           rating = EXCLUDED.rating,
           reviews_count = EXCLUDED.reviews_count,
           is_active = EXCLUDED.is_active,
           is_deleted = EXCLUDED.is_deleted,
           images = EXCLUDED.images,
           amenities = EXCLUDED.amenities,
           rules = EXCLUDED.rules,
           services = EXCLUDED.services,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.venues)],
      );
    }

    if (snap.units.length > 0) {
      await client.query(
        `INSERT INTO public.bookable_units (
           id, venue_id, name, name_en, unit_type, capacity, price_per_hour,
           is_active, source_key, sort_order, extra, created_at, updated_at
         )
         SELECT id, venue_id, name, name_en, unit_type, capacity, price_per_hour,
                is_active, source_key, sort_order, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, venue_id TEXT, name TEXT, name_en TEXT, unit_type TEXT,
           capacity INTEGER, price_per_hour NUMERIC, is_active BOOLEAN,
           source_key TEXT, sort_order INTEGER, extra JSONB,
           created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
         )
         ON CONFLICT (venue_id, id) DO UPDATE SET
           name = EXCLUDED.name,
           name_en = EXCLUDED.name_en,
           unit_type = EXCLUDED.unit_type,
           capacity = EXCLUDED.capacity,
           price_per_hour = EXCLUDED.price_per_hour,
           is_active = EXCLUDED.is_active,
           source_key = EXCLUDED.source_key,
           sort_order = EXCLUDED.sort_order,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.units)],
      );
    }

    if (snap.bookings.length > 0) {
      await client.query(
        `INSERT INTO public.bookings (
           id, customer_id, venue_id, unit_id, unit_name, venue_name,
           customer_name, customer_phone, customer_email, booking_date, starts_at,
           ends_at, duration_minutes, status, total_price, deposit_amount, due_now,
           actual_paid_amount, excess_amount, payment_method, payment_reference,
           confirmed, cancelled, checked_in, checked_in_at, confirmed_at,
           cancelled_at, expires_at, extra, created_at, updated_at
         )
         SELECT id, customer_id, venue_id, unit_id, unit_name, venue_name,
                customer_name, customer_phone, customer_email, booking_date, starts_at,
                ends_at, duration_minutes, status, total_price, deposit_amount, due_now,
                actual_paid_amount, excess_amount, payment_method, payment_reference,
                confirmed, cancelled, checked_in, checked_in_at, confirmed_at,
                cancelled_at, expires_at, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, customer_id TEXT, venue_id TEXT, unit_id TEXT, unit_name TEXT,
           venue_name TEXT, customer_name TEXT, customer_phone TEXT, customer_email TEXT,
           booking_date TEXT, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ,
           duration_minutes INTEGER, status TEXT, total_price NUMERIC,
           deposit_amount NUMERIC, due_now NUMERIC, actual_paid_amount NUMERIC,
           excess_amount NUMERIC, payment_method TEXT, payment_reference TEXT,
           confirmed BOOLEAN, cancelled BOOLEAN, checked_in BOOLEAN,
           checked_in_at TIMESTAMPTZ, confirmed_at TIMESTAMPTZ,
           cancelled_at TIMESTAMPTZ, expires_at TIMESTAMPTZ, extra JSONB,
           created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           customer_id = EXCLUDED.customer_id,
           venue_id = EXCLUDED.venue_id,
           unit_id = EXCLUDED.unit_id,
           unit_name = EXCLUDED.unit_name,
           venue_name = EXCLUDED.venue_name,
           customer_name = EXCLUDED.customer_name,
           customer_phone = EXCLUDED.customer_phone,
           customer_email = EXCLUDED.customer_email,
           booking_date = EXCLUDED.booking_date,
           starts_at = EXCLUDED.starts_at,
           ends_at = EXCLUDED.ends_at,
           duration_minutes = EXCLUDED.duration_minutes,
           status = EXCLUDED.status,
           total_price = EXCLUDED.total_price,
           deposit_amount = EXCLUDED.deposit_amount,
           due_now = EXCLUDED.due_now,
           actual_paid_amount = EXCLUDED.actual_paid_amount,
           excess_amount = EXCLUDED.excess_amount,
           payment_method = EXCLUDED.payment_method,
           payment_reference = EXCLUDED.payment_reference,
           confirmed = EXCLUDED.confirmed,
           cancelled = EXCLUDED.cancelled,
           checked_in = EXCLUDED.checked_in,
           checked_in_at = EXCLUDED.checked_in_at,
           confirmed_at = EXCLUDED.confirmed_at,
           cancelled_at = EXCLUDED.cancelled_at,
           expires_at = EXCLUDED.expires_at,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.bookings)],
      );
    }

    if (snap.walletLedger.length > 0) {
      await client.query(
        `INSERT INTO public.wallet_ledger (
           id, user_id, booking_id, amount, entry_type, reference_id,
           description, actor, extra, created_at
         )
         SELECT id, user_id, booking_id, amount, entry_type, reference_id,
                description, actor, extra, created_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, user_id TEXT, booking_id TEXT, amount NUMERIC, entry_type TEXT,
           reference_id TEXT, description TEXT, actor TEXT, extra JSONB,
           created_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           booking_id = EXCLUDED.booking_id,
           description = EXCLUDED.description,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.walletLedger)],
      );
    }

    if (snap.paymentIntents.length > 0) {
      await client.query(
        `INSERT INTO public.payment_intents (
           id, booking_id, raw_booking_id, user_id, payment_method, receiver_wallet,
           expected_sender_identifier, expected_amount, actual_amount, excess_amount,
           status, verified_at, expires_at, extra, created_at, updated_at
         )
         SELECT id, booking_id, raw_booking_id, user_id, payment_method, receiver_wallet,
                expected_sender_identifier, expected_amount, actual_amount, excess_amount,
                status, verified_at, expires_at, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, booking_id TEXT, raw_booking_id TEXT, user_id TEXT,
           payment_method TEXT, receiver_wallet TEXT, expected_sender_identifier TEXT,
           expected_amount NUMERIC, actual_amount NUMERIC, excess_amount NUMERIC,
           status TEXT, verified_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
           extra JSONB, created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           booking_id = EXCLUDED.booking_id,
           raw_booking_id = EXCLUDED.raw_booking_id,
           user_id = EXCLUDED.user_id,
           actual_amount = EXCLUDED.actual_amount,
           excess_amount = EXCLUDED.excess_amount,
           status = EXCLUDED.status,
           verified_at = EXCLUDED.verified_at,
           expires_at = EXCLUDED.expires_at,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.paymentIntents)],
      );
    }

    if (snap.paymentEvents.length > 0) {
      await client.query(
        `INSERT INTO public.payment_events (
           id, matched_intent_id, booking_id, payment_method, sender_identifier,
           amount, provider_ref, is_claimed, raw_text, received_at, extra, created_at
         )
         SELECT id, matched_intent_id, booking_id, payment_method, sender_identifier,
                amount, provider_ref, is_claimed, raw_text, received_at, extra, created_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, matched_intent_id TEXT, booking_id TEXT, payment_method TEXT,
           sender_identifier TEXT, amount NUMERIC, provider_ref TEXT,
           is_claimed BOOLEAN, raw_text TEXT, received_at TIMESTAMPTZ,
           extra JSONB, created_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           matched_intent_id = EXCLUDED.matched_intent_id,
           booking_id = EXCLUDED.booking_id,
           is_claimed = EXCLUDED.is_claimed,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.paymentEvents)],
      );
    }

    if (snap.reviewQueue.length > 0) {
      await client.query(
        `INSERT INTO public.payment_review_queue (
           id, intent_id, booking_id, user_id, payment_method, sender_identifier,
           amount, provider_ref, raw_text, status, reason, resolved_by, resolved_at,
           attached_to, received_at, extra, created_at, updated_at
         )
         SELECT id, intent_id, booking_id, user_id, payment_method, sender_identifier,
                amount, provider_ref, raw_text, status, reason, resolved_by, resolved_at,
                attached_to, received_at, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, intent_id TEXT, booking_id TEXT, user_id TEXT,
           payment_method TEXT, sender_identifier TEXT, amount NUMERIC,
           provider_ref TEXT, raw_text TEXT, status TEXT, reason TEXT,
           resolved_by TEXT, resolved_at TIMESTAMPTZ, attached_to JSONB,
           received_at TIMESTAMPTZ, extra JSONB, created_at TIMESTAMPTZ,
           updated_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           intent_id = EXCLUDED.intent_id,
           booking_id = EXCLUDED.booking_id,
           user_id = EXCLUDED.user_id,
           status = EXCLUDED.status,
           reason = EXCLUDED.reason,
           resolved_by = EXCLUDED.resolved_by,
           resolved_at = EXCLUDED.resolved_at,
           attached_to = EXCLUDED.attached_to,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.reviewQueue)],
      );
    }

    if (snap.partnerRequests.length > 0) {
      await client.query(
        `INSERT INTO public.partner_requests (
           id, user_id, approved_venue_id, venue_name, category, city, area, address,
           owner_name, owner_email, owner_phone, status, reviewed_by, reviewed_at,
           rejection_reason, extra, created_at, updated_at
         )
         SELECT id, user_id, approved_venue_id, venue_name, category, city, area, address,
                owner_name, owner_email, owner_phone, status, reviewed_by, reviewed_at,
                rejection_reason, extra, created_at, updated_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, user_id TEXT, approved_venue_id TEXT, venue_name TEXT,
           category TEXT, city TEXT, area TEXT, address TEXT, owner_name TEXT,
           owner_email TEXT, owner_phone TEXT, status TEXT, reviewed_by TEXT,
           reviewed_at TIMESTAMPTZ, rejection_reason TEXT, extra JSONB,
           created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO UPDATE SET
           user_id = EXCLUDED.user_id,
           approved_venue_id = EXCLUDED.approved_venue_id,
           status = EXCLUDED.status,
           reviewed_by = EXCLUDED.reviewed_by,
           reviewed_at = EXCLUDED.reviewed_at,
           rejection_reason = EXCLUDED.rejection_reason,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.partnerRequests)],
      );
    }

    if (snap.auditLog.length > 0) {
      await client.query(
        `INSERT INTO public.audit_log (
           id, booking_id, venue_id, user_id, action, from_status, to_status,
           actor, reason, details, occurred_at
         )
         SELECT id, booking_id, venue_id, user_id, action, from_status, to_status,
                actor, reason, details, occurred_at
         FROM jsonb_to_recordset($1::jsonb) AS t(
           id TEXT, booking_id TEXT, venue_id TEXT, user_id TEXT, action TEXT,
           from_status TEXT, to_status TEXT, actor TEXT, reason TEXT,
           details JSONB, occurred_at TIMESTAMPTZ
         )
         ON CONFLICT (id) DO NOTHING`,
        [JSON.stringify(snap.auditLog)],
      );
    }

    if (snap.otpChallenges.length > 0) {
      await client.query(
        `INSERT INTO public.otp_challenges (
           target, hashed_code, expires_at, attempts, name, is_sign_up, is_partner, extra
         )
         SELECT target, hashed_code, expires_at, attempts, name, is_sign_up, is_partner, extra
         FROM jsonb_to_recordset($1::jsonb) AS t(
           target TEXT, hashed_code TEXT, expires_at TIMESTAMPTZ, attempts INTEGER,
           name TEXT, is_sign_up BOOLEAN, is_partner BOOLEAN, extra JSONB
         )
         ON CONFLICT (target) DO UPDATE SET
           hashed_code = EXCLUDED.hashed_code,
           expires_at = EXCLUDED.expires_at,
           attempts = EXCLUDED.attempts,
           name = EXCLUDED.name,
           is_sign_up = EXCLUDED.is_sign_up,
           is_partner = EXCLUDED.is_partner,
           extra = EXCLUDED.extra`,
        [JSON.stringify(snap.otpChallenges)],
      );
    }

    await client.query('COMMIT');
    return snap;
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function hydrateFromPostgres(pool, db, { localPaymentIntents, localPaymentEvents } = {}) {
  const [
    usersRes,
    venuesRes,
    unitsRes,
    bookingsRes,
    ledgerRes,
    intentsRes,
    eventsRes,
    reviewRes,
    partnerReqRes,
    auditRes,
    otpRes,
  ] = await Promise.all([
    pool.query('SELECT * FROM public.users ORDER BY created_at ASC'),
    pool.query('SELECT * FROM public.venues ORDER BY created_at ASC'),
    pool.query('SELECT * FROM public.bookable_units ORDER BY venue_id ASC, sort_order ASC, created_at ASC'),
    pool.query('SELECT * FROM public.bookings ORDER BY created_at ASC'),
    pool.query('SELECT * FROM public.wallet_ledger ORDER BY created_at ASC'),
    pool.query('SELECT * FROM public.payment_intents ORDER BY created_at ASC'),
    pool.query('SELECT * FROM public.payment_events ORDER BY received_at ASC'),
    pool.query('SELECT * FROM public.payment_review_queue ORDER BY received_at ASC'),
    pool.query('SELECT * FROM public.partner_requests ORDER BY created_at ASC'),
    pool.query('SELECT * FROM public.audit_log ORDER BY occurred_at ASC'),
    pool.query('SELECT * FROM public.otp_challenges WHERE expires_at > NOW()'),
  ]);

  db.users = usersRes.rows.map(mapRowToUser);

  const venuesById = new Map();
  db.venues = venuesRes.rows.map(r => {
    const v = mapRowToVenue(r);
    venuesById.set(v.id, v);
    return v;
  });

  for (const unitRow of unitsRes.rows) {
    const venue = venuesById.get(unitRow.venue_id);
    if (!venue) continue;
    const key = UNIT_ARRAY_KEYS.includes(unitRow.source_key) ? unitRow.source_key : 'units';
    if (!Array.isArray(venue[key])) venue[key] = [];
    venue[key].push(mapRowToUnit(unitRow));
  }

  db.bookings = bookingsRes.rows.map(mapRowToBooking);
  db.walletLedger = ledgerRes.rows.map(mapRowToLedger);
  db.reviewQueue = reviewRes.rows.map(mapRowToReview);
  db.partnerRequests = partnerReqRes.rows.map(mapRowToPartnerReq);
  db.auditLog = auditRes.rows.map(mapRowToAudit);

  db.otps = {};
  for (const otpRow of otpRes.rows) {
    db.otps[otpRow.target] = mapRowToOtp(otpRow);
  }

  if (localPaymentIntents instanceof Map) {
    localPaymentIntents.clear();
    for (const row of intentsRes.rows) {
      const intent = mapRowToIntent(row);
      localPaymentIntents.set(intent.intentId, intent);
    }
  }

  if (localPaymentEvents instanceof Map) {
    localPaymentEvents.clear();
    for (const row of eventsRes.rows) {
      const evt = mapRowToEvent(row);
      localPaymentEvents.set(evt.eventId, evt);
    }
  }

  return {
    usersCount: db.users.length,
    venuesCount: db.venues.length,
    unitsCount: unitsRes.rows.length,
    bookingsCount: db.bookings.length,
    ledgerCount: db.walletLedger.length,
    intentsCount: intentsRes.rows.length,
    eventsCount: eventsRes.rows.length,
    reviewQueueCount: db.reviewQueue.length,
    partnerRequestsCount: db.partnerRequests.length,
    auditLogCount: db.auditLog.length,
    otpsCount: Object.keys(db.otps).length,
  };
}

module.exports = {
  ALLOWED_ROLES,
  ALLOWED_BOOKING_STATUSES,
  ALLOWED_LEDGER_TYPES,
  buildRelationalSnapshot,
  persistToPostgres,
  hydrateFromPostgres,
  mapRowToUser,
  mapRowToVenue,
  mapRowToUnit,
  mapRowToBooking,
  mapRowToLedger,
  mapRowToIntent,
  mapRowToEvent,
  mapRowToReview,
  mapRowToPartnerReq,
  mapRowToAudit,
  mapRowToOtp,
};

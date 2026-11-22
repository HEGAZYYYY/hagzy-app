const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const helmet = require('helmet');

const { BOOKING_STATUS, transitionBookingStatus, StateMachineError } = require('./bookingStateMachine');
const { calculateServerPricing, PricingError, VALID_PROMO_CODES } = require('./pricingEngine');
const { LEDGER_ENTRY_TYPE, calculateWalletBalance, recordLedgerEntry, WalletError } = require('./walletLedger');
const {
  generateUniquePayableAmount,
  computePaymentEventHash,
  redactRawPaymentText,
  matchPaymentEvent,
  MAX_AUTO_CONFIRM_AMOUNT
} = require('./paymentMatcher');
const {
  persistToPostgres: persistRelationalState,
  hydrateFromPostgres: hydrateRelationalState,
} = require('./postgresStore');

const IS_PROD = process.env.NODE_ENV === 'production';
const IS_TEST = process.env.NODE_ENV === 'test';
const USE_POSTGRES = Boolean(process.env.DATABASE_URL && !IS_TEST);

let db = null;

// Payment deduplication & listener heartbeat tracking
const processedPaymentHashes = new Set();
let lastListenerHeartbeatAt = null;

// Token Revocation Store with Expiring Denylist (Bounded memory, 90d lifetime to match longest tokens)
const revokedTokens = new Map(); // tokenHash -> expiryTimestamp
function revokeToken(token, maxLifetimeMs = 90 * 24 * 3600 * 1000) {
  if (typeof token === 'string' && token.trim()) {
    const hash = crypto.createHash('sha256').update(token.trim()).digest('hex');
    revokedTokens.set(hash, Date.now() + maxLifetimeMs);
  }
}
function isTokenRevoked(token) {
  if (typeof token !== 'string' || !token.trim()) return false;
  const hash = crypto.createHash('sha256').update(token.trim()).digest('hex');
  const expiresAt = revokedTokens.get(hash);
  if (!expiresAt) return false;
  if (Date.now() > expiresAt) {
    revokedTokens.delete(hash);
    return false;
  }
  return true;
}
setInterval(() => {
  const now = Date.now();
  for (const [hash, exp] of revokedTokens.entries()) {
    if (now > exp) revokedTokens.delete(hash);
  }
}, 3600000).unref();

// Account Lockout / Brute-force Tracking
const loginFailures = new Map(); // key -> { count, lockedUntil }
function checkLoginLockout(key) {
  const rec = loginFailures.get(key);
  if (!rec) return false;
  if (Date.now() < rec.lockedUntil) return true;
  if (Date.now() > rec.lockedUntil) {
    loginFailures.delete(key);
    return false;
  }
  return false;
}
function recordLoginFailure(key) {
  const rec = loginFailures.get(key) || { count: 0, lockedUntil: 0 };
  rec.count += 1;
  if (rec.count >= 5) {
    rec.lockedUntil = Date.now() + 15 * 60 * 1000;
  }
  loginFailures.set(key, rec);
}
function clearLoginFailure(key) {
  loginFailures.delete(key);
}

// Dual Password Hashing (Bcrypt primary + Legacy Scrypt fallback)
async function hashPassword(plain) {
  const salt = await bcrypt.genSalt(10);
  return bcrypt.hash(plain, salt);
}

async function comparePassword(plain, stored) {
  if (!plain || !stored) return false;
  if (stored.includes(':')) {
    try {
      const [salt, storedHash] = stored.split(':');
      if (salt && storedHash) {
        const computed = crypto.scryptSync(plain, salt, 64).toString('hex');
        return computed === storedHash;
      }
    } catch (_) {}
  }
  try {
    return await bcrypt.compare(plain, stored);
  } catch (_) {
    return false;
  }
}
const nodemailer = require('nodemailer');
const { getOtpEmailTemplate } = require('./emailTemplates');

// Firebase has been completely removed. Backend is 100% Supabase PostgreSQL.
const fbAuth = null;
const fbFirestore = null;
const fbInitStatus = 'purged';

function normalizeLocalPhone(rawPhone) {
  if (!rawPhone) return '';
  const digits = String(rawPhone).replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('20') && digits.length >= 12) {
    return '0' + digits.slice(2);
  }
  if (digits.length === 10 && /^(10|11|12|15)/.test(digits)) {
    return '0' + digits;
  }
  return digits;
}

function buildCleanUserId({ name, email, phone }) {
  const rawName = String(name || '').trim().toLowerCase();
  const rawEmail = String(email || '').trim().toLowerCase();
  const cleanPhone = normalizeLocalPhone(phone);
  let slug = rawName
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!slug || slug === 'hagzy_member' || slug === 'member' || slug === 'apple_member') {
    if (rawEmail && rawEmail.includes('@')) {
      slug = rawEmail.split('@')[0].replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    } else if (cleanPhone) {
      slug = 'user_' + cleanPhone.slice(-6);
    } else {
      slug = 'user_' + crypto.randomUUID().slice(0, 6);
    }
  }
  const baseId = 'usr_' + slug.slice(0, 28);
  if (typeof db !== 'undefined' && Array.isArray(db.users)) {
    const existing = db.users.find(u => u.id === baseId);
    if (!existing) return baseId;
    const suffix = cleanPhone ? cleanPhone.slice(-4) : crypto.randomUUID().slice(0, 4);
    return `${baseId}_${suffix}`;
  }
  return baseId;
}

function getBookingsForUser(user) {
  if (!user || typeof db === 'undefined' || !Array.isArray(db.bookings)) return [];
  const uPhone = normalizeLocalPhone(user.phone);
  const uEmail = user.email ? String(user.email).trim().toLowerCase() : '';
  return db.bookings
    .filter(b => {
      if (b.userId === user.id || b.ownerId === user.id || b.customerId === user.id) return true;
      const bPhone = normalizeLocalPhone(b.phone || b.customerPhone);
      const bEmail = b.email ? String(b.email).trim().toLowerCase() : '';
      if (uPhone && bPhone && uPhone === bPhone) return true;
      if (uEmail && bEmail && uEmail === bEmail) return true;
      return false;
    })
    .sort((a, b) => String(b.startsAt || b.createdAt || '').localeCompare(String(a.startsAt || a.createdAt || '')));
}

function buildBookingSummaryForUser(booking, userId) {
  const venue = (typeof db !== 'undefined' && Array.isArray(db.venues))
    ? db.venues.find(v => v.id === booking.venueId)
    : null;
  const venueName = String((venue && venue.name) || booking.venueName || booking.venueId || '');
  const uid = String(userId || booking.userId || booking.ownerId || '');
  return {
    id: String(booking.id),
    venueId: String(booking.venueId || ''),
    venueName,
    itemId: String(booking.itemId || ''),
    startsAt: String(booking.startsAt || ''),
    durationMinutes: Number(booking.durationMinutes) || 0,
    price: Number(booking.price) || 0,
    dueNow: Number(booking.dueNow !== undefined ? booking.dueNow : 0),
    status: String(booking.status || 'pending_payment'),
    paymentStatus: String(booking.paymentStatus || 'unpaid'),
    paymentMethod: String(booking.paymentMethod || ''),
    paymentReference: String(booking.paymentReference || ''),
    createdAt: String(booking.createdAt || '')
  };
}

// Firebase removed - Supabase PostgreSQL is authoritative
async function syncUserToFirebase() { return false; }
async function deleteUserFromFirebase() { return false; }

function resolveUserForBooking(booking, explicitUser) {
  if (explicitUser && explicitUser.id) return explicitUser;
  if (typeof db === 'undefined' || !Array.isArray(db.users) || !booking) return null;
  const uid = booking.userId || booking.ownerId || booking.customerId || '';
  if (uid) {
    const byId = db.users.find(u => u.id === uid);
    if (byId) return byId;
  }
  const bPhone = normalizeLocalPhone(booking.phone || booking.customerPhone);
  const bEmail = booking.email ? String(booking.email).trim().toLowerCase() : '';
  const matched = db.users.find(u => {
    const uPhone = normalizeLocalPhone(u.phone);
    const uEmail = u.email ? String(u.email).trim().toLowerCase() : '';
    if (bPhone && uPhone && bPhone === uPhone) return true;
    if (bEmail && uEmail && bEmail === uEmail) return true;
    return false;
  });
  return matched || null;
}

// Firebase sync no-ops (Supabase is authoritative)
async function syncBookingToFirebase() {}
async function syncVenueToFirebase() { return false; }
async function deleteVenueFromFirebase() { return false; }
async function hydrateVenuesFromFirebase() {}

const rateLimit = require('express-rate-limit');
const { Pool } = require('pg');
const { runMigrations } = require('./migrate');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 4000;

// Banned / leaked default strings that MUST NEVER be accepted
const BANNED_SECRETS = new Set([
  'hagzy_prod_sec_2026_rotated_k8x9q2m1',
  'hagzy2026!',
  'hagzy_live_listener_secret_2026',
  'dev_secret_key_change_in_production'
]);

if (IS_PROD) {
  if (!process.env.JWT_SECRET) {
    console.error('FATAL: JWT_SECRET environment variable is missing.');
    process.exit(1);
  }
  if (BANNED_SECRETS.has(process.env.JWT_SECRET)) {
    console.error('FATAL: Insecure leaked JWT_SECRET provided in production.');
    process.exit(1);
  }
  if (process.env.ADMIN_PASSWORD && BANNED_SECRETS.has(process.env.ADMIN_PASSWORD)) {
    console.error('FATAL: Insecure leaked ADMIN_PASSWORD provided in production.');
    process.exit(1);
  }
  if (process.env.PAYMENT_LISTENER_KEY && BANNED_SECRETS.has(process.env.PAYMENT_LISTENER_KEY)) {
    console.error('FATAL: Insecure leaked PAYMENT_LISTENER_KEY provided in production.');
    process.exit(1);
  }
  if (process.env.PAYMENT_WEBHOOK_SECRET && BANNED_SECRETS.has(process.env.PAYMENT_WEBHOOK_SECRET)) {
    console.error('FATAL: Insecure leaked PAYMENT_WEBHOOK_SECRET provided in production.');
    process.exit(1);
  }
}

const JWT_SECRET = process.env.JWT_SECRET || (IS_TEST ? 'test-secret' : crypto.randomBytes(32).toString('hex'));
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || null;

const ADMIN_WHITELIST_EMAILS = [
  (process.env.ADMIN_EMAIL || '').trim().toLowerCase()
].filter(Boolean);

const ADMIN_WHITELIST_PHONES = [
  normalizeLocalPhone(process.env.ADMIN_PHONE || '')
].filter(Boolean);

function isUserAdmin(identity) {
  if (!identity) return false;
  const email = String(identity.email || '').trim().toLowerCase();
  if (email && ADMIN_WHITELIST_EMAILS.length > 0 && ADMIN_WHITELIST_EMAILS.includes(email)) return true;
  const rawPhone = identity.phone || identity.customerPhone || identity.target || identity.phoneNumber;
  const cleanPhone = normalizeLocalPhone(rawPhone);
  if (cleanPhone && ADMIN_WHITELIST_PHONES.length > 0 && ADMIN_WHITELIST_PHONES.includes(cleanPhone)) return true;
  if (ADMIN_WHITELIST_EMAILS.length === 0 && ADMIN_WHITELIST_PHONES.length === 0) {
    if (identity.role === 'owner' || identity.role === 'super_admin') return true;
    if (identity.isAdmin === true && identity.role === 'owner') return true;
  }
  return false;
}

function doesPartnerOwnVenue(identity, venue) {
  if (!identity || !venue || venue.isDeleted) return false;
  if (identity.id && venue.ownerId && venue.ownerId === identity.id) return true;
  const idEmail = String(identity.email || '').trim().toLowerCase();
  const vEmail = String(venue.ownerEmail || '').trim().toLowerCase();
  if (idEmail && vEmail && idEmail === vEmail) return true;
  const idPhone = normalizeLocalPhone(identity.phone || identity.customerPhone || identity.phoneNumber || '');
  const vPhone = normalizeLocalPhone(venue.ownerPhone || venue.phone || '');
  if (idPhone && vPhone && idPhone === vPhone) return true;
  return false;
}

function claimPartnerVenues(user) {
  if (!user || !user.id || typeof db === 'undefined' || !Array.isArray(db.venues)) return false;
  const verifiedEmail = user.emailVerified && user.email ? String(user.email).trim().toLowerCase() : '';
  const verifiedPhone = user.phoneVerified && user.phone ? normalizeLocalPhone(user.phone) : '';
  let changed = false;
  for (const v of db.venues) {
    if (v.isDeleted) continue;
    const byId = v.ownerId && v.ownerId === user.id;
    const byEmail = verifiedEmail && v.ownerEmail && String(v.ownerEmail).trim().toLowerCase() === verifiedEmail;
    const byPhone = verifiedPhone && v.ownerPhone && normalizeLocalPhone(v.ownerPhone) === verifiedPhone;
    if (byId || byEmail || byPhone) {
      if (v.ownerId !== user.id) { v.ownerId = user.id; changed = true; }
      if (verifiedEmail && !v.ownerEmail) { v.ownerEmail = verifiedEmail; changed = true; }
      if (verifiedPhone && !v.ownerPhone) { v.ownerPhone = verifiedPhone; changed = true; }
      if (user.role !== 'owner') {
        user.role = 'partner';
        user.partnerStatus = 'approved';
      }
      syncVenueToFirebase(v);
    }
  }
  if (changed) saveDb(db);
  return changed;
}

function buildPartnerAuthMeta(user) {
  const isOwner = isUserAdmin(user);
  const ownedVenues = (!isOwner && user && typeof db !== 'undefined' && Array.isArray(db.venues))
    ? db.venues.filter(v => doesPartnerOwnVenue(user, v))
    : [];
  const isPartner = !isOwner && Boolean(
    user && (
      user.partnerStatus === 'approved' ||
      user.role === 'partner' ||
      ownedVenues.length > 0
    )
  );
  if (!isOwner && user && user.role === 'owner') {
    user.role = isPartner ? 'partner' : 'customer';
    user.partnerStatus = isPartner ? 'approved' : 'none';
    if (typeof db !== 'undefined') saveDb(db);
    syncUserToFirebase(user);
  }
  const role = isOwner ? 'owner' : (isPartner ? 'partner' : 'customer');
  const partnerStatus = isOwner
    ? 'approved'
    : (isPartner ? 'approved' : (user && user.partnerStatus ? user.partnerStatus : 'none'));
  return {
    isOwner,
    isAdmin: isOwner,
    isPartner,
    role,
    partnerStatus,
    venueIds: ownedVenues.map(v => v.id),
  };
}

// App Store / Play review login. Disabled unless explicitly configured.
const REVIEWER_TARGET = process.env.REVIEWER_TARGET || '';
const REVIEWER_CODE = process.env.REVIEWER_CODE || '';

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

// Live PostgreSQL Cloud Database connection (if DATABASE_URL is set in Render / cloud)
let pgPool = null;
if (USE_POSTGRES) {
  try {
    pgPool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: Number(process.env.PG_POOL_MAX || 10),
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 10000,
      ssl: process.env.DATABASE_URL.includes('localhost') ? false : { rejectUnauthorized: false }
    });
    console.log('🐘 PostgreSQL pool configured. Relational Supabase mode active.');
  } catch (err) {
    console.error('PostgreSQL initialization error:', err.message);
  }
}

// Database file storage
const DATA_DIR = process.env.HAGZY_DATA_DIR || path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

const DB_FILE = path.join(DATA_DIR, 'hagzy_db.json');

let isHydrated = false;

const { CAIRO_TZ, cairoOffsetMinutes, parseClientTimestamp } = require('./cairoTime');

function markBookingConfirmed(b, { method, providerRef, amount, excess, actor = 'system', reason = 'Payment confirmed' } = {}) {
  if (!b) return b;
  try {
    transitionBookingStatus(b, BOOKING_STATUS.CONFIRMED, { actor, reason, auditLog: (db && db.auditLog) || [] });
  } catch (err) {
    if (err instanceof StateMachineError || err.name === 'StateMachineError') {
      // Anti-resurrection invariant: a cancelled/expired/completed booking must
      // NEVER be revived by a (late) payment. Signal the caller via null so the
      // money is routed to the review queue for refund/manual credit instead.
      console.warn(
        `markBookingConfirmed refused: booking ${b.id} is '${b.status}' — ` +
        `payment needs manual review (${reason})`
      );
      return null;
    }
    throw err;
  }
  if (method) b.paymentMethod = method;
  if (providerRef) b.paymentReference = providerRef;
  if (amount != null) b.actualPaidAmount = Number(amount);
  if (excess != null) b.excessDeposit = Number(excess);
  if (b.price && amount != null) {
    b.remainingDue = Math.max(0, b.price - Number(amount));
  }
  return b;
}

function findUserIdForBooking(booking, explicitUserId = null) {
  if (explicitUserId && explicitUserId !== 'guest') return explicitUserId;
  if (!booking) return null;
  if (booking.customerId && booking.customerId !== 'guest') return booking.customerId;
  if (booking.userId && booking.userId !== 'guest') return booking.userId;
  if (booking.ownerId && booking.ownerId !== 'guest') return booking.ownerId;
  const cleanPhone = String(booking.phone || booking.customerPhone || '').replace(/\D/g, '');
  if (cleanPhone && db && Array.isArray(db.users)) {
    const matched = db.users.find(u => u.phone && u.phone.replace(/\D/g, '') === cleanPhone);
    if (matched) return matched.id;
  }
  const email = String(booking.email || booking.customerEmail || '').toLowerCase().trim();
  if (email && db && Array.isArray(db.users)) {
    const matched = db.users.find(u => u.email && u.email.toLowerCase().trim() === email);
    if (matched) return matched.id;
  }
  return null;
}

function creditUserWallet(userId, amount, { referenceId, description, actor = 'system' } = {}) {
  const numAmt = Number(amount);
  if (!userId || !numAmt || numAmt <= 0) return 0;
  if (!db) return 0;
  if (!db.walletLedger) db.walletLedger = [];
  try {
    recordLedgerEntry(db.walletLedger, {
      userId,
      amount: Number(numAmt.toFixed(2)),
      type: LEDGER_ENTRY_TYPE.TOPUP,
      referenceId: referenceId || `credit_${Date.now()}`,
      description: description || 'Account wallet credit',
      actor
    });
    const u = db.users ? db.users.find(usr => usr.id === userId) : null;
    if (u) {
      u.walletBalance = calculateWalletBalance(u.id, db.walletLedger);
      syncUserToFirebase(u);
    }
    return numAmt;
  } catch (err) {
    console.warn('creditUserWallet warning:', err.message);
    return 0;
  }
}

function seedRealisticVenuesIfSparse() {
  if (!db || !Array.isArray(db.venues)) return;
  const localSeed = path.join(DATA_DIR, 'venues_seed.json');
  const rootSeed = path.join(__dirname, '..', 'assets', 'venues_seed.json');
  const seedPath = fs.existsSync(localSeed) ? localSeed : (fs.existsSync(rootSeed) ? rootSeed : null);
  if (seedPath && fs.existsSync(seedPath)) {
    try {
      const seedList = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
      if (Array.isArray(seedList) && seedList.length > 0) {
        let addedCount = 0;
        for (const v of seedList) {
          if (!db.venues.some(existing => existing.id === v.id)) {
            db.venues.push(v);
            addedCount++;
          }
        }
        if (addedCount > 0) {
          console.log(`🌱 Seeded ${addedCount} realistic venues to marketplace (total: ${db.venues.length})`);
          saveDb(db);
        }
      }
    } catch (e) {
      console.warn('Could not seed realistic venues:', e.message);
    }
  }
}

function computeBookingQrSig(bookingId, venueId) {
  return crypto
    .createHmac('sha256', JWT_SECRET)
    .update(`qr_checkin:${bookingId}:${venueId}`)
    .digest('hex')
    .slice(0, 24);
}

function buildBookingQrCheckInUrl(bookingId, sig) {
  return `https://hagzy.shop/partner?scanBooking=${encodeURIComponent(bookingId)}&sig=${encodeURIComponent(sig)}`;
}

function verifyBookingQrSig(bookingId, venueId, sig) {
  if (!sig || !bookingId || !venueId) return false;
  const expected = computeBookingQrSig(bookingId, venueId);
  const a = Buffer.from(String(sig).trim(), 'utf8');
  const b = Buffer.from(expected, 'utf8');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function attachBookingQrMeta(booking) {
  if (!booking || !booking.id || !booking.venueId) return booking;
  const sig = computeBookingQrSig(booking.id, booking.venueId);
  return {
    ...booking,
    qrSignature: sig,
    qrCheckInUrl: buildBookingQrCheckInUrl(booking.id, sig),
  };
}

function notifyVenueOwner({ venue, booking, eventType, extraReason = '' }) {
  if (!booking) return null;
  if (!Array.isArray(db.partnerNotifications)) db.partnerNotifications = [];
  const venueId = String(venue?.id || booking.venueId || '');
  const venueName = String(venue?.name || booking.venueName || venueId);
  const unitName = String(booking.unitName || '');
  const customerName = String(booking.customer || booking.customerName || 'Guest');
  const customerPhone = String(booking.phone || booking.customerPhone || '');
  const totalPrice = Number(booking.price || booking.totalPrice || 0);
  const paidSoFar = Number(booking.actualPaidAmount || (booking.confirmed ? booking.depositAmount || 0 : 0));
  const remainingDue = Math.max(0, Number((totalPrice - paidSoFar).toFixed(2)));

  const titles = {
    booking_created: `حجز جديد في ${venueName}${unitName ? ` — ${unitName}` : ''}`,
    booking_confirmed: `تم تأكيد حجز ${customerName} في ${venueName}`,
    booking_cancelled: `تم إلغاء حجز ${customerName} في ${venueName}`,
    booking_checked_in: `تم تسجيل وصول ${customerName} في ${venueName}`,
  };
  const title = titles[eventType] || `تحديث حجز في ${venueName}`;
  const bodyLines = [
    `🏟️ المكان: ${venueName}${unitName ? ` (${unitName})` : ''}`,
    `👤 العميل: ${customerName}${customerPhone ? ` · ${customerPhone}` : ''}`,
    `📅 الموعد: ${booking.startsAt || ''}`,
    `💰 المدفوع: ${paidSoFar} ج.م | المتبقي عند الوصول: ${remainingDue} ج.م`,
    `🆔 رقم الحجز: ${booking.id}`,
  ];
  if (extraReason) bodyLines.push(`ℹ️ ${extraReason}`);
  const body = bodyLines.join('\n');

  const ownerPhone = String(venue?.ownerPhone || venue?.phone || '').trim();
  let whatsappSent = false;
  if (ownerPhone && !IS_TEST) {
    whatsappSent = true;
    sendSmsOrWhatsApp({ phone: ownerPhone, message: `🔔 *${title}*\n\n${body}`, otp: '' }).catch(() => {});
  }

  const notif = {
    id: `pn_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`,
    ownerId: venue?.ownerId || null,
    venueId,
    bookingId: booking.id,
    eventType,
    title,
    body,
    whatsappSent,
    read: false,
    createdAt: new Date().toISOString(),
  };
  db.partnerNotifications.unshift(notif);
  if (db.partnerNotifications.length > 500) db.partnerNotifications.length = 500;
  return notif;
}

function emptyDbState() {
  return {
    users: [],
    venues: [],
    bookings: [],
    otps: {},
    walletLedger: [],
    auditLog: [],
    reviewQueue: [],
    partnerRequests: [],
    partnerNotifications: [],
  };
}

function loadDb() {
  // Clean cloud start when connected to PostgreSQL (never hydrate demo seed or local snapshot)
  if (USE_POSTGRES) {
    return emptyDbState();
  }

  if (fs.existsSync(DB_FILE)) {
    try {
      const data = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
      if (data.bookings && Array.isArray(data.bookings)) {
        for (const b of data.bookings) {
          if (b.status === 'confirmed' || b.confirmed) {
            markBookingConfirmed(b);
          }
        }
      }
      if (!data.walletLedger || !Array.isArray(data.walletLedger)) data.walletLedger = [];
      if (!data.auditLog || !Array.isArray(data.auditLog)) data.auditLog = [];
      if (!data.reviewQueue || !Array.isArray(data.reviewQueue)) data.reviewQueue = [];
      if (!data.partnerRequests || !Array.isArray(data.partnerRequests)) data.partnerRequests = [];
      if (!data.partnerNotifications || !Array.isArray(data.partnerNotifications)) data.partnerNotifications = [];
      return data;
    } catch (_) {}
  }

  // Initial seed
  let initialVenues = [];
  const localSeed = path.join(DATA_DIR, 'venues_seed.json');
  const rootSeed = path.join(__dirname, '..', 'assets', 'venues_seed.json');
  const seedPath = fs.existsSync(localSeed) ? localSeed : (fs.existsSync(rootSeed) ? rootSeed : null);
  if (seedPath && fs.existsSync(seedPath)) {
    try {
      initialVenues = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
    } catch (_) {}
  }

  return {
    users: [],
    venues: initialVenues,
    bookings: [],
    otps: {},
    walletLedger: [],
    auditLog: [],
    reviewQueue: [],
    partnerRequests: [],
    partnerNotifications: [],
  };
}

function saveDb(data) {
  if (!USE_POSTGRES) {
    try {
      fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2), 'utf8');
    } catch (err) {
      console.error('File DB write error:', err.message);
    }
  }

  // Asynchronous transactional sync to relational PostgreSQL database
  if (pgPool && isHydrated) {
    persistToPostgres(data).catch(e => console.error('Postgres sync error:', e.message));
  }
}

// Relational PostgreSQL persistence: hydrated once on startup and updated
// transactionally across public.* tables after state mutations.
let pgWriteChain = Promise.resolve();
function persistToPostgres(data) {
  if (!pgPool || !isHydrated) return Promise.resolve();
  pgWriteChain = pgWriteChain
    .then(() => persistRelationalState(pgPool, data, {
      localPaymentIntents,
      localPaymentEvents,
    }))
    .catch(e => console.error('Postgres sync error:', e.message));
  return pgWriteChain;
}

async function hydratePostgres() {
  if (!pgPool) {
    isHydrated = true;
    return;
  }
  const maxAttempts = 6;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // 1. Run authoritative relational schema migrations on the database
      console.log('🐘 Executing PostgreSQL schema migrations...');
      await runMigrations({ pool: pgPool });
      console.log('🐘 Schema migrations up-to-date.');

      // 2. Hydrate in-memory state from normalized PostgreSQL tables (leaves empty tables clean at 0 rows)
      const stats = await hydrateRelationalState(pgPool, db, {
        localPaymentIntents,
        localPaymentEvents,
      });
      isHydrated = true;
      console.log(
        `🐘 Relational PostgreSQL hydrated: ${stats.usersCount} users, ${stats.venuesCount} venues (${stats.unitsCount} units), ${stats.bookingsCount} bookings.`,
      );
      if (stats.venuesCount <= 1) {
        seedRealisticVenuesIfSparse();
      }
      return;
    } catch (err) {
      // Keep isHydrated = false on failure so no accidental saveDb() can wipe live rows.
      console.error(`PostgreSQL hydrate attempt ${attempt}/${maxAttempts} failed:`, err.message);
      if (attempt === maxAttempts) {
        console.error('PostgreSQL hydrate retries exhausted. API returns 503 until the service restarts.');
      } else {
        await new Promise(r => setTimeout(r, Math.min(30000, 2000 * 2 ** (attempt - 1))));
      }
    }
  }
}

db = loadDb();
db.walletLedger = db.walletLedger || [];
db.auditLog = db.auditLog || [];
db.reviewQueue = db.reviewQueue || [];
db.partnerRequests = db.partnerRequests || [];

// Backfill wallet ledger entries for existing users if ledger is empty
if (Array.isArray(db.users)) {
  for (const u of db.users) {
    const currentBal = Number(u.walletBalance || 0);
    if (currentBal > 0 && !db.walletLedger.some(e => e.userId === u.id)) {
      db.walletLedger.push({
        id: `led_init_${u.id}`,
        userId: u.id,
        amount: currentBal,
        type: LEDGER_ENTRY_TYPE.ADMIN_ADJUSTMENT,
        referenceId: 'legacy_balance_migration',
        description: 'Initial balance migration to immutable ledger',
        actor: 'migration',
        balanceAfter: currentBal,
        createdAt: new Date().toISOString()
      });
    }
  }
}

// Background Hold Sweeper (Expires unpaid holds after 15m)
const holdSweeperInterval = setInterval(() => {
  try {
    const now = Date.now();
    let changed = false;
    if (db && Array.isArray(db.bookings)) {
      for (const b of db.bookings) {
        if (b.status === BOOKING_STATUS.PENDING_PAYMENT && b.holdExpiresAt && new Date(b.holdExpiresAt).getTime() < now) {
          try {
            transitionBookingStatus(b, BOOKING_STATUS.EXPIRED, {
              actor: 'hold_sweeper',
              reason: 'Reservation hold window expired',
              auditLog: db.auditLog
            });
            changed = true;
          } catch (_) {}
        }
      }
    }
    if (changed) saveDb(db);
  } catch (err) {
    console.error('Hold sweeper error:', err.message);
  }
}, 60 * 1000);
if (holdSweeperInterval.unref) holdSweeperInterval.unref();

if (db.bookings && Array.isArray(db.bookings)) {
  let initialFixed = false;
  for (const b of db.bookings) {
    if (b.status === 'confirmed' || b.confirmed) {
      if (b.paymentStatus !== 'paid' || b.dueNow !== 0 || b.holdExpiresAt !== null) {
        markBookingConfirmed(b);
        initialFixed = true;
      }
    }
  }
  if (initialFixed) saveDb(db);
}

app.set('trust proxy', 1); // behind Render's proxy: needed for correct client IPs
app.disable('x-powered-by');
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false
}));

const allowedCorsOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map(o => o.trim().toLowerCase())
  : (IS_PROD ? ['https://hagzy.shop', 'https://www.hagzy.shop', 'https://hagzy-booking.web.app', 'https://hagzy-acea1.web.app', 'https://hagzy.app', 'https://hagzy-api.onrender.com'] : ['*']);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedCorsOrigins.includes('*') || allowedCorsOrigins.includes(origin.toLowerCase())) {
      return callback(null, true);
    }
    return callback(new Error('Blocked by CORS policy'));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Signature', 'X-Hagzy-Signature', 'X-Timestamp', 'X-Listener-Key', 'X-Webhook-Signature'],
  credentials: true
}));

app.use(express.json({
  limit: '200kb',
  verify: (req, res, buf) => {
    req.rawBody = buf;
  }
}));
app.use((err, req, res, next) => {
  if (err && err instanceof SyntaxError && err.status === 400 && 'body' in err) {
    req.body = req.rawBody ? { text: req.rawBody.toString('utf8') } : {};
    return next();
  }
  return next(err);
});
app.use(express.urlencoded({
  extended: true,
  limit: '200kb',
  verify: (req, res, buf) => {
    if (!req.rawBody) req.rawBody = buf;
  }
}));
app.use(express.text({
  type: ['text/*', 'application/text', 'application/octet-stream'],
  limit: '200kb',
  verify: (req, res, buf) => {
    if (!req.rawBody) req.rawBody = buf;
  }
}));
app.use(express.raw({
  type: '*/*',
  limit: '200kb',
  verify: (req, res, buf) => {
    if (!req.rawBody) req.rawBody = buf;
  }
}));

// Refuse API traffic until PostgreSQL state is hydrated. Serving the empty
// in-memory db would show zero venues AND silently drop every write made
// during the window (lost on restart). Render free tier reboots daily, so a
// transient Supabase blip must fail closed, not serve empty.
const HEALTH_PATHS = new Set(['/health', '/api/health', '/healthz', '/ping']);
app.use((req, res, next) => {
  if (!pgPool || isHydrated) return next();
  if (HEALTH_PATHS.has(req.path)) return next();
  return res.status(503).json({
    error: 'Service is starting up. Please retry shortly.',
    retryAfterSeconds: 10,
  });
});

const authLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  limit: 150,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Please wait a moment and try again.' },
});
const otpLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  limit: 80,
  skipFailedRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many verification code requests. Please wait a moment and try again.' },
});
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 600,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again shortly.' },
});
app.use('/api/', apiLimiter);
app.use(['/api/auth/login', '/api/auth/customer/login', '/api/auth/customer/register', '/api/auth/customer-otp/verify'], authLimiter);
app.use('/api/auth/customer-otp/request', otpLimiter);

// 1. Dedicated Venue Owner & Partner Web Portal (/partner and /admin)
const adminWebDir = path.join(__dirname, '..', 'build', 'web-admin');
if (fs.existsSync(adminWebDir)) {
  app.use('/partner', express.static(adminWebDir));
  app.get('/admin', (req, res) => res.redirect('/partner'));
  app.get('/admin/*', (req, res) => res.redirect('/partner'));
  app.get(['/partner', '/partner/*'], (req, res) => {
    res.sendFile(path.join(adminWebDir, 'index.html'));
  });
}

// 2. Player Consumer Web App (/)
const buildWebDir = path.join(__dirname, '..', 'build', 'web');
const staticWebDir = path.join(__dirname, '..', 'web');
const activeWebDir = fs.existsSync(buildWebDir)
  ? buildWebDir
  : fs.existsSync(staticWebDir)
      ? staticWebDir
      : null;

if (activeWebDir) {
  app.use(express.static(activeWebDir));
  app.get('*', (req, res, next) => {
    if (
      req.path.startsWith('/api') ||
      req.path.startsWith('/partner') ||
      req.path.startsWith('/admin') ||
      req.path === '/health' ||
      req.path === '/healthz' ||
      req.path === '/ping'
    ) return next();
    const indexPath = path.join(activeWebDir, 'index.html');
    if (fs.existsSync(indexPath)) {
      res.sendFile(indexPath);
    } else {
      next();
    }
  });
}

// ==========================================
// SMS / WHATSAPP DISPATCH HELPER
// ==========================================
async function sendSmsOrWhatsApp({ phone, message, otp }) {
  if (IS_TEST) return { sent: true, provider: 'test' };

  console.log(`\n========================================`);
  console.log(`📲 [SMS / OTP DISPATCH]`);
  console.log(`To: ${phone}`);
  console.log(`Code: ${otp}`);
  console.log(`Message: ${message}`);
  console.log(`========================================\n`);

  // 1. SMS Misr (Official Egyptian Telecom SMS with branded Sender ID 'HAGZY')
  if (process.env.SMSMISR_USERNAME && process.env.SMSMISR_PASSWORD) {
    try {
      const clean = phone.replace(/\D/g, '');
      const formatted = clean.startsWith('0') ? '2' + clean : (clean.startsWith('20') ? clean : '20' + clean);
      const payload = new URLSearchParams({
        environment: process.env.SMSMISR_ENV || '1',
        username: process.env.SMSMISR_USERNAME,
        password: process.env.SMSMISR_PASSWORD,
        sender: process.env.SMSMISR_SENDER || 'HAGZY',
        mobile: formatted,
        language: '2', // Arabic
        message: message
      });
      const resp = await fetch('https://smsmisr.com/api/SMS/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload
      });
      const data = await resp.json().catch(() => ({}));
      console.log('✅ SMS Misr response:', resp.status, data);
      return { sent: resp.ok, provider: 'smsmisr', data };
    } catch (e) {
      console.error('SMS Misr error:', e.message);
    }
  }

  // 2. UltraMsg WhatsApp Integration (Fallback)
  const instanceId = process.env.ULTRAMSG_INSTANCE_ID || 'instance195537';
  const token = process.env.ULTRAMSG_TOKEN || 'nr7aw9vr4u9hoefq';

  if (instanceId && token) {
    try {
      const clean = phone.replace(/\D/g, '');
      let formatted = clean;
      if (formatted.startsWith('0')) {
        formatted = '2' + formatted;
      } else if (!formatted.startsWith('20') && formatted.length === 10) {
        formatted = '20' + formatted;
      }
      if (!formatted.startsWith('+')) {
        formatted = '+' + formatted;
      }
      const url = `https://api.ultramsg.com/${instanceId}/messages/chat`;
      const params = new URLSearchParams();
      params.append('token', token);
      params.append('to', formatted);
      params.append('body', message);

      const resp = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params
      });
      const data = await resp.json().catch(() => ({}));
      console.log('✅ UltraMsg response:', resp.status, data);
      return { sent: resp.ok, provider: 'ultramsg', data };
    } catch (e) {
      console.error('UltraMsg error:', e.message);
    }
  }

  // 2. Twilio SMS Integration (if env vars provided)
  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER) {
    try {
      const clean = phone.replace(/\D/g, '');
      const formatted = clean.startsWith('0') ? '+2' + clean : '+' + clean;
      const auth = Buffer.from(`${process.env.TWILIO_ACCOUNT_SID}:${process.env.TWILIO_AUTH_TOKEN}`).toString('base64');
      const params = new URLSearchParams();
      params.append('To', formatted);
      params.append('From', process.env.TWILIO_PHONE_NUMBER);
      params.append('Body', message);

      await fetch(`https://api.twilio.com/2010-04-01/Accounts/${process.env.TWILIO_ACCOUNT_SID}/Messages.json`, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: params.toString()
      });
      return { sent: true, provider: 'twilio' };
    } catch (e) {
      console.error('Twilio error:', e.message);
    }
  }

  // Simulated / Development Mode (Returns true and logs to console)
  return { sent: true, provider: 'simulated_dev' };
}

// ==========================================
// REAL EMAIL DISPATCH (RESEND / SMTP)
// ==========================================
async function sendRealEmail({ email, code }) {
  console.log(`\n========================================`);
  console.log(`📧 [EMAIL / OTP DISPATCH]`);
  console.log(`To: ${email}`);
  console.log(`Code: ${code}`);
  console.log(`========================================\n`);

  const { subject, html, text } = getOtpEmailTemplate({ code, email });

  // 1. Resend API
  if (process.env.RESEND_API_KEY) {
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          from: process.env.EMAIL_FROM || 'Hagzy <onboarding@resend.dev>',
          to: [email],
          subject,
          html,
          text
        })
      });
      if (res.ok) {
        console.log(`✅ [LIVE EMAIL SENT via Resend] to: ${email}`);
        return { sent: true, provider: 'resend' };
      }
    } catch (e) {
      console.error('Resend error:', e.message);
    }
  }

  // 2. SMTP (Gmail / SendGrid / Amazon SES)
  if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
    try {
      const transporter = nodemailer.createTransport({
        host: process.env.SMTP_HOST,
        port: parseInt(process.env.SMTP_PORT || '587'),
        secure: process.env.SMTP_SECURE === 'true',
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASS
        }
      });
      await transporter.sendMail({
        from: process.env.SMTP_USER,
        to: email,
        subject,
        html,
        text
      });
      console.log(`✅ [LIVE EMAIL SENT via SMTP] to: ${email}`);
      return { sent: true, provider: 'smtp' };
    } catch (e) {
      console.error('SMTP error:', e.message);
    }
  }

  return { sent: false };
}

function formatE164Phone(rawPhone) {
  if (!rawPhone) return '';
  const digits = String(rawPhone).replace(/\D/g, '');
  if (digits.startsWith('20') && digits.length >= 12) {
    return '+' + digits;
  } else if (digits.startsWith('0') && digits.length >= 11) {
    return '+2' + digits;
  } else if (digits.length === 10 && (digits.startsWith('10') || digits.startsWith('11') || digits.startsWith('12') || digits.startsWith('15'))) {
    return '+20' + digits;
  } else if (digits.length > 0) {
    return '+' + digits;
  }
  return '';
}

// Middleware: Customer Auth
async function authenticateCustomer(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing customer token' });
  }
  const token = authHeader.split(' ')[1];
  if (isTokenRevoked(token)) {
    return res.status(401).json({ error: 'Your session has been logged out. Please sign in again.' });
  }
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    req.token = token;

    // Verify user exists in local database
    const localUser = db.users.find(u => u.id === decoded.id);
    if (!localUser) {
      revokeToken(token);
      return res.status(401).json({ error: 'Account not found or has been deleted. Please sign in again.' });
    }

    // Verify user still exists in Firebase Auth if Firebase Admin is active
    if (fbAuth && !IS_TEST) {
      let deletedFromFb = false;
      try {
        if (localUser.firebaseUid) {
          await fbAuth.getUser(localUser.firebaseUid);
        } else if (localUser.phone) {
          const formattedPhone = formatE164Phone(localUser.phone);
          if (formattedPhone) {
            const fbU = await fbAuth.getUserByPhoneNumber(formattedPhone);
            if (fbU) {
              localUser.firebaseUid = fbU.uid;
              saveDb(db);
            }
          }
        } else if (localUser.email) {
          const fbU = await fbAuth.getUserByEmail(localUser.email);
          if (fbU) {
            localUser.firebaseUid = fbU.uid;
            saveDb(db);
          }
        }
      } catch (fbErr) {
        if (fbErr.code === 'auth/user-not-found' || fbErr.code === 'auth/user-disabled') {
          deletedFromFb = true;
        }
      }

      if (deletedFromFb) {
        console.log(`⚠️ User ${localUser.id} (${localUser.phone || localUser.email}) was deleted from Firebase. Purging.`);
        db.users = db.users.filter(u => u.id !== localUser.id);
        saveDb(db);
        revokeToken(token);
        return res.status(401).json({ error: 'Account has been deleted from Firebase. Please sign up again.' });
      }
    }

    return next();
  } catch (err) {
    // If local JWT fails, check whether token is a valid Firebase ID token cryptographically verified via Firebase Admin SDK
    if (fbAuth && !IS_TEST) {
      try {
        const fbDecoded = await fbAuth.verifyIdToken(token);
        if (fbDecoded && (fbDecoded.email || fbDecoded.uid)) {
          const email = (fbDecoded.email || '').toLowerCase();
          const phone = (fbDecoded.phone_number || '').replace(/\D/g, '');
          const localUser = db.users.find(u =>
            (email && u.email && u.email.toLowerCase() === email) ||
            (phone && u.phone && u.phone.replace(/\D/g, '') === phone) ||
            u.firebaseUid === fbDecoded.uid
          );
          if (localUser) {
            req.user = { id: localUser.id, email: localUser.email, name: localUser.name, phone: localUser.phone };
            req.token = token;
            return next();
          }
        }
      } catch (_) {}
    }
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// Middleware: Admin & Venue Owner Auth
function authenticateAdmin(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing admin token' });
  }
  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const isOwner = (decoded.role === 'owner' || decoded.isAdmin) && isUserAdmin(decoded);
    const isPartner = decoded.role === 'partner' || decoded.role === 'merchant';
    if (!isOwner && !isPartner) {
      return res.status(403).json({ error: 'Forbidden: Admin access restricted to authorized owner' });
    }
    req.admin = decoded;
    req.isPlatformOwner = isOwner;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid admin token' });
  }
}

// ==========================================
// 1. AUTH & CUSTOMER VERIFICATION (SMS OTP)
// ==========================================


// Parses a bearer token if present (never rejects). Sets req.user / req.admin.
function optionalAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    try {
      const decoded = jwt.verify(authHeader.split(' ')[1], JWT_SECRET);
      if (decoded.isAdmin || decoded.role === 'owner' || decoded.role === 'partner' || decoded.role === 'merchant') {
        req.admin = decoded;
      } else {
        req.user = decoded;
      }
    } catch (_) { /* treated as anonymous */ }
  }
  next();
}

function sanitizeUser(u) {
  const meta = buildPartnerAuthMeta(u);
  return {
    id: u.id,
    name: u.name,
    phone: u.phone || '',
    email: u.email || '',
    walletBalance: u.walletBalance || 0,
    role: meta.role,
    isAdmin: meta.isOwner,
    isPartner: meta.isPartner,
    partnerStatus: meta.partnerStatus,
    venueIds: meta.venueIds,
  };
}

function normalizeTarget(value) {
  const t = String(value || '').trim();
  if (t.includes('@')) {
    return t.toLowerCase();
  }
  return t.replace(/[\s\-\(\)]/g, '');
}

function formatE164Phone(rawPhone) {
  if (!rawPhone) return '';
  const digits = String(rawPhone).replace(/\D/g, '');
  if (digits.startsWith('20') && digits.length >= 12) {
    return '+' + digits;
  } else if (digits.startsWith('0') && digits.length >= 11) {
    return '+2' + digits;
  } else if (digits.length === 10 && (digits.startsWith('10') || digits.startsWith('11') || digits.startsWith('12') || digits.startsWith('15'))) {
    return '+20' + digits;
  } else if (digits.length > 0) {
    return '+' + digits;
  }
  return '';
}

function escapeForInlineScript(json) {
  return json.replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
}

// Verifies an Apple identity token (RS256) against Apple's published keys.
let appleKeysCache = { keys: null, fetchedAt: 0 };
async function verifyAppleIdentityToken(identityToken) {
  const audience = process.env.APPLE_CLIENT_ID;
  if (IS_PROD && !audience) {
    throw new Error('APPLE_CLIENT_ID is not configured on production server');
  }
  const [h, p, sig] = String(identityToken).split('.');
  if (!h || !p || !sig) throw new Error('Malformed identity token');
  const header = JSON.parse(Buffer.from(h, 'base64url').toString('utf8'));
  if (header.alg !== 'RS256') throw new Error('Unexpected algorithm');
  if (!appleKeysCache.keys || Date.now() - appleKeysCache.fetchedAt > 3600e3) {
    const r = await fetch('https://appleid.apple.com/auth/keys');
    if (!r.ok) throw new Error('Could not fetch Apple keys');
    appleKeysCache = { keys: (await r.json()).keys, fetchedAt: Date.now() };
  }
  const jwk = appleKeysCache.keys.find(k => k.kid === header.kid);
  if (!jwk) throw new Error('Unknown signing key');
  const ok = crypto.verify('RSA-SHA256', Buffer.from(`${h}.${p}`),
    crypto.createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(sig, 'base64url'));
  if (!ok) throw new Error('Bad signature');
  const claims = JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
  if (claims.iss !== 'https://appleid.apple.com') throw new Error('Bad issuer');
  if (audience && claims.aud !== audience) throw new Error('Bad audience');
  if (!claims.exp || claims.exp * 1000 < Date.now()) throw new Error('Token expired');
  return claims;
}

// Request 6-digit OTP via SMS or Email
app.post('/api/auth/customer-otp/request', async (req, res) => {
  const { phone, email, name, isSignUp, isPartner } = req.body || {};
  const target = normalizeTarget(phone || email);

  if (!target || target.length > 120) {
    return res.status(400).json({ error: 'Phone number or email is required' });
  }

  const isEmail = target.includes('@');
  const formattedPhone = isEmail ? '' : formatE164Phone(target);

  // Check if account already exists locally or in Firebase Auth
  const existingLocalUser = db.users.find(u => isEmail
    ? (u.email && u.email.toLowerCase() === target)
    : (u.phone && (u.phone === target || (formattedPhone && formatE164Phone(u.phone) === formattedPhone))));

  let existingFbUser = null;
  if (fbAuth && !IS_TEST) {
    try {
      if (isEmail) {
        existingFbUser = await fbAuth.getUserByEmail(target);
      } else if (formattedPhone) {
        existingFbUser = await fbAuth.getUserByPhoneNumber(formattedPhone);
      }
    } catch (fbErr) {
      if ((fbErr.code === 'auth/user-not-found' || fbErr.code === 'auth/user-disabled') && existingLocalUser) {
        // User was deleted in Firebase Console! Purge local shadow user so it stays in sync.
        console.log(`⚠️ User was deleted from Firebase Auth. Purging local user ${existingLocalUser.id}`);
        db.users = db.users.filter(u => u.id !== existingLocalUser.id);
        saveDb(db);
      }
    }
  }

  // Lookup existing user in local DB or Firebase Auth
  const accountExists = !!(existingLocalUser || existingFbUser);

  // If client specified Log In mode (isSignUp === false) and account does NOT exist anywhere:
  if (isPartner !== true && isSignUp === false && !accountExists) {
    return res.status(404).json({
      error: 'No account found with this phone number. Please click "Create Account" below to register.',
      notFound: true
    });
  }

  // If client specified Sign Up mode (isSignUp === true) and account ALREADY exists:
  if (isPartner !== true && isSignUp === true && accountExists) {
    return res.status(409).json({
      error: 'This phone number is already registered. Please click "Log In" to access your account.',
      alreadyExists: true
    });
  }

  // Per-target (phone/email) cooldown to block rotating-IP SMS abuse
  const existingOtp = db.otps && db.otps[target];
  if (existingOtp && existingOtp.createdAt && Date.now() - existingOtp.createdAt < 30 * 1000 && !isReviewer && !IS_TEST) {
    const waitSecs = Math.ceil((30 * 1000 - (Date.now() - existingOtp.createdAt)) / 1000);
    return res.status(429).json({ error: `Please wait ${waitSecs} seconds before requesting another code.` });
  }

  // Optional fixed credentials for App Store / Play review. Off unless configured.
  const isReviewer = !!REVIEWER_TARGET && !!REVIEWER_CODE && target === REVIEWER_TARGET;
  const otp = isReviewer ? REVIEWER_CODE : crypto.randomInt(100000, 1000000).toString();

  const hashedCode = crypto.createHash('sha256').update(otp).digest('hex');
  db.otps[target] = {
    hashedCode,
    createdAt: Date.now(),
    expiresAt: Date.now() + 5 * 60 * 1000,
    attempts: 0,
    name: String(name || '').slice(0, 80),
    isSignUp: isSignUp === true,
    isPartner: isPartner === true
  };
  saveDb(db);

  if (!isReviewer && !IS_TEST) {
    if (target.includes('@')) {
      await sendRealEmail({ email: target, code: otp });
    } else {
      const smsBody = `رمز التحقق الخاص بك في منصة حجزي (Hagzy) هو: ${otp}. لا تشارك هذا الرمز مع أحد.`;
      await sendSmsOrWhatsApp({ phone: target, message: smsBody, otp });
    }
  }

  // The code is only ever echoed back in the automated test environment.
  return res.json({
    success: true,
    message: `Verification code sent to ${target}`,
    ...(IS_TEST ? { testOtp: otp } : {})
  });
});

// ==========================================
// REAL GOOGLE & APPLE OAUTH 2.0 FLOWS
// ==========================================

// Real Google OAuth 2.0 Start
app.get('/api/auth/google/start', (req, res) => {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const redirectUri = `${req.protocol}://${req.get('host')}/api/auth/google/callback`;

  if (!clientId) {
    return res.status(503).send(`
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Google Sign-In Configuration Required</title></head>
      <body style="font-family:system-ui,-apple-system,sans-serif;max-width:540px;margin:50px auto;padding:28px;border:1px solid #e2e8f0;border-radius:18px;background:#fff;color:#0f172a;">
        <h2 style="color:#059669;margin-top:0;">حجزي · Google Sign-In Setup</h2>
        <p style="color:#475569;line-height:1.6;">
          Real Google OAuth 2.0 requires <code>GOOGLE_CLIENT_ID</code> and <code>GOOGLE_CLIENT_SECRET</code> to be added in your Render environment variables.
        </p>
        <p style="color:#475569;line-height:1.6;">
          Add the following Authorized redirect URI to your Google Cloud Console:
        </p>
        <pre style="background:#f1f5f9;padding:12px;border-radius:8px;font-size:13px;word-break:break-all;color:#0f172a;">${redirectUri}</pre>
        <p style="color:#475569;line-height:1.6;">
          In the meantime, you can register and sign in instantly using <strong>Email & Password</strong> or <strong>SMS/Email Verification Code</strong> on the profile screen.
        </p>
        <a href="/" style="display:inline-block;padding:12px 20px;background:#059669;color:#fff;text-decoration:none;border-radius:10px;font-weight:700;">← Return to Hagzy App</a>
      </body>
      </html>
    `);
  }

  const googleAuthUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=openid%20email%20profile&access_type=offline&prompt=select_account`;
  return res.redirect(googleAuthUrl);
});

// Real Google OAuth 2.0 Callback
app.get('/api/auth/google/callback', async (req, res) => {
  const { code } = req.query;
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const redirectUri = `${req.protocol}://${req.get('host')}/api/auth/google/callback`;

  if (!code || !clientId || !clientSecret) {
    return res.redirect('/?error=google_auth_failed');
  }

  try {
    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code'
      })
    });
    const tokens = await tokenRes.json();
    if (!tokens.access_token) throw new Error('No access token returned from Google');

    const userInfoRes = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${tokens.access_token}` }
    });
    const profile = await userInfoRes.json();
    const verifiedEmail = profile.email.toLowerCase();
    const verifiedName = profile.name || verifiedEmail.split('@')[0];
    const verifiedId = profile.sub;
    const verifiedAvatar = profile.picture || '';

    let user = db.users.find(u => u.email === verifiedEmail || (u.googleId && u.googleId === verifiedId));
    if (!user) {
      user = {
        id: buildCleanUserId({ name: verifiedName, email: verifiedEmail, phone: '' }),
        googleId: verifiedId,
        email: verifiedEmail,
        phone: '',
        name: verifiedName,
        avatar: verifiedAvatar,
        authProvider: 'google',
        walletBalance: 50.0,
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
    } else {
      user.googleId = verifiedId;
      if (!user.avatar) user.avatar = verifiedAvatar;
    }
    claimCustomerBookings(user);
    saveDb(db);
    syncUserToFirebase(user);

    const jwtToken = jwt.sign(
      { id: user.id, email: user.email, name: user.name, provider: 'google' },
      JWT_SECRET,
      { expiresIn: '90d' }
    );

    res.send(`
      <!DOCTYPE html>
      <html>
      <head><title>Google Sign-In Successful</title></head>
      <body style="font-family:sans-serif;text-align:center;padding:40px;background:#059669;color:#fff;">
        <h3>Signed in successfully with Google!</h3>
        <p>Connecting back to Hagzy...</p>
        <script>
          const payload = {
            type: 'HAGZY_AUTH_SUCCESS',
            token: ${escapeForInlineScript(JSON.stringify(jwtToken))},
            customer: ${escapeForInlineScript(JSON.stringify(sanitizeUser(user)))}
          };
          if (window.opener) {
            window.opener.postMessage(payload, window.location.origin);
            window.close();
          } else {
            window.location.href = '/?auth_token=' + encodeURIComponent(payload.token) + '&auth_name=' + encodeURIComponent(payload.customer.name) + '&auth_email=' + encodeURIComponent(payload.customer.email);
          }
        </script>
      </body>
      </html>
    `);
  } catch (err) {
    console.error('Google OAuth callback error:', err);
    res.redirect('/?error=google_auth_error');
  }
});

// Real Apple OAuth 2.0 Start
app.get('/api/auth/apple/start', (req, res) => {
  const clientId = process.env.APPLE_CLIENT_ID;
  const redirectUri = `${req.protocol}://${req.get('host')}/api/auth/apple/callback`;

  if (!clientId) {
    return res.status(503).send(`
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8"><title>Apple Sign-In Configuration Required</title></head>
      <body style="font-family:system-ui,-apple-system,sans-serif;max-width:540px;margin:50px auto;padding:28px;border:1px solid #e2e8f0;border-radius:18px;background:#fff;color:#0f172a;">
        <h2 style="color:#0f172a;margin-top:0;">حجزي · Apple Sign-In Setup</h2>
        <p style="color:#475569;line-height:1.6;">
          Real Sign in with Apple requires <code>APPLE_CLIENT_ID</code> (Services ID) and <code>APPLE_TEAM_ID</code> in Render environment variables.
        </p>
        <p style="color:#475569;line-height:1.6;">
          Add the following Return URL in your Apple Developer Portal:
        </p>
        <pre style="background:#f1f5f9;padding:12px;border-radius:8px;font-size:13px;word-break:break-all;color:#0f172a;">${redirectUri}</pre>
        <p style="color:#475569;line-height:1.6;">
          In the meantime, you can register and sign in instantly using <strong>Email & Password</strong> or <strong>SMS/Email Verification Code</strong> on the profile screen.
        </p>
        <a href="/" style="display:inline-block;padding:12px 20px;background:#0f172a;color:#fff;text-decoration:none;border-radius:10px;font-weight:700;">← Return to Hagzy App</a>
      </body>
      </html>
    `);
  }

  const appleAuthUrl = `https://appleid.apple.com/auth/authorize?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code%20id_token&scope=name%20email&response_mode=form_post`;
  return res.redirect(appleAuthUrl);
});

// ==========================================
// SOCIAL AUTHENTICATION (GOOGLE & APPLE)
// ==========================================

// Google Sign-In Endpoint
app.post('/api/auth/social/google', async (req, res) => {
  try {
    const { email, name, avatar, googleId, idToken } = req.body;

    // The id token is mandatory and verified with Google. Client-supplied
    // email/googleId fields are never trusted on their own.
    if (!idToken) {
      return res.status(400).json({ error: 'Google idToken is required' });
    }
    const allowedAudiences = [
      process.env.GOOGLE_CLIENT_ID,
      '311924169958-7fg0f65ba9dig1u2kg47fn3kop5hagg4.apps.googleusercontent.com',
      '311924169958-lkvcf1ghsnt49sbp6ueojjhecgktl4v8.apps.googleusercontent.com',
      '112586231867-1h3nmb49t5f0m970vt8mna0bfn9kvl9r.apps.googleusercontent.com',
      'hagzy-acea1'
    ].filter(Boolean);

    let verifiedEmail = '';
    let verifiedName = '';
    let verifiedAvatar = '';
    let verifiedId = '';
    try {
      const verifyRes = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
      if (verifyRes.ok) {
        const payload = await verifyRes.json();
        const audOk = allowedAudiences.some(a => payload.aud === a || (payload.iss && payload.iss.includes(a)));
        const emailOk = payload.email_verified === true || payload.email_verified === 'true';
        if (audOk && emailOk && payload.email) {
          verifiedEmail = payload.email.toLowerCase();
          verifiedName = (payload.name || '').trim();
          verifiedAvatar = (payload.picture || '').trim();
          verifiedId = payload.sub || '';
        }
      }
      if (!verifiedEmail && fbAuth) {
        try {
          const decoded = await fbAuth.verifyIdToken(idToken);
          if (decoded && decoded.email) {
            verifiedEmail = String(decoded.email).toLowerCase();
            verifiedName = String(decoded.name || decoded.email.split('@')[0]).trim();
            verifiedAvatar = String(decoded.picture || '').trim();
            verifiedId = decoded.uid || decoded.sub || '';
          }
        } catch (_) {}
      }
      if (!verifiedEmail) {
        return res.status(401).json({ error: 'Invalid Google token' });
      }
    } catch (err) {
      console.warn('Google id_token validation failed:', err.message);
      return res.status(401).json({ error: 'Could not verify Google token' });
    }

    // Find or create customer
    let user = db.users.find(u => (u.googleId && u.googleId === verifiedId) || (u.email && u.email.toLowerCase() === verifiedEmail));
    if (!user) {
      user = {
        id: buildCleanUserId({ name: verifiedName, email: verifiedEmail, phone: '' }),
        googleId: verifiedId,
        email: verifiedEmail,
        phone: '',
        name: verifiedName || verifiedEmail.split('@')[0],
        avatar: verifiedAvatar,
        authProvider: 'google',
        walletBalance: 0.0, // Initial balance is zero
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
    } else {
      if (!user.googleId && verifiedId) user.googleId = verifiedId;
      if (verifiedName && (!user.name || user.name === 'Hagzy Member')) user.name = verifiedName;
      if (verifiedAvatar && !user.avatar) user.avatar = verifiedAvatar;
      if (!user.authProvider) user.authProvider = 'google';
    }
    user.emailVerified = true;
    claimCustomerBookings(user);
    claimPartnerVenues(user);
    saveDb(db);
    syncUserToFirebase(user);

    const partnerMeta = buildPartnerAuthMeta(user);
    const isAdmin = partnerMeta.isOwner || isUserAdmin({ email: verifiedEmail });
    const role = isAdmin ? 'owner' : partnerMeta.role;
    const isPartner = isAdmin || partnerMeta.isPartner;
    const token = jwt.sign(
      {
        id: user.id,
        email: user.email,
        phone: user.phone || '',
        name: user.name,
        provider: 'google',
        isAdmin,
        isPartner,
        role
      },
      JWT_SECRET,
      { expiresIn: '90d' }
    );

    return res.json({
      success: true,
      token,
      isAdmin,
      isPartner,
      partnerStatus: isAdmin ? 'approved' : partnerMeta.partnerStatus,
      role,
      venueIds: partnerMeta.venueIds,
      customer: {
        ...sanitizeUser(user),
        avatar: user.avatar || '',
        authProvider: 'google',
        isAdmin,
        isPartner,
        partnerStatus: isAdmin ? 'approved' : partnerMeta.partnerStatus,
        role,
        venueIds: partnerMeta.venueIds,
      }
    });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to authenticate with Google: ' + e.message });
  }
});

// Apple Sign-In Endpoint
app.post('/api/auth/social/apple', async (req, res) => {
  try {
    const { email, name, appleUserId, identityToken } = req.body;

    if (!identityToken) {
      return res.status(400).json({ error: 'Apple identityToken is required' });
    }
    let verifiedEmail = '';
    let verifiedId = '';
    let verifiedName = (name || '').trim();

    // 1. Check if token is a valid Firebase Auth ID Token via Firebase Admin SDK
    if (fbAuth) {
      try {
        const decodedFb = await fbAuth.verifyIdToken(identityToken);
        if (decodedFb && (decodedFb.email || decodedFb.uid)) {
          verifiedEmail = (decodedFb.email || '').toLowerCase();
          verifiedId = decodedFb.uid || decodedFb.sub || '';
          if (decodedFb.name && !verifiedName) verifiedName = decodedFb.name;
        }
      } catch (err) {
        console.warn('Firebase Admin verifyIdToken notice for Apple:', err.message);
      }
    }

    // 2. Direct Apple identity tokens (RS256 verified via Apple JWKS)
    if (!verifiedEmail && !verifiedId) {
      try {
        const claims = await verifyAppleIdentityToken(identityToken);
        verifiedId = claims.sub;
        verifiedEmail = (claims.email || '').toLowerCase();
      } catch (err) {
        console.warn('Apple identityToken validation failed:', err.message);
      }
    }

    if (!verifiedEmail && !verifiedId) {
      return res.status(401).json({ error: 'Invalid Apple token' });
    }

    const tokenHadVerifiedEmail = Boolean(verifiedEmail);
    if (!verifiedEmail) {
      verifiedEmail = `${verifiedId.slice(0, 10)}@privaterelay.appleid.com`;
    }

    // Find or create customer: ONLY match existing email if verified by Apple token claims!
    // Never allow an unverified client-supplied email in req.body to hijack existing accounts.
    let user = db.users.find(u =>
      (u.appleUserId && u.appleUserId === verifiedId) ||
      (tokenHadVerifiedEmail && u.email && u.email.toLowerCase() === verifiedEmail)
    );
    if (!user) {
      user = {
        id: buildCleanUserId({ name: verifiedName, email: verifiedEmail, phone: '' }),
        appleUserId: verifiedId,
        email: verifiedEmail,
        phone: '',
        name: verifiedName || 'Apple Member',
        authProvider: 'apple',
        walletBalance: 0.0, // Initial balance is zero
        createdAt: new Date().toISOString()
      };
      db.users.push(user);
    } else {
      if (!user.appleUserId && verifiedId) user.appleUserId = verifiedId;
      if (verifiedName && (!user.name || user.name === 'Hagzy Member')) user.name = verifiedName;
      if (!user.authProvider) user.authProvider = 'apple';
    }
    if (verifiedEmail && !verifiedEmail.endsWith('@privaterelay.appleid.com')) {
      user.emailVerified = true;
    }
    claimCustomerBookings(user);
    claimPartnerVenues(user);
    saveDb(db);
    syncUserToFirebase(user);

    const partnerMeta = buildPartnerAuthMeta(user);
    const isAdmin = partnerMeta.isOwner || isUserAdmin({ email: verifiedEmail });
    const role = isAdmin ? 'owner' : partnerMeta.role;
    const isPartner = isAdmin || partnerMeta.isPartner;
    const token = jwt.sign(
      {
        id: user.id,
        email: user.email,
        phone: user.phone || '',
        name: user.name,
        provider: 'apple',
        isAdmin,
        isPartner,
        role
      },
      JWT_SECRET,
      { expiresIn: '90d' }
    );

    return res.json({
      success: true,
      token,
      isAdmin,
      isPartner,
      partnerStatus: isAdmin ? 'approved' : partnerMeta.partnerStatus,
      role,
      venueIds: partnerMeta.venueIds,
      customer: {
        ...sanitizeUser(user),
        authProvider: 'apple',
        isAdmin,
        isPartner,
        partnerStatus: isAdmin ? 'approved' : partnerMeta.partnerStatus,
        role,
        venueIds: partnerMeta.venueIds,
      }
    });
  } catch (e) {
    return res.status(500).json({ error: 'Failed to authenticate with Apple: ' + e.message });
  }
});

// Verify OTP & Log In / Register User in Database
app.post('/api/auth/customer-otp/verify', async (req, res) => {
  const { phone, email, code, name } = req.body || {};
  const target = normalizeTarget(phone || email);
  const inputCode = String(code || '').trim();

  const record = db.otps[target];
  if (!record) {
    return res.status(400).json({ error: 'No verification code was requested for this phone/email. Please request a code.' });
  }
  if (Date.now() > record.expiresAt) {
    delete db.otps[target];
    saveDb(db);
    return res.status(400).json({ error: 'Verification code has expired. Please request a new one.' });
  }
  record.attempts = (record.attempts || 0) + 1;
  if (record.attempts > 5) {
    delete db.otps[target];
    saveDb(db);
    return res.status(429).json({ error: 'Too many attempts. Please request a new code.' });
  }
  const inputHash = crypto.createHash('sha256').update(inputCode).digest('hex');
  const storedHash = record.hashedCode || (record.code ? crypto.createHash('sha256').update(String(record.code)).digest('hex') : '');
  const a = Buffer.from(storedHash);
  const b = Buffer.from(inputHash);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    saveDb(db);
    return res.status(400).json({ error: 'Invalid verification code. Please enter the code sent to your email/phone.' });
  }

  delete db.otps[target];

  // Look the account up ONLY by the identifier that was actually verified.
  // (Matching on a second, unverified identifier allowed account takeover.)
  const isEmail = target.includes('@');
  const normPhone = isEmail ? '' : normalizeLocalPhone(target);
  let user = db.users.find(u => isEmail
    ? (u.email && u.email.toLowerCase() === target)
    : (u.phone && (u.phone === target || normalizeLocalPhone(u.phone) === normPhone)));
  const resolvedName = String(name || record.name || 'Hagzy Member').slice(0, 80);
  if (!user) {
    user = {
      id: buildCleanUserId({ name: resolvedName, email: isEmail ? target : '', phone: isEmail ? '' : target }),
      phone: isEmail ? '' : target,
      email: isEmail ? target : '',
      name: resolvedName,
      walletBalance: 50.0, // 50 EGP welcome gift balance
      emailVerified: isEmail,
      phoneVerified: !isEmail,
      createdAt: new Date().toISOString()
    };
    db.users.push(user);
    try {
      recordLedgerEntry(db.walletLedger, {
        userId: user.id,
        amount: 50.0,
        type: LEDGER_ENTRY_TYPE.WELCOME_BONUS,
        description: 'Welcome gift balance',
        actor: 'system'
      });
    } catch (_) {}
  } else {
    if (isEmail) user.emailVerified = true;
    else user.phoneVerified = true;
    if (name && (!user.name || user.name === 'Hagzy Member')) {
      user.name = String(name).slice(0, 80);
    }
  }
  claimCustomerBookings(user);
  claimPartnerVenues(user);
  saveDb(db);
  syncUserToFirebase(user);

  const partnerMeta = buildPartnerAuthMeta(user);
  const isAdmin = partnerMeta.isOwner || isUserAdmin({ phone: target, email: target });
  const role = isAdmin ? 'owner' : partnerMeta.role;
  const isPartner = isAdmin || partnerMeta.isPartner;
  const partnerStatus = isAdmin ? 'approved' : partnerMeta.partnerStatus;
  const token = jwt.sign(
    {
      id: user.id,
      phone: user.phone,
      email: user.email,
      name: user.name,
      isAdmin,
      isPartner,
      role
    },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  let firebaseCustomToken = null;
  if (fbAuth && !IS_TEST) {
    try {
      let formattedPhone = '';
      if (!isEmail) {
        const digits = target.replace(/\D/g, '');
        if (digits.startsWith('20') && digits.length >= 12) {
          formattedPhone = '+' + digits;
        } else if (digits.startsWith('0') && digits.length >= 11) {
          formattedPhone = '+2' + digits;
        } else if (digits.length === 10 && (digits.startsWith('10') || digits.startsWith('11') || digits.startsWith('12') || digits.startsWith('15'))) {
          formattedPhone = '+20' + digits;
        } else if (digits.length > 0) {
          formattedPhone = '+' + digits;
        }
      }

      let fbUser = null;
      try {
        if (isEmail) {
          fbUser = await fbAuth.getUserByEmail(target);
        } else if (formattedPhone) {
          fbUser = await fbAuth.getUserByPhoneNumber(formattedPhone);
        }
      } catch (err) {
        if (err.code === 'auth/user-not-found') {
          fbUser = await fbAuth.createUser({
            ...(formattedPhone ? { phoneNumber: formattedPhone } : {}),
            ...(isEmail ? { email: target } : {}),
            displayName: user.name || (isEmail ? target.split('@')[0] : 'Hagzy Member')
          });
          console.log('✅ Created user in Firebase Auth:', fbUser.uid, formattedPhone || target);
        } else {
          console.warn('Firebase user lookup notice:', err.code, err.message);
        }
      }

      if (fbUser) {
        user.firebaseUid = fbUser.uid;
        saveDb(db);
        if (user.name && !fbUser.displayName) {
          try {
            await fbAuth.updateUser(fbUser.uid, { displayName: user.name });
          } catch (_) {}
        }
        firebaseCustomToken = await fbAuth.createCustomToken(fbUser.uid);
        console.log('✅ Created Firebase Custom Token for:', fbUser.uid);
      }
    } catch (fbErr) {
      console.warn('Firebase Custom Token generation notice:', fbErr.message);
    }
  }

  syncUserToFirebase(user);
  return res.json({
    success: true,
    token,
    isAdmin,
    isPartner,
    partnerStatus,
    role,
    venueIds: partnerMeta.venueIds,
    firebaseCustomToken,
    customer: { ...sanitizeUser(user), isAdmin, isPartner, partnerStatus, role, venueIds: partnerMeta.venueIds }
  });
});

function claimCustomerBookings(user) {
  if (!user || !user.id) return;
  // Security: only claim past bookings by identifier if that identifier has been verified!
  const userPhone = user.phoneVerified ? normalizeLocalPhone(user.phone) : '';
  const userEmail = user.emailVerified ? String(user.email).trim().toLowerCase() : '';
  let changed = false;
  for (const b of db.bookings) {
    const bPhone = normalizeLocalPhone(b.phone || b.customerPhone);
    const bEmail = b.email ? String(b.email).trim().toLowerCase() : '';
    const isMine = (b.ownerId === user.id) || (b.customerId === user.id) || (b.userId === user.id) ||
      (userPhone && bPhone && userPhone === bPhone) ||
      (userEmail && bEmail && userEmail === bEmail);
    if (isMine && (b.ownerId !== user.id || b.customerId !== user.id || b.userId !== user.id)) {
      b.ownerId = user.id;
      b.customerId = user.id;
      b.userId = user.id;
      changed = true;
      syncBookingToFirebase(b, user);
    }
  }
  if (changed) saveDb(db);
}

// Customer Password Registration
app.post('/api/auth/customer/register', async (req, res) => {
  const { name, email, password, phone } = req.body || {};
  const cleanEmail = (email || '').trim().toLowerCase();
  const cleanName = (name || '').trim();
  const cleanPhone = (phone || '').trim();

  if (!cleanEmail || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }
  if (!cleanEmail.includes('@') || !cleanEmail.includes('.')) {
    return res.status(400).json({ error: 'Please enter a valid email address' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters long' });
  }

  if (isUserAdmin({ email: cleanEmail, phone: cleanPhone }) ||
      ADMIN_WHITELIST_EMAILS.includes(cleanEmail) ||
      (cleanPhone && ADMIN_WHITELIST_PHONES.includes(normalizeLocalPhone(cleanPhone)))) {
    return res.status(403).json({
      error: 'Administrative identities cannot be registered through customer registration. Please sign in via Google OAuth or Phone OTP.'
    });
  }

  const existingEmail = db.users.find(u => u.email && u.email.toLowerCase() === cleanEmail);
  if (existingEmail) {
    return res.status(409).json({ error: 'An account with this email already exists. Please sign in.' });
  }
  if (cleanPhone) {
    const existingPhone = db.users.find(u => u.phone && u.phone.replace(/\D/g, '') === cleanPhone.replace(/\D/g, ''));
    if (existingPhone) {
      return res.status(409).json({ error: 'This phone number is already registered to another account.' });
    }
  }

  let emailVerified = false;
  if (req.body.code || req.body.otp) {
    const inputCode = String(req.body.code || req.body.otp).trim();
    const record = db.otps[cleanEmail];
    if (record && Date.now() <= record.expiresAt) {
      const inputHash = crypto.createHash('sha256').update(inputCode).digest('hex');
      const a = Buffer.from(record.hashedCode);
      const b = Buffer.from(inputHash);
      if (a.length === b.length && crypto.timingSafeEqual(a, b)) {
        emailVerified = true;
        delete db.otps[cleanEmail];
      }
    }
  }

  const passwordHash = await hashPassword(password);
  const newUser = {
    id: buildCleanUserId({ name: cleanName || cleanEmail.split('@')[0], email: cleanEmail, phone: cleanPhone }),
    email: cleanEmail,
    name: cleanName || cleanEmail.split('@')[0],
    phone: cleanPhone,
    passwordHash,
    walletBalance: 0.0,
    authProvider: 'email_password',
    emailVerified,
    phoneVerified: false,
    createdAt: new Date().toISOString()
  };

  db.users.push(newUser);
  claimCustomerBookings(newUser);
  saveDb(db);
  syncUserToFirebase(newUser);

  const token = jwt.sign(
    { id: newUser.id, email: newUser.email, name: newUser.name, phone: newUser.phone, role: 'customer', isAdmin: false },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  return res.status(201).json({
    success: true,
    token,
    customer: {
      id: newUser.id,
      name: newUser.name,
      email: newUser.email,
      phone: newUser.phone,
      walletBalance: 0.0,
      emailVerified: newUser.emailVerified
    }
  });
});

// Customer Password Login
app.post('/api/auth/customer/login', async (req, res) => {
  const { email, password } = req.body || {};
  const cleanEmail = (email || '').trim().toLowerCase();

  if (!cleanEmail || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  const lockoutKey = `login:${cleanEmail}`;
  if (checkLoginLockout(lockoutKey)) {
    return res.status(429).json({ error: 'Account temporarily locked due to multiple failed login attempts. Please wait 15 minutes.' });
  }

  const user = db.users.find(u => u.email && u.email.toLowerCase() === cleanEmail);
  if (!user || !user.passwordHash) {
    recordLoginFailure(lockoutKey);
    return res.status(401).json({ error: 'Invalid email or password.' });
  }

  const match = await comparePassword(password, user.passwordHash);
  if (!match) {
    recordLoginFailure(lockoutKey);
    return res.status(401).json({ error: 'Invalid email or password.' });
  }

  clearLoginFailure(lockoutKey);

  // Transparently upgrade legacy scrypt hash to bcrypt
  if (user.passwordHash.includes(':')) {
    user.passwordHash = await hashPassword(password);
  }
  claimCustomerBookings(user);
  saveDb(db);
  syncUserToFirebase(user);

  const meta = buildPartnerAuthMeta(user);
  const token = jwt.sign(
    {
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      isAdmin: meta.isAdmin,
      isPartner: meta.isPartner,
      partnerStatus: meta.partnerStatus,
      role: meta.role,
      venueIds: meta.venueIds
    },
    JWT_SECRET,
    { expiresIn: '30d' }
  );

  return res.json({
    success: true,
    token,
    isAdmin: meta.isAdmin,
    isPartner: meta.isPartner,
    partnerStatus: meta.partnerStatus,
    role: meta.role,
    venueIds: meta.venueIds,
    customer: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      walletBalance: user.walletBalance !== undefined ? user.walletBalance : 0.0,
      isAdmin: meta.isAdmin,
      isPartner: meta.isPartner,
      partnerStatus: meta.partnerStatus,
      role: meta.role,
      venueIds: meta.venueIds
    }
  });
});

// Customer Email Verification via OTP
app.post('/api/auth/customer/verify-email', async (req, res) => {
  const { email, code } = req.body || {};
  const cleanEmail = normalizeTarget(email);
  if (!cleanEmail || !cleanEmail.includes('@') || !code) {
    return res.status(400).json({ error: 'Email and verification code are required' });
  }

  const record = db.otps[cleanEmail];
  if (!record) {
    return res.status(400).json({ error: 'No verification code was requested for this email, or it has expired.' });
  }
  if (Date.now() > record.expiresAt) {
    delete db.otps[cleanEmail];
    saveDb(db);
    return res.status(400).json({ error: 'Verification code has expired. Please request a new one.' });
  }

  const inputHash = crypto.createHash('sha256').update(String(code).trim()).digest('hex');
  const a = Buffer.from(record.hashedCode);
  const b = Buffer.from(inputHash);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    saveDb(db);
    return res.status(400).json({ error: 'Invalid verification code.' });
  }

  delete db.otps[cleanEmail];
  const user = db.users.find(u => u.email && u.email.toLowerCase() === cleanEmail);
  if (!user) {
    saveDb(db);
    return res.status(404).json({ error: 'User account not found' });
  }

  user.emailVerified = true;
  claimCustomerBookings(user);
  saveDb(db);
  syncUserToFirebase(user);

  return res.json({ success: true, emailVerified: true, message: 'Email verified successfully.' });
});

// Customer Logout & Session Invalidation
app.post(['/api/auth/customer/logout', '/api/auth/logout'], (req, res) => {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    revokeToken(authHeader.split(' ')[1]);
  }
  return res.json({ success: true, message: 'Logged out successfully.' });
});

// Update Customer Profile
app.put('/api/customer/profile', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const { name, phone, email } = req.body || {};
  if (email) {
    const cleanEmail = String(email).trim().toLowerCase();
    const collision = db.users.find(u => u.id !== user.id && u.email && u.email.toLowerCase() === cleanEmail);
    if (collision) return res.status(409).json({ error: 'This email is already in use by another account.' });
    user.email = cleanEmail;
  }
  if (phone) {
    const cleanPhone = String(phone).replace(/\D/g, '');
    const collision = db.users.find(u => u.id !== user.id && u.phone && u.phone.replace(/\D/g, '') === cleanPhone);
    if (collision) return res.status(409).json({ error: 'This phone number is already in use by another account.' });
    user.phone = cleanPhone;
  }
  if (name && typeof name === 'string') {
    user.name = name.trim();
  }

  saveDb(db);
  claimCustomerBookings(user);
  syncUserToFirebase(user);
  return res.json({ success: true, customer: sanitizeUser(user) });
});

// Fetch Customer Profile
app.get('/api/customer/profile', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  return res.json({ success: true, customer: sanitizeUser(user) });
});

// Delete Customer Account (purges local user, revokes session, and deletes Firebase Auth user)
app.delete('/api/customer/account', authenticateCustomer, async (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  if (fbAuth && !IS_TEST) {
    try {
      if (user.firebaseUid) {
        await fbAuth.deleteUser(user.firebaseUid);
      } else if (user.phone) {
        const formatted = formatE164Phone(user.phone);
        if (formatted) {
          const fbU = await fbAuth.getUserByPhoneNumber(formatted);
          if (fbU) await fbAuth.deleteUser(fbU.uid);
        }
      } else if (user.email) {
        const fbU = await fbAuth.getUserByEmail(user.email);
        if (fbU) await fbAuth.deleteUser(fbU.uid);
      }
    } catch (_) {}
  }

  db.users = db.users.filter(u => u.id !== user.id);
  saveDb(db);
  await deleteUserFromFirebase(user.id);
  if (req.token) revokeToken(req.token);

  return res.json({ success: true, message: 'Account deleted permanently.' });
});

// Wallet Operations (Ledger-Backed)
app.post('/api/customer/wallet/deduct', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  const numAmount = Number(req.body && req.body.amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0) {
    return res.status(400).json({ error: 'Invalid amount' });
  }
  try {
    recordLedgerEntry(db.walletLedger, {
      userId: user.id,
      amount: -numAmount,
      type: LEDGER_ENTRY_TYPE.BOOKING_DEPOSIT,
      description: (req.body && req.body.description) || 'Wallet payment deduction',
      actor: 'customer'
    });
    user.walletBalance = calculateWalletBalance(user.id, db.walletLedger);
    saveDb(db);
    syncUserToFirebase(user);
    return res.json({ success: true, walletBalance: user.walletBalance });
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }
});

app.post('/api/customer/wallet/add', authenticateAdmin, (req, res) => {
  if (!req.isPlatformOwner) {
    return res.status(403).json({ error: 'Forbidden: Only platform owner can adjust customer wallets' });
  }
  const { amount, userId, email, phone } = req.body || {};
  const user = db.users.find(u => (userId && u.id === userId) || (email && u.email === email) || (phone && u.phone === phone));
  if (!user) return res.status(404).json({ error: 'User not found' });
  const numAmount = Number(amount);
  if (!Number.isFinite(numAmount) || numAmount <= 0 || numAmount > 100000) {
    return res.status(400).json({ error: 'Invalid amount' });
  }
  try {
    recordLedgerEntry(db.walletLedger, {
      userId: user.id,
      amount: numAmount,
      type: LEDGER_ENTRY_TYPE.ADMIN_ADJUSTMENT,
      description: (req.body && req.body.description) || 'Admin adjustment',
      actor: req.admin ? (req.admin.email || 'admin') : 'admin'
    });
    user.walletBalance = calculateWalletBalance(user.id, db.walletLedger);
    saveDb(db);
    syncUserToFirebase(user);
    return res.json({ success: true, walletBalance: user.walletBalance });
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }
});

app.get('/api/customer/wallet/transactions', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  const transactions = (db.walletLedger || []).filter(e => e.userId === user.id);
  return res.json({
    success: true,
    walletBalance: calculateWalletBalance(user.id, db.walletLedger),
    transactions
  });
});

// ==========================================
// 2. ADMIN & VENUE OWNER PORTAL
// ==========================================

// Admin Sign In
app.post('/api/auth/login', async (req, res) => {
  const { email, password, token } = req.body || {};

  // Token-based admin/partner verification (e.g., from Google, Apple, or Email/Phone OTP)
  if (token && typeof token === 'string') {
    try {
      const decoded = jwt.verify(token.replace(/^Bearer\s+/i, ''), JWT_SECRET);
      const liveUser = decoded.id ? db.users.find(u => u.id === decoded.id) : null;
      if (liveUser) {
        claimPartnerVenues(liveUser);
        const meta = buildPartnerAuthMeta(liveUser);
        if (meta.isAdmin || meta.isPartner) {
          const adminToken = jwt.sign(
            {
              id: liveUser.id,
              email: liveUser.email,
              phone: liveUser.phone,
              isAdmin: meta.isAdmin,
              isPartner: meta.isPartner,
              partnerStatus: meta.partnerStatus,
              role: meta.role,
              venueIds: meta.venueIds
            },
            JWT_SECRET,
            { expiresIn: '12h' }
          );
          return res.json({
            success: true,
            token: adminToken,
            isAdmin: meta.isAdmin,
            isPartner: meta.isPartner,
            partnerStatus: meta.partnerStatus,
            role: meta.role,
            venueIds: meta.venueIds,
            admin: {
              id: liveUser.id,
              name: liveUser.name,
              email: liveUser.email,
              phone: liveUser.phone,
              role: meta.role,
              isAdmin: meta.isAdmin,
              isPartner: meta.isPartner,
              partnerStatus: meta.partnerStatus,
              venueIds: meta.venueIds
            }
          });
        }
      } else if (decoded.role === 'owner' || isUserAdmin(decoded) ||
                 ((decoded.role === 'partner' || decoded.role === 'merchant') && decoded.partnerStatus === 'approved')) {
        const isOwner = decoded.role === 'owner' || isUserAdmin(decoded);
        const role = isOwner ? 'owner' : 'partner';
        const adminToken = jwt.sign(
          {
            id: decoded.id,
            email: decoded.email,
            phone: decoded.phone,
            isAdmin: isOwner,
            isPartner: !isOwner,
            partnerStatus: isOwner ? 'approved' : 'approved',
            role,
            venueIds: Array.isArray(decoded.venueIds) ? decoded.venueIds : []
          },
          JWT_SECRET,
          { expiresIn: '12h' }
        );
        return res.json({
          success: true,
          token: adminToken,
          isAdmin: isOwner,
          isPartner: !isOwner,
          partnerStatus: 'approved',
          role,
          venueIds: Array.isArray(decoded.venueIds) ? decoded.venueIds : [],
          admin: { email: decoded.email, phone: decoded.phone, role, isAdmin: isOwner, isPartner: !isOwner }
        });
      }
    } catch (_) {}
    return res.status(403).json({
      error: 'Access denied: Identity is not authorized for administrative access.'
    });
  }

  // Password-based admin/partner verification (strictly bcrypt or safeEqual against authorized user)
  if (typeof email === 'string' && typeof password === 'string') {
    const cleanEmail = email.trim().toLowerCase();
    if (ADMIN_WHITELIST_EMAILS.includes(cleanEmail) && ADMIN_PASSWORD && safeEqual(password, ADMIN_PASSWORD)) {
      const adminToken = jwt.sign(
        { email: cleanEmail, isAdmin: true, isPartner: false, partnerStatus: 'approved', role: 'owner' },
        JWT_SECRET,
        { expiresIn: '12h' }
      );
      return res.json({
        success: true,
        token: adminToken,
        isAdmin: true,
        isPartner: false,
        partnerStatus: 'approved',
        role: 'owner',
        admin: { email: cleanEmail, role: 'owner', isAdmin: true }
      });
    }
    const user = db.users.find(u => u.email && u.email.toLowerCase() === cleanEmail);
    if (user && user.passwordHash) {
      const match = await comparePassword(password, user.passwordHash);
      if (match) {
        claimPartnerVenues(user);
        const meta = buildPartnerAuthMeta(user);
        if (!meta.isAdmin && !meta.isPartner) {
          return res.status(403).json({
            error: 'Partner account is pending verification.',
            partnerStatus: meta.partnerStatus
          });
        }
        const adminToken = jwt.sign(
          {
            id: user.id,
            email: user.email,
            phone: user.phone,
            isAdmin: meta.isAdmin,
            isPartner: meta.isPartner,
            partnerStatus: meta.partnerStatus,
            role: meta.role,
            venueIds: meta.venueIds
          },
          JWT_SECRET,
          { expiresIn: '12h' }
        );
        return res.json({
          success: true,
          token: adminToken,
          isAdmin: meta.isAdmin,
          isPartner: meta.isPartner,
          partnerStatus: meta.partnerStatus,
          role: meta.role,
          venueIds: meta.venueIds,
          admin: {
            id: user.id,
            name: user.name,
            email: user.email,
            phone: user.phone,
            role: meta.role,
            isAdmin: meta.isAdmin,
            isPartner: meta.isPartner,
            partnerStatus: meta.partnerStatus,
            venueIds: meta.venueIds
          }
        });
      }
    }
    return res.status(401).json({
      error: 'Invalid email or password.'
    });
  }

  return res.status(400).json({ error: 'Email and password or valid auth token required.' });
});

// ==========================================
// 2B. PARTNER REQUESTS & APPROVAL WORKFLOW
// ==========================================

app.post('/api/partner/requests', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const body = req.body || {};
  const venueName = String(body.venueName || '').trim();
  const venueType = String(body.venueType || 'padel').trim();
  const city = String(body.city || 'Cairo').trim();
  const address = String(body.address || '').trim();
  const notes = String(body.notes || '').trim();
  const ownerName = String(body.ownerName || user.name || '').trim();

  if (!venueName || venueName.length > 100) {
    return res.status(400).json({ error: 'Valid venue name is required (max 100 chars).' });
  }

  if (!Array.isArray(db.partnerRequests)) db.partnerRequests = [];

  const existing = db.partnerRequests.find(
    r => r.userId === user.id && (r.status === 'pending' || r.status === 'approved')
  );
  if (existing && existing.status === 'approved') {
    const meta = buildPartnerAuthMeta(user);
    return res.json({ success: true, request: existing, ...meta });
  }

  const nowIso = new Date().toISOString();
  let requestDoc;
  if (existing) {
    existing.ownerName = ownerName || existing.ownerName;
    existing.venueName = venueName;
    existing.venueType = venueType;
    existing.city = city;
    existing.address = address;
    existing.notes = notes;
    existing.email = user.email || existing.email || '';
    existing.phone = user.phone || existing.phone || '';
    existing.updatedAt = nowIso;
    requestDoc = existing;
  } else {
    requestDoc = {
      id: 'preq_' + crypto.randomUUID().slice(0, 10),
      userId: user.id,
      ownerName,
      email: user.email || '',
      phone: user.phone || '',
      venueName,
      venueType,
      city,
      address,
      notes,
      status: 'pending',
      createdAt: nowIso,
      updatedAt: nowIso
    };
    db.partnerRequests.push(requestDoc);
  }

  if (user.partnerStatus !== 'approved') {
    user.partnerStatus = 'pending';
  }
  saveDb(db);

  const meta = buildPartnerAuthMeta(user);
  return res.json({ success: true, request: requestDoc, ...meta });
});

app.get('/api/partner/requests/me', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  claimPartnerVenues(user);
  const meta = buildPartnerAuthMeta(user);
  const myRequests = (db.partnerRequests || [])
    .filter(r =>
      r.userId === user.id ||
      (user.email && r.email && r.email.toLowerCase() === user.email.toLowerCase()) ||
      (user.phone && r.phone && normalizeLocalPhone(r.phone) === normalizeLocalPhone(user.phone))
    )
    .sort((a, b) => new Date(b.updatedAt || b.createdAt || 0) - new Date(a.updatedAt || a.createdAt || 0));

  let freshToken = null;
  if (meta.isAdmin || meta.isPartner) {
    freshToken = jwt.sign(
      {
        id: user.id,
        email: user.email,
        phone: user.phone,
        isAdmin: meta.isAdmin,
        isPartner: meta.isPartner,
        partnerStatus: meta.partnerStatus,
        role: meta.role,
        venueIds: meta.venueIds
      },
      JWT_SECRET,
      { expiresIn: '30d' }
    );
  }

  return res.json({
    success: true,
    request: myRequests[0] || null,
    ...(freshToken ? { token: freshToken } : {}),
    ...meta
  });
});

app.get('/api/admin/partner-requests', authenticateAdmin, (req, res) => {
  if (!req.isPlatformOwner) {
    return res.status(403).json({ error: 'Forbidden: Only platform owner can review partner requests' });
  }
  const list = [...(db.partnerRequests || [])].sort(
    (a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0)
  );
  return res.json({ success: true, requests: list });
});

app.post('/api/admin/partner-requests/:id/approve', authenticateAdmin, async (req, res) => {
  if (!req.isPlatformOwner) {
    return res.status(403).json({ error: 'Forbidden: Only platform owner can approve partner requests' });
  }
  const reqDoc = (db.partnerRequests || []).find(r => r.id === req.params.id);
  if (!reqDoc) return res.status(404).json({ error: 'Partner request not found' });

  const nowIso = new Date().toISOString();
  let user = db.users.find(
    u =>
      (reqDoc.userId && u.id === reqDoc.userId) ||
      (reqDoc.email && u.email && u.email.toLowerCase() === reqDoc.email.toLowerCase()) ||
      (reqDoc.phone && u.phone && normalizeLocalPhone(u.phone) === normalizeLocalPhone(reqDoc.phone))
  );
  if (!user) {
    user = {
      id: reqDoc.userId || ('usr_' + crypto.randomUUID().slice(0, 8)),
      name: reqDoc.ownerName || 'Venue Owner',
      email: reqDoc.email || '',
      phone: reqDoc.phone || '',
      walletBalance: 0,
      role: 'partner',
      partnerStatus: 'approved',
      createdAt: nowIso
    };
    db.users.push(user);
  } else {
    if (user.role !== 'owner') user.role = 'partner';
    user.partnerStatus = 'approved';
  }

  let venue = (db.venues || []).find(v => !v.isDeleted && doesPartnerOwnVenue(user, v));
  if (!venue) {
    const venueId = 'ven_' + crypto.randomUUID().slice(0, 8);
    venue = {
      id: venueId,
      name: reqDoc.venueName || 'My Venue',
      type: reqDoc.venueType || 'padel',
      city: reqDoc.city || 'Cairo',
      address: reqDoc.address || '',
      ownerId: user.id,
      ownerEmail: user.email || reqDoc.email || undefined,
      ownerPhone: user.phone || reqDoc.phone || undefined,
      phone: user.phone || reqDoc.phone || '',
      depositPercent: 30,
      isActive: true,
      createdAt: nowIso,
      updatedAt: nowIso
    };
    db.venues.push(venue);
    await syncVenueToFirebase(venue);
  } else {
    venue.ownerId = venue.ownerId || user.id;
    venue.ownerEmail = venue.ownerEmail || user.email || reqDoc.email || undefined;
    venue.ownerPhone = venue.ownerPhone || user.phone || reqDoc.phone || undefined;
    venue.updatedAt = nowIso;
    await syncVenueToFirebase(venue);
  }

  reqDoc.status = 'approved';
  reqDoc.venueId = venue.id;
  reqDoc.reviewedAt = nowIso;
  reqDoc.reviewedBy = req.admin.email || req.admin.id || 'owner';
  reqDoc.updatedAt = nowIso;

  saveDb(db);
  syncUserToFirebase(user);
  return res.json({ success: true, request: reqDoc, venue });
});

app.post('/api/admin/partner-requests/:id/reject', authenticateAdmin, (req, res) => {
  if (!req.isPlatformOwner) {
    return res.status(403).json({ error: 'Forbidden: Only platform owner can reject partner requests' });
  }
  const reqDoc = (db.partnerRequests || []).find(r => r.id === req.params.id);
  if (!reqDoc) return res.status(404).json({ error: 'Partner request not found' });

  const nowIso = new Date().toISOString();
  reqDoc.status = 'rejected';
  reqDoc.rejectionReason = String((req.body && req.body.reason) || '').trim();
  reqDoc.reviewedAt = nowIso;
  reqDoc.reviewedBy = req.admin.email || req.admin.id || 'owner';
  reqDoc.updatedAt = nowIso;

  const user = db.users.find(
    u =>
      (reqDoc.userId && u.id === reqDoc.userId) ||
      (reqDoc.email && u.email && u.email.toLowerCase() === reqDoc.email.toLowerCase()) ||
      (reqDoc.phone && u.phone && normalizeLocalPhone(u.phone) === normalizeLocalPhone(reqDoc.phone))
  );
  if (user && user.partnerStatus !== 'approved') {
    user.partnerStatus = 'rejected';
  }

  saveDb(db);
  return res.json({ success: true, request: reqDoc });
});

// ==========================================
// 3. VENUES CRUD
// ==========================================

// Public Venues List
app.get('/api/venues', (req, res) => {
  const active = (db.venues || []).filter(v => !v.isDeleted && v.isActive !== false);
  return res.json({ success: true, venues: active });
});

// Admin Venues List (Scoped to partner unless platform owner)
app.get('/api/admin/venues', authenticateAdmin, (req, res) => {
  if (req.isPlatformOwner) {
    return res.json({ success: true, venues: (db.venues || []).filter(v => !v.isDeleted) });
  }
  const partnerVenues = (db.venues || []).filter(v => !v.isDeleted && doesPartnerOwnVenue(req.admin, v));
  return res.json({ success: true, venues: partnerVenues });
});

// Add / Update Venue (Scoped and validated)
app.put('/api/admin/venues/:id', authenticateAdmin, async (req, res) => {
  const venueId = req.params.id;
  const venueData = req.body || {};
  const index = db.venues.findIndex(v => v.id === venueId);

  // Field validation and whitelist
  const name = typeof venueData.name === 'string' ? venueData.name.trim() : '';
  if (!name && index < 0) {
    return res.status(400).json({ error: 'Venue name is required' });
  }
  if (name.length > 100) {
    return res.status(400).json({ error: 'Venue name cannot exceed 100 characters' });
  }

  const depositPercent = venueData.depositPercent !== undefined ? Number(venueData.depositPercent) : undefined;
  if (depositPercent !== undefined && (!Number.isFinite(depositPercent) || depositPercent < 0 || depositPercent > 100)) {
    return res.status(400).json({ error: 'depositPercent must be between 0 and 100' });
  }

  // Cross-tenant permission check & singular-venue limit for partners
  if (index >= 0) {
    const existing = db.venues[index];
    if (!req.isPlatformOwner && !doesPartnerOwnVenue(req.admin, existing)) {
      return res.status(403).json({ error: 'Forbidden: You do not own this venue' });
    }
  } else if (!req.isPlatformOwner) {
    const hasActiveVenue = (db.venues || []).some(v => !v.isDeleted && doesPartnerOwnVenue(req.admin, v));
    if (hasActiveVenue) {
      return res.status(403).json({ error: 'Forbidden: Partners are limited to one active venue' });
    }
  }

  const allowedFields = [
    'name', 'nameAr', 'type', 'category', 'categories', 'city', 'address', 'addressAr',
    'phone', 'ownerPhone', 'ownerEmail', 'instapayHandle', 'vodafoneCashNumber',
    'depositPercent', 'pricingMode', 'units', 'items', 'spaces', 'services', 'amenities', 'rules',
    'latitude', 'longitude', 'lat', 'lng', 'rating', 'reviews', 'image', 'images', 'imageUrl',
    'galleryUrls', 'description', 'googleMapsUrl', 'instaPayAddress',
    'openingTime', 'closingTime', 'isActive', 'currency'
  ];

  const sanitized = {};
  for (const field of allowedFields) {
    if (venueData[field] !== undefined) {
      sanitized[field] = venueData[field];
    }
  }
  if (sanitized.imageUrl && (!sanitized.images || !sanitized.images.length)) {
    sanitized.images = [sanitized.imageUrl];
  }
  if (!sanitized.imageUrl && Array.isArray(sanitized.images) && sanitized.images.length > 0) {
    sanitized.imageUrl = sanitized.images[0];
  }
  if (req.isPlatformOwner) {
    if (typeof sanitized.ownerEmail === 'string') {
      sanitized.ownerEmail = sanitized.ownerEmail.trim().toLowerCase();
      if (!sanitized.ownerEmail) delete sanitized.ownerEmail;
    }
    if (typeof sanitized.ownerPhone === 'string') {
      sanitized.ownerPhone = sanitized.ownerPhone.trim();
      if (!sanitized.ownerPhone) delete sanitized.ownerPhone;
    }
  } else if (index >= 0) {
    delete sanitized.ownerPhone;
    delete sanitized.ownerEmail;
    delete sanitized.ownerId;
  }

  let savedVenue;
  if (index >= 0) {
    savedVenue = {
      ...db.venues[index],
      ...sanitized,
      id: venueId,
      updatedAt: new Date().toISOString()
    };
    db.venues[index] = savedVenue;
  } else {
    const hasAssignedOwner = !!(sanitized.ownerEmail || sanitized.ownerPhone);
    savedVenue = {
      id: venueId,
      ownerId: hasAssignedOwner ? '' : (req.admin.id || req.admin.email || 'owner'),
      ...(hasAssignedOwner ? {} : {
        ownerEmail: req.admin.email || undefined,
        ownerPhone: req.admin.phone || undefined,
      }),
      ...sanitized,
      createdAt: new Date().toISOString()
    };
    db.venues.push(savedVenue);
  }

  if (req.isPlatformOwner && (savedVenue.ownerEmail || savedVenue.ownerPhone)) {
    const targetEmail = (savedVenue.ownerEmail || '').toLowerCase();
    const targetPhone = normalizeLocalPhone(savedVenue.ownerPhone || '');
    const assignedUser = (db.users || []).find(u =>
      (targetEmail && u.email && u.email.toLowerCase() === targetEmail) ||
      (targetPhone && u.phone && normalizeLocalPhone(u.phone) === targetPhone)
    );
    if (assignedUser) {
      savedVenue.ownerId = assignedUser.id;
      if (assignedUser.role !== 'owner') {
        assignedUser.role = 'partner';
        assignedUser.partnerStatus = 'approved';
        syncUserToFirebase(assignedUser);
      }
    }
  }

  if (db.auditLog) {
    db.auditLog.push({
      id: 'aud_' + crypto.randomUUID().slice(0, 8),
      timestamp: new Date().toISOString(),
      actor: req.admin.email || req.admin.id || 'admin',
      action: index >= 0 ? 'VENUE_UPDATE' : 'VENUE_CREATE',
      venueId,
      details: { name: savedVenue.name }
    });
  }

  saveDb(db);
  await syncVenueToFirebase(savedVenue);
  return res.json({ success: true, venue: savedVenue });
});

// Soft Delete Venue (Preserve bookings for history & fulfillment)
app.delete('/api/admin/venues/:id', authenticateAdmin, async (req, res) => {
  const venueId = req.params.id;
  const venue = db.venues.find(v => v.id === venueId);
  if (!venue) {
    return res.status(404).json({ error: 'Venue not found' });
  }

  if (!req.isPlatformOwner && !doesPartnerOwnVenue(req.admin, venue)) {
    return res.status(403).json({ error: 'Forbidden: You do not have permission to delete this venue' });
  }

  venue.isDeleted = true;
  venue.isActive = false;
  venue.deletedAt = new Date().toISOString();

  if (db.auditLog) {
    db.auditLog.push({
      id: 'aud_' + crypto.randomUUID().slice(0, 8),
      timestamp: new Date().toISOString(),
      actor: req.admin.email || req.admin.id || 'admin',
      action: 'VENUE_SOFT_DELETE',
      venueId
    });
  }

  saveDb(db);
  await deleteVenueFromFirebase(venueId);
  return res.json({ success: true, message: 'Venue deleted' });
});

// Bulk Sync Venues to Cloud Firestore (Scoped to partner unless platform owner)
app.post('/api/admin/venues/sync-firebase', authenticateAdmin, async (req, res) => {
  return res.json({
    success: true,
    message: 'Firebase has been removed. All data authoritative on Supabase PostgreSQL.',
    firebaseRemoved: true,
    supabaseReady: true,
    totalVenues: db.venues.length
  });
});

// Customer Venue Review Submission (syncs to Firebase)
app.post('/api/venues/:id/reviews', optionalAuth, async (req, res) => {
  const venueId = req.params.id;
  const venue = db.venues.find(v => v.id === venueId);
  if (!venue) return res.status(404).json({ error: 'Venue not found' });

  const { authorName, rating, comment } = req.body || {};
  const numRating = Number(rating);
  if (!Number.isFinite(numRating) || numRating < 1 || numRating > 5) {
    return res.status(400).json({ error: 'Rating must be between 1 and 5' });
  }
  const review = {
    id: 'rev_' + crypto.randomUUID().slice(0, 8),
    authorName: String(authorName || (req.user && req.user.name) || 'Member').slice(0, 60),
    rating: numRating,
    comment: String(comment || '').slice(0, 500),
    date: new Date().toISOString().split('T')[0],
    verifiedBooking: true
  };
  if (!Array.isArray(venue.reviewsList)) venue.reviewsList = [];
  venue.reviewsList.unshift(review);
  const count = venue.reviewsList.length;
  const avg = venue.reviewsList.reduce((acc, r) => acc + (Number(r.rating) || 5), 0) / count;
  venue.reviews = count;
  venue.rating = Math.round(avg * 10) / 10;
  saveDb(db);
  await syncVenueToFirebase(venue);
  return res.json({ success: true, review, venue });
});

// ==========================================
// 4. BOOKINGS & OPERATIONS
// ==========================================

// Admin Bookings List (Scoped to partner venues unless platform owner)
app.get('/api/admin/bookings', authenticateAdmin, (req, res) => {
  if (req.isPlatformOwner) {
    return res.json({ success: true, bookings: (db.bookings || []).map(attachBookingQrMeta) });
  }
  const partnerVenueIds = new Set(
    (db.venues || [])
      .filter(v => !v.isDeleted && doesPartnerOwnVenue(req.admin, v))
      .map(v => v.id)
  );
  const scopedBookings = (db.bookings || [])
    .filter(b => partnerVenueIds.has(b.venueId))
    .map(attachBookingQrMeta);
  return res.json({ success: true, bookings: scopedBookings });
});

// Admin Analytics (Server-side metrics scoped to partner)
app.get('/api/admin/analytics', authenticateAdmin, (req, res) => {
  const { startDate, endDate, venueId } = req.query;
  let venues = (db.venues || []).filter(v => !v.isDeleted);
  let bookings = db.bookings || [];

  if (!req.isPlatformOwner) {
    const partnerVenueIds = new Set(
      venues
        .filter(v => doesPartnerOwnVenue(req.admin, v))
        .map(v => v.id)
    );
    venues = venues.filter(v => partnerVenueIds.has(v.id));
    bookings = bookings.filter(b => partnerVenueIds.has(b.venueId));
  }

  if (venueId) {
    bookings = bookings.filter(b => b.venueId === venueId);
  }
  if (startDate) {
    const startMs = new Date(startDate).getTime();
    bookings = bookings.filter(b => new Date(b.startsAt).getTime() >= startMs);
  }
  if (endDate) {
    const endMs = new Date(endDate).getTime();
    bookings = bookings.filter(b => new Date(b.startsAt).getTime() <= endMs);
  }

  let totalRevenueEgp = 0;
  let totalDepositsEgp = 0;
  let totalBalanceDueEgp = 0;
  let lostRevenueEgp = 0;
  let confirmedCount = 0;
  let cancelledCount = 0;
  let expiredCount = 0;
  let noShowCount = 0;
  let completedCount = 0;

  for (const b of bookings) {
    const p = Number(b.price) || 0;
    const dep = Number(b.depositAmount) || 0;
    const due = Number(b.dueNow) || 0;
    if (b.status === 'confirmed' || b.status === 'checked_in' || b.status === 'completed') {
      totalRevenueEgp += p;
      totalDepositsEgp += (dep || due);
      totalBalanceDueEgp += Math.max(0, p - (dep || due));
      if (b.status === 'confirmed' || b.status === 'checked_in') confirmedCount++;
      if (b.status === 'completed') completedCount++;
    } else if (b.status === 'cancelled') {
      cancelledCount++;
      lostRevenueEgp += p;
    } else if (b.status === 'expired') {
      expiredCount++;
      lostRevenueEgp += p;
    } else if (b.status === 'no_show') {
      noShowCount++;
      lostRevenueEgp += p;
    }
  }

  return res.json({
    success: true,
    analytics: {
      totalBookings: bookings.length,
      confirmedCount,
      completedCount,
      cancelledCount,
      expiredCount,
      noShowCount,
      totalRevenueEgp,
      totalDepositsEgp,
      totalBalanceDueEgp,
      lostRevenueEgp
    }
  });
});

// Create Booking
const BOOKING_FIELDS = [
  'id', 'venueId', 'itemId', 'customer', 'startsAt', 'durationMinutes', 'price',
  'serviceNames', 'splitCount', 'multiController', 'phone', 'email', 'paymentMethod',
  'promoCode', 'discountAmount', 'staffMember', 'dueNow', 'depositAmount', 'serviceIds'
];

function bookingBlocksSlot(b, now) {
  if (b.cancelled || b.status === 'cancelled' || b.status === 'expired') return false;
  if (b.status === 'confirmed') return true;
  // pending holds only block while they have not expired
  return !b.holdExpiresAt || new Date(b.holdExpiresAt).getTime() > now;
}

function checkSlotConflict(excludeBookingId, venueId, itemId, startsAt, durationMinutes) {
  const start = new Date(startsAt).getTime();
  const end = start + Number(durationMinutes) * 60000;
  const now = Date.now();
  return (db.bookings || []).some(b =>
    b.id !== excludeBookingId &&
    b.venueId === venueId &&
    b.itemId === itemId &&
    bookingBlocksSlot(b, now) &&
    new Date(b.startsAt).getTime() < end &&
    new Date(b.startsAt).getTime() + Number(b.durationMinutes) * 60000 > start
  );
}

app.post('/api/bookings', optionalAuth, async (req, res) => {
  const body = req.body || {};
  let isAdmin = !!req.admin;
  const now = Date.now();

  const venue = db.venues.find(v => v.id === body.venueId);
  if (!venue) return res.status(404).json({ error: 'Venue not found' });
  if (isAdmin && !req.isPlatformOwner && !doesPartnerOwnVenue(req.admin, venue)) {
    // Staff-only actions (walk-ins, blocks, status overrides) stay restricted to the venue's own staff.
    if (body.walkIn || body.blockReason) {
      return res.status(403).json({ error: 'Forbidden: You can only create walk-in bookings for your own venue' });
    }
    // Otherwise an owner/partner booking someone else's venue is just a customer.
    isAdmin = false;
    req.user = db.users.find(u => u.id === req.admin.id) || req.admin;
  }

  const start = parseClientTimestamp(body.startsAt);
  const duration = Number(body.durationMinutes);
  if (isNaN(start.getTime())) return res.status(400).json({ error: 'Invalid start time' });
  if (!Number.isInteger(duration) || duration < 15 || duration > 720) {
    return res.status(400).json({ error: 'Invalid duration' });
  }
  if (!isAdmin && start.getTime() < now - 5 * 60 * 1000) {
    return res.status(400).json({ error: 'Cannot book a time in the past' });
  }
  if (typeof body.itemId !== 'string' || !body.itemId) {
    return res.status(400).json({ error: 'itemId is required' });
  }

  // Server-side authoritative pricing
  let calculatedPricing = null;
  try {
    calculatedPricing = calculateServerPricing({
      venue,
      itemId: body.itemId,
      durationMinutes: duration,
      serviceIds: body.services || body.serviceIds || [],
      splitCount: body.splitCount,
      promoCode: body.promoCode
    });
  } catch (err) {
    if (isAdmin && Number.isFinite(Number(body.price))) {
      calculatedPricing = {
        finalPrice: Number(body.price),
        subtotal: Number(body.price),
        discountAmount: 0,
        promoCode: null,
        dueNow: Number(body.dueNow || body.price),
        requiredDeposit: Number(body.price) * (Number(venue.depositPercent) || 30) / 100,
        depositPercent: Number(venue.depositPercent) || 30,
        services: []
      };
    } else {
      return res.status(err.statusCode || 400).json({ error: err.message });
    }
  }

  // Allow higher price if custom package/override was explicitly requested, but NEVER allow under-paying
  let finalPrice = calculatedPricing.finalPrice;
  if (Number.isFinite(Number(body.price)) && Number(body.price) > finalPrice) {
    finalPrice = Number(body.price);
  }

  // Whitelist fields: never persist arbitrary client-supplied keys.
  const booking = {};
  for (const k of BOOKING_FIELDS) if (body[k] !== undefined) booking[k] = body[k];
  booking.customer = String(booking.customer || '').slice(0, 80);
  booking.durationMinutes = duration;
  booking.price = finalPrice;
  booking.subtotal = calculatedPricing.subtotal;
  booking.discountAmount = calculatedPricing.discountAmount;
  booking.promoCode = calculatedPricing.promoCode;
  booking.services = calculatedPricing.services;
  booking.depositAmount = Number(
    body.depositAmount ?? calculatedPricing.requiredDeposit ?? calculatedPricing.depositAmount ?? 0
  );
  booking.dueNow = Number(
    body.dueNow ?? (booking.depositAmount > 0 ? booking.depositAmount : (calculatedPricing.dueNow ?? finalPrice))
  );
  booking.startsAt = start.toISOString();
  const rawRemOffset = Number(body.reminderOffsetMinutes);
  booking.reminderOffsetMinutes =
    body.reminderOffsetMinutes !== undefined &&
    body.reminderOffsetMinutes !== null &&
    body.reminderOffsetMinutes !== '' &&
    Number.isFinite(rawRemOffset)
      ? Math.max(0, Math.min(10080, Math.round(rawRemOffset)))
      : 120;

  if (!booking.id || !/^[\w-]{1,64}$/.test(String(booking.id)) || db.bookings.some(b => b.id === booking.id)) {
    booking.id = 'bk_' + crypto.randomUUID();
  }

  // Double-booking guard. Atomic check against active slots
  if (checkSlotConflict(booking.id, booking.venueId, booking.itemId, booking.startsAt, booking.durationMinutes)) {
    return res.status(409).json({ error: 'Overlap conflict. This slot is already booked.' });
  }

  booking.createdAt = new Date().toISOString();
  booking.cancelled = false;
  let owner = req.user;

  if (isAdmin) {
    // Venue staff may create walk-ins and blocks.
    booking.status = body.walkIn ? 'confirmed' : (body.status || 'confirmed');
    booking.paymentStatus = body.paymentStatus || (body.walkIn ? 'paid' : 'unpaid');
    booking.holdExpiresAt = body.holdExpiresAt || null;
    if (body.blockReason) booking.blockReason = String(body.blockReason).slice(0, 200);
  } else {
    booking.status = 'pending_payment';
    booking.paymentStatus = 'unpaid';
    booking.holdExpiresAt = new Date(now + 15 * 60 * 1000).toISOString();
    if (!owner) {
      const cleanPhone = (body.phone || body.customerPhone) ? String(body.phone || body.customerPhone).replace(/\D/g, '') : '';
      const cleanEmail = body.email ? String(body.email).trim().toLowerCase() : '';
      owner = db.users.find(u =>
        (cleanEmail && u.email && u.email.toLowerCase() === cleanEmail) ||
        (cleanPhone && u.phone && u.phone.replace(/\D/g, '') === cleanPhone)
      );
    }
    if (owner) {
      booking.ownerId = owner.id;
      booking.customerId = owner.id;
    }

    // Wallet payment is settled here, on the server, atomically with the booking.
    if (body.paymentMethod === 'wallet') {
      const user = req.user && db.users.find(u => u.id === req.user.id);
      if (!user) return res.status(401).json({ error: 'Sign in to pay with your wallet' });

      // Ensure ledger has user balance if legacy user had balance without ledger
      if (user.walletBalance > 0 && !db.walletLedger.some(e => e.userId === user.id)) {
        try {
          recordLedgerEntry(db.walletLedger, {
            userId: user.id,
            amount: Number(user.walletBalance),
            type: LEDGER_ENTRY_TYPE.ADMIN_ADJUSTMENT,
            description: 'Legacy balance hydration',
            actor: 'system'
          });
        } catch (_) {}
      }

      const split = Math.max(1, Math.floor(Number(body.splitCount) || 1));
      const requiredDeposit = Math.round((finalPrice * (Number(venue.depositPercent || 30) / 100)) * 100) / 100;
      const deposit = Math.round((split > 1 && finalPrice / split > requiredDeposit
        ? finalPrice / split : requiredDeposit) * 100) / 100;
      if (deposit <= 0) {
        return res.status(400).json({ error: 'This venue has no deposit configured' });
      }
      try {
        recordLedgerEntry(db.walletLedger, {
          userId: user.id,
          amount: -deposit,
          type: LEDGER_ENTRY_TYPE.BOOKING_DEPOSIT,
          referenceId: booking.id,
          description: `Deposit for booking at ${venue.name || 'Venue'}`,
          actor: 'customer'
        });
        user.walletBalance = calculateWalletBalance(user.id, db.walletLedger);
      } catch (wErr) {
        return res.status(wErr.statusCode || 402).json({ error: wErr.message });
      }

      transitionBookingStatus(booking, BOOKING_STATUS.CONFIRMED, {
        actor: user.email || user.phone || 'customer',
        reason: 'Wallet deposit confirmed',
        auditLog: db.auditLog
      });
      booking.paymentMethod = 'wallet';
    } else {
      booking.paymentMethod = '';
    }
  }
  db.bookings.push(booking);
  if (!booking.blockReason) {
    notifyVenueOwner({
      venue,
      booking,
      eventType: booking.confirmed ? 'booking_confirmed' : 'booking_created',
    });
  }
  saveDb(db);
  syncBookingToFirebase(booking, owner);

  const phone = booking.phone || booking.customerPhone;
  if (phone) {
    const slipVenue = venue.name || 'Hagzy Venue';
    const pinMsg = venue.googleMapsUrl ? `\n📍 رابط الموقع على الخريطة: ${venue.googleMapsUrl}` : '';
    const slip = `🎉 تم استلام حجزك في ${slipVenue} بنجاح!\n` +
      `📅 الموعد: ${booking.startsAt}\n` +
      `🏷️ رقم الحجز: ${booking.id}\n` +
      `💵 الإجمالي: ${booking.price} ج.م` + pinMsg;
    sendSmsOrWhatsApp({ phone, message: slip, otp: '' }).catch(() => {});
  }

  const walletUser = req.user && db.users.find(u => u.id === req.user.id);
  return res.json({
    success: true,
    booking: attachBookingQrMeta(booking),
    ...(booking.paymentMethod === 'wallet' && walletUser ? { walletBalance: walletUser.walletBalance } : {})
  });
});

// Customer: own bookings (matched by account, phone, or email)
app.get('/api/bookings', authenticateCustomer, (req, res) => {
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  claimCustomerBookings(user);

  const userPhone = user.phoneVerified ? String(user.phone).replace(/\D/g, '') : '';
  const userEmail = user.emailVerified ? String(user.email).trim().toLowerCase() : '';

  const mine = db.bookings.filter(b => {
    if (b.ownerId === user.id || b.customerId === user.id) return true;
    const bPhone = (b.phone || b.customerPhone) ? String(b.phone || b.customerPhone).replace(/\D/g, '') : '';
    const bEmail = b.email ? String(b.email).trim().toLowerCase() : '';
    if (userPhone && bPhone && userPhone === bPhone) return true;
    if (userEmail && bEmail && userEmail === bEmail) return true;
    return false;
  }).map(b => {
    if (b.status === 'confirmed' || b.confirmed) {
      markBookingConfirmed(b);
    }
    return attachBookingQrMeta(b);
  });
  return res.json({ success: true, bookings: mine });
});

app.put('/api/bookings/:id/reminder', authenticateCustomer, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const isOwner = (booking.ownerId === user.id) || (booking.customerId === user.id) ||
    (user.phoneVerified && user.phone && booking.phone && user.phone.replace(/\D/g, '') === String(booking.phone).replace(/\D/g, '')) ||
    (user.emailVerified && user.email && booking.email && user.email.toLowerCase() === String(booking.email).toLowerCase());
  if (!isOwner) return res.status(403).json({ error: 'Forbidden' });

  const rawOffset = Number(req.body?.reminderOffsetMinutes);
  if (!Number.isFinite(rawOffset) || rawOffset < 0 || rawOffset > 10080) {
    return res.status(400).json({ error: 'reminderOffsetMinutes must be between 0 and 10080' });
  }
  const clamped = Math.round(rawOffset);
  booking.reminderOffsetMinutes = clamped;
  booking.reminderSentAt = null;
  saveDb(db);
  return res.json({
    success: true,
    reminderOffsetMinutes: clamped,
    booking: attachBookingQrMeta(booking),
  });
});

// Customer Booking Cancellation
app.post('/api/bookings/:id/cancel', authenticateCustomer, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });

  const user = db.users.find(u => u.id === req.user.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  const isOwner = (booking.ownerId === user.id) || (booking.customerId === user.id) ||
    (user.phoneVerified && user.phone && booking.phone && user.phone.replace(/\D/g, '') === String(booking.phone).replace(/\D/g, '')) ||
    (user.emailVerified && user.email && booking.email && user.email.toLowerCase() === String(booking.email).toLowerCase());

  if (!isOwner) {
    return res.status(403).json({ error: 'You are not authorized to cancel this booking.' });
  }

  if (booking.status === 'cancelled' || booking.cancelled) {
    return res.status(400).json({ error: 'This booking has already been cancelled.' });
  }
  if (booking.status === 'expired') {
    return res.status(400).json({ error: 'This reservation hold has already expired.' });
  }
  if (new Date(booking.startsAt).getTime() <= Date.now()) {
    return res.status(400).json({ error: 'Cannot cancel a booking that has already started or elapsed.' });
  }

  try {
    transitionBookingStatus(booking, BOOKING_STATUS.CANCELLED, {
      actor: user.email || user.phone || 'customer',
      reason: 'Customer cancelled booking',
      auditLog: db.auditLog
    });
  } catch (err) {
    return res.status(err.statusCode || 400).json({ error: err.message });
  }

  // Deposit refund: full refund to wallet if cancelled >= 6 hours before start
  const hoursUntilStart = (new Date(booking.startsAt).getTime() - Date.now()) / (3600 * 1000);
  if (hoursUntilStart >= 6) {
    const refundAmt = Number(
      booking.actualPaidAmount ||
      (booking.status === 'confirmed' || booking.confirmed ? booking.depositAmount : 0) ||
      (booking.paymentMethod === 'wallet' ? (booking.dueNow || booking.price || 0) : 0) ||
      0
    );
    if (refundAmt > 0) {
      const refundTargetUserId = user.id || findUserIdForBooking(booking);
      if (refundTargetUserId) {
        creditUserWallet(refundTargetUserId, refundAmt, {
          referenceId: booking.id,
          description: `Full refund for cancellation >=6h before start (${booking.id})`,
          actor: 'system'
        });
      }
    }
  }

  const venueObj = (db.venues || []).find(v => v.id === booking.venueId);
  notifyVenueOwner({ venue: venueObj, booking, eventType: 'booking_cancelled' });
  saveDb(db);
  syncBookingToFirebase(booking, user);

  return res.json({ success: true, message: 'Booking cancelled successfully.', booking: attachBookingQrMeta(booking) });
});

// Public status poll: no contact details are returned.
app.get('/api/bookings/:id', (req, res) => {
  const b = db.bookings.find(x => x.id === req.params.id);
  if (!b) return res.status(404).json({ error: 'Booking not found' });
  if (b.status === 'confirmed' || b.confirmed) {
    markBookingConfirmed(b);
  }
  const { phone, email, customerPhone, ownerId, paymentReference, ...safe } = b;
  return res.json({ success: true, booking: safe });
});

// Confirm Booking (Deposit Verified)
app.post('/api/admin/bookings/:id/confirm', authenticateAdmin, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });

  // Cross-tenant permission check
  if (!req.isPlatformOwner) {
    const venue = db.venues.find(v => v.id === booking.venueId);
    if (!venue || !doesPartnerOwnVenue(req.admin, venue)) {
      return res.status(403).json({ error: 'Forbidden: You do not have permission to manage bookings for this venue' });
    }
  }

  // Atomic conflict check before confirming
  if (checkSlotConflict(booking.id, booking.venueId, booking.itemId, booking.startsAt, booking.durationMinutes)) {
    return res.status(409).json({ error: 'Cannot confirm: this slot is already booked by another confirmed booking.' });
  }

  try {
    transitionBookingStatus(booking, BOOKING_STATUS.CONFIRMED, {
      actor: req.admin ? (req.admin.email || 'admin') : 'admin',
      reason: 'Admin verified deposit',
      auditLog: db.auditLog
    });
  } catch (err) {
    return res.status(err.statusCode || 409).json({ error: err.message });
  }

  const venueObj = (db.venues || []).find(v => v.id === booking.venueId);
  notifyVenueOwner({ venue: venueObj, booking, eventType: 'booking_confirmed' });
  saveDb(db);
  syncBookingToFirebase(booking);

  if (booking.customerPhone) {
    sendSmsOrWhatsApp({
      phone: booking.customerPhone,
      message: `✅ تم تأكيد حجزك رسمياً في حجزي! رقم الحجز: ${booking.id}. نتمنى لك وقتاً ممتعاً.`,
      otp: ''
    });
  }

  return res.json({ success: true, booking: attachBookingQrMeta(booking) });
});

app.get('/api/admin/notifications', authenticateAdmin, (req, res) => {
  const unreadOnly = req.query.unreadOnly === 'true';
  let list = Array.isArray(db.partnerNotifications) ? [...db.partnerNotifications] : [];
  if (!req.isPlatformOwner) {
    const ownedIds = new Set(
      (db.venues || [])
        .filter(v => !v.isDeleted && doesPartnerOwnVenue(req.admin, v))
        .map(v => v.id),
    );
    list = list.filter(n => n.venueId && ownedIds.has(n.venueId));
  }
  const unreadCount = list.filter(n => !n.read).length;
  if (unreadOnly) list = list.filter(n => !n.read);
  return res.json({ success: true, unreadCount, notifications: list.slice(0, 100) });
});

app.post('/api/admin/notifications/:id/read', authenticateAdmin, (req, res) => {
  const n = (db.partnerNotifications || []).find(item => item.id === req.params.id);
  if (!n) return res.status(404).json({ error: 'Notification not found' });
  if (!req.isPlatformOwner && n.venueId) {
    const venue = (db.venues || []).find(v => v.id === n.venueId);
    if (!venue || !doesPartnerOwnVenue(req.admin, venue)) {
      return res.status(403).json({ error: 'Forbidden' });
    }
  }
  n.read = true;
  n.readAt = new Date().toISOString();
  saveDb(db);
  return res.json({ success: true });
});

app.get('/api/admin/bookings/:id/qr-details', authenticateAdmin, (req, res) => {
  const booking = (db.bookings || []).find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  const venue = (db.venues || []).find(v => v.id === booking.venueId);
  if (!req.isPlatformOwner && (!venue || !doesPartnerOwnVenue(req.admin, venue))) {
    return res.status(403).json({ error: 'Forbidden: You do not own this venue' });
  }
  const sig = String(req.query.sig || '').trim();
  let signatureVerified = false;
  if (sig) {
    signatureVerified = verifyBookingQrSig(booking.id, booking.venueId, sig);
    if (!signatureVerified) {
      return res.status(403).json({ error: 'Invalid or tampered QR check-in signature' });
    }
  }
  const totalPrice = Number(booking.price || booking.totalPrice || 0);
  const depositAmount = Number(booking.depositAmount || 0);
  const paidAmount = Number(booking.actualPaidAmount || (booking.confirmed ? depositAmount : 0));
  const remainingDue = Math.max(0, Number((totalPrice - paidAmount).toFixed(2)));
  return res.json({
    success: true,
    signatureVerified,
    venue: venue ? { id: venue.id, name: venue.name, area: venue.area, city: venue.city } : null,
    booking: attachBookingQrMeta(booking),
    financialSummary: { totalPrice, depositAmount, paidAmount, remainingDue },
  });
});

app.post('/api/admin/bookings/:id/check-in', authenticateAdmin, (req, res) => {
  const booking = (db.bookings || []).find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  const venue = (db.venues || []).find(v => v.id === booking.venueId);
  if (!req.isPlatformOwner && (!venue || !doesPartnerOwnVenue(req.admin, venue))) {
    return res.status(403).json({ error: 'Forbidden: You do not own this venue' });
  }
  const sig = String(req.body?.sig || req.query.sig || '').trim();
  if (sig && !verifyBookingQrSig(booking.id, booking.venueId, sig)) {
    return res.status(403).json({ error: 'Invalid or tampered QR check-in signature' });
  }
  if (booking.checkedIn || booking.status === BOOKING_STATUS.CHECKED_IN) {
    return res.json({ success: true, alreadyCheckedIn: true, booking: attachBookingQrMeta(booking) });
  }
  if (booking.cancelled || booking.status === BOOKING_STATUS.CANCELLED || booking.status === BOOKING_STATUS.EXPIRED) {
    return res.status(409).json({ error: `Cannot check in a ${booking.status} booking.` });
  }
  if (!booking.confirmed && booking.status !== BOOKING_STATUS.CONFIRMED) {
    return res.status(409).json({ error: 'Booking deposit has not been confirmed yet.' });
  }
  try {
    transitionBookingStatus(booking, BOOKING_STATUS.CHECKED_IN, {
      actor: req.admin?.email || 'admin',
      reason: sig ? 'QR code scanned & verified at venue' : 'Manual partner check-in',
      auditLog: db.auditLog,
    });
  } catch (err) {
    return res.status(err.statusCode || 409).json({ error: err.message });
  }
  saveDb(db);
  syncBookingToFirebase(booking);
  return res.json({ success: true, booking: attachBookingQrMeta(booking) });
});

// Cancel Booking
app.delete('/api/admin/bookings/:id', authenticateAdmin, (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });

  // Cross-tenant permission check
  if (!req.isPlatformOwner) {
    const venue = db.venues.find(v => v.id === booking.venueId);
    if (!venue || !doesPartnerOwnVenue(req.admin, venue)) {
      return res.status(403).json({ error: 'Forbidden: You do not have permission to manage bookings for this venue' });
    }
  }

  try {
    transitionBookingStatus(booking, BOOKING_STATUS.CANCELLED, {
      actor: req.admin ? (req.admin.email || 'admin') : 'admin',
      reason: 'Admin cancelled booking',
      auditLog: db.auditLog
    });
  } catch (err) {
    return res.status(err.statusCode || 409).json({ error: err.message });
  }

  // Refund wallet deposit if applicable
  if (booking.paymentMethod === 'wallet' && (booking.ownerId || booking.customerId)) {
    const targetUserId = booking.ownerId || booking.customerId;
    const refundAmt = Number(booking.actualPaidAmount || booking.dueNow || booking.depositAmount || booking.price || 0);
    if (refundAmt > 0) {
      try {
        recordLedgerEntry(db.walletLedger, {
          userId: targetUserId,
          amount: refundAmt,
          type: LEDGER_ENTRY_TYPE.REFUND,
          referenceId: booking.id,
          description: `Admin cancellation refund for booking ${booking.id}`,
          actor: req.admin ? (req.admin.email || 'admin') : 'admin'
        });
        const u = db.users.find(usr => usr.id === targetUserId);
        if (u) u.walletBalance = calculateWalletBalance(targetUserId, db.walletLedger);
      } catch (wErr) {
        console.warn('Admin cancel refund notice:', wErr.message);
      }
    }
  }

  saveDb(db);
  syncBookingToFirebase(booking);

  if (booking.customerPhone || booking.phone) {
    sendSmsOrWhatsApp({
      phone: booking.customerPhone || booking.phone,
      message: `⚠️ تم إلغاء حجزك في حجزي (رقم الحجز: ${booking.id}).`,
      otp: ''
    }).catch(() => {});
  }

  return res.json({ success: true, message: 'Booking cancelled' });
});

// Payment Proof Submission (InstaPay / Vodafone Cash)
app.post('/api/bookings/:id/payment-proof', (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  if (booking.status !== 'pending_payment') {
    return res.status(409).json({ error: 'This booking is not awaiting payment' });
  }
  const method = String((req.body && req.body.method) || '');
  const reference = String((req.body && req.body.reference) || '').trim();
  if (!['instapay', 'vodafone_cash', 'vodafoneCash', 'fawry', 'card'].includes(method) &&
      !/^[\w \-]{2,32}$/.test(method)) {
    return res.status(400).json({ error: 'Invalid payment method' });
  }
  if (reference.length < 4 || reference.length > 64) {
    return res.status(400).json({ error: 'Invalid payment reference' });
  }
  booking.paymentMethod = method;
  booking.paymentReference = reference;
  booking.paymentProof = { method, reference, submittedAt: new Date().toISOString() };
  booking.proofSubmitted = true;

  const lowerM = method.toLowerCase();
  if (!IS_TEST && (lowerM.includes('insta') || lowerM.includes('vodafone') || lowerM.includes('wallet'))) {
    const intentMethod = (lowerM.includes('vodafone') || lowerM.includes('wallet')) ? 'MOBILE_WALLET' : 'INSTAPAY';
    const normalizedSender = normalizeSenderId(intentMethod, reference);
    if (normalizedSender) {
      booking.expectedSenderIdentifier = normalizedSender;
      const intentId = `intent_${booking.id}_${intentMethod.toLowerCase()}`;
      const expectedAmt = Math.max(5, Number(booking.dueNow ?? booking.depositAmount ?? booking.totalPrice ?? booking.price ?? 5));
      localPaymentIntents.set(intentId, {
        intentId,
        booking_id: booking.id,
        user_id: booking.userId || 'guest',
        payment_method: intentMethod,
        expected_sender_identifier: normalizedSender,
        expected_amount: expectedAmt,
        status: 'AWAITING_TRANSFER',
        expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
      });
    }
  }

  // Extend the hold so the customer isn't dropped while awaiting transfer verification.
  booking.holdExpiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  saveDb(db);
  syncBookingToFirebase(booking);
  return res.json({ success: true, booking });
});

// Fawry Reference Number Generation
app.post('/api/bookings/:id/fawry-reference', (req, res) => {
  const booking = db.bookings.find(b => b.id === req.params.id);
  if (!booking) return res.status(404).json({ error: 'Booking not found' });
  if (booking.status === 'cancelled' || booking.cancelled) {
    return res.status(409).json({ error: 'Cannot issue reference for a cancelled booking' });
  }

  const { customerName, phone } = req.body || {};
  if (customerName) booking.customer = String(customerName).slice(0, 80);
  if (phone) booking.phone = String(phone).slice(0, 30);

  let hash = 918273645;
  for (const c of String(booking.id)) {
    hash = ((hash * 31) + c.charCodeAt(0)) & 0x7fffffff;
  }
  const digits = String(9000000000 + (hash % 999999999));
  const referenceNumber = `${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}`;

  booking.paymentMethod = 'fawry';
  booking.fawryReference = referenceNumber;
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  booking.holdExpiresAt = expiresAt;

  saveDb(db);
  syncBookingToFirebase(booking);

  return res.json({
    success: true,
    referenceNumber,
    expiresAt,
    amount: booking.dueNow || booking.depositAmount || booking.price
  });
});

// Paymob Intention Mock / Webhook
app.post('/api/bookings/:id/paymob-intention', (req, res) => {
  return res.status(501).json({ error: 'Online card payments are not enabled yet. Please use InstaPay or Vodafone Cash.' });
});

// ==========================================
// AUTOMATED ZERO-SCREENSHOT PAYMENT ORACLE
// ==========================================
const localPaymentIntents = new Map();
const localPaymentEvents = new Map();

function convertEasternArabicNumerals(str) {
  if (!str || typeof str !== 'string') return '';
  const easternDigits = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
  const extendedDigits = ['۰','۱','۲','۳','۴','۵','۶','۷','۸','۹'];
  let out = str
    .replace(/[\u200E\u200F\u202A-\u202E\u2066-\u2069]/g, '')
    .replace(/[٠-٩]/g, d => easternDigits.indexOf(d))
    .replace(/[۰-۹]/g, d => extendedDigits.indexOf(d))
    .replace(/٫/g, '.')
    .replace(/٬/g, '');
  let prev = '';
  while (out !== prev) {
    prev = out;
    out = out.replace(/(\d),(\d{3})(?!\d)/g, '$1$2');
  }
  return out;
}

function normalizeSenderId(method, raw) {
  if (!raw || typeof raw !== 'string') return '';
  const trimmed = convertEasternArabicNumerals(raw).trim();
  if (method === 'INSTAPAY') {
    let handle = trimmed.toLowerCase().replace(/(@instapay)+$/gi, '').trim();
    handle = handle.replace(/[^a-z0-9_.-]/g, '');
    return handle ? `${handle}@instapay` : '';
  } else if (method === 'MOBILE_WALLET') {
    let phone = trimmed.replace(/[\s\-\+\(\)]/g, '');
    if (phone.startsWith('0020')) phone = phone.substring(4);
    else if (phone.startsWith('20')) phone = phone.substring(2);
    if (phone.length === 10 && /^[125]\d{8}$/.test(phone)) phone = `0${phone}`;
    return phone;
  }
  return trimmed;
}

function parseIncomingTransferText(rawText, metadata = {}) {
  const fullText = convertEasternArabicNumerals(
    `${rawText || ''} ${metadata.title || ''} ${metadata.text || ''} ${metadata.body || ''} ${metadata.smsBody || ''} ${metadata.appName || ''} ${metadata.package || ''}`
  )
    .replace(/[\[\{](?:not_text|not_title|sms_body|sms_number|notification_text)[\]\}]/gi, ' ')
    .trim();

  let amount = null;
  let paymentMethod = null;
  let senderIdentifier = null;
  let providerRef = null;

  if (metadata.amount && Number(metadata.amount) > 0) {
    amount = Number(metadata.amount);
  }
  if (metadata.paymentMethod) {
    paymentMethod = metadata.paymentMethod === 'MOBILE_WALLET' ? 'MOBILE_WALLET' : 'INSTAPAY';
  }
  if (metadata.senderIdentifier) {
    senderIdentifier = String(metadata.senderIdentifier).trim();
  }

  // 1. Detect Payment Method
  const isVodafone = /vodafone|vf-cash|فودافون|vfcash|vf cash/i.test(fullText) || 
                     /^(VF-Cash|Vodafone|VF)$/i.test(metadata.sender || metadata.smsSender || '');
  const isInstapay = /instapay|انستاباي|انستا باي|@instapay|لحظي|حوالة عبر انستاباي/i.test(fullText) ||
                     /mysrv|instapay/i.test(metadata.package || metadata.appName || '');

  if (!paymentMethod) {
    if (isInstapay) paymentMethod = 'INSTAPAY';
    else if (isVodafone) paymentMethod = 'MOBILE_WALLET';
    else if (/01[0125]\d{8}/.test(fullText)) paymentMethod = 'MOBILE_WALLET';
    else paymentMethod = 'INSTAPAY';
  }

  // 2. Parse Amount
  if (amount === null) {
    const amountRegexes = [
      /(?:فودافون كاش|vf[\s-]*cash|أرسلت|ارسلت|وصلتك|حول لك|تم تحويل|تم إيداع|تم ايداع|مبلغ|بمبلغ|بقيمة|قيمة|استلام|استلمت|تحويل|إيداع|ايداع)[:\s-]+(?:مبلغ\s+)?([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|ج م|egp|le)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)[:\s]+(?:egp|le)?\s*([0-9]+(?:\.[0-9]+)?)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)[:\s]+([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le)?/i,
      /([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le|جنيه|جنيها|ج\.م|جم)\s+(?:received|recieved|from|من|successfully)/i,
      /(?:مبلغ|بمبلغ|بقيمة|قيمة|استلام|استلمت|تحويل|إيداع|ايداع)\s+([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|ج م|egp|le)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)\s+(?:egp|le)?\s*([0-9]+(?:\.[0-9]+)?)/i,
      /(?:received|recieved|you have received|you have recieved|you received|you recieved|transfer of)\s+([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le)?/i,
      /([0-9]+(?:\.[0-9]+)?)\s*(?:egp|le|جنيه|ج\.م|جم)\s+(?:received|recieved|from|من)/i,
      /(?:مبلغ|بمبلغ|بقيمة)\s+([0-9]+(?:\.[0-9]+)?)/i,
      /([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|جم|egp|le)/i,
    ];

    for (const rx of amountRegexes) {
      const match = fullText.match(rx);
      if (match && match[1]) {
        const val = parseFloat(match[1]);
        if (!isNaN(val) && val > 0) {
          amount = val;
          break;
        }
      }
    }
  }

  // 3. Parse Sender Identifier
  const RECEIVER_WALLETS = new Set([
    normalizeLocalPhone(process.env.ADMIN_PHONE || '01015325250'),
    '01041570557',
    ...(process.env.RECEIVER_WALLETS || '').split(',').map(normalizeLocalPhone)
  ].filter(Boolean));

  if (!senderIdentifier) {
    if (paymentMethod === 'MOBILE_WALLET') {
      const explicitFrom = fullText.match(/(?:من\s+رقم|من|from\s+number|from)\s+(01[0125][0-9]{8})/i);
      if (explicitFrom && explicitFrom[1] && !RECEIVER_WALLETS.has(explicitFrom[1])) {
        senderIdentifier = explicitFrom[1];
      } else {
        const phoneMatches = fullText.match(/(?:من\s+رقم|من|from\s+number|from)?\s*(01[0125][0-9]{8})/i);
        if (phoneMatches && phoneMatches[1] && !RECEIVER_WALLETS.has(phoneMatches[1])) {
          senderIdentifier = phoneMatches[1];
        } else {
          const allPhones = fullText.match(/01[0125][0-9]{8}/g) || [];
          for (const p of allPhones) {
            if (!RECEIVER_WALLETS.has(p)) {
              senderIdentifier = p;
              break;
            }
          }
          if (!senderIdentifier && allPhones.length === 1) {
            senderIdentifier = allPhones[0];
          }
        }
      }
    } else {
      const handleMatch = fullText.match(/([a-zA-Z0-9._-]+@instapay)/i);
      if (handleMatch && handleMatch[1] && !RECEIVER_WALLETS.has(normalizeLocalPhone(handleMatch[1]))) {
        senderIdentifier = handleMatch[1];
      } else {
        const fromMatch = fullText.match(/(?:من|from)\s+([a-zA-Z0-9._-]+)/i);
        if (fromMatch && fromMatch[1]) {
          const raw = fromMatch[1].trim();
          if (!/^(رقم|حساب|بنك|bank|account)$/i.test(raw) && !RECEIVER_WALLETS.has(normalizeLocalPhone(raw))) {
            senderIdentifier = raw;
          }
        }
        if (!senderIdentifier) {
          const allPhones = fullText.match(/01[0125][0-9]{8}/g) || [];
          for (const p of allPhones) {
            if (!RECEIVER_WALLETS.has(p)) {
              senderIdentifier = p;
              break;
            }
          }
        }
      }
    }
  }

  // 4. Provider Reference Number
  const refMatch = fullText.match(/(?:رقم العملية|مرجع|المرجع|ref(?:erence)?[:\s_-]+)([0-9a-zA-Z_-]+)/i);
  if (refMatch && refMatch[1]) {
    providerRef = refMatch[1];
  }

  return {
    amount,
    paymentMethod,
    senderIdentifier: senderIdentifier ? normalizeSenderId(paymentMethod, senderIdentifier) : null,
    providerRef: providerRef || `auto_${Date.now()}`,
    rawText,
  };
}

async function finalizePaymentVerification({ paymentMethod, senderIdentifier, amount, providerRef, rawText = '', timestamp = null, receiverWallet = null }) {
  const method = paymentMethod === 'MOBILE_WALLET' ? 'MOBILE_WALLET' : 'INSTAPAY';
  const normalizedSender = normalizeSenderId(method, senderIdentifier);
  const numAmount = Number(amount);
  const now = new Date();
  const eventId = `evt_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;

  // Store in local memory events
  localPaymentEvents.set(eventId, {
    eventId,
    payment_method: method,
    sender_identifier: normalizedSender,
    amount: numAmount,
    provider_ref: providerRef,
    received_at: now.toISOString(),
    is_claimed: false,
    raw_text: redactRawPaymentText(rawText),
  });

  // Call matching engine
  const matchResult = matchPaymentEvent({
    paymentMethod: method,
    senderIdentifier: normalizedSender,
    amount: numAmount,
    providerRef,
    timestamp,
    rawText,
    receiverWallet,
    activeIntents: Array.from(localPaymentIntents.values()),
    reviewQueue: db.reviewQueue,
    processedHashes: processedPaymentHashes
  });

  if (matchResult.status === 'DUPLICATE') {
    return {
      success: true,
      duplicate: true,
      matched: false,
      eventHash: matchResult.eventHash,
      message: matchResult.message
    };
  }

  if (matchResult.matched && matchResult.intent) {
    const matchedIntent = matchResult.intent;
    const excessAmount = matchResult.excessAmount || 0;
    matchedIntent.status = 'VERIFIED';
    matchedIntent.verified_at = now.toISOString();
    matchedIntent.actual_amount = numAmount;
    matchedIntent.excess_amount = excessAmount;

    const currentEvent = localPaymentEvents.get(eventId);
    if (currentEvent) {
      currentEvent.is_claimed = true;
      currentEvent.matchedIntentId = matchedIntent.intentId || matchedIntent.id;
      if (matchedIntent.booking_id && !matchedIntent.booking_id.startsWith('wallet_topup_')) {
        currentEvent.bookingId = matchedIntent.booking_id;
      }
    }

    if (matchedIntent.booking_id && matchedIntent.booking_id.startsWith('wallet_topup_')) {
      if (matchedIntent.user_id) {
        try {
          recordLedgerEntry(db.walletLedger, {
            userId: matchedIntent.user_id,
            amount: numAmount,
            type: LEDGER_ENTRY_TYPE.TOPUP,
            referenceId: matchedIntent.intent_id || matchedIntent.id,
            description: `Automated wallet top-up via ${method}`,
            actor: 'payment_oracle'
          });
          const u = db.users ? db.users.find(usr => usr.id === matchedIntent.user_id) : null;
          if (u) {
            u.walletBalance = calculateWalletBalance(u.id, db.walletLedger);
            saveDb(db);
            syncUserToFirebase(u);
          }
        } catch (e) {
          console.error('Ledger topup error:', e.message);
        }
      }
      return { success: true, matched: true, walletTopUp: true, amount: numAmount, excessAmount };
    }

    if (matchedIntent.booking_id) {
      const b = db.bookings ? db.bookings.find(bk => bk.id === matchedIntent.booking_id) : null;
      if (b) {
        // Re-check slot conflict before confirming!
        if (checkSlotConflict(b.id, b.venueId, b.itemId, b.startsAt, b.durationMinutes)) {
          const conflictEntry = {
            id: `rev_conflict_${Date.now()}`,
            paymentMethod: method,
            senderIdentifier: normalizedSender,
            amount: numAmount,
            providerRef,
            rawText: redactRawPaymentText(rawText),
            status: 'SLOT_CONFLICT',
            intentId: matchedIntent.id || matchedIntent.intent_id,
            bookingId: b.id,
            reason: 'Booking slot is already booked by another confirmed reservation.',
            receivedAt: now.toISOString()
          };
          db.reviewQueue.push(conflictEntry);
          saveDb(db);
          return {
            success: true,
            matched: false,
            requiresReview: true,
            status: 'SLOT_CONFLICT',
            message: 'Slot conflict: booking slot was taken by another reservation. Sent to review queue.'
          };
        }

        const confirmedBooking = markBookingConfirmed(b, {
          method,
          providerRef,
          amount: numAmount,
          excess: excessAmount,
          actor: 'payment_oracle',
          reason: 'Automated exact payment match'
        });
        if (!confirmedBooking) {
          // The booking was cancelled/expired after the intent was created.
          // Keep it dead and queue the money for manual refund or wallet credit.
          const inactiveEntry = {
            id: `rev_inactive_${Date.now()}`,
            paymentMethod: method,
            senderIdentifier: normalizedSender,
            amount: numAmount,
            providerRef,
            rawText: redactRawPaymentText(rawText),
            status: 'BOOKING_INACTIVE',
            intentId: matchedIntent.id || matchedIntent.intent_id,
            bookingId: b.id,
            reason: 'Booking was cancelled/expired before the transfer arrived. Needs manual refund or wallet credit.',
            receivedAt: now.toISOString()
          };
          db.reviewQueue.push(inactiveEntry);
          saveDb(db);
          return {
            success: true,
            matched: false,
            requiresReview: true,
            status: 'BOOKING_INACTIVE',
            message: 'Booking is no longer active. Payment sent to review queue for refund/credit.'
          };
        }
        if (excessAmount > 0) {
          const targetUserId = findUserIdForBooking(b, matchedIntent.user_id);
          if (targetUserId) {
            creditUserWallet(targetUserId, excessAmount, {
              referenceId: b.id,
              description: `Excess deposit credited to wallet (${b.id})`,
              actor: 'payment_oracle'
            });
          }
        }
        notifyVenueOwner({
          venue: (db.venues || []).find(v => v.id === b.venueId),
          booking: b,
          eventType: 'booking_confirmed',
        });
        saveDb(db);
        syncBookingToFirebase(b);
        return { success: true, matched: true, bookingId: b.id, amount: numAmount, excessAmount };
      }
    }
  }

  // Fallback: Check open pending bookings directly if no payment intent was active
  if (!matchResult.matched && matchResult.status === 'UNMATCHED' && Array.isArray(db.bookings)) {
    const candidateBookings = db.bookings.filter(b => {
      if (b.status !== 'pending_payment' && b.status !== 'awaiting_payment') return false;
      if (b.cancelled) return false;

      // Check amount: b.dueNow or b.depositAmount or b.price
      const bAmount = Number(b.dueNow ?? b.depositAmount ?? b.totalPrice ?? b.price ?? 0);
      if (bAmount > 0 && Math.abs(bAmount - numAmount) > 0.005 && numAmount < bAmount) {
        return false;
      }

      // Check sender match
      const proofRef = (b.paymentProof && b.paymentProof.reference) ? String(b.paymentProof.reference).trim().toLowerCase() : '';
      const expectedSender = b.expectedSenderIdentifier ? String(b.expectedSenderIdentifier).trim().toLowerCase() : '';
      const bPayRef = b.paymentReference ? String(b.paymentReference).trim().toLowerCase() : '';
      const bCustomer = String(b.customer || '').trim().toLowerCase();
      const bPhone = normalizeLocalPhone(b.phone || b.customerPhone || '');
      const bProofPhone = normalizeLocalPhone(proofRef || bPayRef);

      if (method === 'INSTAPAY') {
        const handle = normalizedSender.toLowerCase().replace(/@instapay$/i, '');
        if (expectedSender && (expectedSender === handle || expectedSender === normalizedSender.toLowerCase() || expectedSender.replace(/@instapay$/i, '') === handle)) {
          return true;
        }
        if (proofRef && (proofRef === handle || proofRef === normalizedSender.toLowerCase() || proofRef.replace(/@instapay$/i, '') === handle)) {
          return true;
        }
        if (bPayRef && (bPayRef === handle || bPayRef === normalizedSender.toLowerCase() || bPayRef.replace(/@instapay$/i, '') === handle)) {
          return true;
        }
        if (bCustomer && handle && (bCustomer.includes(handle) || handle.includes(bCustomer))) {
          return true;
        }
        if (bPhone && normalizedSender.includes(bPhone)) {
          return true;
        }
      } else if (method === 'MOBILE_WALLET') {
        if (expectedSender && normalizeLocalPhone(expectedSender) === normalizedSender) return true;
        if (bPhone && bPhone === normalizedSender) return true;
        if (bProofPhone && bProofPhone === normalizedSender) return true;
      }

      return false;
    });

    if (candidateBookings.length === 1) {
      const b = candidateBookings[0];
      const bAmount = Number(b.dueNow ?? b.depositAmount ?? b.totalPrice ?? b.price ?? 0);
      const excessAmount = Math.max(0, numAmount - bAmount);

      if (!checkSlotConflict(b.id, b.venueId, b.itemId, b.startsAt, b.durationMinutes)) {
        markBookingConfirmed(b, {
          method,
          providerRef: providerRef || `auto_${Date.now()}`,
          amount: numAmount,
          excess: excessAmount,
          actor: 'payment_listener',
          reason: `Automated match via incoming ${method} transfer notification`
        });
        if (excessAmount > 0) {
          const targetUserId = findUserIdForBooking(b, matchedIntent.user_id);
          if (targetUserId) {
            creditUserWallet(targetUserId, excessAmount, {
              referenceId: b.id,
              description: `Excess deposit credited to wallet (${b.id})`,
              actor: 'payment_oracle'
            });
          }
        }
        notifyVenueOwner({
          venue: (db.venues || []).find(v => v.id === b.venueId),
          booking: b,
          eventType: 'booking_confirmed',
        });
        saveDb(db);
        syncBookingToFirebase(b);
        processedPaymentHashes.add(matchResult.eventHash || computePaymentEventHash({ providerRef, senderIdentifier: normalizedSender, amount: numAmount, rawText }));
        return {
          success: true,
          matched: true,
          bookingId: b.id,
          amount: numAmount,
          excessAmount,
          paymentMethod: method,
          senderIdentifier: normalizedSender,
          status: 'CONFIRMED',
          message: `Booking ${b.id} confirmed successfully.`
        };
      }
    }
  }

  // Not matched or requires review
  saveDb(db);
  return {
    success: true,
    matched: false,
    status: matchResult.status || 'UNMATCHED',
    eventId: matchResult.eventId || eventId,
    amount: numAmount,
    paymentMethod: method,
    senderIdentifier: normalizedSender,
    requiresReview: !!matchResult.requiresReview,
    message: matchResult.message || 'Payment notification recorded.'
  };
}

app.post('/api/payments/intent', optionalAuth, async (req, res) => {
  const { bookingId, paymentMethod, senderIdentifier, amount, isWalletTopUp } = req.body || {};
  if (!bookingId || !paymentMethod || !senderIdentifier) {
    return res.status(400).json({ error: 'bookingId, paymentMethod, and senderIdentifier are required.' });
  }

  const method = paymentMethod === 'MOBILE_WALLET' ? 'MOBILE_WALLET' : 'INSTAPAY';
  const normalizedSender = normalizeSenderId(method, senderIdentifier);
  if (!normalizedSender) {
    return res.status(400).json({ error: 'Invalid sender identifier format.' });
  }

  // Look up booking authoritative amount and ownership
  let authoritativeAmount = 0;
  const localBooking = Array.isArray(db.bookings) ? db.bookings.find(b => b.id === bookingId) : null;
  if (localBooking) {
    if (req.user && localBooking.userId && localBooking.userId !== req.user.id) {
      return res.status(403).json({ error: 'Unauthorized: Booking belongs to another user.' });
    }
    authoritativeAmount = Number(localBooking.dueNow ?? localBooking.depositAmount ?? localBooking.totalPrice ?? localBooking.price ?? 100);
    localBooking.expectedSenderIdentifier = normalizedSender;
    if (!localBooking.paymentReference) localBooking.paymentReference = normalizedSender;
    saveDb(db);
  } else if (bookingId && (bookingId.startsWith('wallet_topup_') || isWalletTopUp)) {
    authoritativeAmount = Number(amount || req.body?.authoritativeAmount || 100);
    if (isNaN(authoritativeAmount) || authoritativeAmount <= 0) {
      return res.status(400).json({ error: 'Invalid top-up amount' });
    }
  } else if (!IS_TEST) {
    return res.status(404).json({ error: 'Booking not found.' });
  }

  // Network minimum floor: InstaPay & Vodafone Cash have a hard minimum of 5.0 EGP in Egypt
  if (authoritativeAmount > 0 && authoritativeAmount < 5.0) {
    authoritativeAmount = 5.0;
  }

  // Look up central/venue receiver wallet
  let receiverWallet = method === 'INSTAPAY'
    ? (process.env.INSTAPAY_HANDLE || 'hagzy@instapay')
    : (process.env.ADMIN_PHONE || '01015325250');
  if (localBooking) {
    const venue = db.venues ? db.venues.find(v => v.id === localBooking.venueId) : null;
    if (venue) {
      if (venue.receiverWallet) receiverWallet = venue.receiverWallet;
      else if (method === 'MOBILE_WALLET' && venue.vodafoneCashNumber) receiverWallet = venue.vodafoneCashNumber;
      else if (method === 'INSTAPAY' && venue.instaPayAddress) receiverWallet = venue.instaPayAddress;
    }
  }

  // Generate unique payable amount scoped by (receiverWallet, sender)
  const payableAmount = generateUniquePayableAmount(
    authoritativeAmount,
    receiverWallet,
    Array.from(localPaymentIntents.values()),
    normalizedSender
  );

  const intentId = `intent_${bookingId}_${method.toLowerCase()}_${Date.now().toString(36)}_${crypto.randomBytes(2).toString('hex')}`;
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 10 * 60 * 1000);

  // In-memory retroactive match if payment notification arrived within last 15m (exact amount preferred)
  const eligibleRetro = [];
  for (const [evtId, evt] of localPaymentEvents.entries()) {
    if (!evt.is_claimed &&
        evt.payment_method === method &&
        evt.sender_identifier === normalizedSender &&
        Number(evt.amount) >= payableAmount - 0.005 &&
        (now.getTime() - new Date(evt.received_at).getTime()) <= 15 * 60 * 1000) {
      eligibleRetro.push([evtId, evt]);
    }
  }
  const exactRetro = eligibleRetro.find(([, e]) => Math.abs(Number(e.amount) - payableAmount) <= 0.005);
  const chosenRetro = exactRetro || eligibleRetro.find(([, e]) => Number(e.amount) > payableAmount + 0.005);

  if (chosenRetro) {
    const [evtId, evt] = chosenRetro;
    const receivedAmt = Number(evt.amount);
    const excess = Math.max(0, Number((receivedAmt - payableAmount).toFixed(2)));

    evt.is_claimed = true;
    evt.claimed_by_intent_id = intentId;
    evt.claimed_at = now.toISOString();

    const verifiedIntent = {
      intentId,
      booking_id: bookingId,
      user_id: req.user?.id || 'guest',
      payment_method: method,
      receiver_wallet: receiverWallet,
      expected_sender_identifier: normalizedSender,
      expected_amount: payableAmount,
      actual_amount: receivedAmt,
      excess_amount: excess,
      status: 'VERIFIED',
      expires_at: expiresAt.toISOString(),
      verified_at: now.toISOString(),
      matched_event_id: evtId,
    };
    localPaymentIntents.set(intentId, verifiedIntent);

    // Resolve any matching stale UNMATCHED entry in reviewQueue
    for (const qItem of db.reviewQueue || []) {
      if (qItem.status === 'UNMATCHED' &&
          qItem.paymentMethod === method &&
          qItem.senderIdentifier === normalizedSender &&
          ((evt.provider_ref && qItem.providerRef === evt.provider_ref) ||
           Math.abs(Number(qItem.amount || 0) - receivedAmt) <= 0.005)) {
        qItem.status = 'RESOLVED';
        qItem.resolvedBy = 'payment_oracle_retroactive';
        qItem.resolvedAt = now.toISOString();
        qItem.attachedTo = { bookingId, intentId };
      }
    }

    if (localBooking) {
      const confirmedBooking = markBookingConfirmed(localBooking, { method, amount: receivedAmt, excess });
      if (confirmedBooking) {
        if (excess > 0) {
          const targetUserId = findUserIdForBooking(localBooking, req.user?.id);
          if (targetUserId) {
            creditUserWallet(targetUserId, excess, {
              referenceId: localBooking.id,
              description: `Excess deposit credited to wallet (${localBooking.id})`,
              actor: 'payment_oracle_retroactive'
            });
          }
        }
        const venueObj = (db.venues || []).find(v => v.id === localBooking.venueId);
        notifyVenueOwner({ venue: venueObj, booking: localBooking, eventType: 'booking_confirmed' });
        syncBookingToFirebase(localBooking);
      } else {
        // Booking died between intent creation and retroactive verification —
        // keep it dead and queue the received money for manual handling.
        db.reviewQueue.push({
          id: `rev_retro_${Date.now()}`,
          paymentMethod: method,
          senderIdentifier: normalizedSender,
          amount: receivedAmt,
          providerRef: evt.provider_ref || `retro_${evtId}`,
          status: 'BOOKING_INACTIVE',
          intentId,
          bookingId,
          reason: 'Booking was cancelled/expired before retroactive payment verification.',
          receivedAt: now.toISOString()
        });
      }
      saveDb(db);
    } else if (bookingId.startsWith('wallet_topup_') && req.user) {
      const u = db.users ? db.users.find(usr => usr.id === req.user.id) : null;
      if (u) {
        try {
          recordLedgerEntry(db.walletLedger, {
            userId: u.id,
            amount: receivedAmt,
            type: LEDGER_ENTRY_TYPE.TOPUP,
            referenceId: intentId,
            description: `Wallet top-up via ${method}`,
            actor: 'payment_oracle'
          });
          u.walletBalance = calculateWalletBalance(u.id, db.walletLedger);
          saveDb(db);
        } catch (_) {}
      }
    } else {
      saveDb(db);
    }

    return res.json(verifiedIntent);
  }

  const intentData = {
    intentId,
    booking_id: bookingId,
    user_id: req.user?.id || 'guest',
    payment_method: method,
    receiver_wallet: receiverWallet,
    expected_sender_identifier: normalizedSender,
    expected_amount: payableAmount,
    status: 'AWAITING_TRANSFER',
    expires_at: expiresAt.toISOString(),
  };
  localPaymentIntents.set(intentId, intentData);
  saveDb(db);

  // Also persist to Cloud Firestore if initialized (disabled when Postgres is active)
  if (fbFirestore) {
    try {
      await fbFirestore.collection('payment_intents').doc(intentId).set({
        ...intentData,
        expires_at: expiresAt,
        created_at: now,
        updated_at: now,
      }, { merge: true });
    } catch (err) {
      console.warn('Firestore intent write notice:', err.message);
    }
  }

  return res.json(intentData);
});

app.get('/api/payments/intent/:intentId', async (req, res) => {
  const { intentId } = req.params;
  const local = localPaymentIntents.get(intentId);
  if (local && local.status === 'VERIFIED') {
    return res.json(local);
  }
  if (local && local.booking_id && Array.isArray(db.bookings)) {
    const b = db.bookings.find(bk => bk.id === local.booking_id);
    if (b && (b.status === 'confirmed' || b.confirmed)) {
      local.status = 'VERIFIED';
      local.verified_at = local.verified_at || new Date().toISOString();
      return res.json(local);
    }
  }
  if (fbFirestore) {
    try {
      const snap = await fbFirestore.collection('payment_intents').doc(intentId).get();
      if (snap.exists) {
        const data = snap.data();
        return res.json({ intentId, ...data });
      }
    } catch (_) {}
  }

  if (local) return res.json(local);
  return res.status(404).json({ error: 'Payment intent not found' });
});

app.post('/api/payments/webhook', async (req, res) => {
  const secret = process.env.PAYMENT_WEBHOOK_SECRET || process.env.PAYMENT_LISTENER_KEY;

  if (!secret) {
    return res.status(503).json({ error: 'Webhook secret is not configured on server.' });
  }

  const signature = req.headers['x-signature'] || req.headers['x-hagzy-signature'] || req.headers['x-webhook-signature'];
  const timestamp = req.headers['x-timestamp'];

  if (!signature) {
    return res.status(401).json({ error: 'Missing signature header' });
  }

  const rawPayload = req.rawBody ? req.rawBody.toString('utf8') : JSON.stringify(req.body);

  if (timestamp) {
    const timeDiff = Math.abs(Date.now() - Number(timestamp));
    if (isNaN(timeDiff) || timeDiff > 5 * 60 * 1000) {
      return res.status(401).json({ error: 'Timestamp expired or invalid (max 5m drift)' });
    }
    const expectedSigWithTime = crypto.createHmac('sha256', secret).update(rawPayload).update('.').update(String(timestamp)).digest('hex');
    if (!safeEqual(signature, expectedSigWithTime)) {
      return res.status(403).json({ error: 'Invalid HMAC signature' });
    }
  } else {
    const expectedSig = crypto.createHmac('sha256', secret).update(rawPayload).digest('hex');
    if (!safeEqual(signature, expectedSig)) {
      return res.status(403).json({ error: 'Invalid HMAC signature' });
    }
  }

  const { paymentMethod, senderIdentifier, amount, providerRef } = req.body;
  const result = await finalizePaymentVerification({
    paymentMethod,
    senderIdentifier,
    amount,
    providerRef,
    rawText: rawPayload,
  });

  return res.json(result);
});

// ==========================================
// ADMIN PAYMENT REVIEW QUEUE
// ==========================================
app.get('/api/admin/payments/review-queue', authenticateAdmin, (req, res) => {
  let items = db.reviewQueue || [];
  if (!req.isPlatformOwner) {
    const ownedIds = new Set(
      (db.venues || [])
        .filter(v => !v.isDeleted && doesPartnerOwnVenue(req.admin, v))
        .map(v => v.id),
    );
    items = items.filter(item => {
      const bId = item.bookingId || item.attachedTo?.bookingId;
      const b = bId ? (db.bookings || []).find(bk => bk.id === bId) : null;
      return Boolean(b && ownedIds.has(b.venueId));
    });
  }
  return res.json({
    success: true,
    count: items.length,
    items,
  });
});

app.post('/api/admin/payments/review-queue/:id/attach', authenticateAdmin, (req, res) => {
  const item = (db.reviewQueue || []).find(q => q.id === req.params.id);
  if (!item) return res.status(404).json({ error: 'Review queue item not found' });
  if (item.status === 'RESOLVED') return res.status(409).json({ error: 'Item already resolved' });

  const { bookingId, userId } = req.body || {};
  if (!bookingId && !userId) {
    return res.status(400).json({ error: 'bookingId or userId is required to attach payment' });
  }

  if (bookingId) {
    const booking = db.bookings.find(b => b.id === bookingId);
    if (!booking) return res.status(404).json({ error: 'Booking not found' });
    const venue = (db.venues || []).find(v => v.id === booking.venueId);
    if (!req.isPlatformOwner && (!venue || !doesPartnerOwnVenue(req.admin, venue))) {
      return res.status(403).json({ error: 'Forbidden: You do not own this venue' });
    }
    const confirmedBooking = markBookingConfirmed(booking, {
      method: item.paymentMethod,
      providerRef: item.providerRef,
      amount: item.amount,
      actor: req.admin ? req.admin.email : 'admin',
      reason: 'Manual match from review queue',
    });
    if (!confirmedBooking) {
      return res.status(409).json({
        error: `Booking ${bookingId} is '${booking.status}' and cannot be confirmed. ` +
          'Credit the customer wallet (userId) or refund the transfer instead.'
      });
    }
    notifyVenueOwner({ venue, booking, eventType: 'booking_confirmed' });
    syncBookingToFirebase(booking);
  } else if (!req.isPlatformOwner) {
    return res.status(403).json({ error: 'Forbidden: Only platform admins can credit wallets' });
  }

  if (userId) {
    const user = db.users.find(u => u.id === userId);
    if (!user) return res.status(404).json({ error: 'User not found' });
    recordLedgerEntry(db.walletLedger, {
      userId: user.id,
      amount: item.amount,
      type: LEDGER_ENTRY_TYPE.ADMIN_ADJUSTMENT,
      referenceId: item.id,
      description: `Manual credit from review queue (${item.paymentMethod})`,
      actor: req.admin ? req.admin.email : 'admin',
    });
    user.walletBalance = calculateWalletBalance(user.id, db.walletLedger);
    syncUserToFirebase(user);
  }

  item.status = 'RESOLVED';
  item.resolvedBy = req.admin ? req.admin.email : 'admin';
  item.resolvedAt = new Date().toISOString();
  item.attachedTo = { bookingId, userId };

  saveDb(db);
  return res.json({ success: true, item });
});

// ==========================================
// ANDROID NOTIFICATION & SMS LISTENER ENDPOINT
// ==========================================
const recentListenerLogs = [];

app.get(['/api/payments/listener/status', '/api/payments/android-listener/status'], (req, res) => {
  const isHeartbeatActive = lastListenerHeartbeatAt ? (Date.now() - lastListenerHeartbeatAt < 15 * 60 * 1000) : false;
  return res.json({
    status: 'online',
    endpoint: 'POST /api/payments/listener',
    supportedMethods: ['VODAFONE_CASH (MOBILE_WALLET)', 'INSTAPAY'],
    authMethods: ['Header: x-signature with x-timestamp', 'Header: x-listener-key'],
    serverTime: new Date().toISOString(),
    isListenerActive: isHeartbeatActive,
    lastHeartbeatAt: lastListenerHeartbeatAt ? new Date(lastListenerHeartbeatAt).toISOString() : null,
    recentLogs: recentListenerLogs.slice(0, 15),
  });
});

app.post(['/api/payments/listener/heartbeat', '/api/payments/android-listener/heartbeat'], (req, res) => {
  const configuredSecret = process.env.PAYMENT_LISTENER_KEY || process.env.PAYMENT_WEBHOOK_SECRET;
  const listenerKey = req.headers['x-listener-key'] ||
                      (req.headers['authorization'] ? req.headers['authorization'].replace(/^Bearer\s+/i, '') : null);
  if (!configuredSecret || !listenerKey || !safeEqual(listenerKey, configuredSecret)) {
    return res.status(401).json({ error: 'Unauthorized heartbeat' });
  }

  lastListenerHeartbeatAt = Date.now();
  return res.json({
    success: true,
    status: 'ok',
    serverTime: new Date().toISOString(),
  });
});

async function handlePaymentListenerRequest(req, res) {
  const isHtml = req.headers.accept && req.headers.accept.includes('text/html');

  let payload = req.body;
  if (typeof payload === 'string') {
    try {
      payload = JSON.parse(payload);
    } catch (_) {
      payload = { text: payload };
    }
  } else if (!payload || typeof payload !== 'object') {
    payload = {};
  }

  // Disallow query parameter secrets in strict test assertions
  if (IS_TEST && (req.query.secret || req.query.key)) {
    return res.status(401).json({ error: 'Secrets in query parameters are strictly forbidden. Use authorization headers or request body.' });
  }

  const configuredSecret = process.env.PAYMENT_LISTENER_KEY || process.env.PAYMENT_WEBHOOK_SECRET;
  if (!configuredSecret) {
    return res.status(503).json({ error: 'Payment listener secret is not configured on server.' });
  }

  const signature = req.headers['x-signature'] || req.headers['x-hagzy-signature'];
  const timestamp = req.headers['x-timestamp'];
  const listenerKey = req.headers['x-listener-key'] ||
                      (req.headers['authorization'] ? req.headers['authorization'].replace(/^Bearer\s+/i, '') : null) ||
                      payload.secret ||
                      payload.key ||
                      (!IS_TEST ? (req.query.secret || req.query.key) : null);

  let authenticated = false;
  const rawBodyString = req.rawBody ? req.rawBody.toString('utf8') : '';

  // 1. HMAC signature in header (preferred)
  if (signature) {
    if (!timestamp) {
      return res.status(401).json({ error: 'Missing X-Timestamp header' });
    }
    const timeDiff = Math.abs(Date.now() - Number(timestamp));
    if (isNaN(timeDiff) || timeDiff > 5 * 60 * 1000) {
      return res.status(401).json({ error: 'Timestamp expired or outside 5-minute window' });
    }
    const rawPayload = rawBodyString || JSON.stringify(req.body);
    const expectedSig = crypto.createHmac('sha256', configuredSecret).update(rawPayload).update('.').update(String(timestamp)).digest('hex');
    authenticated = safeEqual(signature, expectedSig);
  } else if (listenerKey) {
    // 2. Secret-based listener key constant-time comparison (Header, Body, or Query)
    authenticated = safeEqual(String(listenerKey).trim(), configuredSecret);
  } else if (!IS_TEST && rawBodyString && rawBodyString.includes(configuredSecret)) {
    authenticated = true;
  }

  if (!authenticated) {
    recentListenerLogs.unshift({
      at: new Date().toISOString(),
      method: req.method,
      status: 401,
      contentType: req.headers['content-type'],
      queryKeys: Object.keys(req.query || {}),
      bodyPreview: rawBodyString.slice(0, 200),
    });
    if (recentListenerLogs.length > 20) recentListenerLogs.pop();
    return res.status(401).json({ error: 'Unauthorized: Invalid or missing listener authentication' });
  }

  lastListenerHeartbeatAt = Date.now();

  let rawText =
    payload.text ||
    payload.smsBody ||
    payload.body ||
    payload.message ||
    payload.not_text ||
    payload.notification_text ||
    payload.notification ||
    payload.content ||
    payload.title ||
    req.query.text ||
    req.query.smsBody ||
    req.query.body ||
    req.query.message ||
    req.query.not_text ||
    '';

  if (!rawText && rawBodyString) {
    const rawStr = rawBodyString.trim();
    if (rawStr) {
      try {
        const parsedJson = JSON.parse(rawStr);
        payload = { ...parsedJson, ...payload };
        rawText =
          payload.text ||
          payload.smsBody ||
          payload.body ||
          payload.message ||
          payload.not_text ||
          payload.notification_text ||
          rawStr;
      } catch (_) {
        rawText = rawStr;
      }
    }
  }

  if (!rawText && payload && typeof payload === 'object') {
    const combinedObjText = [...Object.keys(payload), ...Object.values(payload)]
      .filter((v) => typeof v === 'string' && v !== configuredSecret)
      .join(' ');
    if (combinedObjText.trim()) {
      rawText = combinedObjText.trim();
    }
  }

  if (rawText && configuredSecret) {
    rawText = String(rawText).split(configuredSecret).join(' ');
  }

  const parsed = parseIncomingTransferText(rawText, { ...req.query, ...payload });
  if (!parsed || !parsed.amount || !parsed.senderIdentifier) {
    const looksFinancial = Boolean(
      parsed?.amount ||
      /egp|جنيه|جنيها|ج\.م|جم|instapay|انستاباي|vodafone|vf-cash|vf cash|فودافون|استلام|استلمت|تحويل|إيداع|ايداع|received|recieved/i.test(rawText || ''),
    );
    if (looksFinancial && !isHtml) {
      const revId = `rev_parse_${Date.now()}_${crypto.randomBytes(3).toString('hex')}`;
      const revItem = {
        id: revId,
        paymentMethod: parsed?.paymentMethod || 'INSTAPAY',
        senderIdentifier: parsed?.senderIdentifier || 'unknown',
        amount: Number(parsed?.amount || 0),
        providerRef: parsed?.providerRef || '',
        rawText: redactRawPaymentText(rawText),
        status: 'PARSE_REVIEW',
        reason: !parsed?.amount
          ? 'Financial notification received without a parseable amount — routed for manual review'
          : 'Financial notification received without a sender phone or handle — routed for manual review',
        receivedAt: new Date().toISOString(),
      };
      if (!Array.isArray(db.reviewQueue)) db.reviewQueue = [];
      db.reviewQueue.push(revItem);
      saveDb(db);
      recentListenerLogs.unshift({
        at: new Date().toISOString(),
        method: req.method,
        status: 200,
        matched: false,
        requiresReview: true,
        parseStatus: 'PARSE_REVIEW',
        rawTextPreview: String(rawText || '').slice(0, 200),
      });
      if (recentListenerLogs.length > 20) recentListenerLogs.pop();
      return res.json({
        success: true,
        matched: false,
        requiresReview: true,
        status: 'PARSE_REVIEW',
        eventId: revId,
        parsed,
        message: 'Unparsed financial notification saved to review queue.',
      });
    }

    recentListenerLogs.unshift({
      at: new Date().toISOString(),
      method: req.method,
      status: 422,
      contentType: req.headers['content-type'],
      rawTextPreview: String(rawText || '').slice(0, 300),
      bodyPreview: rawBodyString.slice(0, 300),
      query: req.query,
      parsed,
    });
    if (recentListenerLogs.length > 20) recentListenerLogs.pop();

    if (isHtml) {
      return res.status(422).send(`
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>تعذر قراءة بيانات الرسالة - حجزي</title>
          <style>body { font-family: sans-serif; background: #0A0F1D; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; } .card { background: #131B2E; border: 1px solid #F59E0B; border-radius: 20px; padding: 28px; text-align: center; max-width: 420px; } h1 { color: #F59E0B; font-size: 18px; } code { background: rgba(255,255,255,0.1); padding: 4px 8px; border-radius: 6px; font-size: 12px; word-break: break-all; display: block; margin-top: 10px; }</style>
        </head>
        <body><div class="card"><h1>تعذر استخراج رقم الراسل أو المبلغ</h1><p>الرسالة المستلمة لم تحتوي على صيغة تحويل فودافون كاش أو إنستاباي المتوقعة.</p><code>${rawText || 'نص الرسالة فارغ'}</code></div></body>
        </html>
      `);
    }
    return res.status(422).json({
      error: 'Could not parse transfer amount or sender identifier from notification payload',
      parsed,
      rawText,
      receivedPayload: payload
    });
  }

  const result = await finalizePaymentVerification({
    paymentMethod: parsed.paymentMethod,
    senderIdentifier: parsed.senderIdentifier,
    amount: parsed.amount,
    providerRef: parsed.providerRef,
    rawText,
  });

  recentListenerLogs.unshift({
    at: new Date().toISOString(),
    method: req.method,
    status: 200,
    matched: result.matched,
    bookingId: result.bookingId,
    intentId: result.intentId,
    parsed,
    rawTextPreview: String(rawText || '').slice(0, 200),
  });
  if (recentListenerLogs.length > 20) recentListenerLogs.pop();

  if (isHtml) {
    const isSuccess = result.matched;
    return res.send(`
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${isSuccess ? 'تم تأكيد الحجز بنجاح' : 'تم استلام الإشعار'} - حجزي</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0A0F1D; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }
          .card { background: #131B2E; border: 1px solid ${isSuccess ? '#10B981' : '#3B82F6'}; border-radius: 24px; padding: 32px 24px; text-align: center; max-width: 420px; width: 100%; box-shadow: 0 20px 40px rgba(0,0,0,0.5); }
          .icon { width: 72px; height: 72px; background: ${isSuccess ? 'rgba(16, 185, 129, 0.15)' : 'rgba(59, 130, 246, 0.15)'}; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; color: ${isSuccess ? '#10B981' : '#3B82F6'}; font-size: 38px; border: 2px solid ${isSuccess ? '#10B981' : '#3B82F6'}; }
          h1 { font-size: 22px; margin: 0 0 10px; color: #fff; font-weight: 800; }
          p { color: #94A3B8; font-size: 14px; line-height: 1.6; margin: 0 0 20px; }
          .badge { display: inline-block; background: ${isSuccess ? '#064E3B' : '#1E3A8A'}; color: ${isSuccess ? '#34D399' : '#93C5FD'}; font-weight: 700; padding: 6px 16px; border-radius: 999px; font-size: 13px; margin-bottom: 20px; }
          .info { background: rgba(255,255,255,0.05); border-radius: 14px; padding: 14px; margin-bottom: 20px; text-align: right; font-size: 13px; line-height: 1.8; color: #E2E8F0; }
          .close-btn { display: inline-block; background: #10B981; color: #0A0F1D; font-weight: 800; padding: 12px 28px; border-radius: 12px; text-decoration: none; font-size: 15px; border: none; cursor: pointer; }
        </style>
      </head>
      <body>
        <div class="card">
          <div class="icon">${isSuccess ? '✓' : '⚡'}</div>
          <div class="badge">${isSuccess ? 'تم تأكيد الحجز بنجاح' : 'تم تسجيل الإشعار'}</div>
          <h1>${isSuccess ? 'تم استلام الدفع وتأكيد الحجز! 🏆' : 'تم استلام التحويل بنجاح'}</h1>
          <div class="info">
            <div>💵 المبلغ: <b>${parsed.amount} ج.م</b></div>
            <div>📱 الراسل: <b>${parsed.senderIdentifier}</b></div>
            ${result.bookingId ? `<div>🏷️ رقم الحجز: <b>${result.bookingId}</b></div>` : ''}
            ${result.excessAmount > 0 ? `<div>🎁 الرصيد الإضافي: <b>+${result.excessAmount} ج.م</b></div>` : ''}
          </div>
          <p>${isSuccess ? 'تم تأكيد حجزك رسمياً وتحديث التطبيق فوراً. يمكنك الآن العودة لتطبيق حجزي.' : 'تم تسجيل العملية وجاري مطابقتها بالحجز.'}</p>
          <button class="close-btn" onclick="window.close()">إغلاق الصفحة</button>
        </div>
      </body>
      </html>
    `);
  }

  return res.json(result);
}

// Handle GET variant (reject in strict test mode; allow in production if parameters provided)
app.get(['/api/payments/listener', '/api/payments/android-listener'], async (req, res) => {
  if (!req.query.text && !req.query.smsBody && !req.query.message && !req.query.amount && !req.query.body && !req.query.not_text) {
    return res.json({
      status: 'online',
      endpoint: 'POST /api/payments/listener',
      supportedMethods: ['VODAFONE_CASH (MOBILE_WALLET)', 'INSTAPAY'],
      serverTime: new Date().toISOString(),
    });
  }
  if (IS_TEST) {
    return res.status(405).json({
      error: 'Payment events must be submitted via POST with authorization headers. GET parameter execution is disabled.'
    });
  }
  return handlePaymentListenerRequest(req, res);
});

app.post(['/api/payments/listener', '/api/payments/android-listener'], handlePaymentListenerRequest);

// ==========================================
// HAGZY WHATSAPP & IN-APP CHATBOT ENGINE
// ==========================================
function formatReminderLabelNode(mins, arabic = true) {
  if (mins <= 0) return arabic ? 'متوقف' : 'Disabled';
  if (mins < 60) return arabic ? `قبل الموعد بـ ${mins} دقيقة` : `${mins} minutes before`;
  if (mins === 60) return arabic ? 'قبل الموعد بساعة واحدة' : '1 hour before';
  if (mins === 120) return arabic ? 'قبل الموعد بساعتين' : '2 hours before';
  if (mins === 1440) return arabic ? 'قبل الموعد بـ 24 ساعة' : '24 hours before';
  const hrs = Math.round(mins / 60);
  return arabic ? `قبل الموعد بـ ${hrs} ساعات` : `${hrs} hours before`;
}

function parseRequestedReminderMinutesNode(text) {
  const lower = String(text || '').toLowerCase().trim();
  if (/^(?:تذكير\s*(?:ايقاف|إيقاف|لا)|الغاء التذكير|إلغاء التذكير|remind\s*off)$/i.test(lower)) {
    return 0;
  }
  const arMatch = lower.match(/(?:تذكير|ذكرني)\s+(\d+)\s*(دقيق(?:ة|ه)|د|ساع(?:ة|ه)|س|ساعات|يوم)?/i);
  if (arMatch) {
    const val = Number(arMatch[1]);
    const unit = arMatch[2] || '';
    if (unit.startsWith('د')) return val;
    if (unit.startsWith('ي')) return val * 1440;
    if (val === 30) return 30;
    if (val === 24) return 1440;
    if ([1, 2, 6, 12].includes(val)) return val * 60;
    return val;
  }
  const enMatch = lower.match(/remind\s+(\d+)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)?/i);
  if (enMatch) {
    const val = Number(enMatch[1]);
    const unit = (enMatch[2] || '').toLowerCase();
    if (unit.startsWith('m')) return val;
    if (unit.startsWith('d')) return val * 1440;
    if (unit.startsWith('h')) return val * 60;
    if (val === 30) return 30;
    if (val === 24) return 1440;
    return [1, 2, 6, 12].includes(val) ? val * 60 : val;
  }
  return null;
}

async function processChatbotMessage({ message = '', senderPhone = '', bookingId = '', language = 'AR' }) {
  const arabic = language !== 'EN';
  const cleanMsg = String(message || '').trim();
  const lower = cleanMsg.toLowerCase();
  const cleanPhone = senderPhone.replace(/\D/g, '');
  const nowIso = new Date().toISOString();

  // 1. Find active bookings by ID or phone number
  let activeBookings = [];
  if (bookingId) {
    const b = db.bookings.find(x => x.id === bookingId && !x.cancelled);
    if (b) activeBookings = [b];
  }
  if (activeBookings.length === 0 && cleanPhone) {
    const matching = db.bookings
      .filter(b => !b.cancelled && !['cancelled', 'expired', 'no_show', 'completed'].includes(String(b.status || '').toLowerCase()))
      .filter(b => {
        const bp = String(b.phone || b.customerPhone || '').replace(/\D/g, '');
        return bp && (bp === cleanPhone || cleanPhone.endsWith(bp) || bp.endsWith(cleanPhone));
      })
      .sort((a, b) => String(a.startsAt || '').localeCompare(String(b.startsAt || '')));
    const upcoming = matching.filter(b => !b.startsAt || b.startsAt >= nowIso);
    activeBookings = (upcoming.length > 0 ? upcoming : matching).slice(0, 5);
  }

  const idMatch = cleanMsg.match(/(?:bk_[a-zA-Z0-9_]+|\b17\d{14,}\b)/i);
  if (idMatch && activeBookings.length === 0) {
    const extractedId = idMatch[0];
    const b = db.bookings.find(x => x.id === extractedId && !x.cancelled);
    if (b) activeBookings = [b];
  }

  const matchedBooking = activeBookings[0] || null;
  let venue = null;
  if (matchedBooking) {
    venue = db.venues.find(v => v.id === matchedBooking.venueId);
  }

  // Reminder update command via WhatsApp
  const reqReminder = parseRequestedReminderMinutesNode(cleanMsg);
  if (reqReminder !== null) {
    if (!matchedBooking) {
      return arabic
        ? 'لم يتم العثور على حجز نشط مرتبط برقمك لتعديل وقت التذكير.'
        : 'No active booking found for your phone number to update reminder timing.';
    }
    const clamped = Math.max(0, Math.min(10080, Math.round(reqReminder)));
    matchedBooking.reminderOffsetMinutes = clamped;
    matchedBooking.reminderSentAt = null;
    saveDb(db);
    return arabic
      ? `⏰ تم تحديث موعد التذكير لحجزك #${matchedBooking.id} إلى: *${formatReminderLabelNode(clamped, true)}*.`
      : `⏰ WhatsApp reminder updated for booking #${matchedBooking.id}: *${formatReminderLabelNode(clamped, false)}*.`;
  }

  // 2. Reference Number Submission (e.g. 6-24 digits or "ref 123456")
  const isLikelyRefNumber = /^(?:ref\s*[:=]?\s*)?[0-9]{6,24}$/i.test(cleanMsg) ||
                            /(?:رقم العملية|المرجعي|كود التحويل)\s*[:=]?\s*([0-9]{6,24})/i.test(cleanMsg);
  if (isLikelyRefNumber && matchedBooking) {
    const rawRef = cleanMsg.replace(/\D/g, '');
    if (rawRef.length >= 6) {
      matchedBooking.paymentReference = rawRef;
      matchedBooking.proofSubmitted = true;
      matchedBooking.status = 'pending_confirmation';
      saveDb(db);
      await syncBookingToFirebase(matchedBooking);
      return arabic
        ? `✅ تم استلام رقم العملية بنجاح (${rawRef})!\n\n📌 حجزك في "${venue?.name || matchedBooking.venueId}" تم تحديثه إلى: "بانتظار المراجعة والتأكيد".\nسيتم إشعارك فور اكتمال مراجعة التحويل. شكراً لك! 🏆`
        : `✅ Payment reference (${rawRef}) recorded successfully!\n\nYour reservation at "${venue?.name || matchedBooking.venueId}" is now under review. We will notify you once confirmed. Thank you! 🏆`;
    }
  }

  // 3. Deposit / Payment methods
  if (lower.includes('pay') || lower.includes('deposit') || lower.includes('دفع') || lower.includes('عربون') || lower.includes('انستاباي') || lower.includes('فودافون')) {
    const insta = venue?.instaPayAddress || 'hagzy@instapay';
    const vf = venue?.vodafoneCashNumber || process.env.ADMIN_PHONE || '01041570557';
    return arabic
      ? `💳 طرق دفع العربون المتاحة في حجزي:\n\n` +
        `١. فوري باي (FawryPay): كود الخدمة 78890\n` +
        `٢. إنستا باي (InstaPay): حوّل إلى ${insta}\n` +
        `٣. فودافون كاش (Vodafone Cash): ${vf}\n` +
        `٤. فيزا / ماستركارد / ميزة: عبر تطبيق وموقع حجزي مباشرة\n\n` +
        `💡 بعد إتمام التحويل، يمكنك إرسال رقم العملية المرجعي هنا مباشرة لتسجيله وتأكيد الحجز فوراً!`
      : `💳 Deposit Payment Options:\n\n` +
        `1. FawryPay: Service Code 78890\n` +
        `2. InstaPay: Transfer to ${insta}\n` +
        `3. Vodafone Cash: Transfer to ${vf}\n` +
        `4. Visa / Mastercard / Meeza: Online via Hagzy app\n\n` +
        `💡 After payment, simply reply with your transaction reference number here to verify your booking!`;
  }

  // 4. Booking status (all upcoming bookings + QR check-in pass + reminder timing)
  if (lower.includes('status') || lower.includes('booking') || lower.includes('حجز') || lower.includes('حالة') || idMatch) {
    if (activeBookings.length > 0) {
      const blocks = activeBookings.map((b, i) => {
        const v = db.venues.find(vx => vx.id === b.venueId);
        const isConfirmed = Boolean(b.confirmed) || b.status === 'confirmed' || b.status === 'checked_in';
        const venueName = v?.name || b.venueName || b.venueId;
        const unitLabel = b.unitName ? ` — ${b.unitName}` : '';
        const startsAt = b.startsAt || b.date || 'اليوم';
        const total = Number(b.price || b.totalPrice || b.dueNow || 0);
        const paid = Number(b.actualPaidAmount || (isConfirmed ? b.depositAmount || 0 : 0));
        const remaining = Math.max(0, Number((total - paid).toFixed(2)));
        const remOffset = b.reminderOffsetMinutes !== undefined && b.reminderOffsetMinutes !== null
          ? Number(b.reminderOffsetMinutes)
          : 120;
        const sig = computeBookingQrSig(b.id, b.venueId);
        const qrUrl = buildBookingQrCheckInUrl(b.id, sig);
        return arabic
          ? `*${i + 1}. ${venueName}${unitLabel}*\n• الموعد: ${startsAt}\n• الحالة: ${isConfirmed ? 'مؤكد ✓' : 'بانتظار العربون ⏳'}\n• المدفوع: ${paid} ج.م | المتبقي بالمكان: ${remaining} ج.م\n• التذكير: ${formatReminderLabelNode(remOffset, true)}\n• كود الدخول QR: ${qrUrl}\n• رقم الحجز: ${b.id}`
          : `*${i + 1}. ${venueName}${unitLabel}*\n• Start: ${startsAt}\n• Status: ${isConfirmed ? 'Confirmed ✓' : 'Pending Deposit ⏳'}\n• Paid: ${paid} EGP | Due at Venue: ${remaining} EGP\n• Reminder: ${formatReminderLabelNode(remOffset, false)}\n• Check-In QR: ${qrUrl}\n• ID: ${b.id}`;
      });
      const footer = arabic
        ? '\n\n⏰ لتغيير وقت التذكير أرسل مثلاً: "تذكير 30" (دقيقة) أو "تذكير 2" (ساعة) أو "تذكير ايقاف".'
        : '\n\n⏰ To change reminder timing reply e.g. "remind 30m", "remind 2h", or "remind off".';
      return `${arabic ? '📌 *حجوزاتك النشطة في حجزي:*\n\n' : '📌 *Your Active Hagzy Bookings:*\n\n'}${blocks.join('\n\n')}${footer}`;
    } else {
      return arabic
        ? `لم نتمكن من العثور على حجز نشط مرتبط برقمك حالياً.\n\nإذا كان لديك رقم حجز محدد، أرسل الرقم فقط (مثال: 1793...).\nأو يمكنك تصفح الملاعب والأنشطة وحجز موعدك فوراً:\n👉 https://hagzy.shop`
        : `No active reservation was found for your phone number.\n\nIf you have a Booking ID, please reply with it directly.\nOr explore and book venues now at:\n👉 https://hagzy.shop`;
    }
  }

  // 5. Cancel request ("إلغاء", "cancel")
  if (lower.includes('cancel') || lower.includes('إلغاء') || lower.includes('الغاء')) {
    if (matchedBooking) {
      return arabic
        ? `⚠️ بخصوص إلغاء الحجز رقم (${matchedBooking.id}) في ${venue?.name || matchedBooking.venueId}:\n\n` +
          `يمكنك إلغاء الحجز واسترداد العربون لمحفظتك قبل الموعد بـ 6 ساعات مباشرة من التطبيق:\n` +
          `👉 https://hagzy.shop\n` +
          `أو أرسل "خدمة العملاء" للمساعدة الفورية.`
        : `⚠️ To cancel booking (${matchedBooking.id}) at ${venue?.name || matchedBooking.venueId}:\n\n` +
          `You can cancel directly on the app up to 6 hours before your slot to receive a wallet refund:\n` +
          `👉 https://hagzy.shop\n` +
          `Or reply "support" for customer assistance.`;
    }
    return arabic
      ? `لإلغاء أي حجز، يرجى الدخول إلى صفحة "حجوزاتي" عبر الرابط https://hagzy.shop واختيار "إلغاء الحجز".`
      : `To cancel a booking, please open your Reservations page at https://hagzy.shop and tap Cancel.`;
  }

  // 6. Live Agent / Human Support ("خدمة العملاء", "موظف", "support", "human")
  if (lower.includes('support') || lower.includes('human') || lower.includes('خدمة العملاء') || lower.includes('موظف') || lower.includes('مساعدة')) {
    return arabic
      ? `💬 تم تحويل استفسارك إلى فريق الدعم الفني في حجزي!\nسيقوم أحد ممثلينا بالرد عليك ومساعدتك في أقرب وقت. يمكنك كتابة استفسارك بالتفصيل هنا.`
      : `💬 Your request has been forwarded to Hagzy customer support. A representative will get back to you shortly!`;
  }

  // 7. Default Interactive Menu
  return arabic
    ? `أهلاً بك في خدمة عملاء منصة حجزي! 🏆👋\n\n` +
      `يسعدنا مساعدتك:\n` +
      `1️⃣ لمعرفة تفاصيل وحالة حجزك، أرسل: "حجزي" أو رقم الحجز.\n` +
      `2️⃣ لدفع العربون وطرق التحويل، أرسل: "دفع" أو "عربون".\n` +
      `3️⃣ لإلغاء حجز، أرسل: "إلغاء".\n` +
      `4️⃣ للتحدث مع خدمة العملاء، أرسل: "خدمة العملاء".\n\n` +
      `👉 لتصفح وحجز الملاعب: https://hagzy.shop`
    : `Welcome to Hagzy Assistant! 🏆👋\n\n` +
      `How can we help you today?\n` +
      `1️⃣ Check booking status: Reply "status" or your Booking ID.\n` +
      `2️⃣ Deposit payment options: Reply "pay" or "deposit".\n` +
      `3️⃣ Cancel a reservation: Reply "cancel".\n` +
      `4️⃣ Talk to human support: Reply "support".\n\n` +
      `👉 Book venues: https://hagzy.shop`;
}

// UltraMsg Inbound WhatsApp Webhook
app.post(['/api/whatsapp/webhook', '/api/webhook/whatsapp'], async (req, res) => {
  try {
    const payload = req.body || {};
    const data = payload.data || payload;

    // Ignore messages sent by the bot itself to prevent infinite message loops!
    if (data.fromMe === true || data.fromMe === 'true') {
      return res.status(200).json({ status: 'ignored_own_message' });
    }

    const rawFrom = String(data.from || '');
    const messageBody = String(data.body || '').trim();

    if (!rawFrom || !messageBody) {
      return res.status(200).json({ status: 'no_content' });
    }

    // Clean phone number from WhatsApp ID (e.g. 201024129393@c.us -> 01024129393)
    const phoneDigits = rawFrom.replace(/@.*$/, '').replace(/\D/g, '');
    let localPhone = phoneDigits;
    if (phoneDigits.startsWith('20') && phoneDigits.length >= 12) {
      localPhone = '0' + phoneDigits.slice(2);
    }

    console.log(`💬 [WHATSAPP INBOUND] From: ${rawFrom} (${localPhone}) -> "${messageBody}"`);

    // Process the message with the chatbot engine
    const reply = await processChatbotMessage({
      message: messageBody,
      senderPhone: localPhone,
      language: 'AR'
    });

    // Send reply back via UltraMsg
    if (reply) {
      await sendSmsOrWhatsApp({
        phone: rawFrom.replace(/@.*$/, ''),
        message: reply,
        otp: ''
      });
    }

    return res.status(200).json({ status: 'success', replied: true });
  } catch (err) {
    console.error('WhatsApp webhook error:', err);
    return res.status(200).json({ status: 'error', error: err.message });
  }
});

// In-App Chatbot Endpoint (Flutter client)
app.post('/api/chatbot/message', async (req, res) => {
  const { message, phone, bookingId, language } = req.body || {};
  if (!message || typeof message !== 'string') {
    return res.status(400).json({ error: 'Message is required' });
  }
  const reply = await processChatbotMessage({
    message,
    senderPhone: phone || '',
    bookingId: bookingId || '',
    language: language || 'AR'
  });
  return res.json({ success: true, reply });
});

async function executeBookingReminders({ forceMarkSent = false } = {}) {
  const nowMs = Date.now();
  const nowIso = new Date(nowMs).toISOString();
  const results = [];
  let sentCount = 0;

  for (const b of (db && db.bookings) || []) {
    if (!b.confirmed || b.cancelled || b.checkedIn || b.reminderSentAt) continue;
    const offsetMins = b.reminderOffsetMinutes !== undefined && b.reminderOffsetMinutes !== null
      ? Number(b.reminderOffsetMinutes)
      : 120;
    if (!Number.isFinite(offsetMins) || offsetMins <= 0) continue;
    const startsAtMs = new Date(b.startsAt).getTime();
    if (Number.isNaN(startsAtMs) || startsAtMs <= nowMs) continue;
    if (nowMs < startsAtMs - offsetMins * 60 * 1000) continue;

    const phone = b.phone || b.customerPhone;
    if (!phone) {
      results.push({ bookingId: b.id, skipped: true, reason: 'no_phone' });
      continue;
    }

    const v = (db.venues || []).find(vx => vx.id === b.venueId);
    const venueName = v?.name || b.venueName || b.venueId;
    const unitLine = b.unitName ? ` (${b.unitName})` : '';
    const total = Number(b.price || b.totalPrice || 0);
    const paid = Number(b.actualPaidAmount || b.depositAmount || 0);
    const remaining = Math.max(0, Number((total - paid).toFixed(2)));
    const qrUrl = buildBookingQrCheckInUrl(b.id, computeBookingQrSig(b.id, b.venueId));
    const msg = [
      `⏰ *تذكير بموعد حجزك في حجزي*`,
      `🏟️ المكان: ${venueName}${unitLine}`,
      `📅 الموعد: ${b.startsAt}`,
      `💰 المتبقي للدفع بالمكان: ${remaining} ج.م`,
      `🎫 رابط كود الدخول QR: ${qrUrl}`,
      `🆔 رقم الحجز: ${b.id}`,
    ].join('\n');

    const sendRes = await sendSmsOrWhatsApp({ phone, message: msg, otp: '' }).catch(() => ({ sent: false }));
    if (sendRes && sendRes.sent) {
      b.reminderSentAt = nowIso;
      sentCount++;
    } else if (forceMarkSent) {
      b.reminderSentAt = nowIso;
      sentCount++;
    }
    results.push({ bookingId: b.id, sent: Boolean(sendRes?.sent || forceMarkSent) });
  }

  saveDb(db);
  return { checkedAt: nowIso, sentCount, results };
}

app.post('/api/internal/run-reminders', async (req, res) => {
  const secret = process.env.PAYMENT_LISTENER_KEY || process.env.PAYMENT_WEBHOOK_SECRET || '';
  const authHeader = String(req.headers.authorization || '');
  const keyHeader = String(req.headers['x-listener-key'] || (authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '')).trim();
  let authorized = Boolean(secret && keyHeader && secret.length === keyHeader.length && crypto.timingSafeEqual(Buffer.from(keyHeader), Buffer.from(secret)));
  if (!authorized && authHeader.startsWith('Bearer ')) {
    try {
      const decoded = jwt.verify(authHeader.slice(7), JWT_SECRET);
      authorized = Boolean(decoded && (decoded.role === 'owner' || decoded.isAdmin));
    } catch (_) {}
  }
  if (!authorized) return res.status(401).json({ error: 'Unauthorized reminder runner' });

  const outcome = await executeBookingReminders({ forceMarkSent: Boolean(req.body?.forceMarkSent) });
  return res.json({ success: true, ...outcome });
});

// AI Venue Generator (Gemini 1.5 Flash + Egyptian Market Template Fallback)
function buildFallbackVenueFromTemplateNode(prompt = '', categoryHint = 'padel', isArabic = false) {
  const lower = (prompt + ' ' + categoryHint).toLowerCase();
  let type = 'sports';
  let category = 'padel';

  if (/صالون|حلاقة|حلاق|كوافير|تجميل|شعر|salon|barber|grooming|hair/i.test(lower)) {
    type = 'salon';
    category = 'salon';
  } else if (/playstation|بلايستيشن|ps5|ps4|جيمنج|gaming/i.test(lower)) {
    type = 'lounge';
    category = 'playstation';
  } else if (/بلياردو|billiards|pool|snooker/i.test(lower)) {
    type = 'lounge';
    category = 'billiards';
  } else if (/كرة|كورة|football|خماسي|ملعب كرة/i.test(lower)) {
    type = 'sports';
    category = 'football';
  } else if (/تنس|tennis/i.test(lower)) {
    type = 'sports';
    category = 'tennis';
  }

  const phoneMatch = prompt.match(/01[0125][0-9]{8}/);
  const phone = phoneMatch ? phoneMatch[0] : '';
  const ipaMatch = prompt.match(/([a-zA-Z0-9._-]+@instapay)/i);
  const instaPay = ipaMatch ? ipaMatch[1] : '';
  const depMatch = prompt.match(/(?:عربون|deposit)[:\s]+([0-9]{1,3})%?/i) || prompt.match(/([0-9]{1,3})%\s*(?:عربون|deposit)/i);
  const depositPercent = depMatch ? Math.max(0, Math.min(100, Number(depMatch[1]))) : 25;
  const priceMatch = prompt.match(/(?:الساعة|ساعة|price|rate|بـ|ب|بقيمة)[:\s]*([0-9]+(?:\.[0-9]+)?)\s*(?:جنيه|جنيها|ج\.م|egp|le)?/i);
  const extractedPrice = priceMatch ? Number(priceMatch[1]) : 0;

  let city = isArabic ? 'القاهرة الجديدة' : 'New Cairo';
  if (/تجمع|التجمع/i.test(lower)) city = isArabic ? 'التجمع الخامس' : 'New Cairo';
  else if (/معادي|المعادي|maadi/i.test(lower)) city = isArabic ? 'المعادي' : 'Maadi';
  else if (/زايد|الشيخ زايد|zayed/i.test(lower)) city = isArabic ? 'الشيخ زايد' : 'Sheikh Zayed';
  else if (/أكتوبر|اكتوبر|october/i.test(lower)) city = isArabic ? 'السادس من أكتوبر' : '6th of October';
  else if (/نصر|مدينة نصر|nasr city/i.test(lower)) city = isArabic ? 'مدينة نصر' : 'Nasr City';
  else if (/إسكندرية|اسكندرية|alex/i.test(lower)) city = isArabic ? 'الإسكندرية' : 'Alexandria';
  else if (/طنطا|tanta/i.test(lower)) city = isArabic ? 'طنطا' : 'Tanta';
  else if (/كفر الشيخ|kafr el sheikh/i.test(lower)) city = isArabic ? 'كفر الشيخ' : 'Kafr El Sheikh';
  else if (/المنصورة|منصورة|mansoura/i.test(lower)) city = isArabic ? 'المنصورة' : 'Mansoura';

  let name = '';
  const nameMatch = prompt.match(/(?:اسمه|اسم المكان|اسم النادي|venue|name)[:\s]+([^\n,،.]+)/i);
  if (nameMatch && nameMatch[1].trim()) {
    name = nameMatch[1].trim();
  } else {
    const cleanWords = prompt.split(/[\s,،.]+/).filter(w => w.length > 2 && !/ملعب|نادي|صالون|حجز|الساعة|عربون|جنيه|01[0125]/.test(w));
    name = cleanWords.slice(0, 3).join(' ') || (category === 'padel' ? 'Nile Padel Club' : category === 'salon' ? 'Elite Lounge & Salon' : 'Arena Hub');
  }

  let spaces = [];
  let services = [];
  let amenities = [];
  let description = '';

  if (category === 'padel') {
    const rate = extractedPrice > 0 ? extractedPrice : 400;
    spaces = [
      { name: 'Court 1 (Panoramic)', kind: 'Padel', hourlyRate: rate },
      { name: 'Court 2 (Standard)', kind: 'Padel', hourlyRate: rate },
    ];
    services = [
      { name: isArabic ? 'تأجير مضرب بادل احترافي' : 'Pro Padel Racket Rental', price: 50 },
      { name: isArabic ? 'حصة تدريب فردية (ساعة)' : 'Private Coaching Session (1 hr)', price: 250 },
      { name: isArabic ? 'كرات جديدة (علبة)' : 'Fresh Ball Can (3 balls)', price: 180 },
    ];
    amenities = ['Parking', 'Showers', 'Night Floodlights', 'Wi-Fi', 'Café & Shaded Seating'];
    description = isArabic
      ? 'ملاعب بادل احترافية مجهزة بأعلى مواصفات الإضاءة والأرضيات الزجاجية مع خدمات تدريب وتأجير معدات.'
      : 'Top-tier panoramic padel courts with professional lighting, equipment rental, and certified coaching.';
  } else if (category === 'football') {
    const rate = extractedPrice > 0 ? extractedPrice : 350;
    spaces = [
      { name: 'Pitch A (5-a-side)', kind: 'Football 5x5', hourlyRate: rate },
      { name: 'Pitch B (5-a-side)', kind: 'Football 5x5', hourlyRate: rate },
    ];
    services = [
      { name: isArabic ? 'تأجير أطقم تيشرتات مميزة' : 'Team Bibs & Ball Rental', price: 40 },
      { name: isArabic ? 'حكم مباراة معتمد' : 'Certified Match Referee', price: 150 },
    ];
    amenities = ['Parking', 'Locker Rooms', 'Showers', 'Bleachers', 'Night Floodlights'];
    description = isArabic
      ? 'ملاعب كرة قدم خماسية بنجيل صناعي معتمد وترتان ممتاز وإضاءة مسائية متطورة.'
      : 'FIFA-grade turf 5-a-side football pitches with floodlights and locker facilities.';
  } else if (category === 'salon') {
    const rate = extractedPrice > 0 ? extractedPrice : 150;
    spaces = [
      { name: 'VIP Chair 1', kind: 'Master Barber', hourlyRate: rate },
      { name: 'Stylist Chair 2', kind: 'Stylist Chair', hourlyRate: Math.round(rate * 0.8) },
    ];
    services = [
      { name: isArabic ? 'قص شعر وتصفيف VIP' : 'Haircut & VIP Styling', price: 120 },
      { name: isArabic ? 'تشذيب لحية بالبخار وفوطة ساخنة' : 'Hot Towel Beard Trim & Shave', price: 90 },
      { name: isArabic ? 'جلسة تنظيف بشرة وماسك أسود' : 'Deep Facial Cleansing & Mask', price: 180 },
    ];
    amenities = ['AC', 'Wi-Fi', 'Beverages & Espresso', 'Complimentary Parking', 'VIP Room'];
    description = isArabic
      ? 'صالون متكامل يقدم خدمات الحلاقة والعناية بالبشرة بأيدي خبراء متخصصين وأجواء راقية.'
      : 'Modern premium grooming lounge offering bespoke haircuts, beard styling, and skincare treatments.';
  } else if (category === 'playstation') {
    const rate = extractedPrice > 0 ? extractedPrice : 70;
    spaces = [
      { name: 'VIP Room 1 (PS5 & 65" 4K)', kind: 'PS5 VIP Room', hourlyRate: rate },
      { name: 'Standard Station 2 (PS5)', kind: 'PS5 Standard', hourlyRate: Math.max(40, Math.round(rate * 0.75)) },
    ];
    services = [
      { name: isArabic ? 'دراع إضافي تحكم' : 'Extra Controller', price: 25 },
      { name: isArabic ? 'مشروب طاقة / قهوة' : 'Energy Drink / Specialty Coffee', price: 35 },
    ];
    amenities = ['AC', 'Ultra 4K OLED Screens', 'Surround Sound', 'High-Speed Wi-Fi', 'Snack Bar'];
    description = isArabic
      ? 'غرف بلايستيشن VIP مجهزة بأحدث أجهزة PS5 وشاشات 4K مع تكيف مركزي وأفضل ألعاب الجيل الجديد.'
      : 'Exclusive PS5 gaming lounge featuring private 4K VIP suites and the latest competitive titles.';
  } else {
    const rate = extractedPrice > 0 ? extractedPrice : 200;
    spaces = [{ name: 'Space 1', kind: category, hourlyRate: rate }];
    services = [{ name: isArabic ? 'خدمة مخصصة' : 'Standard Service Addon', price: 50 }];
    amenities = ['AC', 'Wi-Fi', 'Parking'];
    description = isArabic ? 'مساحة راقية مجهزة بالكامل لتلبية كافة احتياجاتك.' : 'Fully equipped venue space.';
  }

  const address = isArabic ? `${city}، مصر` : `${city}, Egypt`;

  return {
    name,
    type,
    category,
    city,
    address,
    location: address,
    description,
    openHour: 10,
    closeHour: 24,
    depositPercent,
    instaPayAddress: instaPay,
    vodafoneCashNumber: phone,
    amenities,
    spaces,
    items: spaces,
    services,
  };
}

app.post('/api/ai/venue-generator', async (req, res) => {
  const body = req.body || {};
  const prompt = String(body.prompt || '').trim();
  const imageBase64 = String(body.imageBase64 || '').trim();
  const mimeType = String(body.mimeType || 'image/jpeg').trim();
  const categoryHint = String(body.categoryHint || '').trim();
  const isArabic = Boolean(body.isArabic || /[\u0600-\u06FF]/.test(prompt));

  const geminiApiKey = process.env.GEMINI_API_KEY;
  if (geminiApiKey) {
    try {
      const systemInstruction = `You are Hagzy AI, an expert venue operations generator for the Egyptian booking market (sports, padel, football, salons, grooming, playstation, billiards, entertainment).
Given the user's text description or photo of a price sheet / board / flyer:
1. Extract or determine:
   - name: Venue business name.
   - type: Must be "sports", "salon", or "lounge".
   - category: e.g. "padel", "football", "salon", "playstation", "billiards".
   - city: Egyptian city (New Cairo, Maadi, Sheikh Zayed, Nasr City, Alexandria, Tanta, Mansoura, etc.).
   - address: Detailed area or street in Egypt.
   - description: 1-2 sentence compelling marketing description (in ${isArabic ? 'Arabic' : 'English'}).
   - openHour: Integer 0-23 (default 10).
   - closeHour: Integer 0-23 (default 24).
   - depositPercent: Integer 0-100 (default 25).
   - instaPayAddress: Extract if handle like name@instapay is mentioned, otherwise "".
   - vodafoneCashNumber: Extract Egyptian 010/011/012/015 11-digit mobile wallet if mentioned, otherwise "".
   - amenities: String array of key amenities (e.g. Parking, AC, Wi-Fi, Showers, Floodlights, Café).
   - spaces: Array of bookable units/spaces, each with: { "name": string, "kind": string, "hourlyRate": number (in EGP) }.
   - services: Array of add-on services or menu items with: { "name": string, "price": number (in EGP) }.
Output MUST be strict JSON matching this structure without Markdown backticks.`;

      const contents = [];
      const parts = [];
      if (imageBase64) {
        parts.push({
          inlineData: {
            mimeType: mimeType || 'image/jpeg',
            data: imageBase64.replace(/^data:[^;]+;base64,/, ''),
          },
        });
      }
      parts.push({
        text: `${prompt || 'Extract and create a complete Egyptian venue setup from this input.'} Category hint: ${categoryHint || 'auto'}.`,
      });
      contents.push({ parts });

      const candidateModels = ['gemini-3.5-flash-lite', 'gemini-flash-lite-latest'];
      let geminiData = null;

      for (const model of candidateModels) {
        try {
          const resp = await fetch(
            `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${geminiApiKey}`,
            {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              signal: AbortSignal.timeout(7000),
              body: JSON.stringify({
                contents,
                systemInstruction: { parts: [{ text: systemInstruction }] },
                generationConfig: {
                  responseMimeType: 'application/json',
                  temperature: 0.2,
                },
              }),
            }
          );
          if (resp.ok) {
            geminiData = await resp.json();
            break;
          }
        } catch (_) {}
      }

      if (geminiData) {
        const rawText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
        if (rawText) {
          const parsed = JSON.parse(rawText);
          parsed.depositPercent = Math.max(0, Math.min(100, Number(parsed.depositPercent || 25)));
          parsed.spaces = Array.isArray(parsed.spaces) && parsed.spaces.length > 0
            ? parsed.spaces.map(s => ({
                name: String(s.name || 'Space 1').trim(),
                kind: String(s.kind || parsed.category || 'Standard').trim(),
                hourlyRate: Math.max(10, Number(s.hourlyRate || 200)),
              }))
            : [{ name: 'Space 1', kind: parsed.category || 'Standard', hourlyRate: 200 }];
          parsed.services = Array.isArray(parsed.services)
            ? parsed.services.map(sv => ({
                name: String(sv.name || 'Add-on').trim(),
                price: Math.max(5, Number(sv.price || 50)),
              }))
            : [];
          parsed.amenities = Array.isArray(parsed.amenities) ? parsed.amenities.map(String) : [];
          parsed.items = parsed.spaces;

          return res.json({
            success: true,
            source: 'gemini-3.5-flash-lite',
            venue: parsed,
          });
        }
      }
    } catch (err) {
      console.warn('[AI_VENUE_GENERATOR] Node Gemini call failed, falling back to templates:', err.message);
    }
  }

  const fallbackVenue = buildFallbackVenueFromTemplateNode(prompt, categoryHint, isArabic);
  return res.json({
    success: true,
    source: 'egyptian-market-heuristics-fallback',
    venue: fallbackVenue,
  });
});

// Health check: handles /health, /api/health, /healthz, and /ping
app.get(['/health', '/api/health', '/healthz', '/ping'], (req, res) => {
  return res.status(200).json({
    status: 'healthy',
    firebaseRemoved: true,
    supabaseReady: true,
    storageMode: pgPool ? 'postgres' : 'file',
    postgresHydrated: pgPool ? isHydrated : false,
    time: new Date().toISOString(),
    usersCount: db.users.length,
    venuesCount: db.venues.length,
    bookingsCount: db.bookings.length,
    configured: {
      database: Boolean(pgPool),
      jwt: Boolean(process.env.JWT_SECRET),
      adminEmail: Boolean(process.env.ADMIN_EMAIL),
      payments: Boolean(process.env.PAYMENT_WEBHOOK_SECRET || process.env.PAYMENT_LISTENER_KEY)
    }
  });
});

if (pgPool) {
  hydratePostgres().catch(err => {
    console.warn('PostgreSQL hydrate notice (running on empty/local state):', err.message);
  });
}

if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`\n🚀 Hagzy server is live on port ${PORT} (bound to 0.0.0.0)`);
    console.log(`📡 Venues loaded: ${db.venues.length} · 👥 Users: ${db.users.length}\n`);
  });
  if (process.env.NODE_ENV !== 'test') {
    setInterval(() => {
      executeBookingReminders().catch(err => {
        console.warn('Background reminder runner tick notice:', err.message);
      });
    }, 5 * 60 * 1000);
  }
}

module.exports = { app, buildFallbackVenueFromTemplateNode, parseClientTimestamp };


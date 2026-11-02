-- Migration 002: Authoritative Relational Schema
-- Tables: users, venues, bookable_units, bookings, payment_intents, payment_events, wallet_ledger, audit_log

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Users table
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE,
  phone TEXT UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  password_hash TEXT,
  role TEXT NOT NULL DEFAULT 'customer',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Venues table
CREATE TABLE IF NOT EXISTS venues (
  id TEXT PRIMARY KEY,
  owner_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'sports',
  location TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  deposit_percent NUMERIC(5,2) NOT NULL DEFAULT 30.00,
  receiver_wallet TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Bookable units / spaces
CREATE TABLE IF NOT EXISTS bookable_units (
  id TEXT PRIMARY KEY,
  venue_id TEXT NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'space',
  hourly_rate NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Bookings table
CREATE TABLE IF NOT EXISTS bookings (
  id TEXT PRIMARY KEY,
  venue_id TEXT NOT NULL REFERENCES venues(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL,
  customer_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  customer_name TEXT NOT NULL DEFAULT '',
  customer_phone TEXT NOT NULL DEFAULT '',
  customer_email TEXT NOT NULL DEFAULT '',
  starts_at TIMESTAMPTZ NOT NULL,
  duration_minutes INTEGER NOT NULL CHECK (duration_minutes >= 15 AND duration_minutes <= 720),
  price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
  due_now NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  status TEXT NOT NULL DEFAULT 'pending_payment' CHECK (status IN ('pending_payment', 'confirmed', 'completed', 'cancelled', 'expired', 'no_show')),
  payment_method TEXT NOT NULL DEFAULT '',
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'refunded', 'partially_paid')),
  hold_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Payment Intents
CREATE TABLE IF NOT EXISTS payment_intents (
  id TEXT PRIMARY KEY,
  booking_id TEXT,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('INSTAPAY', 'MOBILE_WALLET', 'FAWRY', 'CARD')),
  receiver_wallet TEXT,
  expected_sender_identifier TEXT NOT NULL,
  expected_amount NUMERIC(10,2) NOT NULL CHECK (expected_amount > 0),
  actual_amount NUMERIC(10,2),
  status TEXT NOT NULL DEFAULT 'AWAITING_TRANSFER' CHECK (status IN ('AWAITING_TRANSFER', 'VERIFIED', 'EXPIRED', 'FAILED')),
  expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. Payment Events (Log of incoming webhooks/notifications)
CREATE TABLE IF NOT EXISTS payment_events (
  id TEXT PRIMARY KEY,
  event_hash TEXT UNIQUE NOT NULL,
  payment_method TEXT NOT NULL,
  sender_identifier TEXT NOT NULL,
  amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  provider_ref TEXT,
  raw_text TEXT,
  status TEXT NOT NULL CHECK (status IN ('MATCHED', 'DUPLICATE', 'UNMATCHED', 'AMBIGUOUS_MATCH', 'REQUIRES_MANUAL_REVIEW', 'REJECTED_STALE')),
  matched_intent_id TEXT REFERENCES payment_intents(id) ON DELETE SET NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. Wallet Ledger (Append-only, strictly immutable)
CREATE TABLE IF NOT EXISTS wallet_ledger (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount <> 0),
  entry_type TEXT NOT NULL CHECK (entry_type IN ('TOPUP', 'BOOKING_DEPOSIT', 'REFUND', 'WELCOME_BONUS', 'ADMIN_ADJUSTMENT')),
  reference_id TEXT,
  description TEXT NOT NULL DEFAULT '',
  actor TEXT NOT NULL DEFAULT 'system',
  balance_after NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. Audit Log
CREATE TABLE IF NOT EXISTS audit_log (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  from_state TEXT,
  to_state TEXT,
  actor TEXT NOT NULL,
  reason TEXT,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for performance and isolation
CREATE INDEX IF NOT EXISTS bookings_venue_starts_idx ON bookings (venue_id, starts_at);
CREATE INDEX IF NOT EXISTS bookings_customer_idx ON bookings (customer_id);
CREATE INDEX IF NOT EXISTS wallet_ledger_user_idx ON wallet_ledger (user_id, created_at);
CREATE INDEX IF NOT EXISTS payment_intents_sender_amt_idx ON payment_intents (payment_method, expected_sender_identifier, expected_amount, status);
CREATE INDEX IF NOT EXISTS payment_events_hash_idx ON payment_events (event_hash);
CREATE INDEX IF NOT EXISTS audit_log_entity_idx ON audit_log (entity_type, entity_id);


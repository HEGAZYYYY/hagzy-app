-- 002_authoritative_schema.sql
-- Clean, strictly linked relational PostgreSQL schema for Hagzy (Supabase-ready).

CREATE TABLE IF NOT EXISTS public.users (
  id TEXT PRIMARY KEY,
  firebase_uid TEXT UNIQUE,
  google_id TEXT UNIQUE,
  apple_user_id TEXT UNIQUE,
  email TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  name TEXT NOT NULL DEFAULT '',
  avatar TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'partner', 'owner', 'super_admin')),
  partner_status TEXT NOT NULL DEFAULT 'none' CHECK (partner_status IN ('none', 'pending', 'approved', 'rejected')),
  auth_provider TEXT NOT NULL DEFAULT 'otp',
  password_hash TEXT,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  phone_verified BOOLEAN NOT NULL DEFAULT FALSE,
  wallet_balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.venues (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  name_en TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  area TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  owner_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  owner_email TEXT NOT NULL DEFAULT '',
  owner_phone TEXT NOT NULL DEFAULT '',
  price_per_hour NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (price_per_hour >= 0),
  deposit_percent INTEGER NOT NULL DEFAULT 0 CHECK (deposit_percent BETWEEN 0 AND 100),
  pricing_mode TEXT NOT NULL DEFAULT 'per_hour',
  rating NUMERIC(3, 2) NOT NULL DEFAULT 0.00,
  reviews_count INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  images JSONB NOT NULL DEFAULT '[]'::jsonb,
  amenities JSONB NOT NULL DEFAULT '[]'::jsonb,
  rules JSONB NOT NULL DEFAULT '[]'::jsonb,
  services JSONB NOT NULL DEFAULT '[]'::jsonb,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.bookable_units (
  id TEXT NOT NULL,
  venue_id TEXT NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_en TEXT NOT NULL DEFAULT '',
  unit_type TEXT NOT NULL DEFAULT 'unit',
  capacity INTEGER,
  price_per_hour NUMERIC(12, 2),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  source_key TEXT NOT NULL DEFAULT 'units',
  sort_order INTEGER NOT NULL DEFAULT 0,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (venue_id, id)
);

CREATE TABLE IF NOT EXISTS public.bookings (
  id TEXT PRIMARY KEY,
  customer_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  venue_id TEXT NOT NULL REFERENCES public.venues(id) ON DELETE RESTRICT,
  unit_id TEXT,
  unit_name TEXT NOT NULL DEFAULT '',
  venue_name TEXT NOT NULL DEFAULT '',
  customer_name TEXT NOT NULL DEFAULT '',
  customer_phone TEXT NOT NULL DEFAULT '',
  customer_email TEXT NOT NULL DEFAULT '',
  booking_date TEXT NOT NULL DEFAULT '',
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ,
  duration_minutes INTEGER NOT NULL DEFAULT 60 CHECK (duration_minutes > 0),
  status TEXT NOT NULL DEFAULT 'pending_payment' CHECK (status IN ('pending', 'pending_payment', 'confirmed', 'completed', 'cancelled', 'expired', 'no_show', 'checked_in')),
  total_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (total_price >= 0),
  deposit_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (deposit_amount >= 0),
  due_now NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (due_now >= 0),
  actual_paid_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (actual_paid_amount >= 0),
  excess_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (excess_amount >= 0),
  payment_method TEXT NOT NULL DEFAULT '',
  payment_reference TEXT NOT NULL DEFAULT '',
  confirmed BOOLEAN NOT NULL DEFAULT FALSE,
  cancelled BOOLEAN NOT NULL DEFAULT FALSE,
  checked_in BOOLEAN NOT NULL DEFAULT FALSE,
  checked_in_at TIMESTAMPTZ,
  confirmed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_bookings_venue_unit FOREIGN KEY (venue_id, unit_id) REFERENCES public.bookable_units(venue_id, id) ON DELETE SET NULL (unit_id)
);

CREATE TABLE IF NOT EXISTS public.wallet_ledger (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  booking_id TEXT REFERENCES public.bookings(id) ON DELETE SET NULL,
  amount NUMERIC(12, 2) NOT NULL,
  entry_type TEXT NOT NULL CHECK (entry_type IN ('TOPUP', 'BOOKING_DEPOSIT', 'REFUND', 'WELCOME_BONUS', 'EXCESS_PAYMENT', 'ADMIN_ADJUSTMENT')),
  reference_id TEXT,
  description TEXT NOT NULL DEFAULT '',
  actor TEXT NOT NULL DEFAULT 'system',
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_intents (
  id TEXT PRIMARY KEY,
  booking_id TEXT REFERENCES public.bookings(id) ON DELETE SET NULL,
  raw_booking_id TEXT NOT NULL DEFAULT '',
  user_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('INSTAPAY', 'MOBILE_WALLET')),
  receiver_wallet TEXT NOT NULL DEFAULT '',
  expected_sender_identifier TEXT NOT NULL DEFAULT '',
  expected_amount NUMERIC(12, 2) NOT NULL CHECK (expected_amount > 0),
  actual_amount NUMERIC(12, 2),
  excess_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  status TEXT NOT NULL DEFAULT 'AWAITING_TRANSFER' CHECK (status IN ('AWAITING_TRANSFER', 'VERIFIED', 'EXPIRED', 'UNDERPAID_REVIEW', 'CANCELLED')),
  verified_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_events (
  id TEXT PRIMARY KEY,
  matched_intent_id TEXT REFERENCES public.payment_intents(id) ON DELETE SET NULL,
  booking_id TEXT REFERENCES public.bookings(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('INSTAPAY', 'MOBILE_WALLET')),
  sender_identifier TEXT NOT NULL DEFAULT '',
  amount NUMERIC(12, 2) NOT NULL,
  provider_ref TEXT NOT NULL DEFAULT '',
  is_claimed BOOLEAN NOT NULL DEFAULT FALSE,
  raw_text TEXT NOT NULL DEFAULT '',
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.payment_review_queue (
  id TEXT PRIMARY KEY,
  intent_id TEXT REFERENCES public.payment_intents(id) ON DELETE SET NULL,
  booking_id TEXT REFERENCES public.bookings(id) ON DELETE SET NULL,
  user_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  payment_method TEXT NOT NULL DEFAULT 'INSTAPAY',
  sender_identifier TEXT NOT NULL DEFAULT '',
  amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
  provider_ref TEXT NOT NULL DEFAULT '',
  raw_text TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
  reason TEXT NOT NULL DEFAULT '',
  resolved_by TEXT,
  resolved_at TIMESTAMPTZ,
  attached_to JSONB,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.partner_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  approved_venue_id TEXT REFERENCES public.venues(id) ON DELETE SET NULL,
  venue_name TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  area TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  owner_name TEXT NOT NULL DEFAULT '',
  owner_email TEXT NOT NULL DEFAULT '',
  owner_phone TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by TEXT,
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT NOT NULL DEFAULT '',
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
  id TEXT PRIMARY KEY,
  booking_id TEXT REFERENCES public.bookings(id) ON DELETE SET NULL,
  venue_id TEXT REFERENCES public.venues(id) ON DELETE SET NULL,
  user_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL DEFAULT '',
  from_status TEXT,
  to_status TEXT,
  actor TEXT NOT NULL DEFAULT 'system',
  reason TEXT NOT NULL DEFAULT '',
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.otp_challenges (
  target TEXT PRIMARY KEY,
  hashed_code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  name TEXT NOT NULL DEFAULT '',
  is_sign_up BOOLEAN NOT NULL DEFAULT FALSE,
  is_partner BOOLEAN NOT NULL DEFAULT FALSE,
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Foreign Key & Query Indexes
CREATE INDEX IF NOT EXISTS idx_users_lower_email ON public.users (LOWER(email)) WHERE email <> '';
CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users (phone) WHERE phone <> '';

CREATE INDEX IF NOT EXISTS idx_venues_owner_id ON public.venues (owner_id);
CREATE INDEX IF NOT EXISTS idx_venues_active ON public.venues (city, category) WHERE is_active = TRUE AND is_deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_bookable_units_venue_id ON public.bookable_units (venue_id);

CREATE INDEX IF NOT EXISTS idx_bookings_customer_id ON public.bookings (customer_id);
CREATE INDEX IF NOT EXISTS idx_bookings_venue_id ON public.bookings (venue_id);
CREATE INDEX IF NOT EXISTS idx_bookings_venue_unit ON public.bookings (venue_id, unit_id);
CREATE INDEX IF NOT EXISTS idx_bookings_slot_lookup ON public.bookings (venue_id, starts_at) WHERE status IN ('pending_payment', 'pending', 'confirmed', 'checked_in');
CREATE INDEX IF NOT EXISTS idx_bookings_status_created ON public.bookings (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_ledger_user_id ON public.wallet_ledger (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_ledger_booking_id ON public.wallet_ledger (booking_id);

CREATE INDEX IF NOT EXISTS idx_payment_intents_booking_id ON public.payment_intents (booking_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_user_id ON public.payment_intents (user_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_awaiting ON public.payment_intents (payment_method, expected_sender_identifier, expected_amount) WHERE status = 'AWAITING_TRANSFER';

CREATE INDEX IF NOT EXISTS idx_payment_events_matched_intent_id ON public.payment_events (matched_intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_events_booking_id ON public.payment_events (booking_id);
CREATE INDEX IF NOT EXISTS idx_payment_events_received_at ON public.payment_events (received_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_review_queue_intent_id ON public.payment_review_queue (intent_id);
CREATE INDEX IF NOT EXISTS idx_payment_review_queue_booking_id ON public.payment_review_queue (booking_id);
CREATE INDEX IF NOT EXISTS idx_payment_review_queue_user_id ON public.payment_review_queue (user_id);
CREATE INDEX IF NOT EXISTS idx_payment_review_queue_pending ON public.payment_review_queue (received_at DESC) WHERE status <> 'RESOLVED' AND status <> 'DISMISSED';

CREATE INDEX IF NOT EXISTS idx_partner_requests_user_id ON public.partner_requests (user_id);
CREATE INDEX IF NOT EXISTS idx_partner_requests_approved_venue_id ON public.partner_requests (approved_venue_id);
CREATE INDEX IF NOT EXISTS idx_partner_requests_pending ON public.partner_requests (created_at DESC) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_audit_log_booking_id ON public.audit_log (booking_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_venue_id ON public.audit_log (venue_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON public.audit_log (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_occurred_at ON public.audit_log (occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_otp_challenges_expires_at ON public.otp_challenges (expires_at);

-- updated_at Triggers
CREATE OR REPLACE TRIGGER trg_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_venues_updated_at BEFORE UPDATE ON public.venues FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_bookable_units_updated_at BEFORE UPDATE ON public.bookable_units FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_bookings_updated_at BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_payment_intents_updated_at BEFORE UPDATE ON public.payment_intents FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_payment_review_queue_updated_at BEFORE UPDATE ON public.payment_review_queue FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_partner_requests_updated_at BEFORE UPDATE ON public.partner_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE OR REPLACE TRIGGER trg_otp_challenges_updated_at BEFORE UPDATE ON public.otp_challenges FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Row Level Security + Direct Client API Lockdown
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'users', 'venues', 'bookable_units', 'bookings', 'wallet_ledger',
    'payment_intents', 'payment_events', 'payment_review_queue',
    'partner_requests', 'audit_log', 'otp_challenges'
  ]
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated;', tbl);
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl AND policyname = 'deny_client_api_access'
    ) THEN
      EXECUTE format('CREATE POLICY deny_client_api_access ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);', tbl);
    END IF;
  END LOOP;
END;
$$;

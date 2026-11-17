-- 004_supabase_auth_rls_rpc.sql
-- Links Supabase Auth (auth.users) 1:1 to public.users, adds normalized serverless tables,
-- scoped Realtime RLS policies, storage bucket, and atomic Postgres RPCs.

-- 1. Link public.users <-> auth.users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_users_auth_user'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT fk_users_auth_user
      FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_auth_user_id
  ON public.users (auth_user_id);

-- 2. Allow extended booking workflow statuses used by payment proof / chatbot flows
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_status_check;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_status_check CHECK (
  status IN (
    'pending',
    'pending_payment',
    'pending_confirmation',
    'awaiting_payment',
    'confirmed',
    'completed',
    'cancelled',
    'expired',
    'no_show',
    'checked_in'
  )
);

-- 3. Normalized venue reviews & durable serverless runtime state tables
CREATE TABLE IF NOT EXISTS public.venue_reviews (
  id TEXT PRIMARY KEY,
  venue_id TEXT NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  user_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  booking_id TEXT REFERENCES public.bookings(id) ON DELETE SET NULL,
  author_name TEXT NOT NULL DEFAULT 'Member',
  rating NUMERIC(2, 1) NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT NOT NULL DEFAULT '',
  verified_booking BOOLEAN NOT NULL DEFAULT TRUE,
  review_date TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_venue_reviews_venue_id ON public.venue_reviews (venue_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_venue_reviews_user_id ON public.venue_reviews (user_id);
CREATE INDEX IF NOT EXISTS idx_venue_reviews_booking_id ON public.venue_reviews (booking_id);

CREATE TABLE IF NOT EXISTS public.revoked_tokens (
  token_hash TEXT PRIMARY KEY,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_revoked_tokens_expires_at ON public.revoked_tokens (expires_at);

CREATE TABLE IF NOT EXISTS public.payment_event_hashes (
  event_hash TEXT PRIMARY KEY,
  payment_event_id TEXT REFERENCES public.payment_events(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_event_hashes_event_id ON public.payment_event_hashes (payment_event_id);

CREATE TABLE IF NOT EXISTS public.gateway_heartbeats (
  id TEXT PRIMARY KEY DEFAULT 'default',
  last_heartbeat_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source TEXT NOT NULL DEFAULT 'android_listener',
  recent_logs JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE TRIGGER trg_gateway_heartbeats_updated_at
  BEFORE UPDATE ON public.gateway_heartbeats
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Lockdown internal state tables strictly to server / service_role
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'revoked_tokens',
    'payment_event_hashes',
    'gateway_heartbeats'
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

-- 4. Refresh v_user_overview with auth_user_id for 1:1 moderation
CREATE OR REPLACE VIEW public.v_user_overview
WITH (security_invoker = true) AS
WITH booking_stats AS (
  SELECT
    customer_id,
    COUNT(*)::INTEGER AS total_bookings,
    COUNT(*) FILTER (WHERE status IN ('confirmed', 'completed', 'checked_in'))::INTEGER AS confirmed_bookings,
    MAX(created_at) AS last_booking_at
  FROM public.bookings
  WHERE customer_id IS NOT NULL
  GROUP BY customer_id
),
ledger_stats AS (
  SELECT
    user_id,
    COALESCE(SUM(amount), 0)::NUMERIC(12, 2) AS ledger_balance
  FROM public.wallet_ledger
  GROUP BY user_id
),
venue_stats AS (
  SELECT
    owner_id,
    COUNT(*) FILTER (WHERE is_deleted = FALSE)::INTEGER AS owned_venues
  FROM public.venues
  WHERE owner_id IS NOT NULL
  GROUP BY owner_id
)
SELECT
  u.id AS user_id,
  u.name,
  u.email,
  u.phone,
  u.role,
  u.partner_status,
  u.auth_provider,
  u.email_verified,
  u.phone_verified,
  u.wallet_balance,
  COALESCE(ls.ledger_balance, 0.00) AS computed_ledger_balance,
  COALESCE(bs.total_bookings, 0) AS total_bookings,
  COALESCE(bs.confirmed_bookings, 0) AS confirmed_bookings,
  COALESCE(vs.owned_venues, 0) AS owned_venues,
  bs.last_booking_at,
  u.created_at,
  u.updated_at,
  u.auth_user_id
FROM public.users u
LEFT JOIN booking_stats bs ON bs.customer_id = u.id
LEFT JOIN ledger_stats ls ON ls.user_id = u.id
LEFT JOIN venue_stats vs ON vs.owner_id = u.id;

REVOKE ALL ON public.v_user_overview FROM PUBLIC, anon, authenticated;

-- 5. User-scoped & public read RLS policies for Supabase Realtime (column-safe, zero writes from clients)
-- Note: Uses ALTER POLICY / guarded CREATE POLICY (no DROP POLICY) so it runs cleanly in both migrations and MCP SQL.
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'venues',
    'bookable_units',
    'users',
    'bookings',
    'wallet_ledger',
    'payment_intents'
  ]
  LOOP
    IF EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl AND policyname = 'deny_client_api_access'
    ) THEN
      EXECUTE format('ALTER POLICY deny_client_api_access ON public.%I USING (FALSE) WITH CHECK (FALSE);', tbl);
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON TABLE public.venues FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, name, name_en, category, city, area, address, description, phone,
  price_per_hour, deposit_percent, pricing_mode, rating, reviews_count,
  is_active, is_deleted, images, amenities, rules, services, extra, created_at, updated_at
) ON public.venues TO anon, authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'venues' AND policyname = 'public_read_active_venues'
  ) THEN
    ALTER POLICY public_read_active_venues ON public.venues
      USING (is_active = TRUE AND is_deleted = FALSE);
  ELSE
    CREATE POLICY public_read_active_venues ON public.venues
      FOR SELECT TO anon, authenticated
      USING (is_active = TRUE AND is_deleted = FALSE);
  END IF;
END;
$$;

REVOKE ALL ON TABLE public.bookable_units FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.bookable_units TO anon, authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bookable_units' AND policyname = 'public_read_active_units'
  ) THEN
    ALTER POLICY public_read_active_units ON public.bookable_units
      USING (
        is_active = TRUE
        AND EXISTS (
          SELECT 1 FROM public.venues v
          WHERE v.id = venue_id AND v.is_active = TRUE AND v.is_deleted = FALSE
        )
      );
  ELSE
    CREATE POLICY public_read_active_units ON public.bookable_units
      FOR SELECT TO anon, authenticated
      USING (
        is_active = TRUE
        AND EXISTS (
          SELECT 1 FROM public.venues v
          WHERE v.id = venue_id AND v.is_active = TRUE AND v.is_deleted = FALSE
        )
      );
  END IF;
END;
$$;

ALTER TABLE public.venue_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.venue_reviews FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, venue_id, author_name, rating, comment, verified_booking, review_date, created_at)
  ON public.venue_reviews TO anon, authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'venue_reviews' AND policyname = 'public_read_venue_reviews'
  ) THEN
    ALTER POLICY public_read_venue_reviews ON public.venue_reviews
      USING (TRUE);
  ELSE
    CREATE POLICY public_read_venue_reviews ON public.venue_reviews
      FOR SELECT TO anon, authenticated
      USING (TRUE);
  END IF;
END;
$$;

REVOKE ALL ON TABLE public.users FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, auth_user_id, email, phone, name, avatar, role, partner_status,
  auth_provider, email_verified, phone_verified, wallet_balance, created_at, updated_at
) ON public.users TO authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'user_read_own_profile'
  ) THEN
    ALTER POLICY user_read_own_profile ON public.users
      USING (auth_user_id = (SELECT auth.uid()));
  ELSE
    CREATE POLICY user_read_own_profile ON public.users
      FOR SELECT TO authenticated
      USING (auth_user_id = (SELECT auth.uid()));
  END IF;
END;
$$;

REVOKE ALL ON TABLE public.bookings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.bookings TO authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bookings' AND policyname = 'user_read_own_bookings'
  ) THEN
    ALTER POLICY user_read_own_bookings ON public.bookings
      USING (
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = customer_id AND u.auth_user_id = (SELECT auth.uid())
        )
      );
  ELSE
    CREATE POLICY user_read_own_bookings ON public.bookings
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = customer_id AND u.auth_user_id = (SELECT auth.uid())
        )
      );
  END IF;
END;
$$;

REVOKE ALL ON TABLE public.wallet_ledger FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.wallet_ledger TO authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'wallet_ledger' AND policyname = 'user_read_own_wallet_ledger'
  ) THEN
    ALTER POLICY user_read_own_wallet_ledger ON public.wallet_ledger
      USING (
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = user_id AND u.auth_user_id = (SELECT auth.uid())
        )
      );
  ELSE
    CREATE POLICY user_read_own_wallet_ledger ON public.wallet_ledger
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = user_id AND u.auth_user_id = (SELECT auth.uid())
        )
      );
  END IF;
END;
$$;

REVOKE ALL ON TABLE public.payment_intents FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.payment_intents TO authenticated;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payment_intents' AND policyname = 'user_read_own_payment_intents'
  ) THEN
    ALTER POLICY user_read_own_payment_intents ON public.payment_intents
      USING (
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = user_id AND u.auth_user_id = (SELECT auth.uid())
        )
      );
  ELSE
    CREATE POLICY user_read_own_payment_intents ON public.payment_intents
      FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.users u
          WHERE u.id = user_id AND u.auth_user_id = (SELECT auth.uid())
        )
      );
  END IF;
END;
$$;

-- 6. Realtime Publication
DO $$
DECLARE
  tbl TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH tbl IN ARRAY ARRAY['venues', 'bookable_units', 'bookings', 'payment_intents', 'wallet_ledger']
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = tbl
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl);
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- 7. Supabase Storage bucket for venue images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'venue-images',
  'venue-images',
  TRUE,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 8. Atomic PostgreSQL RPCs (service_role only)
CREATE OR REPLACE FUNCTION public.rpc_apply_wallet_entry_atomic(
  p_entry_id TEXT,
  p_user_id TEXT,
  p_booking_id TEXT,
  p_amount NUMERIC,
  p_entry_type TEXT,
  p_reference_id TEXT,
  p_description TEXT,
  p_actor TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user RECORD;
  v_new_balance NUMERIC(12, 2);
  v_entry RECORD;
BEGIN
  SELECT id, wallet_balance INTO v_user
  FROM public.users
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'User not found');
  END IF;

  IF p_entry_type = 'WELCOME_BONUS' AND EXISTS (
    SELECT 1 FROM public.wallet_ledger
    WHERE user_id = p_user_id AND entry_type = 'WELCOME_BONUS'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'Welcome gift balance has already been claimed for this account');
  END IF;

  v_new_balance := ROUND(COALESCE(v_user.wallet_balance, 0) + COALESCE(p_amount, 0), 2);
  IF p_amount < 0 AND v_new_balance < 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'status', 402,
      'error', 'Insufficient wallet balance.',
      'available', v_user.wallet_balance,
      'required', ABS(p_amount)
    );
  END IF;

  INSERT INTO public.wallet_ledger (
    id, user_id, booking_id, amount, entry_type, reference_id, description, actor
  )
  VALUES (
    p_entry_id, p_user_id, p_booking_id, ROUND(p_amount, 2), p_entry_type, p_reference_id,
    COALESCE(p_description, ''), COALESCE(p_actor, 'system')
  )
  RETURNING * INTO v_entry;

  SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2) INTO v_new_balance
  FROM public.wallet_ledger
  WHERE user_id = p_user_id;

  UPDATE public.users
  SET wallet_balance = v_new_balance
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'ok', true,
    'walletBalance', v_new_balance,
    'entry', jsonb_build_object(
      'id', v_entry.id,
      'userId', v_entry.user_id,
      'bookingId', v_entry.booking_id,
      'amount', v_entry.amount,
      'type', v_entry.entry_type,
      'referenceId', v_entry.reference_id,
      'description', v_entry.description,
      'actor', v_entry.actor,
      'createdAt', v_entry.created_at
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_book_slot_atomic(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_booking_id TEXT := p_payload->>'id';
  v_customer_id TEXT := NULLIF(p_payload->>'customerId', '');
  v_venue_id TEXT := p_payload->>'venueId';
  v_unit_id TEXT := NULLIF(p_payload->>'unitId', '');
  v_unit_name TEXT := COALESCE(p_payload->>'unitName', '');
  v_venue_name TEXT := COALESCE(p_payload->>'venueName', '');
  v_customer_name TEXT := COALESCE(p_payload->>'customerName', '');
  v_customer_phone TEXT := COALESCE(p_payload->>'customerPhone', '');
  v_customer_email TEXT := LOWER(COALESCE(p_payload->>'customerEmail', ''));
  v_booking_date TEXT := COALESCE(p_payload->>'bookingDate', '');
  v_starts_at TIMESTAMPTZ := (p_payload->>'startsAt')::timestamptz;
  v_duration INTEGER := GREATEST(15, LEAST(720, COALESCE((p_payload->>'durationMinutes')::integer, 60)));
  v_ends_at TIMESTAMPTZ := v_starts_at + make_interval(mins => v_duration);
  v_status TEXT := COALESCE(p_payload->>'status', 'pending_payment');
  v_total_price NUMERIC(12, 2) := ROUND(COALESCE((p_payload->>'totalPrice')::numeric, 0), 2);
  v_deposit_amount NUMERIC(12, 2) := ROUND(COALESCE((p_payload->>'depositAmount')::numeric, 0), 2);
  v_due_now NUMERIC(12, 2) := ROUND(COALESCE((p_payload->>'dueNow')::numeric, 0), 2);
  v_actual_paid NUMERIC(12, 2) := ROUND(COALESCE((p_payload->>'actualPaidAmount')::numeric, 0), 2);
  v_payment_method TEXT := COALESCE(p_payload->>'paymentMethod', '');
  v_confirmed BOOLEAN := COALESCE((p_payload->>'confirmed')::boolean, false);
  v_expires_at TIMESTAMPTZ := NULLIF(p_payload->>'expiresAt', '')::timestamptz;
  v_extra JSONB := COALESCE(p_payload->'extra', '{}'::jsonb);
  v_charge_wallet BOOLEAN := COALESCE((p_payload->>'chargeWallet')::boolean, false);
  v_ledger_id TEXT := NULLIF(p_payload->>'ledgerEntryId', '');
  v_audit_id TEXT := COALESCE(p_payload->>'auditId', 'aud_' || v_booking_id);
  v_actor TEXT := COALESCE(p_payload->>'actor', 'customer');
  v_conflict_exists BOOLEAN;
  v_wallet_balance NUMERIC(12, 2) := NULL;
BEGIN
  IF v_booking_id IS NULL OR v_venue_id IS NULL OR v_starts_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'status', 400, 'error', 'Missing required booking fields');
  END IF;

  -- Serialize concurrent attempts for the same venue + bookable unit
  PERFORM pg_advisory_xact_lock(hashtext(v_venue_id || '::' || COALESCE(v_unit_id, '')));

  SELECT EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.venue_id = v_venue_id
      AND COALESCE(b.unit_id, '') = COALESCE(v_unit_id, '')
      AND b.id <> v_booking_id
      AND b.cancelled = FALSE
      AND b.status NOT IN ('cancelled', 'expired', 'no_show')
      AND (b.status = 'confirmed' OR b.confirmed = TRUE OR b.expires_at IS NULL OR b.expires_at > NOW())
      AND b.starts_at < v_ends_at
      AND COALESCE(b.ends_at, b.starts_at + make_interval(mins => b.duration_minutes)) > v_starts_at
  ) INTO v_conflict_exists;

  IF v_conflict_exists THEN
    RETURN jsonb_build_object('ok', false, 'status', 409, 'error', 'This time slot is already reserved or on hold by another customer.');
  END IF;

  IF v_charge_wallet THEN
    IF v_customer_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'status', 401, 'error', 'Authentication is required to pay with your wallet');
    END IF;

    SELECT wallet_balance INTO v_wallet_balance
    FROM public.users
    WHERE id = v_customer_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok', false, 'status', 404, 'error', 'Account not found');
    END IF;

    IF COALESCE(v_wallet_balance, 0) < v_due_now THEN
      RETURN jsonb_build_object(
        'ok', false,
        'status', 402,
        'error', 'Insufficient wallet balance.',
        'available', v_wallet_balance,
        'required', v_due_now
      );
    END IF;
  END IF;

  INSERT INTO public.bookings (
    id, customer_id, venue_id, unit_id, unit_name, venue_name,
    customer_name, customer_phone, customer_email, booking_date,
    starts_at, ends_at, duration_minutes, status,
    total_price, deposit_amount, due_now, actual_paid_amount,
    payment_method, confirmed, cancelled, confirmed_at, expires_at, extra
  )
  VALUES (
    v_booking_id, v_customer_id, v_venue_id, v_unit_id, v_unit_name, v_venue_name,
    v_customer_name, v_customer_phone, v_customer_email, v_booking_date,
    v_starts_at, v_ends_at, v_duration, v_status,
    v_total_price, v_deposit_amount, v_due_now, v_actual_paid,
    v_payment_method, v_confirmed, FALSE,
    CASE WHEN v_confirmed THEN NOW() ELSE NULL END,
    v_expires_at, v_extra
  );

  IF v_charge_wallet AND v_due_now > 0 THEN
    INSERT INTO public.wallet_ledger (
      id, user_id, booking_id, amount, entry_type, reference_id, description, actor
    )
    VALUES (
      COALESCE(v_ledger_id, 'led_' || v_booking_id),
      v_customer_id,
      v_booking_id,
      -v_due_now,
      'BOOKING_DEPOSIT',
      v_booking_id,
      'Booking deposit for ' || v_venue_name,
      'customer'
    );

    SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2) INTO v_wallet_balance
    FROM public.wallet_ledger
    WHERE user_id = v_customer_id;

    UPDATE public.users
    SET wallet_balance = v_wallet_balance
    WHERE id = v_customer_id;
  END IF;

  INSERT INTO public.audit_log (
    id, booking_id, venue_id, user_id, action, from_status, to_status, actor, reason
  )
  VALUES (
    v_audit_id, v_booking_id, v_venue_id, v_customer_id,
    'booking_created', NULL, v_status, v_actor,
    CASE WHEN v_charge_wallet THEN 'Wallet deposit paid at booking' ELSE 'Booking hold created' END
  );

  RETURN jsonb_build_object(
    'ok', true,
    'walletBalance', v_wallet_balance
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_apply_wallet_entry_atomic(TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_apply_wallet_entry_atomic(TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT) TO service_role;

REVOKE ALL ON FUNCTION public.rpc_book_slot_atomic(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_book_slot_atomic(JSONB) TO service_role;

-- =============================================================================
-- Migration 005: Booking QR Check-In, Customer-Chosen WhatsApp Reminders & Partner Notifications
-- =============================================================================
-- Safe to run standalone or after 004_supabase_auth_rls_rpc.sql (idempotent).

BEGIN;

-- 1) Per-booking WhatsApp reminder timing & idempotent send timestamp
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS reminder_offset_minutes INTEGER NOT NULL DEFAULT 120,
  ADD COLUMN IF NOT EXISTS reminder_sent_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_bookings_due_reminders
  ON public.bookings (starts_at)
  WHERE confirmed = TRUE
    AND cancelled = FALSE
    AND checked_in = FALSE
    AND reminder_sent_at IS NULL
    AND reminder_offset_minutes > 0;

-- 2) Persistent in-app partner / admin notifications (server-only via Edge Functions)
CREATE TABLE IF NOT EXISTS public.partner_notifications (
  id             TEXT PRIMARY KEY,
  owner_id       TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  venue_id       TEXT REFERENCES public.venues(id) ON DELETE CASCADE,
  booking_id     TEXT REFERENCES public.bookings(id) ON DELETE CASCADE,
  event_type     TEXT NOT NULL,
  title          TEXT NOT NULL,
  body           TEXT NOT NULL DEFAULT '',
  whatsapp_sent  BOOLEAN NOT NULL DEFAULT FALSE,
  read           BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_partner_notifications_venue_created
  ON public.partner_notifications (venue_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_partner_notifications_unread
  ON public.partner_notifications (venue_id, created_at DESC)
  WHERE read = FALSE;

ALTER TABLE public.partner_notifications ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.partner_notifications FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.partner_notifications TO service_role;

-- 3) Update atomic booking RPC so reminderOffsetMinutes is stored on creation
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
  v_reminder_offset INTEGER := GREATEST(0, LEAST(10080, COALESCE(NULLIF(p_payload->>'reminderOffsetMinutes', '')::integer, 120)));
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
    payment_method, confirmed, cancelled, confirmed_at, expires_at,
    reminder_offset_minutes, extra
  )
  VALUES (
    v_booking_id, v_customer_id, v_venue_id, v_unit_id, v_unit_name, v_venue_name,
    v_customer_name, v_customer_phone, v_customer_email, v_booking_date,
    v_starts_at, v_ends_at, v_duration, v_status,
    v_total_price, v_deposit_amount, v_due_now, v_actual_paid,
    v_payment_method, v_confirmed, FALSE,
    CASE WHEN v_confirmed THEN NOW() ELSE NULL END,
    v_expires_at, v_reminder_offset, v_extra
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

REVOKE ALL ON FUNCTION public.rpc_book_slot_atomic(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_book_slot_atomic(JSONB) TO service_role;

COMMIT;

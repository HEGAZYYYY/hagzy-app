-- 003_moderation_views.sql
-- Private admin/ops moderation views with security_invoker = true.

CREATE OR REPLACE VIEW public.v_moderation_bookings
WITH (security_invoker = true) AS
SELECT
  b.id AS booking_id,
  b.status,
  b.confirmed,
  b.cancelled,
  b.checked_in,
  b.booking_date,
  b.starts_at,
  b.ends_at,
  b.duration_minutes,
  b.total_price,
  b.deposit_amount,
  b.due_now,
  b.actual_paid_amount,
  b.excess_amount,
  b.payment_method,
  b.payment_reference,
  COALESCE(u.id, b.customer_id) AS linked_user_id,
  COALESCE(NULLIF(u.name, ''), b.customer_name) AS customer_name,
  COALESCE(NULLIF(u.email, ''), b.customer_email) AS customer_email,
  COALESCE(NULLIF(u.phone, ''), b.customer_phone) AS customer_phone,
  u.wallet_balance AS customer_wallet_balance,
  v.id AS venue_id,
  COALESCE(NULLIF(v.name, ''), b.venue_name) AS venue_name,
  v.city AS venue_city,
  v.category AS venue_category,
  v.owner_id AS venue_owner_id,
  v.owner_email AS venue_owner_email,
  bu.id AS unit_id,
  COALESCE(NULLIF(bu.name, ''), b.unit_name) AS unit_name,
  pi.id AS latest_intent_id,
  pi.status AS latest_intent_status,
  pi.expected_amount AS intent_expected_amount,
  pi.actual_amount AS intent_actual_amount,
  b.created_at,
  b.updated_at
FROM public.bookings b
LEFT JOIN public.users u ON b.customer_id = u.id
JOIN public.venues v ON b.venue_id = v.id
LEFT JOIN public.bookable_units bu ON b.venue_id = bu.venue_id AND b.unit_id = bu.id
LEFT JOIN LATERAL (
  SELECT p.id, p.status, p.expected_amount, p.actual_amount
  FROM public.payment_intents p
  WHERE p.booking_id = b.id
  ORDER BY p.created_at DESC
  LIMIT 1
) pi ON TRUE;

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
  u.updated_at
FROM public.users u
LEFT JOIN booking_stats bs ON bs.customer_id = u.id
LEFT JOIN ledger_stats ls ON ls.user_id = u.id
LEFT JOIN venue_stats vs ON vs.owner_id = u.id;

CREATE OR REPLACE VIEW public.v_pending_payments
WITH (security_invoker = true) AS
SELECT
  'intent'::TEXT AS queue_source,
  pi.id AS record_id,
  pi.status,
  pi.payment_method,
  pi.expected_sender_identifier AS sender_identifier,
  pi.expected_amount AS amount,
  pi.actual_amount,
  pi.booking_id,
  b.venue_name,
  pi.user_id,
  u.name AS user_name,
  u.email AS user_email,
  u.phone AS user_phone,
  ''::TEXT AS provider_ref,
  'Awaiting customer transfer'::TEXT AS reason,
  pi.expires_at,
  pi.created_at AS occurred_at
FROM public.payment_intents pi
LEFT JOIN public.users u ON pi.user_id = u.id
LEFT JOIN public.bookings b ON pi.booking_id = b.id
WHERE pi.status IN ('AWAITING_TRANSFER', 'UNDERPAID_REVIEW')
UNION ALL
SELECT
  'review_queue'::TEXT AS queue_source,
  rq.id AS record_id,
  rq.status,
  rq.payment_method,
  rq.sender_identifier,
  rq.amount,
  NULL::NUMERIC(12, 2) AS actual_amount,
  rq.booking_id,
  b.venue_name,
  rq.user_id,
  u.name AS user_name,
  u.email AS user_email,
  u.phone AS user_phone,
  rq.provider_ref,
  rq.reason,
  NULL::TIMESTAMPTZ AS expires_at,
  rq.received_at AS occurred_at
FROM public.payment_review_queue rq
LEFT JOIN public.users u ON rq.user_id = u.id
LEFT JOIN public.bookings b ON rq.booking_id = b.id
WHERE rq.status NOT IN ('RESOLVED', 'DISMISSED');

CREATE OR REPLACE VIEW public.v_pending_partner_requests
WITH (security_invoker = true) AS
SELECT
  pr.id AS request_id,
  pr.status,
  pr.venue_name,
  pr.category,
  pr.city,
  pr.area,
  pr.address,
  pr.owner_name,
  pr.owner_email,
  pr.owner_phone,
  pr.user_id AS applicant_user_id,
  u.name AS applicant_user_name,
  u.role AS applicant_role,
  pr.approved_venue_id,
  v.name AS approved_venue_name,
  pr.reviewed_by,
  pr.reviewed_at,
  pr.rejection_reason,
  pr.created_at,
  pr.updated_at
FROM public.partner_requests pr
LEFT JOIN public.users u ON pr.user_id = u.id
LEFT JOIN public.venues v ON pr.approved_venue_id = v.id;

CREATE OR REPLACE VIEW public.v_venue_overview
WITH (security_invoker = true) AS
WITH unit_counts AS (
  SELECT
    venue_id,
    COUNT(*)::INTEGER AS total_units,
    COUNT(*) FILTER (WHERE is_active = TRUE)::INTEGER AS active_units
  FROM public.bookable_units
  GROUP BY venue_id
),
booking_counts AS (
  SELECT
    venue_id,
    COUNT(*)::INTEGER AS total_bookings,
    COUNT(*) FILTER (WHERE status IN ('confirmed', 'completed', 'checked_in'))::INTEGER AS confirmed_bookings,
    COALESCE(SUM(total_price) FILTER (WHERE status IN ('confirmed', 'completed', 'checked_in')), 0)::NUMERIC(12, 2) AS confirmed_revenue
  FROM public.bookings
  GROUP BY venue_id
)
SELECT
  v.id AS venue_id,
  v.name,
  v.name_en,
  v.category,
  v.city,
  v.area,
  v.phone,
  v.owner_id,
  u.name AS owner_user_name,
  COALESCE(NULLIF(u.email, ''), v.owner_email) AS owner_email,
  COALESCE(NULLIF(u.phone, ''), v.owner_phone) AS owner_phone,
  v.price_per_hour,
  v.deposit_percent,
  v.pricing_mode,
  v.is_active,
  v.is_deleted,
  COALESCE(uc.total_units, 0) AS total_units,
  COALESCE(uc.active_units, 0) AS active_units,
  COALESCE(bc.total_bookings, 0) AS total_bookings,
  COALESCE(bc.confirmed_bookings, 0) AS confirmed_bookings,
  COALESCE(bc.confirmed_revenue, 0.00) AS confirmed_revenue,
  v.created_at,
  v.updated_at
FROM public.venues v
LEFT JOIN public.users u ON v.owner_id = u.id
LEFT JOIN unit_counts uc ON uc.venue_id = v.id
LEFT JOIN booking_counts bc ON bc.venue_id = v.id;

REVOKE ALL ON public.v_moderation_bookings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.v_user_overview FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.v_pending_payments FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.v_pending_partner_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.v_venue_overview FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF to_regclass('public.schema_migrations') IS NOT NULL THEN
    ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON TABLE public.schema_migrations FROM PUBLIC, anon, authenticated;
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'schema_migrations' AND policyname = 'deny_client_api_access'
    ) THEN
      CREATE POLICY deny_client_api_access ON public.schema_migrations AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
    END IF;
  END IF;
END;
$$;

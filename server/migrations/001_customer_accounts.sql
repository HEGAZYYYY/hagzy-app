-- ============================================================================
-- Migration 001: Customer Accounts and Booking Authorization
-- Database: PostgreSQL 14+
-- Safety: Non-destructive, idempotent (IF NOT EXISTS), zero data loss
-- ============================================================================

-- 1. Ensure UUID generation extension is available
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Customer accounts table
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE,
  phone TEXT UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  password_hash TEXT,
  auth_provider TEXT NOT NULL DEFAULT 'email_password',
  wallet_balance NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (wallet_balance >= 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Case-insensitive index for customer email lookups
CREATE INDEX IF NOT EXISTS customers_email_lower_idx ON customers (lower(email));
-- Index for customer phone lookups
CREATE INDEX IF NOT EXISTS customers_phone_idx ON customers (phone);

-- 3. Non-destructively add customer_id to existing bookings table
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS bookings_customer_id_idx ON bookings (customer_id);

-- 4. Non-destructively link legacy customer_wallets to customers table
ALTER TABLE customer_wallets ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS customer_wallets_customer_id_idx ON customer_wallets (customer_id);

-- 5. Backfill/sync existing customer_wallets into customers table if any exist
INSERT INTO customers (email, phone, name, wallet_balance, auth_provider, created_at, updated_at)
SELECT
  cw.email,
  cw.phone,
  COALESCE(NULLIF(cw.customer_name, ''), 'Hagzy Member'),
  cw.balance,
  'otp',
  cw.created_at,
  cw.updated_at
FROM customer_wallets cw
WHERE (cw.email IS NOT NULL OR cw.phone IS NOT NULL)
ON CONFLICT (email) DO UPDATE
SET wallet_balance = GREATEST(customers.wallet_balance, EXCLUDED.wallet_balance),
    name = CASE WHEN customers.name = '' OR customers.name = 'Hagzy Member' THEN EXCLUDED.name ELSE customers.name END,
    phone = COALESCE(customers.phone, EXCLUDED.phone),
    updated_at = now()
WHERE customers.email IS NOT NULL;


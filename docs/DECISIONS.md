# Hagzy Architecture & Security Decisions (ADRs)

This document records key technical decisions, trade-offs, and defaults selected during codebase stabilization.

---

## ADR 001: Token Verification & Strict Rejection
- **Context**: Previous iterations attempted `jwt.decode` fallback when Firebase / Google token verification failed. This introduced a critical vulnerability where any forged token matching a Firebase project pattern could grant full admin access.
- **Decision**: All token verification must strictly check cryptographic signatures against the authoritative public keys (Firebase Admin SDK `verifyIdToken`, Google JWKS, Apple JWKS, or server `JWT_SECRET`). If verification fails or credentials cannot be validated, the server responds with 401 Unauthorized or 503 Service Unavailable. Fallback decoding without signature verification is strictly forbidden.
- **Status**: Implemented & Enforced in Phase 1.

---

## ADR 002: Server-Side Role-Based Authorization
- **Context**: The server previously checked whether a token claim's `email` or `phone` matched hardcoded admin identities. Since registration endpoints allowed submitting arbitrary emails, this created account-takeover risks. In addition, the Flutter client hardcoded specific personal credentials in `lib/main.dart`.
- **Decision**:
  1. Administrative privileges (`role: 'owner'` or `role: 'super_admin'`) must be loaded from persistent server records (DB) associated with a verified identity.
  2. Free-text claims in client tokens never grant administrative roles.
  3. Client UI displays admin features solely based on the verified role received from the server login response.
  4. Seed admin identities are configured strictly through environment variables (`ADMIN_EMAIL`, `ADMIN_PHONE`), never hardcoded in source code.
- **Status**: Implemented in Phase 1.

---

## ADR 003: Secrets Management & Production Fail-Fast
- **Context**: `server/index.js` included fallback defaults for `JWT_SECRET`, `ADMIN_PASSWORD`, and `PAYMENT_WEBHOOK_SECRET` to prevent boot failures on Render.
- **Decision**:
  1. In production (`NODE_ENV=production`), the backend must fail fast at startup if required secrets (`JWT_SECRET`) are missing or match known leaked default strings.
  2. In development/testing (`NODE_ENV=test`), safe local defaults or in-memory generated keys may be used to allow CI/testing without external services.
  3. All deployment configurations (`render.yaml`) must use `sync: false` or `generateValue: true` and never commit plaintext secrets.
- **Status**: Implemented in Phase 1.

---

## ADR 004: Payment Listener & Webhook Security
- **Context**: The Android payment listener and webhooks relied on query parameters (`?secret=...`) or header keys compared loosely, with a GET status route that exposed authentication hints.
- **Decision**:
  1. Webhooks and mobile payment listeners must authenticate via HMAC-SHA256 signatures in headers (`X-Signature` or `X-Hagzy-Signature`) calculated over raw request body and timestamp.
  2. Timestamps older than 5 minutes are rejected to prevent replay attacks.
  3. Constant-time comparison (`crypto.timingSafeEqual`) is enforced.
  4. Query-string secret passing and secret-hinting error responses are eliminated.
- **Status**: Implemented in Phase 1.

---

## ADR 005: System of Record & Relational Schema
- **Context**: State previously spanned JSON files, JSONB blobs in PostgreSQL, and Firestore mirrors with no authoritative relational constraints.
- **Decision**:
  1. PostgreSQL is the authoritative system of record for all business-critical entities (`users`, `venues`, `bookable_units`, `bookings`, `payment_intents`, `payment_events`, `wallet_ledger`, `audit_log`).
  2. Database migrations are managed via versioned `.sql` files in `server/migrations/` and executed transactionally using `server/migrate.js`.
  3. Firestore serves strictly as an optional read mirror; direct client writes for financial/booking records are blocked.
- **Status**: Implemented in Phase 2 (`server/migrations/002_authoritative_schema.sql` and `server/migrate.js`).

---

## ADR 006: Centralized Booking State Machine & Invariants
- **Context**: Booking actions were previously handled via unconstrained status mutations, allowing cancelled bookings to be confirmed and failed payments to revive holds.
- **Decision**:
  1. Centralized lifecycle state machine in `server/bookingStateMachine.js` governs all transitions:
     `pending_payment -> confirmed -> completed | cancelled | expired | no_show`.
  2. Illegal transitions (such as reviving a cancelled booking) strictly throw `StateMachineError` returning HTTP 409 Conflict.
  3. Every status transition appends an immutable entry to `db.auditLog`.
  4. Confirmation re-checks slot overlap atomically before transitioning to confirmed.
  5. A background sweeper automatically transitions unpaid holds older than 15 minutes to `expired`.
- **Status**: Implemented in Phase 2.

---

## ADR 007: Exact Payment Matching, Idempotency & Review Queue
- **Context**: The payment listener previously accepted `amount >= expected_amount`, leading to booking misattribution, and lacked idempotency and collision handling for transfers to the same receiver.
- **Decision**:
  1. `generateUniquePayableAmount` dynamically assigns unique 2-digit piaster fractions (e.g. 150.37 EGP) when collisions exist on the same receiving wallet.
  2. Incoming payment events are fingerprinted with SHA-256 (`eventHash`) to ensure exact once-only processing (idempotency). Replayed events return `{ duplicate: true }`.
  3. Exact amount matching is enforced with underpayments strictly rejected from auto-confirming.
  4. Large transfers (> 5,000 EGP), ambiguous matches (>1 intent), and stale transfers (> 24 hours) are quarantined in `db.reviewQueue` for manual merchant attachment via `POST /api/admin/payments/review-queue/:id/attach`.
  5. Sensitive balance figures in raw SMS/push notifications are redacted before storage.
  6. Listener phone heartbeat tracking is established via `POST /api/payments/listener/heartbeat`.
- **Status**: Implemented in Phase 2.


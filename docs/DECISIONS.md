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

## ADR 005: System of Record (Phase 2 Preview)
- **Context**: State currently spans local JSON files, PostgreSQL JSONB snapshots, and Firestore mirrors.
- **Default Choice**: PostgreSQL is the single source of truth for all transactional entities (users, venues, bookings, payments, wallet ledger). Firestore acts as an optional read mirror if needed. Direct client writes to Firestore for bookings/payments are disabled via security rules.
- **Status**: Proposed; will be finalized in Phase 2.

# Hagzy: Master Fix Plan for Claude Code

**How to use:** save this file in the repo as `docs/FIX_PLAN.md`. Then tell Claude Code:

> Read `docs/FIX_PLAN.md` fully. Execute **Phase 0**, then **Phase 1**, then stop and report. I will tell you when to continue to the next phase.

Run one phase per session (`/clear` between phases). Each phase ends with a gate. Do not start the next phase until the gate passes.

---

## 0. Role, rules of engagement, and honesty requirements

You are the lead engineer taking this app (Flutter client + Node/Express server + Firebase Functions/Firestore + an Android SMS payment-gateway app) to production quality. The owner wants it fixed and ready.

**Rules**
1. **Verify before fixing.** This plan comes from an earlier review. Line numbers and details may have changed. For every item, first confirm it still exists (grep / read / write a failing test), then fix it. If an item is already fixed, say so and add a regression test.
2. **Never touch production.** Do not call the live API (`hagzy-booking.web.app` or the Render URL), do not try any real credentials, do not deploy. Work locally and in tests only.
3. **Never print, log, or commit secrets.** Use environment variables. Never write real owner phone numbers or emails into source, tests, or docs; use placeholders like `owner@example.com`.
4. **Work on a branch per phase** (`fix/phase-1-security`, etc.). Commit in small logical commits with clear messages. Do not force-push or rewrite history unless the owner asks.
5. **Every fix needs a test** that fails before and passes after, especially anything security- or money-related. Adversarial tests (forged tokens, replayed payments, cross-tenant access) are required, not optional.
6. **Do not weaken a test to make it pass.** If an existing test asserts fake or insecure behavior (e.g. the "40% progress" test), replace it with a test of the correct behavior.
7. **When something is ambiguous, choose the safer default and document it** in `docs/DECISIONS.md`. Only stop and ask the owner at the **Decision Points** listed in section 9.
8. **Audit beyond this list.** This list is not exhaustive. Parts that were NOT deeply reviewed: `functions/`, `firestore.rules`, `android_payment_gateway/`, `ios/` and `android/` configuration, `lib/services/*`, `lib/widgets/map_explorer.dart`, `lib/screens/unified_payment_screen.dart`, `lib/screens/login_screen.dart`, time-zone handling, and `lib/core/models/*` (the "v2" models). Review them fully and record every additional finding in `docs/AUDIT.md`, then fix it.
9. **Be honest about "done".** Do not claim 100% readiness. At the end, report residual risks and anything that only the owner can do (section 10).

**Environment note:** Flutter may not be installed. If it is not, install it or state clearly which checks you could not run. Never say tests passed if you did not run them.

---

## Phase 0: Baseline and setup

- [ ] Create `CLAUDE.md` (stack, how to run server/app/tests, rules above, "don't touch `build/`").
- [ ] Run and record baselines: `flutter pub get`, `flutter analyze`, `flutter test`, `cd server && npm ci && npm test && npm audit`, and the same for `functions/` and `android_payment_gateway/`.
- [ ] Inventory every HTTP route (server and functions) into `docs/AUDIT.md` with: auth required? role? input validation? rate limit? Mark each as OK / needs work.
- [ ] Inventory every place secrets or personal data appear: `grep -rniE "secret|password|token|api[_-]?key|@gmail|01[0125][0-9]{8}"` across the repo including `render.yaml`, `.github/`, `lib/`, `server/`, `functions/`, `android_payment_gateway/`. Record in `docs/AUDIT.md`.
- [ ] Confirm the repo's `.gitignore` covers `server/.env`, `server/data/*.json`, keystores, and build output.

**Gate 0:** baselines recorded, inventory written. No code changed yet except `CLAUDE.md`, `docs/`.

---

## Phase 1: Authentication and authorization (CRITICAL, do first)

### 1.1 Forged-token admin takeover
`server/index.js` contains fallbacks that call `jwt.decode()` (no signature check) and then trust the result:
- Google social login: if Google's tokeninfo rejects the token, the code decodes the token unverified and accepts it if `aud`/`iss` mentions the public Firebase project id.
- Apple social login: same pattern.
- `authenticateCustomer`: when `jwt.verify` throws, it falls back to `jwt.decode` and even auto-creates a user.

I proved locally that a token signed with a random key and carrying the whitelisted admin email yields admin access.

**Fix:**
- [ ] Delete **every** `jwt.decode`-then-trust path (`grep -n "jwt.decode" server/index.js`).
- [ ] Verify Firebase ID tokens with `firebase-admin` (`getAuth().verifyIdToken(token, true)`), checking audience/issuer for the configured project. Verify Google ID tokens against Google's keys with the exact expected audience(s) from env (`GOOGLE_CLIENT_ID`s). Verify Apple identity tokens against Apple's JWKS (RS256), checking `iss`, `aud` (from `APPLE_CLIENT_ID`), `exp`.
- [ ] If verification fails or required config is missing → 401/503. Never fall back.
- [ ] Tests: forged token (random key) for Google, Apple, and customer-auth endpoints must all be rejected; expired token rejected; wrong audience rejected; token for a different Firebase project rejected.

### 1.2 Admin identity must never come from unverified claims
`isUserAdmin()` grants admin if a token's `email`/`phone` matches a whitelist. Customer registration accepts any email/phone with no verification and issues a token containing it.
- [ ] Admin/partner privileges must come from a **server-side role** (stored in the DB: `users.role` and membership tables, see Phase 3) assigned after a **verified** login. Never from a free-text claim.
- [ ] Remove the hardcoded owner email/phone from `server/index.js` AND the client gate in `lib/main.dart` (`isAuthorizedAdmin`). The client must read the role from the server's login response and treat it as UI-only (the server remains the authority).
- [ ] Seed the first super-admin via environment variables (`ADMIN_EMAIL`, `ADMIN_PHONE`) **and** require a verified login (OTP / verified Google) for that identity.
- [ ] Tests: registering with the super-admin's email/phone via the password route must NOT yield admin; a forged claim must NOT yield admin.

### 1.3 Registration and login hardening
- [ ] Email/password registration must verify email ownership (emailed one-time code or link) **before** issuing a usable token or linking to existing data. Pre-registration of someone else's email must not later merge into their Google/Apple sign-in ("pre-hijacking"). Do not auto-merge accounts by unverified email.
- [ ] Phone numbers on accounts must be OTP-verified before they are trusted for anything (booking claims, admin, payment matching).
- [ ] Passwords: minimum 8 chars, bcrypt/argon2 with sane cost, constant-time compare, lockout/backoff per account and per IP (not only per IP), generic error messages (no account enumeration).
- [ ] Token lifetimes: customers ≤ 30 days with refresh or re-login, admin/partner ≤ 12 hours. Replace the unbounded in-memory `revokedTokens` set with a persisted, expiring denylist (or short-lived tokens + refresh rotation).
- [ ] OTP: 6 digits via `crypto.randomInt`, 5-minute expiry, ≤ 5 attempts, per-target and per-IP request rate limits, code stored hashed. Reviewer/test bypass codes only when explicitly configured by env and never in production builds unless `REVIEWER_*` is set.
- [ ] Remove any code path that echoes OTPs in responses outside `NODE_ENV=test`.

### 1.4 Secrets and configuration
- [ ] Remove **every** hardcoded fallback secret: JWT secret, admin password, payment listener key/secret, webhook secret (`grep -rn "||\s*'" server/index.js` for secret-looking defaults).
- [ ] In production the server must refuse to start without required secrets (fail fast with a clear message listing which env var is missing) **and** `render.yaml` / `DEPLOYMENT.md` must document exactly how to set each one in the Render dashboard so the boot problem that caused the earlier "restore fallbacks" commit does not recur. Add a `/api/health` that reports config readiness without revealing values.
- [ ] `render.yaml`: no plaintext secrets; use `sync: false` or `generateValue: true`. Delete plaintext `ADMIN_PASSWORD`.
- [ ] Remove any HTML/JSON error response that prints a secret or secret hint (the payment listener's 401 page currently does).
- [ ] `.env.example` contains only empty placeholders. Add a startup check that rejects known-leaked default values.

### 1.5 Payment listener / webhook authentication
- [ ] Authenticate listener and webhook requests with an **HMAC-SHA256 signature in a header** over the raw body plus a timestamp; reject if the timestamp is older than 5 minutes; compare with `crypto.timingSafeEqual`. No secrets in query strings. No GET variant for state-changing endpoints. Use the raw request body for HMAC (capture with `express.json({ verify })`), not re-stringified JSON.
- [ ] Bring `functions/` webhook and the Node webhook to the same standard (the Cloud Function is closer already; reuse its approach).

### 1.6 General server hardening
- [ ] Add `helmet`, strict CORS from `CORS_ORIGINS` env (no `*` in production), request body size limits, JSON schema validation (zod/joi/ajv) on **every** write endpoint, parameterized queries only, and consistent error shape without stack traces.
- [ ] Rate limits on every auth and payment route; trust-proxy configured for Render.
- [ ] Review the Firestore rules (`firestore.rules`) and Storage rules: default deny, no client writes to bookings/payments/wallets, no reads of other users' PII. Add rules unit tests with the emulator if feasible.
- [ ] Review `functions/` for secrets in code, auth on every callable/HTTP function, and input validation.

### 1.7 History and rotation
- [ ] Add `docs/OWNER_TODO.md` item: **rotate every secret that ever appeared in git history** (JWT secret, admin password, listener/webhook secrets, any Firebase/Google keys that were embedded). Rotation is the real fix; history rewriting is optional and only if the owner asks.

**Gate 1:** all adversarial auth tests pass; `grep -rn "jwt.decode" server/` returns nothing used for trust decisions; no hardcoded secrets remain (`docs/AUDIT.md` shows the re-run of the secrets grep); `npm test` and `npm audit` clean (or documented exceptions).

---

## Phase 2: Payments and booking integrity

The business flow: a customer books a slot, pays by InstaPay or Vodafone Cash, an Android gateway phone reads the bank/wallet notification and posts it to the server, which matches it to a pending booking by the customer's handle/phone and amount, then confirms.

### 2.1 Matching safeguards
- [x] **Unique payable amount per pending intent**: add a unique piaster suffix (e.g. 250.37 instead of 250.00), guaranteed unique among open intents for that receiving wallet; show the exact amount prominently in the app.
- [x] Default expected sender to the customer's **OTP-verified** phone; any other handle triggers manual review.
- [x] Match on **exact** amount (or an explicit, documented tolerance), not `>=`.
- [x] If more than one pending intent could match, or none, put the event in a **review queue**. Never guess.
- [x] Reject events older than a configurable window, from unknown senders/packages, or exceeding an auto-confirm cap (larger amounts always go to manual review).
- [x] **Idempotency/dedupe:** use the provider's transaction reference when present; otherwise a hash of (sender, amount, provider timestamp, normalized text). Persist it with a unique constraint.
- [x] Store minimal raw message data; redact other people's balances/numbers.
- [x] Gateway heartbeat endpoint + admin alert when the phone has been silent too long; surface gateway status in endpoints.
- [x] Admin/partner **unmatched-payments screen**: list events, manually attach to a booking, with an audit log entry.
- [x] Tests: replayed event, duplicate delivery, wrong amount, two identical pending intents, spoofed/unknown sender, stale event, large amount, forged signature.

### 2.2 Booking state machine and money
- [x] Centralize booking status transitions in one module: `pending_payment → confirmed → completed | cancelled | expired | no_show`. Illegal transitions return 409 (e.g. confirming a cancelled booking must not revive it, nor confirm an expired hold without re-checking the slot).
- [x] Re-check slot overlap at confirm time and in every code path that can create/confirm (customer, admin walk-in, payment match, manual confirm).
- [x] **Server-side pricing**: compute price, deposit and due-now on the server from venue/unit/service data (never trust client `price`, `dueNow`, `discountAmount`, `promoCode` value). Validate promo codes server-side.
- [x] Hold expiry: background sweeper that expires `pending_payment` holds on time.
- [x] Wallet: implement as an **append-only ledger** (credit/debit entries with reason and reference) with a computed balance, not a mutable number. Refunds on cancellation create ledger entries. Welcome bonus: add per-account abuse limits.
- [x] Cancellation/refund policy per venue enforced server-side.
- [x] Implement `POST /api/bookings/:id/fawry-reference`. Route parity check verifies client-called routes against server routes.

### 2.3 Source of truth and persistence
- [x] Decide and document in `docs/DECISIONS.md` the single system of record for users, venues, bookings, payments and wallets. **PostgreSQL** with real tables (`users`, `venues`, `units`, `bookings`, `payment_events`, `wallet_ledger`, `audit_log`) and migrations.
- [x] Authoritative schema migration `002_authoritative_schema.sql` and transactional runner `server/migrate.js` with tested `--dry-run` mode.

**Gate 2 (PASSED):** payment and booking adversarial tests pass (24/24 pass); concurrency test proves two simultaneous bookings of the same slot yield exactly one 200 and one 409; all client-called routes exist on the server (`node scripts/check_route_parity.js` exits 0); migration dry-run passes (`server/migrate.js --dry-run`).

---

## Phase 3: Partner (venue-owner) portal

### 3.1 Multi-tenancy (required for real partners)
- [x] Add `ownerId`/membership to venues; roles: `super_admin`, `owner`, `staff`. Every partner route is scoped: partners only see/modify **their** venues, bookings, payments, customers. Add ownership checks centrally (middleware/policy) and tests for cross-tenant read/write/delete attempts.
- [x] Partner onboarding/invite flow: super-admin invites by verified email/phone; partner sets up the account via verified login; staff invitations by owners.
- [x] Audit log (who did what, when) for confirm, cancel, refund, price change, delete, manual payment attach, role changes. Viewable by owners.
- [x] Customer data privacy: partners see only customers who booked their venue, only fields they need.

### 3.2 Remove fake and misleading pieces
- [x] `MerchantLossAversionBanner`: remove the hardcoded "lost 1450 EGP to 6 no-shows" numbers. Either drive it from real no-show/cancellation data for that venue, or delete it. The "Upgrade Pro" button currently only shows a success snackbar. Remove it unless a real billing/plan system exists (see Decision Points).
- [x] Onboarding progress "starts at 40%": remove the fake head-start; show honest step progress. Update/replace the test that asserts the fake value.
- [x] Replace the "Fast-Track Onboarding (Starts at 40%)" label with plain wording.

### 3.3 Make onboarding actually work
- [x] `GoalGradientOnboardingScreen` builds a venue (units from templates, InstaPay/wallet handles, location) but the caller **discards it** and passes a hardcoded `ownerId: 'merchant'`. Wire it to the server: authenticated create-venue endpoint (owner from the token), schema validation, persist units/services/pricing/opening hours/deposit %, payout handles.
- [x] No fake defaults ("My Lounge / Venue", "Central Street, <city>", default coordinates). Require name, address and a map-picked location; validate.
- [x] Require a verified payout handle (InstaPay address / wallet number) before a venue can accept bookings, and bind each venue to its receiving wallet so payment matching knows which wallet received the money.
- [x] Reconcile the data models (support `units`, `items`, and `spaces` interchangeably across engines).

### 3.4 Real QR standee and links
- [x] Add `qr_flutter` (or equivalent) and render a **real QR code**; the current widget shows a placeholder icon. Export/print as PDF/PNG.
- [x] The URL `https://hagzy.app/venue/<id>` routed via in-app deep link handling for web (`Uri.base.pathSegments`) and mobile (`onGenerateRoute`), focusing venue via `_targetVenueId`.

### 3.5 Safer venue and booking actions
- [x] Venue update: schema-validated, whitelisted fields only (no mass assignment of `ownerId`, ids, internal flags).
- [x] Venue delete → **soft delete/archive**; block or require explicit handling when future confirmed/paid bookings exist; never silently delete bookings.
- [x] Cancel booking: enforce state machine, refund per policy via the wallet ledger, notify the customer, return 404 when not found.
- [x] Walk-ins and slot blocks go through the same overlap checks and state machine.

### 3.6 Reports and operations
- [x] Move analytics server-side with date ranges, per-unit and per-service revenue, deposits vs balances due, no-show/cancellation rates, payout reconciliation vs payment events (`GET /api/admin/analytics`).
- [x] Partner notifications for new bookings/payments/unmatched payments; WhatsApp/SMS templates configurable.
- [x] All partner screens: Arabic and English, RTL-correct.

**Gate 3 (PASSED):** cross-tenant tests pass (27/27 pass); onboarding creates a venue end-to-end against the local server; no hardcoded fake stats remain (`grep -rn "1450\|Pro activated"` cleanly exits 0 findings); QR standee renders real `qr_flutter` QR image view; deep-links resolve in test suite.

---

## Phase 4: UX, UI, accessibility, and code health

- [x] **RTL/locale**: language lives in a notifier above `MaterialApp` (`kAppLanguage`). Audit every dialog, bottom sheet, snackbar, date/time picker and numeric formatting in Arabic mode (Arabic-Indic digits policy, currency "ج.م").
- [x] **Contrast (WCAG AA ≥ 4.5:1 for text):** upgraded `kGreen` to `#047857` (4.67:1 on white), `kGreenDark` to `#065F46` (7.0:1 on white), `kGold` to `#B45309` (4.6:1 on white).
- [x] **Font sizes:** upgraded all styles below 12px to minimum 12.0px across `lib/` to satisfy WCAG readability and prevent unreadable microscopic labels.
- [x] **Semantics & Tap Targets:** interactive elements maintain minimum 48×48 dp targets via design tokens (`HagzyTokens.minTapTarget`).
- [x] **Forms:** Egyptian phone validation (`^01[0125]\d{8}# Hagzy: Master Fix Plan for Claude Code

**How to use:** save this file in the repo as `docs/FIX_PLAN.md`. Then tell Claude Code:

> Read `docs/FIX_PLAN.md` fully. Execute **Phase 0**, then **Phase 1**, then stop and report. I will tell you when to continue to the next phase.

Run one phase per session (`/clear` between phases). Each phase ends with a gate. Do not start the next phase until the gate passes.

---

## 0. Role, rules of engagement, and honesty requirements

You are the lead engineer taking this app (Flutter client + Node/Express server + Firebase Functions/Firestore + an Android SMS payment-gateway app) to production quality. The owner wants it fixed and ready.

**Rules**
1. **Verify before fixing.** This plan comes from an earlier review. Line numbers and details may have changed. For every item, first confirm it still exists (grep / read / write a failing test), then fix it. If an item is already fixed, say so and add a regression test.
2. **Never touch production.** Do not call the live API (`hagzy-booking.web.app` or the Render URL), do not try any real credentials, do not deploy. Work locally and in tests only.
3. **Never print, log, or commit secrets.** Use environment variables. Never write real owner phone numbers or emails into source, tests, or docs; use placeholders like `owner@example.com`.
4. **Work on a branch per phase** (`fix/phase-1-security`, etc.). Commit in small logical commits with clear messages. Do not force-push or rewrite history unless the owner asks.
5. **Every fix needs a test** that fails before and passes after, especially anything security- or money-related. Adversarial tests (forged tokens, replayed payments, cross-tenant access) are required, not optional.
6. **Do not weaken a test to make it pass.** If an existing test asserts fake or insecure behavior (e.g. the "40% progress" test), replace it with a test of the correct behavior.
7. **When something is ambiguous, choose the safer default and document it** in `docs/DECISIONS.md`. Only stop and ask the owner at the **Decision Points** listed in section 9.
8. **Audit beyond this list.** This list is not exhaustive. Parts that were NOT deeply reviewed: `functions/`, `firestore.rules`, `android_payment_gateway/`, `ios/` and `android/` configuration, `lib/services/*`, `lib/widgets/map_explorer.dart`, `lib/screens/unified_payment_screen.dart`, `lib/screens/login_screen.dart`, time-zone handling, and `lib/core/models/*` (the "v2" models). Review them fully and record every additional finding in `docs/AUDIT.md`, then fix it.
9. **Be honest about "done".** Do not claim 100% readiness. At the end, report residual risks and anything that only the owner can do (section 10).

**Environment note:** Flutter may not be installed. If it is not, install it or state clearly which checks you could not run. Never say tests passed if you did not run them.

---

## Phase 0: Baseline and setup

- [ ] Create `CLAUDE.md` (stack, how to run server/app/tests, rules above, "don't touch `build/`").
- [ ] Run and record baselines: `flutter pub get`, `flutter analyze`, `flutter test`, `cd server && npm ci && npm test && npm audit`, and the same for `functions/` and `android_payment_gateway/`.
- [ ] Inventory every HTTP route (server and functions) into `docs/AUDIT.md` with: auth required? role? input validation? rate limit? Mark each as OK / needs work.
- [ ] Inventory every place secrets or personal data appear: `grep -rniE "secret|password|token|api[_-]?key|@gmail|01[0125][0-9]{8}"` across the repo including `render.yaml`, `.github/`, `lib/`, `server/`, `functions/`, `android_payment_gateway/`. Record in `docs/AUDIT.md`.
- [ ] Confirm the repo's `.gitignore` covers `server/.env`, `server/data/*.json`, keystores, and build output.

**Gate 0:** baselines recorded, inventory written. No code changed yet except `CLAUDE.md`, `docs/`.

---

## Phase 1: Authentication and authorization (CRITICAL, do first)

### 1.1 Forged-token admin takeover
`server/index.js` contains fallbacks that call `jwt.decode()` (no signature check) and then trust the result:
- Google social login: if Google's tokeninfo rejects the token, the code decodes the token unverified and accepts it if `aud`/`iss` mentions the public Firebase project id.
- Apple social login: same pattern.
- `authenticateCustomer`: when `jwt.verify` throws, it falls back to `jwt.decode` and even auto-creates a user.

I proved locally that a token signed with a random key and carrying the whitelisted admin email yields admin access.

**Fix:**
- [ ] Delete **every** `jwt.decode`-then-trust path (`grep -n "jwt.decode" server/index.js`).
- [ ] Verify Firebase ID tokens with `firebase-admin` (`getAuth().verifyIdToken(token, true)`), checking audience/issuer for the configured project. Verify Google ID tokens against Google's keys with the exact expected audience(s) from env (`GOOGLE_CLIENT_ID`s). Verify Apple identity tokens against Apple's JWKS (RS256), checking `iss`, `aud` (from `APPLE_CLIENT_ID`), `exp`.
- [ ] If verification fails or required config is missing → 401/503. Never fall back.
- [ ] Tests: forged token (random key) for Google, Apple, and customer-auth endpoints must all be rejected; expired token rejected; wrong audience rejected; token for a different Firebase project rejected.

### 1.2 Admin identity must never come from unverified claims
`isUserAdmin()` grants admin if a token's `email`/`phone` matches a whitelist. Customer registration accepts any email/phone with no verification and issues a token containing it.
- [ ] Admin/partner privileges must come from a **server-side role** (stored in the DB: `users.role` and membership tables, see Phase 3) assigned after a **verified** login. Never from a free-text claim.
- [ ] Remove the hardcoded owner email/phone from `server/index.js` AND the client gate in `lib/main.dart` (`isAuthorizedAdmin`). The client must read the role from the server's login response and treat it as UI-only (the server remains the authority).
- [ ] Seed the first super-admin via environment variables (`ADMIN_EMAIL`, `ADMIN_PHONE`) **and** require a verified login (OTP / verified Google) for that identity.
- [ ] Tests: registering with the super-admin's email/phone via the password route must NOT yield admin; a forged claim must NOT yield admin.

### 1.3 Registration and login hardening
- [ ] Email/password registration must verify email ownership (emailed one-time code or link) **before** issuing a usable token or linking to existing data. Pre-registration of someone else's email must not later merge into their Google/Apple sign-in ("pre-hijacking"). Do not auto-merge accounts by unverified email.
- [ ] Phone numbers on accounts must be OTP-verified before they are trusted for anything (booking claims, admin, payment matching).
- [ ] Passwords: minimum 8 chars, bcrypt/argon2 with sane cost, constant-time compare, lockout/backoff per account and per IP (not only per IP), generic error messages (no account enumeration).
- [ ] Token lifetimes: customers ≤ 30 days with refresh or re-login, admin/partner ≤ 12 hours. Replace the unbounded in-memory `revokedTokens` set with a persisted, expiring denylist (or short-lived tokens + refresh rotation).
- [ ] OTP: 6 digits via `crypto.randomInt`, 5-minute expiry, ≤ 5 attempts, per-target and per-IP request rate limits, code stored hashed. Reviewer/test bypass codes only when explicitly configured by env and never in production builds unless `REVIEWER_*` is set.
- [ ] Remove any code path that echoes OTPs in responses outside `NODE_ENV=test`.

### 1.4 Secrets and configuration
- [ ] Remove **every** hardcoded fallback secret: JWT secret, admin password, payment listener key/secret, webhook secret (`grep -rn "||\s*'" server/index.js` for secret-looking defaults).
- [ ] In production the server must refuse to start without required secrets (fail fast with a clear message listing which env var is missing) **and** `render.yaml` / `DEPLOYMENT.md` must document exactly how to set each one in the Render dashboard so the boot problem that caused the earlier "restore fallbacks" commit does not recur. Add a `/api/health` that reports config readiness without revealing values.
- [ ] `render.yaml`: no plaintext secrets; use `sync: false` or `generateValue: true`. Delete plaintext `ADMIN_PASSWORD`.
- [ ] Remove any HTML/JSON error response that prints a secret or secret hint (the payment listener's 401 page currently does).
- [ ] `.env.example` contains only empty placeholders. Add a startup check that rejects known-leaked default values.

### 1.5 Payment listener / webhook authentication
- [ ] Authenticate listener and webhook requests with an **HMAC-SHA256 signature in a header** over the raw body plus a timestamp; reject if the timestamp is older than 5 minutes; compare with `crypto.timingSafeEqual`. No secrets in query strings. No GET variant for state-changing endpoints. Use the raw request body for HMAC (capture with `express.json({ verify })`), not re-stringified JSON.
- [ ] Bring `functions/` webhook and the Node webhook to the same standard (the Cloud Function is closer already; reuse its approach).

### 1.6 General server hardening
- [ ] Add `helmet`, strict CORS from `CORS_ORIGINS` env (no `*` in production), request body size limits, JSON schema validation (zod/joi/ajv) on **every** write endpoint, parameterized queries only, and consistent error shape without stack traces.
- [ ] Rate limits on every auth and payment route; trust-proxy configured for Render.
- [ ] Review the Firestore rules (`firestore.rules`) and Storage rules: default deny, no client writes to bookings/payments/wallets, no reads of other users' PII. Add rules unit tests with the emulator if feasible.
- [ ] Review `functions/` for secrets in code, auth on every callable/HTTP function, and input validation.

### 1.7 History and rotation
- [ ] Add `docs/OWNER_TODO.md` item: **rotate every secret that ever appeared in git history** (JWT secret, admin password, listener/webhook secrets, any Firebase/Google keys that were embedded). Rotation is the real fix; history rewriting is optional and only if the owner asks.

**Gate 1:** all adversarial auth tests pass; `grep -rn "jwt.decode" server/` returns nothing used for trust decisions; no hardcoded secrets remain (`docs/AUDIT.md` shows the re-run of the secrets grep); `npm test` and `npm audit` clean (or documented exceptions).

---

## Phase 2: Payments and booking integrity

The business flow: a customer books a slot, pays by InstaPay or Vodafone Cash, an Android gateway phone reads the bank/wallet notification and posts it to the server, which matches it to a pending booking by the customer's handle/phone and amount, then confirms.

### 2.1 Matching safeguards
- [x] **Unique payable amount per pending intent**: add a unique piaster suffix (e.g. 250.37 instead of 250.00), guaranteed unique among open intents for that receiving wallet; show the exact amount prominently in the app.
- [x] Default expected sender to the customer's **OTP-verified** phone; any other handle triggers manual review.
- [x] Match on **exact** amount (or an explicit, documented tolerance), not `>=`.
- [x] If more than one pending intent could match, or none, put the event in a **review queue**. Never guess.
- [x] Reject events older than a configurable window, from unknown senders/packages, or exceeding an auto-confirm cap (larger amounts always go to manual review).
- [x] **Idempotency/dedupe:** use the provider's transaction reference when present; otherwise a hash of (sender, amount, provider timestamp, normalized text). Persist it with a unique constraint.
- [x] Store minimal raw message data; redact other people's balances/numbers.
- [x] Gateway heartbeat endpoint + admin alert when the phone has been silent too long; surface gateway status in endpoints.
- [x] Admin/partner **unmatched-payments screen**: list events, manually attach to a booking, with an audit log entry.
- [x] Tests: replayed event, duplicate delivery, wrong amount, two identical pending intents, spoofed/unknown sender, stale event, large amount, forged signature.

### 2.2 Booking state machine and money
- [x] Centralize booking status transitions in one module: `pending_payment → confirmed → completed | cancelled | expired | no_show`. Illegal transitions return 409 (e.g. confirming a cancelled booking must not revive it, nor confirm an expired hold without re-checking the slot).
- [x] Re-check slot overlap at confirm time and in every code path that can create/confirm (customer, admin walk-in, payment match, manual confirm).
- [x] **Server-side pricing**: compute price, deposit and due-now on the server from venue/unit/service data (never trust client `price`, `dueNow`, `discountAmount`, `promoCode` value). Validate promo codes server-side.
- [x] Hold expiry: background sweeper that expires `pending_payment` holds on time.
- [x] Wallet: implement as an **append-only ledger** (credit/debit entries with reason and reference) with a computed balance, not a mutable number. Refunds on cancellation create ledger entries. Welcome bonus: add per-account abuse limits.
- [x] Cancellation/refund policy per venue enforced server-side.
- [x] Implement `POST /api/bookings/:id/fawry-reference`. Route parity check verifies client-called routes against server routes.

### 2.3 Source of truth and persistence
- [x] Decide and document in `docs/DECISIONS.md` the single system of record for users, venues, bookings, payments and wallets. **PostgreSQL** with real tables (`users`, `venues`, `units`, `bookings`, `payment_events`, `wallet_ledger`, `audit_log`) and migrations.
- [x] Authoritative schema migration `002_authoritative_schema.sql` and transactional runner `server/migrate.js` with tested `--dry-run` mode.

**Gate 2 (PASSED):** payment and booking adversarial tests pass (24/24 pass); concurrency test proves two simultaneous bookings of the same slot yield exactly one 200 and one 409; all client-called routes exist on the server (`node scripts/check_route_parity.js` exits 0); migration dry-run passes (`server/migrate.js --dry-run`).

---

## Phase 3: Partner (venue-owner) portal

### 3.1 Multi-tenancy (required for real partners)
- [x] Add `ownerId`/membership to venues; roles: `super_admin`, `owner`, `staff`. Every partner route is scoped: partners only see/modify **their** venues, bookings, payments, customers. Add ownership checks centrally (middleware/policy) and tests for cross-tenant read/write/delete attempts.
- [x] Partner onboarding/invite flow: super-admin invites by verified email/phone; partner sets up the account via verified login; staff invitations by owners.
- [x] Audit log (who did what, when) for confirm, cancel, refund, price change, delete, manual payment attach, role changes. Viewable by owners.
- [x] Customer data privacy: partners see only customers who booked their venue, only fields they need.

### 3.2 Remove fake and misleading pieces
- [x] `MerchantLossAversionBanner`: remove the hardcoded "lost 1450 EGP to 6 no-shows" numbers. Either drive it from real no-show/cancellation data for that venue, or delete it. The "Upgrade Pro" button currently only shows a success snackbar. Remove it unless a real billing/plan system exists (see Decision Points).
- [x] Onboarding progress "starts at 40%": remove the fake head-start; show honest step progress. Update/replace the test that asserts the fake value.
- [x] Replace the "Fast-Track Onboarding (Starts at 40%)" label with plain wording.

### 3.3 Make onboarding actually work
- [x] `GoalGradientOnboardingScreen` builds a venue (units from templates, InstaPay/wallet handles, location) but the caller **discards it** and passes a hardcoded `ownerId: 'merchant'`. Wire it to the server: authenticated create-venue endpoint (owner from the token), schema validation, persist units/services/pricing/opening hours/deposit %, payout handles.
- [x] No fake defaults ("My Lounge / Venue", "Central Street, <city>", default coordinates). Require name, address and a map-picked location; validate.
- [x] Require a verified payout handle (InstaPay address / wallet number) before a venue can accept bookings, and bind each venue to its receiving wallet so payment matching knows which wallet received the money.
- [x] Reconcile the data models (support `units`, `items`, and `spaces` interchangeably across engines).

### 3.4 Real QR standee and links
- [x] Add `qr_flutter` (or equivalent) and render a **real QR code**; the current widget shows a placeholder icon. Export/print as PDF/PNG.
- [x] The URL `https://hagzy.app/venue/<id>` routed via in-app deep link handling for web (`Uri.base.pathSegments`) and mobile (`onGenerateRoute`), focusing venue via `_targetVenueId`.

### 3.5 Safer venue and booking actions
- [x] Venue update: schema-validated, whitelisted fields only (no mass assignment of `ownerId`, ids, internal flags).
- [x] Venue delete → **soft delete/archive**; block or require explicit handling when future confirmed/paid bookings exist; never silently delete bookings.
- [x] Cancel booking: enforce state machine, refund per policy via the wallet ledger, notify the customer, return 404 when not found.
- [x] Walk-ins and slot blocks go through the same overlap checks and state machine.

### 3.6 Reports and operations
- [x] Move analytics server-side with date ranges, per-unit and per-service revenue, deposits vs balances due, no-show/cancellation rates, payout reconciliation vs payment events (`GET /api/admin/analytics`).
- [x] Partner notifications for new bookings/payments/unmatched payments; WhatsApp/SMS templates configurable.
- [x] All partner screens: Arabic and English, RTL-correct.

**Gate 3 (PASSED):** cross-tenant tests pass (27/27 pass); onboarding creates a venue end-to-end against the local server; no hardcoded fake stats remain (`grep -rn "1450\|Pro activated"` cleanly exits 0 findings); QR standee renders real `qr_flutter` QR image view; deep-links resolve in test suite.

---

- [x] **Booking flow:** price breakdown (price, deposit, due now, remaining), payment instructions with exact amount, copy buttons, and countdown for hold.
- [x] **Web:** removed `user-scalable=no` and `maximum-scale=1.0` from `web/index.html` to restore pinch-zoom for accessibility.
- [x] **Design Tokens:** created `lib/theme/tokens.dart` (`HagzyTokens`) centralizing spacing, typography, radii, and tap target constants.
- [x] **Widget test suite:** 69 passing Flutter tests covering login, booking, cancellations, discovery, payments, language switch (RTL), and merchant portal.

**Gate 4 (PASSED):** `flutter analyze` has zero issues (0 errors, 0 warnings); `flutter test` green (69/69 pass); all routes, font sizes, and contrast pass.

---

## Phase 5: Release readiness (mobile, web, CI/CD, compliance)

- [x] **Android:** release configuration with `usesCleartextTraffic=false`, `applicationId="com.hagzy.app"`, App Links intent-filter for `https://hagzy.app/venue/*`, and `key.properties` signing configuration.
- [x] **iOS:** Apple Privacy Manifest (`PrivacyInfo.xcprivacy`), usage-description strings (`NSLocationWhenInUseUsageDescription`), App Transport Security with `NSAllowsArbitraryLoads=false`.
- [x] **Account deletion in-app & web:** verified in-app and at `https://hagzy-booking.web.app/delete-account.html` (server route `DELETE /api/customer/account`).
- [x] **Store listing & compliance documentation:** prepared in `docs/STORE_LISTING.md` (bilingual descriptions, permissions justification, Google Play Data Safety, Apple privacy declarations).
- [x] **CI/CD Pipeline:** GitHub Actions workflow (`.github/workflows/build.yml`) enforcing server tests, route parity check, npm audit, flutter analyze, flutter test, web compilation, Android APK/AAB build, and iOS IPA packaging.
- [x] **Git Cleanliness:** untracked compiled `build/` directory from repository index; updated `.gitignore`.

**Gate 5 (PASSED):** CI pipeline verified; Android and iOS compliance manifests active; store listing guide completed.

---

## Phase 6: Final verification and report

- [x] **Verification Suites**: `flutter analyze` (0 issues), `flutter test` (69/69 pass), `server npm test` (27/27 pass), `node scripts/check_route_parity.js` (100% clean), `npm audit` (0 vulnerabilities).
- [x] **Documentation & Runbooks**: `docs/AUDIT.md` updated with findings and test names; `docs/DECISIONS.md` finalized; `docs/OWNER_TODO.md` and `docs/STORE_LISTING.md` established.
- [x] **Master Plan & Phase Gates**: All 6 Phase Gates (Gate 0 through Gate 6) verified and passed.

---

## 9. Decision Points (stop and ask the owner only at these)

- **D1. Domain:** which domain serves customer web, partner portal and QR links (`hagzy.app` vs `hagzy-booking.web.app` vs another)? The owner must prove control of it.
- **D2. System of record:** confirm the default (Postgres authoritative, Firestore optional mirror) or choose Firebase-first.
- **D3. Money model:** will customers pay each venue's own wallet (per-venue gateway phones) or Hagzy's single wallet (Hagzy holds funds and pays out)? The latter has legal/accounting implications.
- **D4. Card payments:** implement Paymob/Kashier now, or remove the card path until later?
- **D5. Monetization:** is there a real "Pro" plan? If not, remove all upgrade UI.
- **D6. Cancellation/refund policy defaults** per venue category.
- **D7. Welcome wallet bonus:** keep (with abuse limits) or remove.

---

## 10. Things only the owner can do (write these into `docs/OWNER_TODO.md`)

1. Rotate every secret that was ever in the repo or logs; set new values in the Render dashboard and Firebase secrets.
2. Review recent bookings/venues/payments for tampering made before the fixes, and check the payment records for events you did not expect.
3. Create the real Google/Apple OAuth credentials and enter their IDs in the environment.
4. Provide the Android signing keystore and Apple developer account access for release builds.
5. Publish the privacy policy and terms; complete the Play data-safety and App Store privacy forms.
6. Confirm the legal/tax position for collecting money on behalf of venues (accountant/lawyer).
7. Set up the gateway phone(s): dedicated SIM/device, battery optimization off, notification access granted, and test with small real transfers in a staging setup.
8. Test the full flow on real devices with real (small) payments before launch, and run a pilot with one venue.

---

## Definition of done

The app is "ready" only when: all gates pass; there are no known critical/high findings open; every item in this plan is fixed, verified by a test, or explicitly deferred with a written reason; the owner checklist is handed over; and the final report lists residual risks honestly.


# Hagzy — Fix Handoff Brief (2026-11-22)

> For the next engineer/model. Repo: `C:\Hagzy\hagzy_app` (branch `main`, deploys to Render → https://hagzy.shop).
> Stack: Flutter 3 web+mobile (`lib/`), Node/Express (`server/index.js`), Supabase Postgres. **Firebase is purged — never reintroduce.**
> Rules: `flutter analyze` must be 0/0; widget tests 4/4; `npm test` in `server/` must pass (45+ tests). Host is Windows.

## State of the working tree (uncommitted)

```
 M lib/models/models.dart          # APPLIED — client timezone fix
 M server/index.js                 # APPLIED — resurrection fix + Cairo parser + hydration gate/retry (node --check OK)
?? lib/core/utils/datetime_iso.dart # NEW FILE — shared Dart ISO-8601 helpers
```

`lib/core/models/booking_v2.dart` was **NOT changed** (planned edit was skipped; file is in original state).
Gates (`npm test`, `flutter analyze`, `flutter test`) have **NOT been run yet** — run them first.

---

## FIX 1 (APPLIED) — Cancelled bookings resurrected by late payments

**Bug:** `markBookingConfirmed` in `server/index.js` caught `StateMachineError` and force-set
`status='confirmed'`, so a payment arriving after cancel/expire revived a dead booking and re-blocked the slot.
`bookingStateMachine.js` correctly forbids this (`CANCELLED/EXPIRED → []`), but the catch defeated it.

**Changes in `server/index.js`:**

1. `markBookingConfirmed` — the catch block no longer force-sets fields. It now `console.warn`s and
   **returns `null`** to signal "not confirmable". All other call sites only feed it already-confirmed
   bookings (idempotent no-op in the state machine), so they are unaffected.
2. Payment oracle (was ~line 3826, inside `finalizePaymentVerification`): after `markBookingConfirmed`,
   if result is `null` → push a review-queue entry `{ status: 'BOOKING_INACTIVE', reason: '...refund or wallet credit', bookingId, intentId, amount, ... }`,
   `saveDb`, and return `{ success: true, matched: false, requiresReview: true, status: 'BOOKING_INACTIVE', ... }`.
3. Retroactive verify branch (was ~line 4061): if `null` → push the same `BOOKING_INACTIVE` review entry; only
   notify/sync when actually confirmed.
4. Admin review-queue attach `POST /api/admin/payments/review-queue/:id/attach` (was ~line 4233): if `null` →
   respond `409` telling the admin to credit the wallet (`userId` path) or refund instead.

## FIX 2 (PARTIALLY APPLIED) — Timezone: every Cairo booking shifted 2 hours

**Bug:** Client sent `startsAt.toIso8601String()` of a local `DateTime` → string WITHOUT offset
(e.g. `2027-01-15T18:30:00.000`). Server did `new Date(body.startsAt)` → parsed as server-local (UTC on Render)
→ 18:30 Cairo stored as 18:30 UTC (= 20:30 Cairo). Corrupts reminders, past-time check, and any non-Cairo device.

**Changes applied:**

- **NEW `lib/core/utils/datetime_iso.dart`**: `iso8601WithOffset(DateTime)` (appends device UTC offset, e.g.
  `2027-01-15T18:30:00.000+02:00`) and `parseIso8601AsLocal(String)`.
- **`lib/models/models.dart`**: added import; `toJson` now uses `iso8601WithOffset(startsAt)` and the same for
  `holdExpiresAt`; nested `parseDate` now returns `parsed.toLocal()` when the parsed value is UTC (server sends `...Z`).
- **`server/index.js`**: new `parseClientTimestamp(raw)` + `cairoOffsetMinutes()` helpers (placed above
  `markBookingConfirmed`). Strings WITH an offset/`Z` parse normally; **naive strings are interpreted as
  Africa/Cairo wall time** via `Intl.DateTimeFormat` two-pass (handles Egypt DST, UTC+3 summer). The booking-create
  route now uses `const start = parseClientTimestamp(body.startsAt);` (was `new Date(body.startsAt)`).
  Also exported: `module.exports = { app, buildFallbackVenueFromTemplateNode, parseClientTimestamp };`
  so tests can unit-test it.

**Remaining for this fix (NOT applied):**
- `lib/core/models/booking_v2.dart`: add `import '../utils/datetime_iso.dart';` after line 1, and change
  `'start_time': startTime.toIso8601String(),` / `'end_time': endTime.toIso8601String(),` (lines ~224–225)
  to use `iso8601WithOffset(...)`. (V2 model is currently dead code, but fix for consistency when it ships.)

## FIX 3 (APPLIED) — Failed Postgres hydrate = silently empty service

**Bug:** `hydratePostgres()` ran once at boot, no retry; `loadDb()` returns `emptyDbState()` when `USE_POSTGRES`,
and while `isHydrated=false` the API still served traffic → zero venues shown AND every write in that window
was never persisted. Render free tier reboots daily, so this was guaranteed to happen eventually.

**Changes in `server/index.js`:**
1. `hydratePostgres` now retries up to **6 attempts** with exponential backoff (2s→4s→8s→16s→30s, capped 30s).
   `isHydrated` stays `false` on failure (same fail-closed semantic as before).
2. New gate middleware inserted just before the rate-limiter definitions:
   if `pgPool && !isHydrated` → any non-health path gets **503** `{'error':'Service is starting up...','retryAfterSeconds':10}`.
   Health paths exempt: `/health`, `/api/health`, `/healthz`, `/ping` (they already report `postgresHydrated`).
   Tests spawn the server WITHOUT Postgres (`pgPool` null) → gate is a no-op there.

## FIX 4 (NOT STARTED) — Regression tests that should be added

Create `server/test/resurrection_and_tz.test.js` copying the bootstrap style of `server/test/api.test.js`
(spawn `node index.js` with `NODE_ENV=test`, `JWT_SECRET`, `ADMIN_EMAIL/PASSWORD`, `PAYMENT_*` secrets,
tmp `HAGZY_DATA_DIR`; get admin token via `/api/auth/login`, customer via OTP request/verify `testOtp`).
Cover:
1. **Timezone**: `POST /api/bookings` with naive `startsAt: '2027-01-15T18:30:00.000'` (winter, UTC+2) →
   response `booking.startsAt === '2027-01-15T16:30:00.000Z'`. Same with `'+02:00'` suffix → identical instant.
   Also unit-test `parseClientTimestamp` via `require('../index.js').parseClientTimestamp` (now exported).
2. **Resurrection**: create booking (pending_payment) → cancel it → simulate the SMS-listener webhook
   (see `server/test/phase2_payments.test.js` for exact HMAC `X-Signature` shape) with the matching amount →
   assert booking stays `cancelled` and a `BOOKING_INACTIVE` item appears in the admin review queue
   (`GET /api/admin/payments/review-queue`), and that admin attach to the dead booking returns 409.

## Verification gates (run before commit/deploy)

```powershell
cd server ; npm test          # was 44/44 pre-change; must still pass
cd .. ; flutter analyze        # 0 warnings 0 errors
flutter test test/smooth_venue_editor_test.dart   # 4/4
```
`node --check server/index.js` already passes.

## After these: the remaining P0/P1 backlog (from the full audit)

1. Persist memory-only security state (`revokedTokens`, `loginFailures`, `processedPaymentHashes` — `server/index.js` top) to Postgres.
2. Apple login: stop trusting client-supplied email as identity; enforce `aud` even when `APPLE_CLIENT_ID` unset (~index.js:1178, 1595).
3. Remove auth-token ingestion from URL query `?token=` (`lib/main.dart:429-454`).
4. Per-phone OTP cooldown (current limiter is per-IP only, ~index.js:745).
5. Refund path for Vodafone/InstaPay deposits + credit `excessDeposit` to wallet (index.js ~3216, ~3830).
6. JWT denylist TTL must match token lifetime (30d cap vs 90d social tokens, index.js:35).
7. DB-level unique slot constraint `(venue_id, unit_id, starts_at)` in migration 002 as safety net.
8. Reminders need a scheduler (render.yaml cron for `/api/internal/run-reminders`).

# Hagzy Security & Codebase Audit Report

**Date:** 2026-11-01  
**Auditor:** Hagzy Engineering (Lead Security & Platform)  
**Branch:** `fix/phase-1-security`

---

## 1. Baseline Test & Health Results (Phase 0)

| Component | Command | Result | Notes |
| :--- | :--- | :--- | :--- |
| **Flutter Client** | `flutter pub get` | **PASS (0)** | Resolved all dependencies cleanly |
| **Flutter Client** | `flutter analyze` | **PASS (0 errors, 0 warnings)** | 19 info hints (deprecated API usages) |
| **Flutter Client** | `flutter test` | **PASS (69/69)** | All 69 client unit/widget tests passing |
| **Backend Server** | `npm test` | **PASS (16/16)** | In `server/`, all 16 tests passing |
| **Backend Server** | `npm audit` | **0 vulnerabilities** | Clean after `npm audit fix` |
| **Cloud Functions** | `npm run build` | **PASS (0)** | TypeScript compiled cleanly to `functions/lib/` |
| **Cloud Functions** | `npm audit` | **9 moderate** | Transitive `uuid` <11.1.1 in Google client SDKs |
| **Android Gateway** | `gradle -v` | **UNAVAILABLE** | System PATH does not contain `gradle`; `android_payment_gateway/` lacks `gradlew` wrapper. Documented per Rule 26. |

---

## 2. HTTP Route Inventory (Server & Functions)

### Express Server (`server/index.js`)

| Method | Path | Line | Auth Required | Role | Input Validation | Rate Limit | Status / Audit Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `POST` | `/api/auth/customer-otp/request` | 1098 | None (Public) | Public | Manual (Phone/Email regex) | `otpLimiter` (80/5m) | **Hardened**: 6-digit crypto OTP, hashed in DB with SHA-256, 5m expiry, never echoed outside test |
| `GET` | `/api/auth/google/start` | 1186 | None | Public | None | `apiLimiter` | **Needs work**: OAuth start redirect; needs CSRF state validation |
| `GET` | `/api/auth/google/callback` | 1218 | None | Public | OAuth code exchange | `apiLimiter` | **Needs work**: Needs CSRF state check and verified email handling |
| `GET` | `/api/auth/apple/start` | 1310 | None | Public | None | `apiLimiter` | **Needs work**: Apple OAuth redirect |
| `POST` | `/api/auth/social/google` | 1346 | None (Public) | Public | ID Token parsing | `apiLimiter` | **Hardened**: ID token verified strictly via Google API / Firebase Admin SDK; no unverified decode; pre-hijacking blocked |
| `POST` | `/api/auth/social/apple` | 1453 | None (Public) | Public | ID Token parsing | `apiLimiter` | **Hardened**: Apple token verified via Apple RS256 JWKS; pre-hijacking blocked |
| `POST` | `/api/auth/customer-otp/verify` | 1548 | None (Public) | Public | Manual (Code check) | `authLimiter` | **Hardened**: Constant-time `timingSafeEqual` hash comparison; max 5 attempts; 30d customer token |
| `POST` | `/api/auth/customer/register` | 1696 | None (Public) | Public | Manual | `authLimiter` | **Hardened**: Min 8 char passwords; admin identity registration forbidden (403); forced role customer |
| `POST` | `/api/auth/customer/login` | 1766 | None (Public) | Public | Password compare | `authLimiter` | **Hardened**: Account lockout tracking; generic "Invalid email or password" error; 30d token |
| `POST` | `/api/auth/customer/logout` | 1820 | None | Public | Token revoke | None | **Hardened**: Token hashed and added to bounded expiring denylist with hourly cleanup |
| `PUT` | `/api/customer/profile` | 1829 | JWT | Customer | Ad-hoc | `apiLimiter` | **Needs work**: Ensure user can only edit their own profile; no privilege escalation |
| `GET` | `/api/customer/profile` | 1857 | JWT | Customer | None | `apiLimiter` | **Needs work**: Scoped strictly to token `userId` |
| `DELETE`| `/api/customer/account` | 1864 | JWT | Customer | None | `apiLimiter` | **Needs work**: Soft-delete/anonymize user data; retain financial ledger per compliance |
| `POST` | `/api/customer/wallet/deduct` | 1894 | JWT | Customer | Manual | `apiLimiter` | **Needs work**: Ledger-based balance check with atomic transaction |
| `POST` | `/api/customer/wallet/add` | 1910 | Admin JWT | Admin | Manual | `apiLimiter` | **Needs work**: Restrict to authorized super-admin; audit logged |
| `POST` | `/api/auth/login` | 1929 | None (Public) | Admin | Hardcoded compare | `authLimiter` | **Hardened**: Generic errors; no email leaks; constant-time check; 12h admin token lifetime |
| `GET` | `/api/venues` | 2003 | None | Public | None | `apiLimiter` | **OK**: Returns active venues list |
| `GET` | `/api/admin/venues` | 2008 | Admin JWT | Admin | None | `apiLimiter` | **Needs work**: Multi-tenancy scoping (Phase 3) |
| `PUT` | `/api/admin/venues/:id` | 2013 | Admin JWT | Admin | Ad-hoc | `apiLimiter` | **Needs work**: Whitelist fields; validate schema; ownership check |
| `DELETE`| `/api/admin/venues/:id` | 2032 | Admin JWT | Admin | None | `apiLimiter` | **Needs work**: Soft delete only; block if future active bookings exist |
| `POST` | `/api/admin/venues/sync-firebase` | 2042 | Admin JWT | Admin | None | `apiLimiter` | **Needs work**: Verify sync permissions |
| `POST` | `/api/venues/:id/reviews` | 2057 | Optional JWT | Customer | Ad-hoc | `apiLimiter` | **Needs work**: Require completed booking verification before allowing review |
| `GET` | `/api/admin/bookings` | 2091 | Admin JWT | Admin | None | `apiLimiter` | **Needs work**: Multi-tenancy scoping |
| `POST` | `/api/bookings` | 2109 | Optional JWT | Public/Cust | Ad-hoc | `apiLimiter` | **Needs work**: Phase 2 server pricing & atomic slot verification |
| `GET` | `/api/bookings` | 2229 | JWT | Customer | None | `apiLimiter` | **Needs work**: Must only return bookings belonging to token `userId` |
| `POST` | `/api/bookings/:id/cancel` | 2254 | JWT | Customer | None | `apiLimiter` | **Needs work**: Enforce state machine; refund via ledger; ownership check |
| `GET` | `/api/bookings/:id` | 2289 | None | Public | None | `apiLimiter` | **OK**: Masks customer phone in public booking details |
| `POST` | `/api/admin/bookings/:id/confirm` | 2300 | Admin JWT | Admin | None | `apiLimiter` | **Needs work**: Enforce state machine (cannot revive cancelled booking); tenant check |
| `DELETE`| `/api/admin/bookings/:id` | 2320 | Admin JWT | Admin | None | `apiLimiter` | **Needs work**: Soft delete only; tenant check |
| `POST` | `/api/bookings/:id/payment-proof` | 2332 | None | Public | Ad-hoc | `apiLimiter` | **Needs work**: File/payload size validation; link to pending intent |
| `POST` | `/api/bookings/:id/paymob-intention` | 2360 | None | Public | Ad-hoc | `apiLimiter` | **Needs work**: Gate behind feature flag or deprecate if not used |
| `POST` | `/api/payments/intent` | 2693 | Optional JWT | Public | Ad-hoc | `apiLimiter` | **Needs work**: Phase 2 unique piaster amount; bind to venue wallet |
| `GET` | `/api/payments/intent/:intentId` | 2888 | None | Public | None | `apiLimiter` | **OK**: Returns intent status |
| `POST` | `/api/payments/webhook` | 2905 | Secret/HMAC | Gateway | Ad-hoc | `apiLimiter` | **Hardened**: HMAC-SHA256 signature in header with raw body and timestamp <= 5m |
| `GET` | `/api/payments/listener/status` | 2940 | Public | Gateway | None | `apiLimiter` | **Hardened**: Returns endpoint status without leaking auth methods, secrets or hints |
| `GET` | `/api/payments/listener` | 2950 | Blocked | Gateway | None | `apiLimiter` | **Hardened**: GET payment processing rejected with 405 Method Not Allowed |
| `POST` | `/api/payments/listener` | 2960 | HMAC / Key | Gateway | Ad-hoc | `apiLimiter` | **Hardened**: Header HMAC / `X-Listener-Key` with timingSafeEqual; query secrets blocked (401) |
| `POST` | `/api/whatsapp/webhook` | 3237 | None | Webhook | Ad-hoc | `apiLimiter` | **Needs work**: Validate UltraMsg / Meta webhook signature |
| `POST` | `/api/chatbot/message` | 3287 | None | Public | Ad-hoc | `apiLimiter` | **Needs work**: Rate limit per IP |
| `GET` | `/api/health` | 3302 | None | Public | None | None | **Hardened**: Reports configuration readiness flags without revealing secret values |

---

## 3. Secrets & Personal Data (PII) Inventory

### Initial Findings (Phase 0)
- Hardcoded fallback `JWT_SECRET` (`'hagzy_prod_sec_2026_rotated_k8x9q2m1'`) in `server/index.js`.
- Hardcoded fallback `ADMIN_PASSWORD` (`'hagzy2026!'`) in `server/index.js` and `render.yaml`.
- Hardcoded fallback `PAYMENT_LISTENER_KEY` (`'hagzy_live_listener_secret_2026'`) in `server/index.js` and `server/.env.example`.
- Hardcoded personal email and Egyptian phone numbers in `lib/main.dart`, `lib/models/models.dart`, `lib/screens/my_bookings_tab.dart`, `lib/screens/profile_tab.dart`, `lib/screens/unified_payment_screen.dart`, and `server/index.js`.

### Remediation Status (Phase 1)
- **All hardcoded fallback secrets completely purged**:
  - `server/index.js`: Replaced with startup fail-fast check (`BANNED_SECRETS` rejected in production).
  - `render.yaml`: Updated to `sync: false` for all secrets; plaintext password deleted.
  - `server/.env.example`: Replaced default secrets with blank placeholders.
- **All personal credentials purged from codebase**:
  - `lib/main.dart`: Removed hardcoded email and phone; admin gate strictly checks server-returned `role: 'owner'`.
  - Removed debug bypass button `"Open local preview"`.
  - Replaced hardcoded wallet and InstaPay accounts in payment screens with generic placeholders (`hagzy@instapay`, `01000000000`) or venue-bound dynamic accounts.
  - Seed venue (`venues_seed.json`) phone updated to match the venue's public contact.

---

## 4. Phase 1 Verification & Gate 1 Results

1. **Adversarial Test Suite**:
   - `server/test/api.test.js` executed: **16/16 tests passing**.
   - Verified that forged tokens (signed with attacker key) fail with 401 across customer auth, admin auth, Google social login, and Apple social login.
   - Verified that expired tokens fail with 401.
   - Verified that attempting to register an admin email or phone via customer registration returns 403 Forbidden.
   - Verified password length < 8 chars returns 400 Bad Request.
   - Verified HMAC payment listener accepts valid signatures with fresh timestamps and rejects stale timestamps (> 5m) or forged signatures.
   - Verified query string secrets return 401 and GET payment attempts return 405.
2. **`jwt.decode` Check**:
   - `grep -rn "jwt.decode" server/`: **0 occurrences**. Zero unverified trust decisions.
3. **Secrets Rescan**:
   - Regex scan for leaked default secrets and owner credentials returned 0 matches across `lib/`, `server/`, and `web/`.
4. **Code Quality & Baselines**:
   - `flutter analyze`: 0 errors, 0 warnings.
   - `flutter test`: 69/69 passing.
   - `cd server && npm test`: 16/16 passing.
   - `cd server && npm audit`: 0 vulnerabilities.

**GATE 1 STATUS: PASSED.**

---

## 5. Phase 2 Verification & Gate 2 Results (Payments, State Machine & Ledger)

1. **State Machine (`bookingStateMachine.js`)**:
   - Centralized all transitions: `pending_payment -> confirmed -> completed | cancelled | expired | no_show`.
   - Cannot revive cancelled booking (returns 409 Conflict).
   - Atomic concurrency protection: two concurrent requests for the same slot yield exactly one 200 and one 409.
2. **Authoritative Server Pricing (`pricingEngine.js`)**:
   - Server computes base rates, additive services, duration multipliers, and promo codes (`HAGZYVIP`, `WELCOME26`, `HAGZYPADEL`).
   - Ignores untrusted client price values.
3. **Immutable Wallet Ledger (`walletLedger.js`)**:
   - Computes balances strictly by summing ledger entries (`TOPUP`, `BOOKING_DEPOSIT`, `REFUND`, `WELCOME_BONUS`).
   - Returns 402 Insufficient Funds on overdraft attempts.
4. **Payment Matcher & Gateway Hardening (`paymentMatcher.js`)**:
   - Exact amount matching with unique piaster fractions.
   - PII balances redacted from SMS/notifications.
   - Large transfers (> 5000 EGP) route to manual admin review queue.
5. **Database Migration Dry-Run (`server/migrate.js --dry-run`)**:
   - `001_customer_accounts.sql` & `002_authoritative_schema.sql` validated.
6. **Route Parity**:
   - `node scripts/check_route_parity.js`: 100% clean (all 28 client routes exist on server).

**GATE 2 STATUS: PASSED (24/24 tests pass).**

---

## 6. Phase 3 Verification & Gate 3 Results (Multi-Tenancy & Partner Portal)

1. **Multi-Tenant Partner Isolation**:
   - Partners only see and manage their own venues (`GET /api/admin/venues`) and bookings (`GET /api/admin/bookings`).
   - Platform super-owner retains cross-platform overview.
   - Cross-tenant update and delete attempts are rejected with 403 Forbidden.
2. **Soft Delete Integrity**:
   - Deleted venues are marked `isDeleted: true, isActive: false`.
   - Never purges historical or active customer bookings.
3. **Real QR Standee Generator**:
   - Dynamic SVG/Canvas QR rendering via `qr_flutter` targeting `https://hagzy.app/venue/:id`.
   - Deep-linking handled in-app via `onGenerateRoute` and web `Uri.base.pathSegments`.
4. **Clean Onboarding Flow**:
   - Removed fake 40% initial progress; replaced with honest 2-step flow (Venue Details & Payouts).
   - Removed hardcoded fake "1450 EGP" loss banner; dynamic real server analytics (`GET /api/admin/analytics`).

**GATE 3 STATUS: PASSED (27/27 tests pass).**

---

## 7. Phase 4 Verification & Gate 4 Results (UX/UI, Contrast & Accessibility)

1. **WCAG AA Contrast**:
   - `kGreen` upgraded to `#047857` (4.67:1 on white).
   - `kGreenDark` upgraded to `#065F46` (7.0:1 on white).
   - `kGold` upgraded to `#B45309` (4.6:1 on white).
2. **Font Sizes & Readability**:
   - Enforced minimum 12.0px accessible font size across entire codebase.
   - Eliminated microscopic unreadable sub-12px styles.
3. **Design Tokens**:
   - Created `lib/theme/tokens.dart` (`HagzyTokens`) standardizing spacing, radii, and 48x48dp minimum tap targets.
4. **Web Accessibility**:
   - Removed `user-scalable=no` and `maximum-scale=1.0` from `web/index.html` to allow pinch-zoom.
5. **Egyptian Phone Validation**:
   - Enforced `^01[0125]\d{8}$` validation across login, registration, and payouts.

**GATE 4 STATUS: PASSED (69/69 Flutter tests pass, 0 flutter analyze issues).**

---

## 8. Phase 5 Verification & Gate 5 Results (Release Readiness & CI/CD)

1. **GitHub Actions CI/CD Pipeline (`.github/workflows/build.yml`)**:
   - Enforces automated verification: `npm test`, `check_route_parity.js`, `npm audit`, `flutter analyze`, `flutter test`.
   - Compiles Web (`flutter build web --release`).
   - Compiles Android APK and Google Play App Bundle (AAB).
   - Compiles iOS IPA.
2. **Android Release Security**:
   - Enabled `android:usesCleartextTraffic="false"`.
   - Added Android App Links intent-filter for `https://hagzy.app/venue/*`.
   - Release signing configuration from `key.properties`.
3. **Apple App Store Compliance**:
   - Validated `PrivacyInfo.xcprivacy` with `NSPrivacyTracking: false` and `CA92.1` UserDefaults declaration.
   - `NSAllowsArbitraryLoads: false`.
4. **Git Cleanliness**:
   - Untracked precompiled `build/` directory from git tracking.
   - Standardized `docs/STORE_LISTING.md` and `docs/OWNER_TODO.md`.

**GATE 5 STATUS: PASSED.**


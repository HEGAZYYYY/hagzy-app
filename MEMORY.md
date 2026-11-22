# Hagzy (حجزي) — Project Memory & System Architecture

> **Authoritative Context Document for AI Assistants (Z.ai / ZCode, Claude, Cursor, Antigravity)**  
> **Last Updated**: November 2026  
> **Repository**: `https://github.com/HEGAZYYYY/hagzy-app.git` (Branch: `main`)  
> **Live Production URL**: [https://hagzy.shop](https://hagzy.shop) (Auto-deployed via Render)

---

## 1. Project Overview & Business Domain

**Hagzy (حجزي)** is an Egyptian end-to-end booking and venue management platform tailored for local recreational, wellness, and workspaces:
- **Sports Venues**: Padel courts, 5v5 / 7v7 football pitches, tennis.
- **Salons & Barbershops**: Individual barber/styling chairs, grooming stations, additive service checklists (haircut, beard trim, VIP package).
- **Entertainment Lounges**: PlayStation lounges, billiards, escape rooms (with per-person group pricing where cost per player drops as the group grows).
- **Workspaces & Study Lounges**: Co-working spaces, private meeting rooms, hot desks, flexible passes (hourly, day pass, weekly pass).

**Target Market & Localization**:
- Bilingual UI (Egyptian Arabic `ar` as first-class citizen, English `en`).
- Currency: Egyptian Pounds (EGP / ج.م) formatted with standard thousands separators.
- Built-in coverage of Egyptian governorates and cities (Cairo, Giza, Alexandria, Mansoura, Tanta, Zagazig, etc.).

---

## 2. Technology Stack & Architectural Invariants

### 2.1. Frontend: Flutter Web & Mobile
- **Framework**: Flutter 3.x (Web & Mobile targets) using Dart.
- **Design System**: Material 3 with custom Hagzy cohesive emerald & slate theme (`HagzyTheme` in `lib/theme/hagzy_theme.dart`).
- **Dark & Light Mode Contract**:
  - Full WCAG AA contrast compliance (contrast ratio $\ge$ 4.5:1 for body text, $\ge$ 3.0:1 for bold/headers).
  - Dynamic getters `kInk`, `kPage`, `kPanel`, `kSurfaceTint`, `kMuted`, `kBorder` adapt reactively to `kDarkMode.value`.
  - Explicit theme definitions for `dialogTheme`, `chipTheme`, `segmentedButtonTheme`, `popupMenuTheme`, `dropdownMenuTheme`, and `listTileTheme` in both `lightTheme()` and `darkTheme()`.
  - Surfaces avoid hardcoded white/black; cards and dialogs adapt dynamically (`dialogBg`, `cardBg`, `surfaceBg`, `textColor`, `mutedColor`).
- **Local Dev Port**: Runs on `http://localhost:5050` (`flutter run -d chrome --web-port 5050 --web-hostname localhost`).

### 2.2. Backend & Authoritative Database: Supabase (PostgreSQL)
- **Database**: **Supabase** (`qgimngblsrfgzavuxpde.supabase.co`, project `hagzy-prod`).
- **CRITICAL ARCHITECTURAL RULE**: **Firebase has been completely purged.** Do NOT re-introduce Firebase Admin, Firestore SDKs, or Firebase configurations. All data lives in Supabase / PostgreSQL.
- **Schema & Migrations**: Located in `server/migrations/`:
  - `001_customer_accounts.sql`: Customer profiles, auth tables, wallets.
  - `002_authoritative_schema.sql`: Full relational schema (venues, items/units, bookings, payments, audit logs, review queues).
  - `003_moderation_views.sql`: Partner review views, platform analytics.
  - `004_supabase_auth_rls_rpc.sql`: Row-Level Security (RLS) policies and stored procedures.
  - `005_qr_reminders_notifications.sql`: QR check-in tokens, reminder schedules, automated notifications.
  - Auto-executed transactionally on startup via `server/migrate.js`.
- **Node.js API Server** (`server/`):
  - Express.js backend on Node 20+, deployed on Render.
  - Operates a low-latency state engine with transactional write-through to PostgreSQL (`hagzy_state` table) and atomic disk backups (`hagzy_db.json`).
  - Strict secret validation: fails fast on boot in production if `JWT_SECRET` is missing.
  - Local API Port: `http://localhost:4000`.

---

## 3. Core Features & Codebase Layout

```text
hagzy_app/
├── lib/
│   ├── features/
│   │   ├── checkout_psychology/     # Deposit guarantees, receipt uploads, loss-aversion dialogs
│   │   ├── discovery/               # Search, venue cards, banners, lobby feeds
│   │   ├── merchant_portal/         # Merchant onboarding, QR standee generator
│   │   ├── passport_wallet/         # Customer wallet balance, top-up sheet, vouchers
│   │   ├── social_lobby/            # Social challenge rosters, public player squads
│   │   └── universal_booking/       # Booking sheets for hourly, tiered, pass, & salon modes
│   ├── models/                      # Venue, Item, Booking, Service, CustomerProfile data models
│   ├── screens/
│   │   ├── admin_workspace.dart     # Owner & Partner merchant portal, venue moderation, QR scanner
│   │   ├── book_tab.dart            # Main booking tab, room spotlights, venue details modals
│   │   ├── login_screen.dart        # Phone OTP login, customer registration, Google Auth
│   │   ├── my_bookings_tab.dart     # Customer active & past bookings, QR access pass
│   │   ├── profile_tab.dart         # Customer profile, wallet, dark mode toggle, language toggle
│   │   ├── smooth_venue_editor.dart # 0-AI clean venue editor: rooms, chairs, rates, photo file upload
│   │   └── unified_payment_screen.dart # Vodafone Cash / InstaPay direct transfers with auto-matching
│   ├── services/
│   │   ├── api_service.dart         # HTTP client connecting to Node API & Supabase
│   │   └── image_upload_service.dart# File picker & base64/data-URL / remote image uploader
│   ├── theme/
│   │   ├── hagzy_theme.dart         # Cohesive Emerald & Slate palette, dark/light themes, typography
│   │   └── tokens.dart              # Spacing, radius, elevation tokens
│   └── main.dart                    # App entry point, routing, deep links, lifecycle handlers
├── server/
│   ├── migrations/                  # Authoritative SQL migrations (001 to 005)
│   ├── routes/                      # Express routers (auth, bookings, venues, payments, admin, ai)
│   ├── bookingStateMachine.js       # Centralized lifecycle transitions (holds, confirms, cancels)
│   ├── paymentMatcher.js            # Vodafone Cash / InstaPay auto-matching & piaster disambiguation
│   ├── migrate.js                   # Automated PostgreSQL migration runner
│   └── index.js                     # Server entry point & in-memory state engine
└── test/
    ├── smooth_venue_editor_test.dart# Widget tests for venue & room creation
    └── ...                          # Backend integration tests in server/test/
```

---

## 4. Key Workflows & Invariants

### 4.1. Smooth Venue & Room Editor (`smooth_venue_editor.dart`)
- **No AI generation clutter**: Simple, high-speed, direct editing interface for owners.
- **Section 1**: Category selector (Padel, Football, Salon, Workspace, Gaming), Venue Name, City, Address, Deposit Percentage (15%, 20%, 25%, 30%, 50%).
- **Section 2 (Rooms & Chairs)**:
  - Add/Edit dialogs for each unit/room.
  - Image upload directly via file picker (`ImageUploadService.pickImage()`) converting to data URL / storage URL.
  - Custom room description (e.g., "Full HD projector, 4 controllers, soundproof").
  - Peak and standard hourly rates with weekday/weekend split.
- **Section 3 (Salon Services)**: Additive service menu with service title, duration (minutes), and price (EGP).
- **Section 4 (Photos & Amenities)**: Venue cover image (file upload or URL) + multi-select amenities.
- **Section 5 (Payouts & Hours)**: Opening & closing time dropdowns + Vodafone Cash / InstaPay payout numbers.

### 4.2. Egyptian Payment Auto-Verification (`paymentMatcher.js`)
- **Direct P2P Wallets**: Customers transfer deposits directly to the merchant's Vodafone Cash or InstaPay number.
- **Piaster Disambiguation (`generateUniquePayableAmount`)**:
  - When multiple customers initiate bookings with identical round figures (e.g., 100 EGP), the engine appends unique piaster fractions (e.g., 100.14 EGP, 100.28 EGP).
  - This allows instant, deterministic auto-confirmation upon receiving the bank/wallet SMS without manual receipts.
- **Automated Android Listener**:
  - Android phone listener app posts inbound bank/wallet SMS to `/api/payments/listener/webhook` with HMAC-SHA256 signature (`X-Signature`).
  - SHA-256 fingerprinting ensures strict idempotency (duplicate transfers ignored).
  - High-value transfers (> 5,000 EGP) or ambiguous matches route to `db.reviewQueue` for one-click manual claim.

### 4.3. Centralized Booking State Machine (`bookingStateMachine.js`)
- Valid transitions: `pending_payment -> confirmed -> completed | cancelled | expired | no_show`.
- **Anti-resurrection invariant**: Cancelled bookings can never be confirmed (HTTP 409 Conflict).
- Unpaid holds expire automatically after 15 minutes.
- Every state change writes an immutable audit record to `db.auditLog`.

### 4.4. Partner & Admin Security
- Dual-role permissions: Platform `owner` vs venue-specific `partner`.
- Partner venues are strictly isolated; partners cannot view, edit, or cancel bookings belonging to other venues.
- Seed admin accounts are provisioned via environment variables (`ADMIN_PHONE`, `ADMIN_PASSWORD`), never hardcoded in source.

---

## 5. Testing & Verification Rules

Every code change must satisfy three gates before deployment:
1. **Flutter Analyzer**:
   ```powershell
   flutter analyze
   ```
   *Requirement: 0 warnings, 0 errors.*
2. **Flutter Widget Tests**:
   ```powershell
   flutter test test/smooth_venue_editor_test.dart
   ```
   *Requirement: 4/4 passing.*
3. **Backend Integration Tests**:
   ```powershell
   npm test
   ```
   *Requirement: 44/44 passing tests covering security, state machines, payment collisions, and migrations.*

> [!IMPORTANT]
> **PowerShell Syntax Rule**: The host environment is Windows PowerShell. Always use semicolon `;` to chain commands (e.g. `cmd1 ; cmd2`), **never** use `&&`.

---

## 6. Deployment Pipeline

- **GitHub Repository**: Pushes to `origin/main` automatically trigger production deployments.
- **Render Dashboard**: Web service builds the Flutter web application and runs the Express API server.
- **Public Domain**: `https://hagzy.shop`
- **SSL & DNS**: Managed via Cloudflare / Render with automatic TLS certificates.

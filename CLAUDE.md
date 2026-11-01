# Claude Code Guidelines for Hagzy

## Tech Stack
- **Client**: Flutter (Web, Android, iOS) with Dart.
- **Backend API**: Node.js / Express (`server/index.js`).
- **Cloud Functions**: Firebase Functions (`functions/src/index.ts`).
- **Database**: PostgreSQL (cloud / local pool), with Firestore mirror & local JSON backup.
- **Payment Gateway**: Android background service (`android_payment_gateway/` or automated listener).

## Development & Test Commands
- **Flutter Client**:
  - Dependencies: `flutter pub get`
  - Analysis: `flutter analyze`
  - Tests: `flutter test`
  - Run Web: `flutter run -d chrome`
- **Node Backend Server**:
  - Directory: `server/`
  - Dependencies: `npm ci` (or `npm install`)
  - Run server: `npm start` (port 4000)
  - Run tests: `npm test`
  - Audit: `npm audit`
- **Firebase Functions**:
  - Directory: `functions/`
  - Dependencies: `npm ci`
  - Build: `npm run build`
  - Test/Lint: `npm run lint`

## Critical Rules
1. **Never touch production**: Do not call live Render APIs or Firebase Hosting URLs directly with real credentials, and do not deploy to production without explicit user command.
2. **Never print, log, or commit secrets**: Use environment variables (`.env`). Use placeholders like `owner@example.com` or `01000000000` in tests and documentation.
3. **Do not touch `build/` directly**: Never edit generated web/mobile build outputs manually.
4. **Branch per phase**: Create a dedicated branch for each phase (e.g. `fix/phase-1-security`).
5. **Every fix requires tests**: Include adversarial tests (forged tokens, unverified claims, replayed requests).
6. **No weakened tests**: Do not relax test assertions to make broken code pass.
7. **Document decisions**: Any ambiguous choice or architectural assumption must be recorded in `docs/DECISIONS.md`.

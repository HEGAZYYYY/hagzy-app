# 🚀 Hagzy (حجزي) – App Store & Google Play Deployment & Reviewer Guide

This guide contains everything needed to upload and submit **Hagzy** (`com.hagzy.app`, version `1.0.0+1`) to **Google Play Console** and **Apple App Store Connect**.

---

## 1. 🔑 App Reviewer Notes (Copy-Paste into App Store Connect & Google Play Console)

Paste the block below into **App Store Connect → App Review Information → Notes** and **Google Play Console → App content → App access**:

```text
Demo Reviewer Account (No Email Inbox Required):
- Email: reviewer@hagzy.app
- Verification Code (OTP): 123456

How to Sign In:
1. Launch Hagzy and enter reviewer@hagzy.app in the Email Address field.
2. Tap "Log In" to advance to the 6-digit verification code screen.
3. Enter 123456 and tap "Verify & Sign In".

Pre-Seeded Test State:
- Signed-in customer profile ("App Reviewer") with 1,000 EGP in-app wallet balance.
- 1 pre-seeded confirmed upcoming venue booking with a scannable QR Check-In Pass (visible under the "Bookings" tab).
- 1 saved favorite venue (visible under the "Explore" tab).
- Full browsing, area/category filtering, venue booking flow, Dark Mode, and English/Arabic (RTL) switching are available without live payment charges.

Guest Browsing & Account Deletion:
- Users can also browse venues without signing in via "Explore Venues as Guest".
- In-app account deletion can be tested at any time from Profile -> "Delete Account & Personal Data", which permanently clears all local session, wallet, favorite, and booking data and returns to the sign-in screen.
```

---

## 2. 📱 App Identifiers, Privacy & Permissions

* **App Name:** `Hagzy` (حجزي)
* **Bundle Identifier (iOS):** `com.hagzy.app`
* **Application ID (Android):** `com.hagzy.app`
* **Version:** `1.0.0+1` (`pubspec.yaml`)
* **Privacy Policy URL:** `https://hagzy.app/privacy` (hosted from `web/privacy.html`)
* **Terms of Service URL:** `https://hagzy.app/terms` (hosted from `web/terms.html`)
* **Account Deletion URL (Google Play Data Safety):** `https://hagzy.app/delete-account` (hosted from `web/delete-account.html`) + in-app deletion inside **Profile → Delete Account & Personal Data**
* **iOS Privacy Manifest:** `ios/Runner/PrivacyInfo.xcprivacy` (declares `UserDefaults` `CA92.1` + linked Name/Email/Phone + unlinked Coarse Location; `NSPrivacyTracking = false`)
* **iOS Export Compliance:** `ITSAppUsesNonExemptEncryption = false`

### Declared Permissions & Rationales
* **Location (`NSLocationWhenInUseUsageDescription` / `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`):**
  * *Purpose:* Displays nearby sports courts, salons, escape rooms, and gaming lounges on the map and calculates distance in kilometers.
* **Internet (`INTERNET`):**
  * *Purpose:* Required for live availability sync, reservations, and user profile management.

---

## 3. 🤖 Upload to Google Play Console (Android `.aab`)

### Build the Signed Production App Bundle locally
`android/key.properties` and `android/app/upload-keystore.jks` are already configured locally (and excluded from Git).

```powershell
flutter build appbundle --release `
  --dart-define=HAGZY_API_URL=https://qgimngblsrfgzavuxpde.supabase.co/functions/v1/hagzy-api
```

Output file to upload:
`build/app/outputs/bundle/release/app-release.aab`

### Upload Steps in Google Play Console
1. Open [Google Play Console](https://play.google.com/console) → select **Hagzy** (`com.hagzy.app`).
2. Go to **Test and release → Production** (or **Closed testing / Internal testing** first) → **Create new release**.
3. Upload `build/app/outputs/bundle/release/app-release.aab` (enable Play App Signing if prompted on first upload).
4. Add Release Name (`1.0.0 (1)`) and release notes.
5. Under **Policy and programs → App content**, confirm:
   - **Privacy Policy URL**
   - **App Access** (paste the Reviewer Notes from Section 1)
   - **Data Safety** (Name, Email, Phone, Approximate Location; Account deletion available in-app & via web)
   - **Content Rating**, **Target Audience**, and **Ads** (`No ads`)
6. Click **Save → Next → Send for review**.

---

## 4. 🍎 Upload to Apple App Store Connect (iOS via GitHub Actions `macos-latest`)

Because Xcode requires macOS, this repo includes [`.github/workflows/ios-appstore.yml`](.github/workflows/ios-appstore.yml) to compile, sign, and upload directly to App Store Connect from Windows.

### One-Time Setup in Apple Developer & App Store Connect
1. **Register Bundle ID** in [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list):
   - Identifier: `com.hagzy.app`
   - Capabilities: enable **Sign in with Apple** (matches `ios/Runner/Runner.entitlements`).
2. **Create App Record** in [App Store Connect](https://appstoreconnect.apple.com/apps) with Bundle ID `com.hagzy.app`.
3. **Create Apple Distribution Certificate (`.p12`)**:
   - Create an **Apple Distribution** certificate in Apple Developer Portal and export it with its private key as `dist_cert.p12` (protected with a password).
4. **Create App Store Provisioning Profile (`.mobileprovision`)**:
   - Type: **App Store Connect** → App ID: `com.hagzy.app` → select your Apple Distribution certificate → download `Hagzy_AppStore.mobileprovision`.
5. **Create App Store Connect API Key (`.p8`)**:
   - App Store Connect → **Users and Access → Integrations → App Store Connect API → Team Keys → "+"** (Role: **App Manager**).
   - Note the **Issuer ID**, **Key ID**, and download `AuthKey_<KEY_ID>.p8`.

### Encode Files to Base64 on Windows PowerShell
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\dist_cert.p12")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\Hagzy_AppStore.mobileprovision")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\AuthKey_XXXXXX.p8")) | Set-Clipboard
```

### Add the 7 GitHub Repository Secrets
In GitHub (`HEGAZYYYY/hagzy-app`) → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret Name | Value |
| :--- | :--- |
| `APPLE_DISTRIBUTION_CERT_BASE64` | Base64 of `dist_cert.p12` |
| `APPLE_DISTRIBUTION_CERT_PASSWORD` | Password of `dist_cert.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 of `Hagzy_AppStore.mobileprovision` |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer UUID |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` | Base64 of `AuthKey_<KEY_ID>.p8` |

### Trigger the Upload
1. In GitHub → **Actions → Upload iOS to Apple App Store Connect → Run workflow** (`main` branch).
2. Leave `build_name` and `build_number` blank for `1.0.0+1` (or set `build_number: 2` for subsequent uploads).
3. Wait ~10–12 minutes for the build to appear in **App Store Connect → TestFlight → Builds**.
4. In App Store Connect → **App Store tab → 1.0 Prepare for Submission**:
   - Attach the uploaded build.
   - Upload screenshots (6.9" / 6.7" iPhone required), description, keywords, Support URL, and Privacy Policy URL.
   - Paste the Reviewer Notes from Section 1 into **App Review Information → Notes** (and enter `reviewer@hagzy.app` / `123456` in Sign-in Information).
   - Click **Add for Review → Submit to App Review**.

---

## 5. 🧪 Quality & Verification Baseline
* `flutter analyze`: **0 issues**
* `flutter test`: **107 / 107 passing** (including WCAG AA dark-mode contrast checks, responsive LTR/RTL viewport checks, adaptive modal tests, and reviewer login + account deletion tests)
* `npm test --prefix server`: **49 / 49 passing**
* `node scripts/check_route_parity.js`: **37 / 37 client routes verified**
* Legacy `AlertDialog(` count in `lib/`: **0**

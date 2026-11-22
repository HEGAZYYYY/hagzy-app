# 🚀 Hagzy (حجزي) – App Store & Google Play Deployment & Reviewer Guide

This guide contains everything needed to submit Hagzy to the **Apple App Store** and **Google Play Console**, including copy-paste review notes, demo credentials, and build commands.

---

## 1. 🔑 App Reviewer Credentials (Copy-Paste into App Store Connect & Play Console)

When submitting the app, Apple and Google will ask for demo credentials in the **"App Review Information"** section. Copy and paste the following:

```text
Reviewer Access Details:

Option A (1-Tap Fast Login):
On the main login screen, tap the gold button at the bottom:
"Reviewer / Tester Quick Sign-In (Demo)" / "دخول تجريبي لفريق المراجعة"
This immediately logs in as an authorized test account.

Option B (Manual Verification Code):
• Email: reviewer@hagzy.app (or demo@hagzy.app)
• Phone: 01012345678
• Verification Code (OTP): 123456

Testing Bookings & Payments:
• The test account is pre-funded with 1,000 EGP Hagzy Wallet balance.
• Reviewers can book any sports court, escape room, gaming suite, or salon service.
• Reviewers can complete payment instantly via their pre-funded wallet balance.
• If testing Vodafone Cash or InstaPay transfer screens, reviewers can tap the gold button:
  "Reviewer / Tester: Simulate Instant Confirmation"
  to simulate immediate gateway verification without needing real bank transfers.
```

---

## 2. 📱 App Identifiers & Permissions

* **App Name:** `Hagzy` (حجزي)
* **Bundle Identifier (iOS):** `com.hagzy.app`
* **Application ID (Android):** `com.hagzy.app`
* **Version:** `1.0.0+1` (configure in `pubspec.yaml`)

### Declared Permissions & Rationales:
* **Location (`NSLocationWhenInUseUsageDescription` / `ACCESS_FINE_LOCATION`):**
  * *Purpose:* To display sports courts, escape rooms, lounges, and salons near the user on the map and calculate distance in kilometers.
  * *Prompt copy:* "Hagzy uses your location to show sports courts, salons, and venues near you on the map."
* **Internet (`INTERNET`):**
  * *Purpose:* Required for real-time slot booking, live availability sync, and user profile management.

---

## 3. 🛠️ Build & Release Commands

### For Android (Google Play Store):
To generate an optimized release Android App Bundle (AAB):
```bash
# Ensure key.properties is configured for your upload keystore
flutter build appbundle --release
```
* The output file will be generated at:
  `build/app/outputs/bundle/release/app-release.aab`

To generate a standalone APK for testing on physical Android devices:
```bash
flutter build apk --release
```

---

### For iOS (Apple App Store / TestFlight):
```bash
flutter build ipa --release
```
* Open `ios/Runner.xcworkspace` in Xcode.
* Select your Apple Developer Team under **Signing & Capabilities**.
* In Xcode, select **Product > Archive**, then click **Distribute App** to upload to App Store Connect / TestFlight.

---

## 4. 🧪 Verified Features & Recent Fixes

1. **10-Minute Grace Period Countdown Bug Fixed:**
   * Bookings now persist exact `createdAt` and `confirmedAt` timestamps.
   * The 10-minute free cancellation countdown banner now cleanly expires after 600 seconds and never gets stuck indefinitely.
2. **Reviewer Demo Mode Added:**
   * 1-tap reviewer login with pre-funded 1,000 EGP test balance.
   * Reviewer bypass OTP `123456` enabled for `reviewer@hagzy.app`, `demo@hagzy.app`, and `01012345678`.
   * Simulation button on payment screen allows instant verification for automated/manual app testers.
3. **Codebase Cleanup:**
   * Removed temporary scratch files and artifacts.
   * `flutter analyze`: **0 issues found**.
   * `flutter test`: **82/82 tests passing**.
   * Backend suite: **49/49 tests passing**.

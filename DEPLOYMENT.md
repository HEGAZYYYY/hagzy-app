# Hagzy Production & Deployment Blueprint

This document outlines the complete checklist and automated configurations needed to take **Hagzy (حجزي)** from prototype to a fully live production app available to real users across Egypt.

---

## 1. Production Web & Cloud Deployment (Render / Vercel)

### Static Web Hosting (Render / Vercel / Netlify)
1. Build the release web bundle optimized for production:
   ```bash
   flutter build web --release --web-renderer canvaskit
   ```
2. The output in `build/web` can be deployed instantly to **Render Static Site** or **Vercel**.
3. **`render.yaml` Configuration (for root of repository):**
   ```yaml
   services:
     - type: web
       name: hagzy-web
       env: static
       buildCommand: flutter pub get && flutter build web --release
       staticPublishPath: build/web
       routes:
         - type: rewrite
           source: /*
           destination: /index.html
   ```

---

## 2. Egyptian Payment Gateway Integration (Paymob & Fawry)

To replace manual InstaPay/Vodafone Cash reference text with automated card & wallet transactions:
1. **Paymob API Integration:**
   - Add `http` API calls in `lib/hagzy_api.dart` for Paymob Authentication, Order Registration, and Payment Key Generation.
   - Support Meeza cards, Visa/Mastercard, and Vodafone Cash mobile wallets.
2. **Webhook Listener:**
   - Implement backend webhook endpoint `/api/paymob/callback` to instantly verify deposit status and transition bookings from `pendingPayment` to `confirmed`.

---

## 3. SMS & WhatsApp Notifications (Twilio / UltraMsg)

1. **OTP SMS Verification:**
   - Replace simulated test OTP codes in `CustomerProfileTab` with live SMS delivery via Twilio or an Egyptian gateway (e.g., VictoryLink or CEQUENS).
2. **Automated WhatsApp Booking Confirmations:**
   - Use WhatsApp Business API (`https://wa.me/...` or UltraMsg webhook) to send instant booking slips with venue location pins to customers' phones upon deposit confirmation.

---

## 4. Google Play Store & Apple App Store Release

1. **Android App Bundle:**
   ```bash
   flutter build appbundle --release
   ```
   Upload `build/app/outputs/bundle/release/app-release.aab` to Google Play Console.
2. **iOS Archive:**
   ```bash
   flutter build ipa --release
   ```
   Open `ios/Runner.xcworkspace` in Xcode to archive and submit via App Store Connect.

---

## 5. Summary of Automated Code Improvements

- **Governorates & Maps:** Fully mapped all 27 Egyptian governorates with accurate GPS distance sorting.
- **Admin POS & Analytics:** Real-time revenue breakdown by vertical, instant deposit verification, and walk-in/slot blocker tools.
- **Customer Experience:** Book Again carousel with undo support, instant wallet top-ups, and bilingual Arabic/English localization.

# Hagzy: Actions Required by Project Owner

This document outlines tasks and secret rotation requirements that can **only be performed by the repository owner**.

---

## 1. CRITICAL: Secret Rotation (Immediate Action)

Because previous iterations of the repository and deployment files contained hardcoded or default secrets, **all of the following credentials must be rotated immediately** in your external dashboards:

### A. Render Dashboard (Backend Web Service: `hagzy-api`)
Go to [Render Dashboard](https://dashboard.render.com/) -> Select `hagzy-api` -> **Environment**:
1. **`JWT_SECRET`**:
   - Generate a cryptographically secure 64-character secret:
     ```bash
     node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"
     ```
   - Set it as `JWT_SECRET` in Render. *Note: This will safely invalidate all old active sessions.*
2. **`ADMIN_PASSWORD`**:
   - Set a strong, unique owner password (minimum 12 characters).
   - Never use `hagzy2026!` or committed defaults.
3. **`ADMIN_EMAIL`**:
   - Set to your authoritative owner email (e.g. `your-email@gmail.com`).
4. **`ADMIN_PHONE`**:
   - Set to your authoritative Egyptian owner phone number (e.g. `010XXXXXXXX`).
5. **`PAYMENT_WEBHOOK_SECRET` & `PAYMENT_LISTENER_KEY`**:
   - Generate a strong random key:
     ```bash
     node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
     ```
   - Set both variables in Render.
   - Enter the same key into your Android SMS/Notification listener app (MacroDroid / Tasker / Hagzy Gateway App) in the `X-Listener-Key` or HMAC signature header.
6. **`CORS_ORIGINS`**:
   - Set to: `https://hagzy-booking.web.app,https://hagzy.app`

---

## 2. Google Cloud & Firebase Console Rotation
1. **Firebase Service Account Key**:
   - In [Firebase Console](https://console.firebase.google.com/) -> Project Settings -> **Service accounts**:
   - If a private key was ever generated and downloaded locally, generate a new private key and delete old keys.
2. **Google OAuth 2.0 Web Client ID & Secret**:
   - In [Google Cloud Console](https://console.cloud.google.com/) -> APIs & Services -> **Credentials**:
   - Verify Authorized JavaScript origins include only your production domains.
   - If a client secret was created, rotate it.

---

## 3. Database & Booking State Audit
1. **Audit Bookings for Tampering**:
   - Review recent entries in Cloud Firestore (`bookings` collection) and PostgreSQL (`hagzydb`) created prior to November 1, 2026.
   - Verify that all confirmed bookings correspond to legitimate payments in your Vodafone Cash or InstaPay statements.
2. **Review Venues Catalog**:
   - Confirm only authorized venues are listed and all payout handles (InstaPay addresses / wallet numbers) match real accounts.

---

## 4. Mobile Gateway Phone Setup
1. Dedicated Android device running on stable Wi-Fi and power.
2. Battery optimization disabled for the listener application.
3. Notification access granted for InstaPay and SMS permissions for Vodafone Cash.
4. Verify HTTP target URL points to `https://hagzy-api.onrender.com/api/payments/listener` with header `X-Listener-Key` matching `PAYMENT_LISTENER_KEY`.

---

## 5. Android Keystore & Production Release Signing (Google Play)

To generate a production upload key for Google Play and enable automatic release signing in CI/CD:

1. **Generate the Upload Keystore Locally**:
   Run in terminal:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. **Encode Keystore to Base64**:
   - On Linux/macOS:
     ```bash
     base64 < upload-keystore.jks > upload-keystore.base64.txt
     ```
   - On Windows (PowerShell):
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Out-File -Encoding utf8 upload-keystore.base64.txt
     ```
3. **Configure GitHub Repository Secrets**:
   Go to your GitHub repo -> **Settings** -> **Secrets and variables** -> **Actions** -> Add:
   - `ANDROID_KEYSTORE_BASE64`: Paste the entire base64 string from `upload-keystore.base64.txt`.
   - `ANDROID_KEY_ALIAS`: `upload`
   - `ANDROID_KEY_PASSWORD`: The password you chose for the key.
   - `ANDROID_STORE_PASSWORD`: The password you chose for the keystore.
4. **Local Builds (Optional)**:
   Place `upload-keystore.jks` in `android/app/` and create `android/key.properties`:
   ```properties
   storePassword=<your-store-password>
   keyPassword=<your-key-password>
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
   *(Note: `android/key.properties` and `*.jks` are already ignored in `.gitignore`).*

---

## 6. Cloud Hosting & Database Advisory (Render Free Tier vs Paid)

- **Render Free Tier Sleep**:
  - Free web services automatically sleep after 15 minutes of inactivity.
  - Waking up takes 50-70 seconds, which will delay customer bookings and cause incoming payment listener webhooks from your Android gateway to time out.
  - Free PostgreSQL databases on Render expire after 30 days and are automatically deleted.
- **Production Recommendation**:
  - Upgrade the backend service (`hagzy-api`) to a Render Starter plan ($7/mo) before launching to public customers.
  - Upgrade the PostgreSQL instance to a persistent managed database ($7/mo) or Supabase/Neon PostgreSQL, and set the permanent connection string in `DATABASE_URL`.

---

## 7. App Store & Google Play Reviewer Credentials

Apple and Google store reviewers require a test account to review the application:
1. In Render environment variables, configure:
   - `REVIEWER_TARGET`: A fixed test phone number (e.g. `01000000099`) or email (e.g. `reviewer@hagzy.app`).
   - `REVIEWER_CODE`: A fixed 6-digit verification code (e.g. `739281`).
2. Provide these credentials in App Store Connect and Google Play Console under "App Access / Sign-in Information" so reviewers can immediately log in without SMS.


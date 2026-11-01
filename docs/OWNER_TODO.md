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

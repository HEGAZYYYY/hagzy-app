# Hagzy (حجزي) — App Store & Google Play Store Listing & Compliance Guide

## 1. App Metadata

### English
- **App Name**: Hagzy · Instant Bookings in Egypt
- **Subtitle**: Book Padel, PS5, Barber & Sports
- **Short Description**: Discover and instantly book padel courts, gaming lounges, barbershops, and sports venues across Egypt with zero wait time.
- **Full Description**:
  Hagzy (حجزي) is Egypt's premier multi-vertical real-time booking app. 
  Whether you're looking for tournament padel courts in New Cairo, soundproof PS5 gaming lounges in Maadi, or VIP barbershops in Kafr El Sheikh, Hagzy connects you directly with top venues.

  **Why choose Hagzy?**
  - **Instant Booking**: Real-time slot availability — book in under 15 seconds.
  - **Zero Waiting**: Secure your spot instantly without tedious WhatsApp messaging back and forth.
  - **Easy Payment**: Pay securely with InstaPay, Vodafone Cash, or directly with your Hagzy Wallet.
  - **Bilingual Experience**: Built natively from the ground up in Arabic and English with full RTL support.
  - **Transparent Pricing**: Clear deposits, upfront rates, and zero hidden fees.

### Arabic (العربية)
- **اسم التطبيق**: حجزي · حجز فوري للملاعب والأنشطة
- **العنوان الفرعي**: احجز بادل، بلايستيشن، صالونات حلاقة
- **الوصف المختصر**: التطبيق الأول في مصر لحجز ملاعب البادل، غرف البلايستيشن، وصالونات الحلاقة فورياً وبدون انتظار.
- **الوصف الكامل**:
  تطبيق "حجزي" هو وسيلتك الأسرع والأسهل لحجز أماكنك المفضلة في كل محافظات مصر.
  سواء كنت تبحث عن ملعب بادل مجهز في التجمع، غرفة VIP بلايستيشن في المعادي، أو صالون حلاقة رجالي راقي في كفر الشيخ، حجزي يوفر لك حجزاً فورياً ومؤكداً.

  **مميزات حجزي:**
  - **تأكيد فوري**: جدول المواعيد متاح لحظياً ومحدث مباشرة من المكان.
  - **بدون انتظار**: احجز في أقل من ١٥ ثانية دون الحاجة للانتظار على واتساب.
  - **دفع سهل وسريع**: ادفع العربون بسهولة عبر إنستاباي، فودافون كاش، أو محفظة حجزي.
  - **واجهة عربية أصيلة**: تصميم مريح يدعم اللغة العربية بالكامل وبخطوط واضحة.
  - **شفافية كاملة**: تفاصيل الأسعار والعربون واضحة بالكامل قبل الحجز.

---

## 2. Store URLs & Legal Compliance

- **Privacy Policy**: `https://hagzy-booking.web.app/privacy.html`
- **Terms of Service**: `https://hagzy-booking.web.app/terms.html`
- **In-App Account Deletion**: Profile Tab → Delete Account (permanently removes personal data while retaining cryptographic financial audit records as required by Egyptian accounting standards).
- **Web Account Deletion URL**: `https://hagzy-booking.web.app/delete-account.html`

---

## 3. Google Play Data Safety Declarations

| Data Type | Collected | Purpose | Shared with 3rd Parties? | Ephemeral / Stored |
| :--- | :--- | :--- | :--- | :--- |
| **Name** | Yes (Optional) | App functionality & Personalization | No | Stored (deleted on request) |
| **Phone Number** | Yes (Required) | Account management, Authentication, Booking confirmations | No | Stored (deleted on request) |
| **Approximate Location** | Yes (Optional) | Showing nearest venues & GPS search | No | Ephemeral (never tracked in background) |
| **Financial / Payment Info**| Yes (Reference IDs) | Verifying deposits & transaction tracking | No | Retained for accounting compliance |

---

## 4. Apple App Store Privacy Manifest (`PrivacyInfo.xcprivacy`)

- `NSPrivacyTracking`: `false` (No third-party cross-site ad tracking)
- `NSPrivacyCollectedDataTypes`: None shared with third parties
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPICategoryUserDefaults`: Used exclusively to persist user preferences (`kDarkMode`, `kLanguage`, `kCustomerProfile`) locally on-device (`CA92.1`).

---

## 5. Android Payment Gateway App (Sideloaded / Merchant Only)

- The Android Payment Gateway app (`android_payment_gateway`) is **strictly an internal, owner-only companion tool**.
- It is distributed exclusively via private sideloading/APK to dedicated cashier devices.
- It authenticates with the Hagzy server using an encrypted HMAC-SHA256 signature (`x-signature`, `x-timestamp`).
- It is **never published to Google Play or distributed to customers**.

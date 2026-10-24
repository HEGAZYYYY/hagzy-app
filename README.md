<p align="center">
  <img src="assets/hagzy_logo.svg" alt="Hagzy Logo" width="108" height="108" />
</p>

<h1 align="center">Hagzy · حجزي</h1>

<p align="center">
  <strong>Smart Instant Bookings in Egypt · Sports, Salons & Spaces</strong><br/>
  <em>منصة الحجز الفوري وإدارة الأماكن الذكية في مصر · ملاعب، صالونات، وصالات ألعاب</em>
</p>

<p align="center">
  <a href="https://github.com/HEXXXXY/hagzy-app/releases/latest"><img src="https://img.shields.io/badge/Release-v1.0.0-059669?style=for-the-badge&logo=github" alt="Latest Release" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter" alt="Flutter" /></a>
  <a href="https://github.com/HEXXXXY/hagzy-app/releases/latest"><img src="https://img.shields.io/badge/iOS-IPA%20Available-000000?style=for-the-badge&logo=apple" alt="iOS IPA" /></a>
  <a href="https://github.com/HEXXXXY/hagzy-app/releases/latest"><img src="https://img.shields.io/badge/Android-APK%20Available-3DDC84?style=for-the-badge&logo=android" alt="Android APK" /></a>
  <a href="https://hagzy-api.onrender.com"><img src="https://img.shields.io/badge/Web-Live%20App-059669?style=for-the-badge&logo=googlechrome" alt="Web App" /></a>
</p>

---

## 📖 App Overview & Bio

**Hagzy (حجزي)** is a unified, multi-vertical reservation ecosystem and venue-management platform tailored specifically for the Egyptian market. 

Finding and booking football pitches, padel courts, barbershops, or private gaming lounges in Egypt has traditionally meant endless phone calls, unconfirmed WhatsApp voice notes, and manual money transfers with no hold guarantee. Hagzy transforms this experience into a seamless, modern mobile application:

* **⚡ 15-Minute Instant Hold**: Customers lock their preferred slot instantly with zero conflict or double-booking.
* **💳 Egyptian Payment Infrastructure**: Direct checkout with Paymob (Visa, Mastercard, Meeza, and Mobile Wallets like Vodafone Cash, Orange, Etisalat, WE), FawryPay service codes, and manual InstaPay transfer verification.
* **🤖 WhatsApp AI Concierge**: Built-in assistant bot to guide bookings, verify references, and provide customer support.
* **📍 All 27 Governorates**: Searchable venue discovery across Cairo, Giza, Alexandria, Dakahlia, Red Sea, and nationwide.
* **🏢 Venue Owner POS & Operations**: Dedicated venue-management mode with live timeline, revenue analytics, staff roles, and deposit verification.

---

## 📱 Download & Install

Download the pre-compiled, production-ready apps directly:

| Platform | Download Link | File Size | Recommended Installation |
| :--- | :--- | :--- | :--- |
| **🍎 iPhone / iPad** | [**Download `Hagzy.ipa`**](https://github.com/HEXXXXY/hagzy-app/releases/download/v1.0.0/Hagzy.ipa) | `~7.8 MB` | **1-minute install** using [Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/) (No jailbreak needed) |
| **🤖 Android** | [**Download `Hagzy.apk`**](https://github.com/HEXXXXY/hagzy-app/releases/download/v1.0.0/Hagzy.apk) | `~25.5 MB` | **Direct 1-tap install** on any Android device |
| **🌐 Web Application** | [**Launch Web Client**](https://hagzy-api.onrender.com) | — | Instant access in any mobile or desktop web browser |

> [!TIP]
> All build artifacts and previous versions are also archived under [**GitHub Releases**](https://github.com/HEXXXXY/hagzy-app/releases) and [**GitHub Actions**](https://github.com/HEXXXXY/hagzy-app/actions).

### 🍎 How to Install on iPhone (iOS)

1. **Via Sideloadly (Easiest on Windows & Mac — 1 minute)**:
   - Download free [Sideloadly](https://sideloadly.io/).
   - Connect your iPhone to your PC with a USB cable.
   - Drag & drop [`Hagzy.ipa`](https://github.com/HEXXXXY/hagzy-app/releases/download/v1.0.0/Hagzy.ipa) into Sideloadly.
   - Enter your Apple ID and click **Start**.
   - On your iPhone, go to **Settings → General → VPN & Device Management**, tap your Apple ID and tap **Trust**.
   - The Hagzy app is ready on your home screen!

2. **Via AltStore**:
   - Open AltStore on your iPhone, go to the **My Apps** tab, tap **`+`**, and select `Hagzy.ipa`.

3. **Via TrollStore / Scarlet / Esign**:
   - Direct 1-tap installation if your device supports on-device IPA signing.

---

## ✨ Key Features

### 🇪🇬 Multi-Vertical Coverage
- **Sports & Courts**: Padel tennis, 5-a-side football pitches, and basketball courts with split-payment support.
- **Hair & Beauty**: Barbershops, styling salons, grooming packages, and chair reservations.
- **Gaming & Tables**: PS5 VIP rooms, billiards, snooker, and ping pong lounges.

### 💳 Complete Egyptian Payment Gateway Integration
- **Paymob Unified Checkout**: Seamless card and wallet checkout. Includes automated sandbox mode for testing without missing terminal ID errors.
- **FawryPay**: Instant 10-digit reference code generation (service code 78890) payable at any Fawry kiosk or myFawry app.
- **InstaPay & Vodafone Cash**: 1-tap payment proof submission that extends holds and routes directly to the venue owner POS for instant confirmation.
- **Split Payment**: Split pitch fees among teammates (e.g. 4 padel players or 10 football players) while guaranteeing the venue's required deposit.

### 🌐 Bilingual with Native RTL Experience
- Full right-to-left (RTL) mirroring in Arabic (`العربية`) and clean LTR in English (`English`).
- Cairo typography and Egyptian localized terminology across all flows.

### 🏢 Dual-App Architecture (Single Codebase)
- **Customer App**: Clean discovery, search, governorate filtering, slot selection, and digital booking passes.
- **Venue Owner App**: Activated with `--dart-define=HAGZY_ADMIN_APP=true`. Features:
  - Visual calendar timeline with status indicators.
  - Revenue summaries, completed booking totals, and pending deposits.
  - Venue profile editor with image galleries and pricing configuration.
  - Granular staff roles (owner vs. manager).

---

## 🚀 Local Development

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.2.0 or higher)
- Chrome (for web testing) or an Android/iOS emulator

### 1. Clone & Install Dependencies
```bash
git clone https://github.com/HEXXXXY/hagzy-app.git
cd hagzy-app
flutter pub get
```

### 2. Run Customer App
```bash
# Web
flutter run -d chrome

# Android / iOS
flutter run
```

### 3. Run Venue-Owner App
```bash
flutter run --dart-define=HAGZY_ADMIN_APP=true
```

### 4. Connect to Backend API
To sync reservations with the [Hagzy Backend API](https://github.com/HEXXXXY/hagzy-backend):
```bash
flutter run --dart-define=HAGZY_API_URL=http://localhost:3000
```

---

## 🧪 Automated Testing

Both repositories maintain 100% passing test suites:

```bash
# Run all Flutter widget & unit tests (15/15 passing)
flutter test

# Run static analysis (0 warnings / 0 errors)
flutter analyze
```

---

## 🤝 Repositories & Architecture

* **Flutter Mobile & Web Client**: [HEXXXXY/hagzy-app](https://github.com/HEXXXXY/hagzy-app)
* **Backend API & PostgreSQL Store**: [HEXXXXY/hagzy-backend](https://github.com/HEXXXXY/hagzy-backend)

---

## 📄 License

Proprietary — © Hagzy Egypt. All rights reserved.

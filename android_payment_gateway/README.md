# ⚡ Hagzy Payment Gateway (بوابة مدفوعات حجزي)

<div align="center">
  <img src="app/src/main/res/drawable/hagzy_payment_logo.png" alt="Hagzy Payment Gateway Logo" width="128" height="128" style="border-radius: 28px;" />
  <br />
  <h3>Automated Egyptian Mobile Wallet & InstaPay Listener</h3>
  <p>
    <a href="https://github.com/HEGAZYYYY/hagzy-payment-gateway/raw/main/release/HagzyPaymentGateway.apk">
      <img src="https://img.shields.io/badge/Download-HagzyPaymentGateway.apk-059669?style=for-the-badge&logo=android&logoColor=white" alt="Download APK" />
    </a>
  </p>
</div>

> **Dedicated Android Payment Listener & Webhook Relay for Hagzy Booking Platform**  
> Automatically captures peer-to-peer (P2P) Egyptian wallet transactions (Vodafone Cash, InstaPay, Orange Money, Etisalat Cash, WE Pay) and confirms bookings in real-time with zero manual receipt uploads.

---

## 📥 Direct Download (Ready-to-Install APK)

The production-ready signed APK is available for immediate download:

| Download Link | Description |
| :--- | :--- |
| [**Download HagzyPaymentGateway.apk (Direct)**](https://github.com/HEGAZYYYY/hagzy-payment-gateway/raw/main/release/HagzyPaymentGateway.apk) | Direct raw download from the repository |
| [**GitHub Releases (Latest)**](https://github.com/HEGAZYYYY/hagzy-payment-gateway/releases/latest/download/HagzyPaymentGateway.apk) | Automated CI/CD release build |

---

## 🎨 New Brand Identity & Icon

The application launcher icon features the official **Hagzy emerald green** gradient and iconic **H bridge emblem**, accented with a **glowing golden/cyan contactless payment NFC motif** signifying automated real-time payment capture.

Icons are pre-rendered across all Android densities (`mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`) with adaptive circle and squircle masks for full Android 8.0 - Android 15 compatibility.

---

## 📌 Architecture & How It Works

```text
[Customer initiates booking]
       │
       ▼
[Amount with piaster disambiguation: e.g. 150.14 EGP]
       │
       ▼
[Customer transfers via Vodafone Cash or InstaPay]
       │
       ▼
[Inbound SMS / Push Notification on Android Gateway Phone]
       │
       ▼
[Hagzy Payment Gateway: parses amount, reference, sender/receiver]
       │
       ▼
[Cryptographic HMAC-SHA256 signature generated]
       │
       ▼
[POST dispatched to /api/payments/listener/webhook]
       │
       ▼
[Hagzy Backend auto-confirms booking instantaneously]
```

### Key Capabilities
- **Vodafone Cash & Telco Wallets**: Broadcast SMS receiver (`WalletSmsReceiver`) with regex disambiguation for Arabic & English SMS formats.
- **InstaPay Notifications**: Real-time push notification listener (`InstaPayNotificationListenerService`) capturing transaction alerts directly from the InstaPay app.
- **Piaster Disambiguation**: Deterministic matching of fractional amounts (e.g., `100.14 EGP`) to unique customer booking holds.
- **Cryptographic Security**: Every webhook payload includes an `X-Signature` header computed via **HMAC-SHA256** using a shared secret.
- **Offline Resiliency & Deduplication**:
  - SHA-256 fingerprint deduplication prevents processing duplicate SMS/notifications.
  - Room database (`PaymentEvent`) tracks sync status (`PENDING`, `SYNCED`, `FAILED`).
  - Android `WorkManager` (`PaymentRetryWorker`) handles automatic exponential backoff retry during network drops.
- **Foreground Keep-Alive Service**: `GatewayKeepAliveService` runs persistently with wake-lock protection to ensure Android OEM power management does not kill the listener.

---

## 🛠 Prerequisites & Installation

### 1. Requirements
- Android Phone (Android 8.0 Oreo / API 26 or higher).
- A SIM card with the merchant's Vodafone Cash / Telco wallet installed, or the device signed into the merchant's InstaPay account.

### 2. Required Device Permissions
Upon installing the APK:
1. **SMS Permission**: Allow `RECEIVE_SMS` and `READ_SMS`.
2. **Notification Access**: Go to **Settings > Apps > Special App Access > Notification Access** and enable **Hagzy Payment Gateway**.
3. **Battery Optimization**: Exclude Hagzy Payment Gateway from battery optimization ("Unrestricted" background usage).

---

## ⚙️ Configuration

Set your environment variables or configure via app settings / `gradle.properties`:

| Key | Description | Default |
| :--- | :--- | :--- |
| `PAYMENT_WEBHOOK_URL` | Destination webhook endpoint on Hagzy API | `https://qgimngblsrfgzavuxpde.supabase.co/functions/v1/hagzy-api/api/payments/webhook` |
| `PAYMENT_WEBHOOK_SECRET` | HMAC-SHA256 secret shared with Hagzy server | Injected via build config or app settings |

---

## 🚀 Building & Releasing Locally

```powershell
# Set JDK 17
$env:JAVA_HOME = "C:\Hagzy\tools\jdk-17.0.14+7"

# Build debug APK
./gradlew assembleDebug

# Build release APK
./gradlew assembleRelease
```

---

## 🧪 Running Unit Tests

```powershell
$env:JAVA_HOME = "C:\Hagzy\tools\jdk-17.0.14+7"
./gradlew test
```

---

## 📂 Project Structure

```text
app/src/main/
├── AndroidManifest.xml
├── java/com/hagzy/paymentgateway/
│   ├── GatewayApplication.kt             # Application init & service kickstart
│   ├── data/
│   │   ├── local/
│   │   │   ├── GatewayConfig.kt          # SharedPreferences configuration
│   │   │   ├── GatewayDatabase.kt        # Room DB
│   │   │   └── PaymentEventDao.kt        # Payment event queries
│   │   └── model/
│   │       └── PaymentEvent.kt           # Room entity (provider, amount, ref, hash)
│   ├── network/
│   │   ├── PaymentEventPipeline.kt       # Event ingestion & pipeline orchestration
│   │   └── WebhookDispatcher.kt          # OkHttp client & HMAC-SHA256 signing
│   ├── receiver/
│   │   └── WalletSmsReceiver.kt          # Telephony SMS broadcast listener
│   ├── service/
│   │   ├── GatewayKeepAliveService.kt    # Foreground service with sticky notification
│   │   └── InstaPayNotificationListenerService.kt # Notification listener
│   ├── ui/
│   │   └── MainActivity.kt               # Diagnostics dashboard & manual resync
│   ├── util/
│   │   └── PaymentTextParser.kt          # Regex parser for Egyptian wallets & InstaPay
│   └── worker/
│       └── PaymentRetryWorker.kt         # WorkManager periodic exponential backoff
└── res/
    ├── drawable/                         # Vectors, logos, backgrounds
    ├── layout/                           # UI layouts
    ├── mipmap-mdpi/                      # 48x48 launcher & round icons
    ├── mipmap-hdpi/                      # 72x72 launcher & round icons
    ├── mipmap-xhdpi/                     # 96x96 launcher & round icons
    ├── mipmap-xxhdpi/                    # 144x144 launcher & round icons
    ├── mipmap-xxxhdpi/                   # 192x192 launcher & round icons
    └── values/                           # Strings, colors, styles
```

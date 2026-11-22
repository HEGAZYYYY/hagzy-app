# ⚡ Hagzy Payment Gateway (بوابة مدفوعات حجزي)

> **Dedicated Android Payment Listener & Webhook Relay for Hagzy Booking Platform**  
> Automatically captures peer-to-peer (P2P) Egyptian wallet transactions (Vodafone Cash, InstaPay, Orange Money, Etisalat Cash, WE Pay) and confirms bookings in real-time with zero manual receipt uploads.

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

## 🚀 Building & Releasing

### Build Debug APK
```bash
./gradlew assembleDebug
```
Output: `app/build/outputs/apk/debug/app-debug.apk`

### Build Release APK
```bash
./gradlew assembleRelease
```
Output: `app/build/outputs/apk/release/app-release-unsigned.apk`

---

## 🧪 Running Unit Tests

The test suite validates parsing across all Egyptian wallet formats (Arabic and English SMS, InstaPay notification formats, thousands separators, and piaster fractions):

```bash
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
    ├── layout/                           # UI layouts
    └── values/                           # Strings, colors, styles
```

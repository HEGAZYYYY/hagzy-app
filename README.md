# Hagzy (حجزي)

Hagzy has separate customer and venue-owner builds from the same Flutter
project. The customer build opens directly to venue discovery and never displays
owner sign-in or management controls. Build the owner app with
`--dart-define=HAGZY_ADMIN_APP=true`.
The owner app has Explore, My Bookings, Manage Venues (with a POS timeline
and Revenue & Analytics switcher), and Payment Settings. The customer app has
only Explore and My Bookings.

The customer interface supports English and Arabic with right-to-left layout,
language-specific Hagzy branding, saved customer name/phone profile, favorites,
venue details & verified reviews, QR booking passes, WhatsApp squad invites,
and a searchable selector for all 27 Egyptian governorates.

## Run a local preview

```powershell
cd C:\Hagzy\hagzy_app
flutter pub get
flutter run
```

### Open the prototype on a phone over Wi-Fi

Connect the computer and phone to the same trusted Wi-Fi, then run:

```powershell
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5176
```

Open `http://<computer-Wi-Fi-IP>:5176` on the phone. If Windows Firewall asks,
allow access only on your private network. This is a local prototype, not a
public deployment; local-preview venues and bookings save separately on each
device.

Without an API URL, the app runs in **local preview** mode. Preview venues and
reservations stay on this device and are not visible to other users.
To add or update the editable Nader El Khawaga sample salon in the owner
preview, run:

```powershell
flutter run --dart-define=HAGZY_ADMIN_APP=true --dart-define=HAGZY_SEED_NADER_SALON=true
```

## Run the separate venue-owner app

```powershell
flutter run --dart-define=HAGZY_ADMIN_APP=true
```

This build opens directly to owner sign-in (or local preview without a backend).
Do not distribute a preview build as the production owner app.

## Connect shared venue and reservation data

The Express/PostgreSQL API is in `C:\src\hagzy-backend`. Configure and start it
using [its README](../../src/hagzy-backend/README.md), then run Flutter with the
API URL:

```powershell
flutter run --dart-define=HAGZY_API_URL=http://localhost:3000
```

To configure both app modes, pass both compile-time flags:

```powershell
flutter run --dart-define=HAGZY_API_URL=http://localhost:3000 --dart-define=HAGZY_ADMIN_APP=true
```

## Payments, security, and reservation status

- Customer reservations require only a name and phone number; the app remembers
  them on the device for faster repeat bookings.
- Before payment, the deposit sheet clearly shows the cancellation policy (free
  cancellation or reschedule up to 6 hours before the slot; within 6 hours the
  deposit is retained).
- Split payments (`splitCount = 4` or `10`) always charge at least the venue's
  required deposit (`max(deposit, share)`).
- **Paymob Unified Checkout**: initiated by `/api/bookings/:id/paymob-intention`
  using `bookings.due_now` and `extras.booking_id`. Raw card numbers and CVVs
  never touch the Hagzy server. Only the HMAC-SHA512 verified Paymob webhook
  (`POST /api/payments/paymob/callback`, which also verifies `amount_cents`)
  marks a booking `confirmed` and `paid`.
- **FawryPay**: `/api/bookings/:id/fawry-reference` generates a Fawry reference
  code, and `POST /api/payments/fawry/callback` verifies Fawry's SHA-256
  `messageSignature` and paid amount (`>= due_now`) before confirming.
- **InstaPay & Vodafone Cash**: customers submit their transfer reference via
  `/api/bookings/:id/payment-proof` (extending the hold while awaiting owner
  verification in the POS timeline).
- **Expired Holds & Paid-After-Expiry Protection**: expired holds are marked
  `status = 'expired'` rather than deleted from the database. If a payment
  webhook arrives after a hold expires, the server automatically re-confirms
  the booking if the slot is still free, or records `paidAfterExpiry: true` /
  `refundQueued: true` if another booking took the slot.
- **Phone OTP Verification**: cross-device booking lookups (`GET /api/bookings?phone=`)
  require a verified 6-digit OTP (`/api/auth/customer-otp/request` and
  `/api/auth/customer-otp/verify`).

# Hagzy (حجزي)

Hagzy has separate customer and venue-owner builds from the same Flutter
project. The customer build opens directly to venue discovery and never displays
owner sign-in or management controls. Build the owner app with
`--dart-define=HAGZY_ADMIN_APP=true`.
The owner app has Explore, My Bookings, Manage Venues (with a POS timeline
switcher), and Payment Settings. The customer app has only Explore and My
Bookings.

The customer interface supports English and Arabic with right-to-left layout,
language-specific Hagzy branding, and a searchable selector for all 27 Egyptian
governorates.

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

Open `http://<computer-Wi-Fi-IP>:5176` on the phone (this computer's current
Wi-Fi address is `192.168.100.9`). If Windows Firewall asks, allow access only
on your private network. This is a local prototype, not a public deployment;
local-preview venues and bookings save separately on each device. The Hagzy
logo appears in the app header, browser tab, and add-to-home-screen icon.

Without an API URL, the app runs in **local preview** mode. Preview venues and
reservations stay on this device and are not visible to other users.
To add or update the editable Nader EL Khawaga sample salon in the owner
preview, run:

```powershell
flutter run --dart-define=HAGZY_ADMIN_APP=true --dart-define=HAGZY_SEED_NADER_SALON=true
```

The import merges an existing salon with the same name and area rather than
creating a duplicate. It uses the selected 30% deposit and unverified
indicative service prices, and saves only to local preview storage; confirm
rates with the salon before publishing a shared listing.

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

For Android emulators use `http://10.0.2.2:3000`; a physical phone needs the
computer's reachable LAN address. Production builds must use an HTTPS API URL.
Admin sessions are held in memory and are cleared when leaving the admin
experience.

## Payments and reservation status

- Customer reservations require only a name and phone number; no email address
  is requested.
- The deposit screen can open a prefilled WhatsApp message to Hagzy at
  `+201024129393`. Meta Cloud API chatbot replies are not active until the
  business account, webhook, and approved message template are configured.
- Paymob intention creation and hosted checkout are initiated by the backend;
  Paymob secret keys are not entered or stored in the Flutter app.
- A checkout or payment screenshot is **not** proof that a reservation is paid.
  Until verified Paymob callback handling is deployed, reservations remain
  pending/unpaid.
- Fawry is not connected to the shared backend yet.
- InstaPay transfers require manual instructions and verification.
- WhatsApp chatbot confirmations are not connected yet. Do not treat a chat,
  message, or customer claim as proof of deposit or a confirmed reservation.
- Reservations in shared mode are protected from overlapping active bookings
  by a PostgreSQL exclusion constraint. Unpaid holds expire after 15 minutes.
Customer reservation history is stored on the current device; customer accounts
and cross-device customer history are not implemented yet. Admins can view
shared reservations in the POS timeline.
Expired unpaid holds are removed from local booking history and are periodically
deleted by the shared backend; they no longer remain as expired bookings.

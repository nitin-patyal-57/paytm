# FuelPay — BLE Fuel Payment Demo

A two-tablet Android demo of fuel-station payments: the **customer app**
selects fuel, creates a transaction, and hands it to the **pump app** over
Bluetooth Low Energy; the pump attendant accepts, shows a demo payment QR,
simulates success/failure, and the customer sees the result (followed by a
one-time 5-second advertisement on success). A small **Node.js backend**
records transactions and is the only component allowed to finalise payment
outcomes.

> Demo build — payments are simulated. Not affiliated with any real payment
> brand. No real money moves.

## Repository layout

| Path | What it is |
|---|---|
| `apps/customer/` | Android tablet app — BLE **central**, transaction QR, waiting/result/ad screens |
| `apps/pump/` | Android tablet app — BLE **peripheral** (GATT server + advertising), accept/reject, demo payment QR |
| `packages/fuelpay_core/` | Shared Dart package: models, state machine, BLE protocol (framing/messages/UUIDs), validators, backend client, local store, design system |
| `backend/` | Express + PostgreSQL (memory fallback) REST API |
| `docs/` | Architecture and Bluetooth protocol documentation |

## Prerequisites

- Flutter 3.47.x (Dart 3.13+) with Android toolchain (SDK 35/36, JDK 17)
- Node.js 18+ (22 tested)
- PostgreSQL 14+ *(optional — the backend falls back to an in-memory store)*
- Two Android tablets (or emulator + device) with BLE

## Backend

```bash
cd backend
npm install
cp .env.example .env        # adjust DATABASE_URL / PORT as needed
node db/migrate.js          # creates tables when PostgreSQL is configured
npm start                   # serves http://0.0.0.0:3000
npm test                    # 31 unit/integration tests
```

Key endpoints:

- `POST /api/transactions` — create (validated: `FP\d{6,16}` id, ₹100–10,000)
- `POST /api/transactions/:id/status` — validated state transitions
  (**payment outcomes are rejected with `403 OUTCOME_NOT_ALLOWED`**)
- `POST /api/demo-payments/:id/simulate` — the **only** route that may set
  `PAYMENT_SUCCESS` / `PAYMENT_FAILED` (idempotent for identical replays)
- `GET /api/transactions`, `GET /api/health`, `GET /api/payment-provider`

## Apps

```bash
cd apps/pump && flutter pub get && flutter run     # pump tablet first
cd apps/customer && flutter pub get && flutter run  # then customer tablet
```

Debug APKs:

```bash
cd apps/customer && flutter build apk --debug
cd apps/pump     && flutter build apk --debug
```

Both apps default to `http://192.168.1.5:3000`. Set the real LAN IP of your
machine via **⚙ (settings) on either app's home/dashboard screen** — tablets
must use the host's LAN address, not `localhost`. The backend is optional:
with it unreachable, each tablet keeps working from local storage and queues
replication calls for later.

## Demo walkthrough

1. **Pump tablet** opens → it requests Bluetooth permission and starts
   advertising; note the device code, e.g. `FP-7A3C`.
2. **Customer tablet** → pick **Petrol/Diesel** → **Enter amount**
   (₹100–₹10,000) → **Find a pump**.
3. Customer scans → taps **Connect** on *FuelPay Pump FP-7A3C* (BLE
   handshake `HELLO`/`HELLO_ACK`).
4. The **transaction QR + ID** screen appears; `PAYMENT_REQUEST` is written
   to the pump's GATT command characteristic (chunked frames).
5. Pump shows **Incoming payment request** → attendant taps **Accept**
   (`REQUEST_RECEIVED` → `ACCEPTED` → `QR_READY` → `PAYMENT_PENDING`).
6. Customer moves to the **waiting** screen with a live progress timeline.
7. Pump's **Demo payment** screen shows the payment QR + **Success/Failure**
   simulation buttons (explicitly demo, server-side simulation).
8. Outcome travels back over BLE (`PAYMENT_STATUS`) → customer lands on the
   **result** screen.
9. On **success only**, a **5-second advertisement** plays once per
   transaction (guarded by a persistent marker), then a new transaction can
   start. Failure/cancel go straight back to home.
10. If the backend was reachable, `GET /api/transactions` shows the same
    final state (outcomes replicated exclusively through the demo-payment
    endpoint).

## Verification status

| Suite | Result |
|---|---|
| `backend`: `npm test` | **31/31 pass** |
| `packages/fuelpay_core`: `flutter test` | **50/50 pass** |
| `apps/customer`: `flutter analyze` + `flutter test` | **clean / 2 pass** |
| `apps/pump`: `flutter analyze` + `flutter test` | **clean / 2 pass** |

Physical two-tablet BLE behaviour has **not** been exercised in this
environment and must be validated on hardware.

## Documentation

- [docs/architecture.md](docs/architecture.md) — components, state machine,
  offline strategy, security rules
- [docs/bluetooth-protocol.md](docs/bluetooth-protocol.md) — UUIDs, GATT
  layout, framing, message catalogue, platform gotchas

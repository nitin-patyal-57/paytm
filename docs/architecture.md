# FuelPay architecture

## Components

```
┌──────────────────────┐        BLE (GATT + ADV)        ┌──────────────────────┐
│   CUSTOMER tablet    │ ◄───────────────────────────── │    PUMP tablet       │
│  apps/customer       │   command char:  customer→pump │  apps/pump           │
│  role: CENTRAL       │   response char: pump→customer │  role: PERIPHERAL    │
│  scan · connect ·    │   (framed, notified, deduped)  │  advertise · GATT    │
│  write requests      │                                │  server · decisions  │
└──────────┬───────────┘                                └──────────┬───────────┘
           │  REST (best effort, queued when offline)              │
           ▼                                                       ▼
        ┌──────────────────────────────────────────────────────────────┐
        │               backend/  Express + PostgreSQL                │
        │  transaction records · state-machine validation · events     │
        │  demo-payment endpoint = ONLY source of PAYMENT_SUCCESS/FAIL │
        └──────────────────────────────────────────────────────────────┘
```

Shared Dart code lives in `packages/fuelpay_core` so both apps use the same
models, state machine, BLE protocol, validators, backend client, local store
and design system.

## Transaction state machine

Mirrored in `backend/src/stateMachine.js` and
`packages/fuelpay_core/.../transaction_state_machine.dart` — keep in sync.

```
CREATED ─► REQUEST_SENT ─► REQUEST_RECEIVED ─► ACCEPTED ─► QR_READY ─► PAYMENT_PENDING
   │            │                │                │           │            │
   └────────────┴────────────────┴───► CANCELLED ◄─┴───────────┴────────────┘
   └────────────┴────────────────┴───► EXPIRED   ◄─┴───────────┴────────────┘

PAYMENT_PENDING ─► PAYMENT_SUCCESS | PAYMENT_FAILED        (terminal)
CANCELLED | EXPIRED | PAYMENT_SUCCESS | PAYMENT_FAILED     (terminal — no exits)
```

Who moves the transaction:

| Step | Owner | Over BLE | To backend |
|---|---|---|---|
| CREATED → REQUEST_SENT | customer (after write succeeds) | — | `POST /status` |
| → REQUEST_RECEIVED | pump (on `PAYMENT_REQUEST`) | `REQUEST_RECEIVED` ack | `POST /status` |
| → ACCEPTED | pump attendant | `REQUEST_DECISION(ACCEPTED)` | `POST /status` |
| → QR_READY → PAYMENT_PENDING | pump (on accept) | `PAYMENT_STATUS(PAYMENT_PENDING)` | `POST /status` |
| → PAYMENT_SUCCESS / FAILED | **backend demo-payment endpoint only** | `PAYMENT_STATUS` | `POST /demo-payments/:id/simulate` |
| → CANCELLED | either side | `CANCEL_TRANSACTION` / decision(REJECTED) | `POST /status` (outcomes excluded) |

Catch-up: receivers apply `TransactionStateMachine.path(from, to)` (BFS over
legal edges) so a dropped intermediate notification fast-forwards the local
copy instead of being rejected (`path()` in the shared state machine).

## Authority & offline strategy

- **Local store is authoritative for the live flow.** Each tablet persists
  every transaction in SharedPreferences (`LocalTransactionStore`) and
  recovers the in-flight one after a restart (resume banner / prompt).
- **Backend replication is best effort.** Every call that fails with a
  network error is queued (`SyncJob`) and flushed at startup and
  opportunistically later; 4xx responses are dropped (duplicate/diverged).
- **Payment outcomes are special.** The apps never POST
  `PAYMENT_SUCCESS`/`PAYMENT_FAILED` to `/api/transactions/:id/status`
  (the server would return `403 OUTCOME_NOT_ALLOWED`). Outcomes enter the
  backend only via `POST /api/demo-payments/:id/simulate`; if the pump is
  offline, the local fallback (`LocalDemoPayment`, byte-for-byte rules of
  `backend/src/services/paymentService.js`) applies the outcome locally and
  queues the simulate call for later. Backend→pump `409 NOT_PAYABLE` during
  a late flush is healed by replaying the pump's state-machine path up to
  `PAYMENT_PENDING` before retrying (`_catchUpBackend`).
- **Duplicate delivery** on the BLE link is dropped by
  `MessageDeduplicator` (content-keyed, `messageId` excluded), which makes
  retries/reconnect replays idempotent. `HELLO`/`HELLO_ACK` are exempt so
  the handshake can repeat.

## Security rules (demo scope)

- Amount: integer rupees **100–10,000** (`AmountValidator`, enforced in UI,
  protocol decode and backend validation).
- Transaction IDs: `^FP\d{6,16}$`, generated with `Random.secure()` and
  collision-checked against local storage.
- **Identity matching**: any BLE message referencing a transaction is
  checked against the local record (`matchesIdentity`: id + amount + fuel +
  currency) — tampered/replayed cross-transaction messages are rejected.
- **Strict decode**: unknown message types, unsupported protocol versions
  and malformed fields raise `ProtocolException`; nothing is executed
  because it arrived over BLE.
- The customer QR contains only `{v, kind, mode, tx, fuel, amt, cur}` — no
  credentials, tokens or personal data.
- Backend errors never leak internals; validation failures are structured
  (`{error: {code, message, details}}`).
- Demo vs production: everything runs `mode=DEMO` with provider `DEMO`; the
  production provider stub returns `501`.

## UI navigation model

- **Customer** — single root widget renders `FlowStage`
  (`splash → home → amount → scan → qr → waiting → result → ad → home`);
  the stage machine makes back/cancel paths explicit and restart recovery
  trivial (any non-terminal stored transaction re-enters `waiting`).
- **Pump** — dashboard is the only root route; `RequestScreen` and
  `PaymentScreen` are pushed imperatively (auto-prompt on new request,
  `pushReplacement` accept → payment, `popUntil` on Done).

## Advertisement rule

The 5-second promo (`apps/customer/assets/ads/promo.mp4`, 1280×720, silent)
plays **only on success, only once per transaction**: a persistent marker
(`fp_ad_played_v1`, capped set keyed by transaction ID) is consulted before
play and written when it finishes/skips — restarts and duplicate successes
can never trigger a second play.

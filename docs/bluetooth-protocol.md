# FuelPay Bluetooth protocol

Version **1** (`protocolVersion: 1`). Implemented by
`packages/fuelpay_core/lib/src/protocol/` and consumed by both apps'
BLE services.

## Topology

| | Pump app | Customer app |
|---|---|---|
| Role | **Peripheral** — GATT server + advertiser | **Central** — scanner + client |
| Plugin API | `PeripheralManager` | `CentralManager` |
| Advertising | ✅ (service UUID + alias service data) | — |
| Scanning | — | ✅ (filtered by service UUID) |
| Writes | receives on command characteristic | writes command characteristic (with response) |
| Notifications | notifies response characteristic | subscribes + receives |

Single packet transport package: **`bluetooth_low_energy` 6.2.1** for both
directions (one dependency, roles verified against its source).

## Identifiers

| Item | Value |
|---|---|
| Service UUID | `0000f17e-0000-1000-8000-00805f9b34fb` (**16-bit `0xF17E`**, Bluetooth base expansion) |
| Command characteristic (central → peripheral, **write**) | `7e1d0002-a5b3-4c9e-9f26-1d2c3b4a5e6f` |
| Response characteristic (peripheral → central, **notify**) | `7e1d0003-a5b3-4c9e-9f26-1d2c3b4a5e6f` |
| Device alias (service data key = service UUID) | UTF-8 `"FP-XXXX"` (4 hex chars, e.g. `FP-7A3C`) |

### Advertising budget (31 bytes)

```
Flags (3) + Service UUID AD (4, 16-bit compressed)
        + Service Data AD (1 len + 1 type + 2 uuid + 7 alias = 11)
        = 18 bytes  ✅  fits legacy ADV_IND
```

The alias lets customers see “FuelPay Pump FP-7A3C” without touching the
tablet's **system Bluetooth name** — the pump deliberately advertises
`Advertisement(name: null)` (see gotchas).

## GATT layout

```
Service 0xF17E (primary)
├── 7e1d0002-…  properties: [write, writeWithoutResponse]  permissions: [write]
└── 7e1d0003-…  properties: [notify]                       permissions: []
```

The `bluetooth_low_energy` Android implementation **auto-injects the CCC
descriptor (0x2902)** into every characteristic it registers and handles
enable/disable writes itself, firing `characteristicNotifyStateChanged`.
No manual CCC descriptor is required or added.

## Framing

Characteristic values are limited by the negotiated ATT MTU, so logical
messages are split (`MessageFraming`):

```
byte 0     : 0x01 = FIRST, 0x02 = CONTINUATION
bytes 1..2 : total payload length, big-endian (FIRST only)
bytes 3..  : payload slice (FIRST)  |  byte 1.. payload slice (CONTINUATION)
```

- Receiver reassembles via `FrameAssembler`; malformed frames reset the
  buffer (a bad frame cannot poison the next message); partial messages
  older than 10 s are considered stale; the buffer resets on disconnect.
- **Customer → pump**: chunk = `getMaximumWriteLength(withResponse) − 3`.
- **Pump → customer**: chunk = `getMaximumNotifyLength(central) − 3`
  (MTU − 3, clamped 20…512).
- Writes are **serialized** through a future-chain on both sides (the
  platform does not multiplex concurrent writes/notifications safely).
- Declared message size > 4096 bytes is rejected (`TOO_LARGE`).

## Handshake & ordering

```
pump:  addService + startAdvertising(service UUID + alias service data)
customer: scan(serviceUUIDs=[0xF17E]) → alias from serviceData → connect
customer: discoverGATT → requestMTU(247) → ENABLE NOTIFY on response char
customer: HELLO {role:'CUSTOMER'}  ───────► (written only AFTER subscribe
pump:   ◄──── HELLO_ACK {pumpName:'FuelPay Pump FP-7A3C', mode:'DEMO'}      returns)
```

Ordering matters: notifications are a silent no-op until the CCC write
lands, so the customer subscribes (and awaits it) **before** sending
`HELLO`; the pump only ever answers after that point. Handshake timeout 8 s,
connect timeout 15 s, scan window 15 s.

## Message catalogue

JSON, UTF-8, always with `protocolVersion`, `type`, `messageId`.
Strict decode: unknown type / bad version / invalid fields →
`ProtocolException` (dropped, surfaced as a protocol error stream).

| Type | Dir | Fields (beyond envelope) | Notes |
|---|---|---|---|
| `HELLO` | C→P | `role` | handshake, **never deduplicated** |
| `HELLO_ACK` | P→C | `pumpName`, `mode` | handshake, **never deduplicated** |
| `PAYMENT_REQUEST` | C→P | `transactionId`, `fuelType`, `amount`, `currency=INR`, `mode` | amount must be 100–10 000 |
| `REQUEST_RECEIVED` | P→C | `transactionId`, `status='PENDING'`, `mode` | ack; also re-sent on retries |
| `REQUEST_DECISION` | P→C | `transactionId`, `decision=ACCEPTED\|REJECTED`, `reason?`, `mode` | pump accept/reject |
| `PAYMENT_STATUS` | P→C | `transactionId`, `status=PAYMENT_PENDING\|SUCCESS\|FAILED\|CANCELLED`, `mode`, `timestamp?` | `EXPIRED` never travels |
| `CANCEL_TRANSACTION` | C→P | `transactionId`, `reason?` | customer backs out |
| `ERROR` | P→C | `code`, `message`, `transactionId?` | e.g. `VALIDATION_MISMATCH`, `BUSY`, `NOT_DEMO` |

### Duplicate detection & retries

- `MessageDeduplicator` keys on the payload **without** `messageId`
  (content-identical retransmissions are duplicates), TTL 5 min / 128 keys.
- Because content is stable per state, **replays are safe**:
  - customer reconnect → re-sends `PAYMENT_REQUEST`; pump re-acks and
    replays its current decision/status (`_sendStateToCustomer`);
  - pump-side identical notifications a customer already processed are
    dropped there.
- Customer auto-reconnect: up to 3 attempts with 1/2/3 s backoff while a
  non-terminal transaction is on the `qr`/`waiting` stage; on reconnect the
  pending request is re-sent once.

## Android platform gotchas (verified in plugin source)

1. **`Advertisement(name: …)` calls `BluetoothAdapter.setName()`** and its
   future completes only on the `ACTION_LOCAL_NAME_CHANGED` broadcast — it
   can hang on repeat *and* renames the tablet globally. → always
   `name: null`; alias rides in service data.
2. **Serialize writes** — `writeCharacteristic`/`notifyCharacteristic` are
   chained per direction.
3. **Subscribe before HELLO** — notifications silently do nothing until CCC
   is enabled (handled by the plugin, but ordering still matters).
4. **No auto-fragmentation** — framing is mandatory (`headerOverhead = 3`).
5. **16-bit UUIDs are safe** — `UUID.short()` and `UUID.fromString()` of the
   base expansion are value-equal and both `isShort`, so advertising stays
   compressed (4 bytes) while GATT matching still works.
6. **CCC is auto-added** by the Android implementation
   (`api.dart` injects `UUID.short(0x2902)`); it also answers CCC
   read/write itself and emits `characteristicNotifyStateChanged`.

### Manifest permissions

| | Customer | Pump |
|---|---|---|
| Android 12+ | `BLUETOOTH_SCAN` (+`neverForLocation`), `BLUETOOTH_CONNECT` | `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT` |
| Android ≤ 11 | `BLUETOOTH`, `BLUETOOTH_ADMIN` (≤30), `ACCESS_FINE/COARSE_LOCATION` (≤30) | same |
| Misc | `INTERNET`, `usesCleartextTraffic` (demo LAN HTTP), BLE feature required, `minSdk 24` | same |

Permission flow: `permission_handler` first, plugin `authorize()` as
fallback, `showAppSettings()` for permanently denied states.

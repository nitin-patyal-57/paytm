/// BLE identifiers and protocol defaults shared by both apps.
///
/// Topology: the PUMP app is the BLE peripheral (GATT server + advertising);
/// the CUSTOMER app is the BLE central (scans, connects, writes requests).
/// Responses flow back via notifications.
///
/// Advertising budget note: Android legacy advertising allows only 31 bytes
/// (including the Flags block). We therefore advertise a 16-bit service UUID
/// (0xF17E → 4 bytes) plus a short device alias in service data, keeping the
/// payload safely small. The full GATT characteristics use 128-bit UUIDs.
library;

import 'dart:math';

class FuelPayBle {
  FuelPayBle._();

  /// FuelPay GATT service UUID — Bluetooth Base expansion of short 0xF17E.
  static const String serviceUuid = '0000f17e-0000-1000-8000-00805f9b34fb';

  /// Short form of [serviceUuid] (same UUID, convenient for adv filters).
  static const int serviceShortId = 0xF17E;

  /// Central -> peripheral: HELLO, PAYMENT_REQUEST, CANCEL_TRANSACTION.
  static const String commandCharacteristicUuid =
      '7e1d0002-a5b3-4c9e-9f26-1d2c3b4a5e6f';

  /// Peripheral -> central (notifications): acknowledgements, decisions,
  /// payment status updates and errors.
  static const String responseCharacteristicUuid =
      '7e1d0003-a5b3-4c9e-9f26-1d2c3b4a5e6f';

  /// Short human device alias (e.g. "FP-7A3C") carried in service data so
  /// customers can identify the right pump without touching the system-wide
  /// Bluetooth device name.
  static const String aliasPrefix = 'FP-';
  static const int aliasLength = 4;

  /// Branding prefixes.
  static const String pumpNamePrefix = 'FuelPay Pump';
  static const String customerNamePrefix = 'FuelPay Customer';
  static const String namePrefix = 'FuelPay';

  /// Protocol version emitted by these apps.
  static const int protocolVersion = 1;

  /// Versions this build understands. Incompatible peers are rejected
  /// with a clear ERROR message.
  static const List<int> supportedProtocolVersions = [1];

  /// BLE payload budget we code against (conservative even if MTU negotiates
  /// higher; framing handles anything larger anyway).
  static const int defaultChunkSize = 180;

  /// Maximum accepted reassembled message size (guards malformed input).
  static const int maxMessageBytes = 4096;

  /// A partially received message is discarded after this long.
  static const Duration fragmentTimeout = Duration(seconds: 10);

  /// Negotiated MTU we request after connecting (Android typically grants it).
  static const int requestedMtu = 247;

  /// Connection / handshake timeouts.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration handshakeTimeout = Duration(seconds: 8);
  static const Duration scanTimeout = Duration(seconds: 15);

  /// Builds a display name such as "FuelPay Pump FP-7A3C".
  static String pumpDisplayName(String alias) => '$pumpNamePrefix $alias';

  /// True when [alias] looks like a FuelPay device alias (FP-XXXX).
  static bool isValidAlias(String? alias) =>
      alias != null && RegExp(r'^FP-[0-9A-Fa-f]{4}$').hasMatch(alias);

  /// Generates a fresh random device alias such as "FP-7A3C" (persisted by
  /// the pump app so its identity stays stable across restarts).
  static String generateAlias() {
    const hex = '0123456789ABCDEF';
    final rng = Random.secure();
    final buffer = StringBuffer(aliasPrefix);
    for (var i = 0; i < aliasLength; i++) {
      buffer.write(hex[rng.nextInt(16)]);
    }
    return buffer.toString();
  }
}

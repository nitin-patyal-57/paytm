import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

/// BLE peripheral (pump) service: publishes the FuelPay GATT service,
/// advertises the device alias, accepts framed customer messages and
/// notifies responses back.
class BlePeripheralService extends ChangeNotifier {
  BlePeripheralService();

  final PeripheralManager _pm = PeripheralManager();

  final FrameAssembler _assembler = FrameAssembler();
  final MessageDeduplicator _dedupe = MessageDeduplicator();
  final StreamController<ProtocolMessage> _messages =
      StreamController<ProtocolMessage>.broadcast();
  final StreamController<ProtocolException> _protocolErrors =
      StreamController<ProtocolException>.broadcast();

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;
  StreamSubscription<CentralConnectionStateChangedEventArgs>? _connSub;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>? _writeSub;
  StreamSubscription<GATTCharacteristicNotifyStateChangedEventArgs>? _notifySub;
  Timer? _advertiseTimer;

  BluetoothLowEnergyState adapterState = BluetoothLowEnergyState.unknown;
  bool advertising = false;
  String? lastError;

  /// Short alias shown to customers, e.g. "FP-7A3C".
  String deviceCode = 'FP-0000';

  Central? connectedCentral;
  GATTCharacteristic? _commandChar;
  GATTCharacteristic? _responseChar;
  Central? _writerCentral;
  bool _notifyEnabled = false;
  Future<void> _sendChain = Future<void>.value();

  String get displayName => FuelPayBle.pumpDisplayName(deviceCode);

  bool get customerConnected => connectedCentral != null;

  /// True once the customer enabled notifications on the response char.
  /// Android drops notifies sent before this, so acks must wait for it.
  bool get customerSubscribed => _notifyEnabled && connectedCentral != null;

  /// Waits (up to [timeout]) for the customer's CCC subscription to land.
  Future<void> waitForNotifyEnabled(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!_notifyEnabled && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  bool get bluetoothReady => adapterState == BluetoothLowEnergyState.poweredOn;

  Stream<ProtocolMessage> get messages => _messages.stream;
  Stream<ProtocolException> get protocolErrors => _protocolErrors.stream;

  UUID get _serviceUuid => UUID.fromString(FuelPayBle.serviceUuid);

  Advertisement _advertisement() => Advertisement(
    serviceUUIDs: [_serviceUuid],
    serviceData: {_serviceUuid: Uint8List.fromList(utf8.encode(deviceCode))},
  );

  /// One-time setup: attach listeners (subscribe BEFORE events flow).
  Future<void> init({required String alias}) async {
    deviceCode = alias;
    _stateSub ??= _pm.stateChanged.listen((e) {
      adapterState = e.state;
      notifyListeners();
    });
    _connSub ??= _pm.connectionStateChanged.listen(_onConnectionChanged);
    _writeSub ??= _pm.characteristicWriteRequested.listen(_onWriteRequested);
    _notifySub ??= _pm.characteristicNotifyStateChanged.listen(
      _onNotifyStateChanged,
    );
    try {
      adapterState = _pm.state;
    } on Exception {
      adapterState = BluetoothLowEnergyState.unknown;
    }
    notifyListeners();
  }

  /// Requests Bluetooth runtime permissions via the plugin (ADVERTISE/CONNECT
  /// on Android 12+). Returns true when advertising is allowed.
  Future<bool> requestPermissions() async {
    try {
      if (adapterState == BluetoothLowEnergyState.unauthorized) {
        await _pm.authorize();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        adapterState = _pm.state;
      }
      notifyListeners();
      return adapterState != BluetoothLowEnergyState.unauthorized;
    } on Exception catch (e) {
      lastError = 'Permission request failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> openSystemSettings() => _pm.showAppSettings();

  // ------------------------------------------------------------ advertising

  /// Publishes the FuelPay GATT service and starts advertising with the
  /// device alias in service data (the system Bluetooth name is untouched).
  Future<bool> startAdvertising() async {
    lastError = null;
    if (adapterState == BluetoothLowEnergyState.unauthorized) {
      final granted = await requestPermissions();
      if (!granted) {
        lastError = 'Bluetooth permission is required to advertise.';
        notifyListeners();
        return false;
      }
    }
    if (adapterState == BluetoothLowEnergyState.poweredOff) {
      lastError = 'Bluetooth is turned off. Enable Bluetooth and try again.';
      notifyListeners();
      return false;
    }
    try {
      // The plugin opens its GATT server asynchronously when the adapter
      // reaches poweredOn — calling removeAllServices() before that races
      // the plugin init and throws IllegalStateException (server == null).
      if (!await _ensureGattServerReady()) {
        lastError =
            'Bluetooth is still starting up. Wait a second, then tap '
            '“Start advertising” again.';
        notifyListeners();
        return false;
      }
      final command = GATTCharacteristic.mutable(
        uuid: UUID.fromString(FuelPayBle.commandCharacteristicUuid),
        properties: const [
          GATTCharacteristicProperty.write,
          GATTCharacteristicProperty.writeWithoutResponse,
        ],
        permissions: const [GATTCharacteristicPermission.write],
        descriptors: const [],
      );
      final response = GATTCharacteristic.mutable(
        uuid: UUID.fromString(FuelPayBle.responseCharacteristicUuid),
        properties: const [GATTCharacteristicProperty.notify],
        permissions: const [],
        descriptors: const [],
      );
      final service = GATTService(
        uuid: _serviceUuid,
        isPrimary: true,
        includedServices: const [],
        characteristics: [command, response],
      );

      // Server-dependent calls can still race the plugin's async
      // openGATTServer() by a few ms right after poweredOn — retry once.
      await _removeAllServicesWithRetry();
      await _pm.addService(service);
      _commandChar = command;
      _responseChar = response;
      _assembler.reset();

      // NOTE: `name` is intentionally omitted — setting it would rename the
      // tablet's system Bluetooth adapter. The alias travels in service data.
      await _pm.startAdvertising(_advertisement());
      advertising = true;
      // Some Android stacks silently drop advertising after a while (or when
      // the tablet dozes); refresh periodically so customers keep seeing us.
      _advertiseTimer?.cancel();
      _advertiseTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (!advertising) return;
        try {
          await _pm.stopAdvertising();
          await _pm.startAdvertising(_advertisement());
        } on Exception {
          // Best effort refresh only.
        }
      });
      notifyListeners();
      return true;
    } on Exception catch (e) {
      debugPrint('startAdvertising failed: $e');
      lastError =
          'Advertising failed. Toggle Bluetooth off and on, then try again.';
      advertising = false;
      notifyListeners();
      return false;
    }
  }

  /// Waits until the adapter reports poweredOn (and gives the plugin a beat
  /// to finish opening its GATT server). Returns false on timeout.
  Future<bool> _ensureGattServerReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (true) {
      try {
        adapterState = _pm.state;
      } on Exception {
        // Plugin still initialising.
      }
      if (adapterState == BluetoothLowEnergyState.poweredOn) {
        // Let the plugin's async openGATTServer() land.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        notifyListeners();
        return true;
      }
      if (adapterState == BluetoothLowEnergyState.poweredOff ||
          adapterState == BluetoothLowEnergyState.unauthorized ||
          DateTime.now().isAfter(deadline)) {
        notifyListeners();
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      notifyListeners();
    }
  }

  /// removeAllServices() needs the plugin's GATT server; right after
  /// poweredOn that server may still be opening — retry briefly.
  Future<void> _removeAllServicesWithRetry() async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _pm.removeAllServices();
        return;
      } on Exception catch (e) {
        if (attempt >= 4) rethrow;
        debugPrint('removeAllServices attempt ${attempt + 1} failed: $e');
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<void> stopAdvertising() async {
    _advertiseTimer?.cancel();
    _advertiseTimer = null;
    if (!advertising) return;
    advertising = false;
    try {
      await _pm.stopAdvertising();
    } on Exception {
      // Already stopped.
    }
    notifyListeners();
  }

  // ---------------------------------------------------------- GATT events

  void _onConnectionChanged(CentralConnectionStateChangedEventArgs e) {
    if (e.state == ConnectionState.connected) {
      connectedCentral ??= e.central;
      notifyListeners();
      return;
    }
    if (connectedCentral == null || e.central == connectedCentral) {
      connectedCentral = null;
      _writerCentral = null;
      _notifyEnabled = false;
      _assembler.reset();
      notifyListeners();
    }
  }

  void _onNotifyStateChanged(GATTCharacteristicNotifyStateChangedEventArgs e) {
    if (e.characteristic == _responseChar) {
      _notifyEnabled = e.state;
      if (e.state) {
        // Customer enabled notifications — treat as the ready client link.
        connectedCentral = e.central;
        _assembler.reset();
        notifyListeners();
      } else if (e.central == connectedCentral) {
        connectedCentral = null;
        notifyListeners();
      }
    }
  }

  Future<void> _onWriteRequested(
    GATTCharacteristicWriteRequestedEventArgs e,
  ) async {
    final command = _commandChar;
    if (command == null || e.characteristic != command) {
      try {
        await _pm.respondWriteRequestWithError(
          e.request,
          error: GATTError.writeNotPermitted,
        );
      } on Exception {
        // Request may already be answered by the stack.
      }
      return;
    }
    // Acknowledge promptly (characteristic writes expect an ATT response).
    try {
      if (e.request.offset != 0) {
        await _pm.respondWriteRequestWithError(
          e.request,
          error: GATTError.invalidOffset,
        );
        return;
      }
      await _pm.respondWriteRequest(e.request);
    } on Exception {
      return;
    }

    // One assembler per writing central; a new writer resets the buffer.
    if (_writerCentral != e.central) {
      _writerCentral = e.central;
      _assembler.reset();
      connectedCentral ??= e.central;
    }

    try {
      final payload = _assembler.add(e.request.value);
      if (payload == null) return;
      final message = ProtocolMessage.decodeBytes(payload);
      if (message is HelloMessage || message is HelloAckMessage) {
        _messages.add(message);
        return;
      }
      if (!_dedupe.accept(message)) return;
      _messages.add(message);
    } on ProtocolException catch (e) {
      _protocolErrors.add(e);
    } on FormatException catch (e) {
      _protocolErrors.add(
        ProtocolException(
          'INVALID_FRAME',
          e.message.isEmpty ? 'bad frame' : e.message,
        ),
      );
    }
  }

  // ------------------------------------------------------------ transport

  /// Notifies [message] to the connected customer (serialized + framed).
  /// Retries transient notify failures — Android refuses notifies when the
  /// central's CCC subscription hasn't fully landed yet, which resolves
  /// itself within a few hundred ms.
  Future<void> send(ProtocolMessage message) async {
    final central = connectedCentral;
    final response = _responseChar;
    if (central == null || response == null) {
      throw StateError('Customer device is not connected');
    }
    Object? lastFailure;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (connectedCentral == null || _responseChar == null) break;
      }
      try {
        final future = _sendChain.then((_) async {
          final maxLen = await _pm.getMaximumNotifyLength(
            connectedCentral ?? central,
          );
          final chunk = (maxLen - MessageFraming.headerOverhead).clamp(
            1,
            maxLen,
          );
          final frames = MessageFraming.encode(
            Uint8List.fromList(message.encodeBytes()),
            chunkSize: chunk,
          );
          for (final frame in frames) {
            await _pm.notifyCharacteristic(
              connectedCentral ?? central,
              _responseChar ?? response,
              value: frame,
            );
          }
        });
        _sendChain = future.catchError((_) {});
        await future;
        return;
      } on Exception catch (e) {
        lastFailure = e;
        debugPrint('BLE notify attempt ${attempt + 1}/3 failed: $e');
      }
    }
    throw lastFailure is Exception
        ? lastFailure
        : StateError('Customer notify channel is unavailable');
  }

  /// Best-effort error notification — silently skipped when nobody listens.
  Future<void> sendError(
    String code,
    String message, {
    String? transactionId,
  }) async {
    if (connectedCentral == null || !advertising) return;
    try {
      await send(
        ProtocolErrorMessage(
          code: code,
          message: message,
          transactionId: transactionId,
        ),
      );
    } on Exception {
      // Customer may have just disconnected.
    }
  }

  @override
  void dispose() {
    _advertiseTimer?.cancel();
    _stateSub?.cancel();
    _connSub?.cancel();
    _writeSub?.cancel();
    _notifySub?.cancel();
    _messages.close();
    _protocolErrors.close();
    super.dispose();
  }
}

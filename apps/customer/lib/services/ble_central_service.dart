import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

/// A pump discovered during scanning.
class DiscoveredPump {
  DiscoveredPump({required this.peripheral, required this.rssi, this.alias});

  final Peripheral peripheral;
  final int rssi;
  final String? alias;

  /// Stable identity string (MAC-based UUID on Android).
  String get address => peripheral.uuid.toString();

  String get displayName => alias != null
      ? FuelPayBle.pumpDisplayName(alias!)
      : FuelPayBle.pumpNamePrefix;
}

enum BleConnectionPhase { disconnected, connecting, connected, error }

/// BLE central (customer) service: scanning, connection management,
/// framed message transport, validation and duplicate detection.
class BleCentralService extends ChangeNotifier {
  BleCentralService();

  final CentralManager _cm = CentralManager();

  final FrameAssembler _assembler = FrameAssembler();
  final MessageDeduplicator _dedupe = MessageDeduplicator();
  final StreamController<ProtocolMessage> _messages =
      StreamController<ProtocolMessage>.broadcast();
  final StreamController<ProtocolException> _protocolErrors =
      StreamController<ProtocolException>.broadcast();

  StreamSubscription<BluetoothLowEnergyStateChangedEventArgs>? _stateSub;
  StreamSubscription<DiscoveredEventArgs>? _discoveredSub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _connSub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifySub;
  Timer? _scanTimer;

  BluetoothLowEnergyState adapterState = BluetoothLowEnergyState.unknown;
  bool scanning = false;
  BleConnectionPhase phase = BleConnectionPhase.disconnected;
  String? lastError;
  String? pumpDisplayName;
  Peripheral? _connectedPeripheral;
  GATTCharacteristic? _commandChar;
  GATTCharacteristic? _responseChar;
  bool autoReconnect = false;
  int _reconnectAttempts = 0;
  bool _busyConnecting = false;
  Future<void> _sendChain = Future<void>.value();
  final Map<String, DiscoveredPump> _pumps = {};

  /// Discovered pumps keyed by device address.
  List<DiscoveredPump> get pumps {
    final list = _pumps.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  bool get authorized =>
      adapterState == BluetoothLowEnergyState.poweredOn ||
      adapterState == BluetoothLowEnergyState.unknown
  // 'unknown' can mean "not initialised yet"; authorize() decides.
  ;

  bool get bluetoothReady => adapterState == BluetoothLowEnergyState.poweredOn;

  bool get isConnected => phase == BleConnectionPhase.connected;

  Stream<ProtocolMessage> get messages => _messages.stream;
  Stream<ProtocolException> get protocolErrors => _protocolErrors.stream;

  Peripheral? get connectedPeripheral => _connectedPeripheral;

  /// One-time setup: attach listeners (subscribe BEFORE events flow).
  Future<void> init() async {
    _stateSub ??= _cm.stateChanged.listen((e) {
      adapterState = e.state;
      notifyListeners();
    });
    _connSub ??= _cm.connectionStateChanged.listen(_onConnectionChanged);
    _notifySub ??= _cm.characteristicNotified.listen(_onNotified);
    try {
      adapterState = _cm.state;
    } on Exception {
      adapterState = BluetoothLowEnergyState.unknown;
    }
    notifyListeners();
  }

  /// Requests Bluetooth runtime permissions with the plugin's exact scope.
  /// Returns true when scanning/connecting is allowed.
  Future<bool> requestPermissions() async {
    try {
      if (adapterState == BluetoothLowEnergyState.unauthorized) {
        await _cm.authorize();
        // Give the state stream a moment to publish the result.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        adapterState = _cm.state;
      }
      notifyListeners();
      return adapterState != BluetoothLowEnergyState.unauthorized;
    } on Exception catch (e) {
      lastError = 'Permission request failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> openSystemSettings() => _cm.showAppSettings();

  // ------------------------------------------------------------- discovery

  Future<void> startScan({Duration timeout = FuelPayBle.scanTimeout}) async {
    if (scanning) await stopScan();
    _pumps.clear();
    lastError = null;
    if (adapterState == BluetoothLowEnergyState.unauthorized) {
      final granted = await requestPermissions();
      if (!granted) {
        lastError = 'Bluetooth permission is required to find nearby pumps.';
        notifyListeners();
        return;
      }
    }
    if (adapterState == BluetoothLowEnergyState.poweredOff) {
      lastError = 'Bluetooth is turned off. Enable Bluetooth and try again.';
      notifyListeners();
      return;
    }
    _discoveredSub ??= _cm.discovered.listen(_onDiscovered);
    try {
      await _cm.startDiscovery(
        serviceUUIDs: [UUID.fromString(FuelPayBle.serviceUuid)],
      );
      scanning = true;
      notifyListeners();
      _scanTimer = Timer(timeout, stopScan);
    } on Exception catch (e) {
      lastError = 'Scan could not start: $e';
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    if (!scanning) return;
    scanning = false;
    try {
      await _cm.stopDiscovery();
    } on Exception {
      // Scan may already be stopped by the platform.
    }
    notifyListeners();
  }

  void _onDiscovered(DiscoveredEventArgs e) {
    // Service-UUID scan filter already guarantees this is a FuelPay device;
    // extract the human alias when present.
    String? alias;
    final data =
        e.advertisement.serviceData[UUID.fromString(FuelPayBle.serviceUuid)];
    if (data != null && data.isNotEmpty) {
      try {
        final raw = String.fromCharCodes(data);
        if (FuelPayBle.isValidAlias(raw)) alias = raw;
      } on Exception {
        alias = null;
      }
    }
    final key = e.peripheral.uuid.toString();
    _pumps[key] = DiscoveredPump(
      peripheral: e.peripheral,
      rssi: e.rssi,
      alias: alias,
    );
    notifyListeners();
  }

  // -------------------------------------------------------------- connect

  Future<bool> connect(DiscoveredPump pump) async {
    if (_busyConnecting) return false; // connect/reconnect already in flight
    _busyConnecting = true;
    try {
      await stopScan();
      phase = BleConnectionPhase.connecting;
      lastError = null;
      pumpDisplayName = pump.displayName;
      notifyListeners();

      try {
        final target = await _connectWithRetry(pump.peripheral);
        if (target != null) {
          _connectedPeripheral = target;
          autoReconnect = true;
          _reconnectAttempts = 0;
          phase = BleConnectionPhase.connected;
          lastError = null;
          notifyListeners();
          return true;
        }
      } on StateError catch (e) {
        phase = BleConnectionPhase.error;
        lastError = e.message;
        notifyListeners();
        return false;
      }
      phase = BleConnectionPhase.error;
      lastError =
          'Could not reach the pump. Make sure the pump app is open with '
          '“Advertising” on, keep the devices close together, then try again.';
      notifyListeners();
      return false;
    } finally {
      _busyConnecting = false;
    }
  }

  /// Connects with up to 3 attempts. Android frequently fails the first GATT
  /// connect with status 133/257 (`GATT_FAILURE`) when the scan-cached device
  /// handle is stale or the remote stack was momentarily busy — each retry
  /// re-resolves the device with a short targeted scan first. Returns the
  /// peripheral that actually connected, or null when all attempts failed.
  Future<Peripheral?> _connectWithRetry(Peripheral peripheral) async {
    var target = peripheral;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
        target = await _refreshPeripheral(target) ?? target;
      }
      try {
        final ok = await _establish(target);
        if (ok) return target;
      } on TimeoutException {
        debugPrint('BLE connect attempt ${attempt + 1}/3 timed out');
      } on StateError {
        rethrow; // wrong device — retrying will not help
      } catch (e) {
        // Typical: PlatformException(IllegalStateException … status: 257).
        debugPrint('BLE connect attempt ${attempt + 1}/3 failed: $e');
      }
      await _abandonAttempt(target);
    }
    return null;
  }

  /// Re-resolves [current] via a short scan so the next connect attempt uses
  /// a fresh device handle (BLE random addresses rotate over time).
  Future<Peripheral?> _refreshPeripheral(Peripheral current) async {
    final address = current.uuid.toString();
    _pumps.remove(address); // any leftover entry is stale by definition
    try {
      await _cm.startDiscovery(
        serviceUUIDs: [UUID.fromString(FuelPayBle.serviceUuid)],
      );
    } on Exception {
      return null;
    }
    try {
      final deadline = DateTime.now().add(const Duration(milliseconds: 3500));
      while (DateTime.now().isBefore(deadline)) {
        final found = _pumps[address];
        if (found != null) return found.peripheral;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      try {
        await _cm.stopDiscovery();
      } on Exception {
        // Already stopped by the platform.
      }
    }
    return null;
  }

  /// Cleans up a failed connect attempt so the next one starts fresh.
  Future<void> _abandonAttempt(Peripheral peripheral) async {
    try {
      await _cm.disconnect(peripheral);
    } on Exception {
      // Never reached a connected state — nothing to disconnect.
    }
    _commandChar = null;
    _responseChar = null;
    _assembler.reset();
  }

  /// Full connect + GATT discovery + notify subscription + HELLO handshake.
  /// Returns true when the pump answered with HELLO_ACK.
  Future<bool> _establish(Peripheral peripheral) async {
    _assembler.reset();
    _commandChar = null;
    _responseChar = null;

    await _cm.connect(peripheral).timeout(FuelPayBle.connectTimeout);

    final services = await _cm.discoverGATT(peripheral);
    GATTCharacteristic? command;
    GATTCharacteristic? response;
    for (final service in services) {
      if (service.uuid != UUID.fromString(FuelPayBle.serviceUuid)) continue;
      for (final c in service.characteristics) {
        if (c.uuid == UUID.fromString(FuelPayBle.commandCharacteristicUuid)) {
          command = c;
        } else if (c.uuid ==
            UUID.fromString(FuelPayBle.responseCharacteristicUuid)) {
          response = c;
        }
      }
    }
    if (command == null || response == null) {
      throw StateError(
        'The selected device does not expose the FuelPay service.',
      );
    }
    _commandChar = command;
    _responseChar = response;

    try {
      await _cm.requestMTU(peripheral, mtu: FuelPayBle.requestedMtu);
    } on Exception {
      // MTU negotiation is best effort; framing adapts to the real value.
    }

    await _cm.setCharacteristicNotifyState(peripheral, response, state: true);
    // Some chipsets mishandle a write arriving in the same window as the
    // CCC write — settle briefly before the handshake.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    HelloAckMessage? ack;
    for (var round = 0; round < 2 && ack == null; round++) {
      final ackFuture = _messages.stream
          .firstWhere((m) => m is HelloAckMessage)
          .timeout(const Duration(seconds: 4));
      // Handshake runs before `_connectedPeripheral` is assigned, so write
      // through the in-scope GATT handles instead of `_sendRaw`.
      await _sendRawOn(peripheral, command, HelloMessage(role: 'CUSTOMER'));
      try {
        ack = await ackFuture as HelloAckMessage;
      } on TimeoutException {
        debugPrint('Handshake round ${round + 1} timed out; re-subscribing');
        // Subscription may not have stuck — rewrite CCC, then re-send HELLO
        // (the pump acks every HELLO, so this is safe).
        try {
          await _cm.setCharacteristicNotifyState(
            peripheral,
            response,
            state: true,
          );
        } on Exception {
          // Keep going — the retry loop handles a dead link.
        }
      }
    }
    if (ack == null) {
      throw TimeoutException('Handshake with the pump timed out');
    }
    pumpDisplayName = ack.pumpName;
    notifyListeners();
    return true;
  }

  Future<void> _safeDisconnect() async {
    final p = _connectedPeripheral;
    if (p != null) {
      try {
        await _cm.disconnect(p);
      } on Exception {
        // ignore
      }
    }
    _connectedPeripheral = null;
    _commandChar = null;
    _responseChar = null;
    _assembler.reset();
  }

  Future<void> disconnect({bool manual = false}) async {
    if (manual) autoReconnect = false;
    await _safeDisconnect();
    phase = BleConnectionPhase.disconnected;
    pumpDisplayName = null;
    notifyListeners();
  }

  void _onConnectionChanged(PeripheralConnectionStateChangedEventArgs e) {
    final current = _connectedPeripheral;
    if (current == null || e.peripheral != current) {
      return;
    }
    if (e.state == ConnectionState.disconnected) {
      final wasConnected = phase == BleConnectionPhase.connected;
      _commandChar = null;
      _responseChar = null;
      _assembler.reset();
      if (autoReconnect && _reconnectAttempts < 3) {
        phase = BleConnectionPhase.connecting;
        lastError = 'Connection lost. Reconnecting…';
        notifyListeners();
        _reconnectAttempts++;
        Timer(Duration(seconds: _reconnectAttempts), () async {
          if (!autoReconnect || _busyConnecting) return;
          _busyConnecting = true;
          try {
            final target = await _connectWithRetry(current);
            if (target != null) {
              _connectedPeripheral = target;
              _reconnectAttempts = 0;
              phase = BleConnectionPhase.connected;
              lastError = null;
            } else {
              phase = BleConnectionPhase.error;
              lastError =
                  'Reconnection failed. Move closer to the pump and '
                  'reconnect from the scan screen.';
            }
            notifyListeners();
          } finally {
            _busyConnecting = false;
          }
        });
      } else {
        phase = BleConnectionPhase.disconnected;
        if (wasConnected) lastError = 'Disconnected from the pump.';
        notifyListeners();
      }
    }
  }

  // ------------------------------------------------------------ transport

  void _onNotified(GATTCharacteristicNotifiedEventArgs e) {
    final response = _responseChar;
    if (response == null || e.characteristic != response) return;
    try {
      final payload = _assembler.add(e.value);
      if (payload == null) return;
      final message = ProtocolMessage.decodeBytes(payload);
      if (message is HelloMessage || message is HelloAckMessage) {
        _messages.add(message); // handshake messages are never deduplicated
        return;
      }
      if (!_dedupe.accept(message)) return; // duplicate delivery
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

  /// Sends a protocol message to the pump (serialized + framed).
  Future<void> send(ProtocolMessage message) async {
    if (phase != BleConnectionPhase.connected ||
        _connectedPeripheral == null ||
        _commandChar == null) {
      throw StateError('Not connected to a pump');
    }
    await _sendRaw(message);
  }

  Future<void> _sendRaw(ProtocolMessage message) async {
    final peripheral = _connectedPeripheral;
    final command = _commandChar;
    if (peripheral == null || command == null) {
      throw StateError('Not connected');
    }
    await _sendRawOn(peripheral, command, message);
  }

  /// Framed, serialized write to [command] on [peripheral]. Usable both
  /// before the connection is registered (`_establish` handshake) and after.
  Future<void> _sendRawOn(
    Peripheral peripheral,
    GATTCharacteristic command,
    ProtocolMessage message,
  ) async {
    // Serialize writes: the platform does not multiplex concurrent writes.
    final future = _sendChain.then((_) async {
      final maxLen = await _cm.getMaximumWriteLength(
        peripheral,
        type: GATTCharacteristicWriteType.withResponse,
      );
      final chunk = (maxLen - MessageFraming.headerOverhead).clamp(1, maxLen);
      final frames = MessageFraming.encode(
        Uint8List.fromList(message.encodeBytes()),
        chunkSize: chunk,
      );
      for (final frame in frames) {
        await _cm.writeCharacteristic(
          peripheral,
          command,
          value: frame,
          type: GATTCharacteristicWriteType.withResponse,
        );
      }
    });
    _sendChain = future.catchError((_) {});
    await future;
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _stateSub?.cancel();
    _discoveredSub?.cancel();
    _connSub?.cancel();
    _notifySub?.cancel();
    _messages.close();
    _protocolErrors.close();
    super.dispose();
  }
}

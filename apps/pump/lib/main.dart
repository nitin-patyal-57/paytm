import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'app.dart';
import 'services/ble_peripheral_service.dart';
import 'services/pump_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalTransactionStore.open();

  // Stable short BLE alias (generated once, reused across restarts).
  var alias = store.deviceAlias;
  if (alias == null) {
    alias = FuelPayBle.generateAlias();
    await store.setDeviceAlias(alias);
  }

  final api = FuelPayApiClient(baseUrl: store.backendUrl);
  final ble = BlePeripheralService();
  await ble.init(alias: alias);

  final flow = PumpTransactionFlow(api: api, store: store, ble: ble);
  // Kick off boot work (sync flush + recovery) without blocking the frame.
  flow.start();

  runApp(FuelPayPumpApp(flow: flow, ble: ble, store: store, api: api));
}

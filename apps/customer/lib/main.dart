import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'app.dart';
import 'services/ble_central_service.dart';
import 'services/transaction_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalTransactionStore.open();
  final api = FuelPayApiClient(baseUrl: store.backendUrl);
  final ble = BleCentralService();
  final flow = CustomerTransactionFlow(api: api, store: store, ble: ble);

  await ble.init();
  // Kick off boot work (sync-queue flush, recovery) without blocking the
  // first frame; the splash stage covers it.
  flow.start();

  runApp(FuelPayCustomerApp(flow: flow, ble: ble, store: store, api: api));
}

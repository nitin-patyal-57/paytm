import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'screens/dashboard_screen.dart';
import 'services/ble_peripheral_service.dart';
import 'services/pump_flow.dart';

/// Root widget for the pump app — dashboard is the only root route; request
/// and payment screens are pushed on top as transactions arrive.
class FuelPayPumpApp extends StatelessWidget {
  const FuelPayPumpApp({
    super.key,
    required this.flow,
    required this.ble,
    required this.store,
    required this.api,
  });

  final PumpTransactionFlow flow;
  final BlePeripheralService ble;
  final LocalTransactionStore store;
  final FuelPayApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelPay Pump',
      debugShowCheckedModeBanner: false,
      theme: FuelPayTheme.light(),
      home: DashboardScreen(flow: flow, ble: ble, store: store, api: api),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'screens/advertisement_screen.dart';
import 'screens/amount_screen.dart';
import 'screens/home_screen.dart';
import 'screens/qr_screen.dart';
import 'screens/result_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/waiting_screen.dart';
import 'services/ble_central_service.dart';
import 'services/transaction_flow.dart';

/// Root widget: owns nothing but wiring — screens are rendered from the
/// flow's [FlowStage] and repaint when the flow or the BLE link changes.
class FuelPayCustomerApp extends StatelessWidget {
  const FuelPayCustomerApp({
    super.key,
    required this.flow,
    required this.ble,
    required this.store,
    required this.api,
  });

  final CustomerTransactionFlow flow;
  final BleCentralService ble;
  final LocalTransactionStore store;
  final FuelPayApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelPay',
      debugShowCheckedModeBanner: false,
      theme: FuelPayTheme.light(),
      home: _Root(flow: flow, ble: ble, store: store, api: api),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({
    required this.flow,
    required this.ble,
    required this.store,
    required this.api,
  });

  final CustomerTransactionFlow flow;
  final BleCentralService ble;
  final LocalTransactionStore store;
  final FuelPayApiClient api;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([flow, ble]),
      builder: (context, _) {
        return switch (flow.stage) {
          FlowStage.splash => const SplashScreen(),
          FlowStage.home => HomeScreen(flow: flow, store: store, api: api),
          FlowStage.amount => AmountScreen(flow: flow),
          FlowStage.scan => ScanScreen(flow: flow, ble: ble),
          FlowStage.qr => QrScreen(flow: flow, ble: ble),
          FlowStage.waiting => WaitingScreen(flow: flow, ble: ble),
          FlowStage.result => ResultScreen(flow: flow),
          FlowStage.ad => AdvertisementScreen(flow: flow),
        };
      },
    );
  }
}

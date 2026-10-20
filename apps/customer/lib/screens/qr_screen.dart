import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../screens/splash_screen.dart';
import '../services/ble_central_service.dart';
import '../services/transaction_flow.dart';
import '../widgets/shell.dart';

/// Stage 4: shows the transaction ID + QR code while the payment request is
/// transferred to the pump over Bluetooth.
class QrScreen extends StatelessWidget {
  const QrScreen({super.key, required this.flow, required this.ble});

  final CustomerTransactionFlow flow;
  final BleCentralService ble;

  Future<void> _leave(BuildContext context) async {
    if (flow.active != null && !flow.active!.status.isTerminal) {
      final confirmed = await confirmDiscard(context);
      if (!confirmed || !context.mounted) return;
      await flow.cancelActive();
    }
    if (context.mounted) flow.go(FlowStage.amount);
  }

  @override
  Widget build(BuildContext context) {
    final tx = flow.active;
    if (tx == null) {
      // Transaction disappeared (e.g. reset) — recover gracefully.
      return const SplashScreen();
    }
    final statusLine = switch ((
      flow.pumpAcknowledged,
      flow.requestSent,
      ble.isConnected,
    )) {
      (true, _, _) => 'The pump has received your request.',
      (_, true, true) => 'Request sent — waiting for the pump…',
      (_, _, false) => 'Bluetooth disconnected — reconnecting…',
      _ => 'Sending your request over Bluetooth…',
    };
    return StageScaffold(
      title: 'Transaction QR',
      onBack: () => _leave(context),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (flow.error != null) ...[
            ErrorBanner(message: flow.error!, onDismiss: flow.clearError),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              ConnectionBadge(
                connected: ble.isConnected,
                busy: ble.phase == BleConnectionPhase.connecting,
                label: ble.isConnected
                    ? (flow.pumpName ?? 'Pump connected')
                    : ble.phase == BleConnectionPhase.connecting
                    ? 'Reconnecting…'
                    : 'Not connected',
              ),
              const Spacer(),
              StatusChip(tx.status),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
                border: Border.all(color: FuelPayColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: jsonEncode(tx.toQrPayload()),
                    version: QrVersions.auto,
                    size: 230,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tx.transactionId,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: FuelPayColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            child: Column(
              children: [
                InfoRow('Fuel type', tx.fuelType.label),
                const Divider(height: 10),
                InfoRow(
                  'Amount',
                  '₹${AmountValidator.format(tx.amount)}',
                  emphasized: true,
                ),
                const Divider(height: 10),
                InfoRow('Transaction ID', tx.transactionId),
                const Divider(height: 10),
                InfoRow(
                  'Status',
                  flow.pumpAcknowledged
                      ? 'Shared with ${flow.pumpName ?? 'the pump'}'
                      : 'Transferring over Bluetooth',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FuelPayColors.infoBackground,
              borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bluetooth,
                  color: FuelPayColors.info,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusLine,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: FuelPayColors.textPrimary,
                    ),
                  ),
                ),
                if (!flow.pumpAcknowledged && ble.isConnected)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: DemoBadge()),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/ble_peripheral_service.dart';
import '../services/pump_flow.dart';
import '../widgets/shell.dart';

/// Demo payment stage: shows the payment QR for the accepted transaction and
/// offers explicit SUCCESS / FAILED simulation controls (the only way payment
/// outcomes are ever produced in this demo).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.flow, required this.ble});

  final PumpTransactionFlow flow;
  final BlePeripheralService ble;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PumpTransactionFlow get flow => widget.flow;

  Map<String, dynamic> _qrPayload(FuelTransaction tx) => <String, dynamic>{
    'v': 1,
    'kind': 'fuelpay-demo-payment',
    'mode': 'DEMO',
    'tx': tx.transactionId,
    'fuel': tx.fuelType.wireName,
    'amt': tx.amount,
    'cur': tx.currency,
    'note': 'SIMULATED PAYMENT — no real money is transferred',
  };

  Future<void> _simulate({required bool success}) async {
    final failure = await flow.simulatePayment(success: success);
    if (failure != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  void _done() {
    flow.acknowledgeOutcome();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final tx = flow.active;
    if (tx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const StageScaffold(
        title: 'Demo payment',
        body: SizedBox.shrink(),
      );
    }
    final status = tx.status;
    final success = status == TransactionStatus.paymentSuccess;
    final failed = status == TransactionStatus.paymentFailed;
    final settled = success || failed;

    return StageScaffold(
      title: settled ? 'Payment result' : 'Demo payment',
      onBack: settled ? null : () => Navigator.of(context).pop(),
      body: ListenableBuilder(
        listenable: Listenable.merge([flow, widget.ble]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (flow.error != null) ...[
                StatusBanner(
                  message: flow.error!,
                  onDismiss: flow.clearMessages,
                ),
                const SizedBox(height: 16),
              ] else if (flow.info != null && !settled) ...[
                StatusBanner(
                  message: flow.info!,
                  kind: StatusBannerKind.info,
                  onDismiss: flow.clearMessages,
                ),
                const SizedBox(height: 16),
              ],
              if (settled) ...[
                _OutcomeView(success: success, transaction: tx),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  style: success
                      ? AppButtonStyle.success
                      : AppButtonStyle.primary,
                  onPressed: _done,
                ),
                const SizedBox(height: 12),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: FuelPayColors.surface,
                    borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
                    border: Border.all(color: FuelPayColors.border),
                  ),
                  child: Column(
                    children: [
                      StatusChip(tx.status),
                      const SizedBox(height: 14),
                      AmountDisplay(tx.amount),
                      const SizedBox(height: 4),
                      Text(
                        '${tx.fuelType.label} · ${tx.transactionId}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: FuelPayColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            FuelPaySpacing.radiusSmall,
                          ),
                          border: Border.all(color: FuelPayColors.border),
                        ),
                        child: QrImageView(
                          data: jsonEncode(_qrPayload(tx)),
                          version: QrVersions.auto,
                          size: 210,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const DemoBadge(compact: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (!widget.ble.customerConnected)
                  StatusBanner(
                    kind: StatusBannerKind.info,
                    message:
                        'Customer tablet not connected — the result '
                        'will be delivered when it reconnects.',
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Simulate the payment outcome:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: FuelPayColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Success',
                        icon: Icons.check_circle_rounded,
                        style: AppButtonStyle.success,
                        loading: flow.busy,
                        onPressed: () => _simulate(success: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Failure',
                        icon: Icons.cancel_rounded,
                        style: AppButtonStyle.danger,
                        loading: false,
                        onPressed: flow.busy
                            ? null
                            : () => _simulate(success: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Outcomes are simulated server-side by the demo payment '
                  'endpoint — no real payment provider is contacted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.success, required this.transaction});

  final bool success;
  final FuelTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final color = success ? FuelPayColors.success : FuelPayColors.error;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              success ? Icons.check_rounded : Icons.close_rounded,
              size: 52,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            success ? 'Payment successful' : 'Payment failed',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          AmountDisplay(transaction.amount, fontSize: 34, color: color),
          const SizedBox(height: 8),
          Text(
            '${transaction.transactionId} · ${transaction.status.label}'
            '${transaction.statusReason != null ? ' · ${transaction.statusReason}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: FuelPayColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          const DemoBadge(compact: true),
        ],
      ),
    );
  }
}

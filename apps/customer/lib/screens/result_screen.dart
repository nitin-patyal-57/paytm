import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import '../services/transaction_flow.dart';
import '../widgets/shell.dart';

/// Stage 6: final outcome of the transaction. Success continues into the
/// one-time five-second advertisement.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.flow});

  final CustomerTransactionFlow flow;

  @override
  Widget build(BuildContext context) {
    final tx = flow.active;
    if (tx == null) return const _Placeholder();
    final status = tx.status;
    final success = status == TransactionStatus.paymentSuccess;
    final failed = status == TransactionStatus.paymentFailed;
    final color = success
        ? FuelPayColors.success
        : failed
        ? FuelPayColors.error
        : FuelPayColors.textSecondary;
    final icon = success
        ? Icons.check_circle_rounded
        : failed
        ? Icons.cancel_rounded
        : Icons.info_outline_rounded;
    final headline = success
        ? 'Payment successful'
        : failed
        ? 'Payment failed'
        : status == TransactionStatus.cancelled
        ? 'Transaction cancelled'
        : 'Transaction expired';
    final detail = switch (status) {
      TransactionStatus.paymentSuccess =>
        'The demo payment of ₹${AmountValidator.format(tx.amount)} was '
            'completed successfully.',
      TransactionStatus.paymentFailed =>
        tx.statusReason ?? 'The demo payment could not be completed.',
      _ => tx.statusReason ?? 'No payment was made.',
    };
    return StageScaffold(
      title: 'Transaction result',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 54, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                AmountDisplay(tx.amount, fontSize: 40, color: color),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Receipt',
            child: Column(
              children: [
                InfoRow('Fuel type', tx.fuelType.label),
                const Divider(height: 10),
                InfoRow('Amount', '₹${AmountValidator.format(tx.amount)}'),
                const Divider(height: 10),
                InfoRow('Transaction ID', tx.transactionId),
                const Divider(height: 10),
                InfoRow('Status', status.label),
                const Divider(height: 10),
                InfoRow('Mode', 'Demo payment (simulated)'),
                const Divider(height: 10),
                InfoRow('Updated', _formatTime(tx.updatedAt)),
                if (tx.completedAt != null) ...[
                  const Divider(height: 10),
                  InfoRow('Completed', _formatTime(tx.completedAt!)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(child: DemoBadge()),
          const SizedBox(height: 20),
          if (success)
            AppButton(
              label: flow.advertisementPlayed ? 'Done' : 'Continue',
              icon: Icons.play_arrow_rounded,
              style: AppButtonStyle.success,
              onPressed: () {
                if (flow.advertisementPlayed) {
                  flow.resetTransaction();
                } else {
                  flow.go(FlowStage.ad);
                }
              },
            )
          else
            AppButton(
              label: 'Start a new transaction',
              icon: Icons.refresh,
              onPressed: flow.resetTransaction,
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $hh:$mm:$ss';
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const StageScaffold(
      title: 'Transaction result',
      body: Center(child: Text('No transaction to show.')),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import '../screens/splash_screen.dart';
import '../services/ble_central_service.dart';
import '../services/transaction_flow.dart';
import '../widgets/shell.dart';

/// Stage 5: live progress while the pump accepts the request and the demo
/// payment outcome is produced. Terminal results redirect automatically.
class WaitingScreen extends StatelessWidget {
  const WaitingScreen({super.key, required this.flow, required this.ble});

  final CustomerTransactionFlow flow;
  final BleCentralService ble;

  Future<void> _leave(BuildContext context) async {
    final confirmed = await confirmDiscard(context);
    if (!confirmed || !context.mounted) return;
    await flow.cancelActive();
    if (context.mounted) flow.go(FlowStage.home);
  }

  @override
  Widget build(BuildContext context) {
    final tx = flow.active;
    if (tx == null) return const SplashScreen();
    final disconnected = !ble.isConnected;
    return StageScaffold(
      title: 'Waiting for payment',
      onBack: () => _leave(context),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (flow.error != null) ...[
            ErrorBanner(message: flow.error!, onDismiss: flow.clearError),
            const SizedBox(height: 16),
          ],
          SectionCard(
            title: 'Transaction progress',
            trailing: StatusChip(tx.status, compact: true),
            child: _Timeline(status: tx.status, furthest: flow.furthestStatus),
          ),
          const SizedBox(height: 16),
          if (disconnected) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FuelPayColors.warningBackground,
                borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bluetooth_disabled,
                    color: FuelPayColors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Bluetooth disconnected. Reconnect to keep receiving '
                      'updates — the transaction is kept on this tablet.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: FuelPayColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Reconnect',
                    expand: false,
                    onPressed: () => flow.go(FlowStage.scan),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Row(
              children: [
                ConnectionBadge(
                  connected: true,
                  label: flow.pumpName ?? 'Pump connected',
                ),
                const Spacer(),
                Text(
                  'Payments are simulated in demo mode.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SectionCard(
            title: 'Details',
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
                InfoRow('Mode', 'Demo payment (simulated)'),
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

/// Vertical checklist built from the state machine: every step up to the
/// furthest reached state is shown as done, the current state is active and
/// the terminal outcome (if any) closes the list.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.status, required this.furthest});

  final TransactionStatus status;
  final TransactionStatus? furthest;

  static String _label(TransactionStatus s) => switch (s) {
    TransactionStatus.created => 'Transaction created',
    TransactionStatus.requestSent => 'Sent to pump over Bluetooth',
    TransactionStatus.requestReceived => 'Pump received the request',
    TransactionStatus.accepted => 'Pump accepted the request',
    TransactionStatus.qrReady => 'Demo payment QR ready',
    TransactionStatus.paymentPending => 'Waiting for demo payment',
    TransactionStatus.paymentSuccess => 'Payment completed (demo)',
    TransactionStatus.paymentFailed => 'Demo payment failed',
    TransactionStatus.cancelled => 'Cancelled',
    TransactionStatus.expired => 'Expired',
  };

  /// The rows to render: reached states (done) + the current state (active).
  List<TransactionStatus> get _rows {
    if (status == TransactionStatus.created) {
      return const [TransactionStatus.created];
    }
    if (status.isTerminal) {
      final reached = furthest;
      if (reached != null && reached != status) {
        final path =
            TransactionStateMachine.path(TransactionStatus.created, reached) ??
            const <TransactionStatus>[];
        final prefix = path.isEmpty ? const [TransactionStatus.created] : path;
        return [...prefix, status];
      }
      // No progress information (e.g. restored only from a terminal record).
      final path =
          TransactionStateMachine.path(TransactionStatus.created, status) ??
          const <TransactionStatus>[];
      return path.isEmpty ? const [TransactionStatus.created] : path;
    }
    final path =
        TransactionStateMachine.path(TransactionStatus.created, status) ??
        const <TransactionStatus>[];
    return path.isEmpty ? const [TransactionStatus.created] : path;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          _TimelineRow(
            label: _label(rows[i]),
            state: i == rows.length - 1
                ? (status.isTerminal
                      ? (status == TransactionStatus.paymentSuccess
                            ? _RowState.done
                            : _RowState.failed)
                      : _RowState.active)
                : _RowState.done,
          ),
      ],
    );
  }
}

enum _RowState { done, active, failed, pending }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.label, required this.state});

  final String label;
  final _RowState state;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      _RowState.done => FuelPayColors.success,
      _RowState.active => FuelPayColors.primary,
      _RowState.failed => FuelPayColors.error,
      _RowState.pending => FuelPayColors.borderStrong,
    };
    final Widget leading = switch (state) {
      _RowState.done => const Icon(
        Icons.check_circle_rounded,
        color: FuelPayColors.success,
        size: 24,
      ),
      _RowState.active => SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: color),
      ),
      _RowState.failed => const Icon(
        Icons.cancel_rounded,
        color: FuelPayColors.error,
        size: 24,
      ),
      _RowState.pending => Icon(
        Icons.radio_button_unchecked,
        color: color,
        size: 24,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: 28, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: state == _RowState.pending
                    ? FontWeight.w500
                    : FontWeight.w700,
                color: state == _RowState.pending
                    ? FuelPayColors.textSecondary
                    : FuelPayColors.textPrimary,
              ),
            ),
          ),
          if (state == _RowState.done)
            const Text(
              'done',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: FuelPayColors.success,
              ),
            ),
        ],
      ),
    );
  }
}

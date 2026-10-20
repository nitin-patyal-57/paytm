import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import '../services/ble_peripheral_service.dart';
import '../services/pump_flow.dart';
import '../widgets/shell.dart';
import 'payment_screen.dart';

/// Attendant decision screen: shows the incoming request and offers the
/// ACCEPT / REJECT actions required by the demo flow.
class RequestScreen extends StatefulWidget {
  const RequestScreen({super.key, required this.flow, required this.ble});

  final PumpTransactionFlow flow;
  final BlePeripheralService ble;

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  PumpTransactionFlow get flow => widget.flow;

  Future<void> _accept() async {
    final failure = await flow.acceptRequest();
    if (failure != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure)));
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(flow: flow, ble: widget.ble),
      ),
    );
  }

  Future<void> _reject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject request?'),
        content: Text(
          'The customer will be told the request was rejected and '
          '${flow.active?.transactionId ?? 'the transaction'} will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: FuelPayColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final failure = await flow.rejectRequest();
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure)));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tx = flow.active;
    if (tx == null || tx.status != TransactionStatus.requestReceived) {
      // Decision no longer pending (cancelled remotely, etc.).
      return StageScaffold(
        title: 'Payment request',
        onBack: () => Navigator.of(context).pop(),
        body: const Center(
          child: Text(
            'No pending request.',
            style: TextStyle(color: FuelPayColors.textSecondary),
          ),
        ),
      );
    }
    return StageScaffold(
      title: 'Payment request',
      onBack: () => Navigator.of(context).pop(),
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
              ],
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: FuelPayColors.surface,
                  borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
                  border: Border.all(color: FuelPayColors.border, width: 1.4),
                ),
                child: Column(
                  children: [
                    StatusChip(tx.status),
                    const SizedBox(height: 16),
                    Text(
                      tx.fuelType.label,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: FuelPayColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AmountDisplay(tx.amount),
                    const SizedBox(height: 14),
                    Text(
                      tx.transactionId,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: FuelPayColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConnectionBadge(
                      connected: widget.ble.customerConnected,
                      label: widget.ble.customerConnected
                          ? 'Customer tablet linked'
                          : 'Customer disconnected',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Center(child: DemoBadge()),
              const SizedBox(height: 20),
              AppButton(
                label: 'Accept request',
                icon: Icons.check_rounded,
                style: AppButtonStyle.success,
                loading: flow.busy,
                onPressed: _accept,
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Reject',
                icon: Icons.close_rounded,
                style: AppButtonStyle.danger,
                onPressed: _reject,
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

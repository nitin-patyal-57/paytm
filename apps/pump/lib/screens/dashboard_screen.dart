import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/history_screen.dart';
import '../screens/payment_screen.dart';
import '../screens/request_screen.dart';
import '../services/ble_peripheral_service.dart';
import '../services/pump_flow.dart';
import '../widgets/shell.dart';

/// Root screen: device identity + advertising control, live link status,
/// incoming-request prompt, payment continuation and recent history.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
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
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _navigating = false;
  bool _bootstrapped = false;

  PumpTransactionFlow get flow => widget.flow;
  BlePeripheralService get ble => widget.ble;

  @override
  void initState() {
    super.initState();
    flow.addListener(_onChanged);
    ble.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    flow.removeListener(_onChanged);
    ble.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeAutoPrompt();
  }

  /// First launch: ask for ADVERTISE/CONNECT permission and start
  /// advertising so the pump is discoverable without extra taps.
  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();
    final granted = statuses.values.every((s) => s.isGranted);
    if (!granted) {
      await ble.requestPermissions();
    }
    if (!mounted) return;
    if (!ble.advertising) {
      await ble.startAdvertising();
    }
    setState(() {});
  }

  Future<void> _toggleAdvertising(bool enable) async {
    if (enable) {
      final statuses = await [
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ].request();
      if (!statuses.values.every((s) => s.isGranted)) {
        await ble.requestPermissions();
      }
      if (mounted) await ble.startAdvertising();
    } else {
      await ble.stopAdvertising();
    }
    if (mounted) setState(() {});
  }

  void _maybeAutoPrompt() {
    if (_navigating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _navigating) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) return;
      if (flow.promptRequest && flow.decisionTransaction != null) {
        _navigating = true;
        flow.consumeRequestPrompt();
        Navigator.of(context)
            .push<void>(
              MaterialPageRoute(
                builder: (_) => RequestScreen(flow: flow, ble: ble),
              ),
            )
            .whenComplete(() => _navigating = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeAutoPrompt();
    final recent = flow.history().take(4).toList();
    final decision = flow.decisionTransaction;
    return StageScaffold(
      title: 'FuelPay Pump',
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Backend settings',
          onPressed: () => _showBackendDialog(context),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (flow.error != null) ...[
            StatusBanner(message: flow.error!, onDismiss: flow.clearMessages),
            const SizedBox(height: 14),
          ] else if (flow.info != null) ...[
            StatusBanner(
              message: flow.info!,
              kind: StatusBannerKind.info,
              onDismiss: flow.clearMessages,
            ),
            const SizedBox(height: 14),
          ],
          if (ble.lastError != null && !ble.advertising) ...[
            StatusBanner(
              message: ble.lastError!,
              onDismiss: () => setState(() {}),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Open Bluetooth settings',
              style: AppButtonStyle.outlined,
              onPressed: () => ble.openSystemSettings(),
            ),
            const SizedBox(height: 14),
          ],
          // -------------------------------------------------- identity
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [FuelPayColors.primary, Color(0xFF0A4FCC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PUMP DEVICE CODE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ble.deviceCode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Customers search for “${ble.displayName}”',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ConnectionBadge(
                      connected: ble.customerConnected,
                      busy: ble.advertising && !ble.customerConnected,
                      label: ble.customerConnected
                          ? 'Customer connected'
                          : ble.advertising
                          ? 'Waiting for a customer…'
                          : 'Not advertising',
                    ),
                    const Spacer(),
                    Switch(
                      value: ble.advertising,
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.white,
                      onChanged: _toggleAdvertising,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ------------------------------------------------ incoming
          if (decision != null) ...[
            _PendingRequestCard(
              transaction: decision,
              onOpen: () {
                flow.consumeRequestPrompt();
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => RequestScreen(flow: flow, ble: ble),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
          ],
          if (flow.paymentStage || flow.outcomeVisible) ...[
            _PaymentCard(
              transaction: flow.active!,
              outcome: flow.outcomeVisible,
              onOpen: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => PaymentScreen(flow: flow, ble: ble),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
          ],

          // -------------------------------------------------- history
          SectionCard(
            title: 'Recent transactions',
            trailing: TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(store: widget.store),
                  ),
                );
              },
              child: const Text('View all'),
            ),
            child: recent.isEmpty
                ? const Text(
                    'No transactions yet — incoming customer requests '
                    'will appear here.',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: FuelPayColors.textSecondary,
                    ),
                  )
                : Column(
                    children: [
                      for (final tx in recent) ...[
                        if (tx != recent.first) const Divider(height: 18),
                        _HistoryRow(transaction: tx),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FuelPayColors.surfaceMuted,
              borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_outlined,
                  size: 18,
                  color: FuelPayColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    flow.backendOnline
                        ? 'Backend connected: ${widget.api.baseUrl}'
                        : 'Backend offline — changes are queued locally',
                    style: const TextStyle(
                      fontSize: 13,
                      color: FuelPayColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _showBackendDialog(BuildContext context) async {
    final controller = TextEditingController(text: widget.store.backendUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backend URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'http://<lan-ip>:3000',
            hintText: 'http://192.168.1.5:3000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.store.setBackendUrl(controller.text);
      widget.api.baseUrl = widget.store.backendUrl;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backend set to ${widget.store.backendUrl}')),
        );
        (context as Element).markNeedsBuild();
      }
    }
    controller.dispose();
  }
}

class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({required this.transaction, required this.onOpen});

  final FuelTransaction transaction;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FuelPayColors.warningBackground,
      borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
            border: Border.all(color: FuelPayColors.warning, width: 1.6),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: FuelPayColors.warning,
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Incoming payment request',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: FuelPayColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${transaction.fuelType.label} · '
                      '₹${AmountValidator.format(transaction.amount)} · '
                      '${transaction.transactionId}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: FuelPayColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, color: FuelPayColors.warning),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.transaction,
    required this.outcome,
    required this.onOpen,
  });

  final FuelTransaction transaction;
  final bool outcome;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color =
        outcome && transaction.status == TransactionStatus.paymentSuccess
        ? FuelPayColors.success
        : outcome
        ? FuelPayColors.error
        : FuelPayColors.primary;
    final title = outcome
        ? (transaction.status == TransactionStatus.paymentSuccess
              ? 'Payment succeeded (demo)'
              : 'Payment failed (demo)')
        : 'Payment QR ready — awaiting demo payment';
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(
                outcome ? Icons.receipt_long : Icons.qr_code_2,
                color: color,
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${AmountValidator.format(transaction.amount)} · '
                      '${transaction.transactionId}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: FuelPayColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.transaction});

  final FuelTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final time = transaction.updatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${transaction.fuelType.label} · '
                  '₹${AmountValidator.format(transaction.amount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: FuelPayColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${transaction.transactionId} · '
                  '${time.day}/${time.month} '
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          StatusChip(transaction.status, compact: true),
        ],
      ),
    );
  }
}

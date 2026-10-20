import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import '../services/transaction_flow.dart';
import '../widgets/shell.dart';

/// Stage 1: fuel type selection, resume banner for an unfinished
/// transaction, recent history and backend URL settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.flow,
    required this.store,
    required this.api,
  });

  final CustomerTransactionFlow flow;
  final LocalTransactionStore store;
  final FuelPayApiClient api;

  @override
  Widget build(BuildContext context) {
    final recovered = flow.recoveredTransaction;
    final recent = store.transactions().take(5).toList();
    return StageScaffold(
      title: 'FuelPay Customer',
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
            ErrorBanner(message: flow.error!, onDismiss: flow.clearError),
            const SizedBox(height: 16),
          ],
          if (recovered != null) ...[
            _ResumeCard(flow: flow, transaction: recovered),
            const SizedBox(height: 16),
          ],
          const Text(
            'Choose fuel type',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: FuelPayColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _FuelCard(
                  type: FuelType.petrol,
                  icon: Icons.local_gas_station_rounded,
                  color: FuelPayColors.warning,
                  selected: flow.fuel == FuelType.petrol,
                  onTap: () => flow.selectFuel(FuelType.petrol),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _FuelCard(
                  type: FuelType.diesel,
                  icon: Icons.agriculture_rounded,
                  color: FuelPayColors.info,
                  selected: flow.fuel == FuelType.diesel,
                  onTap: () => flow.selectFuel(FuelType.diesel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'Enter amount',
            icon: Icons.arrow_forward,
            onPressed: flow.fuel == null
                ? null
                : () => flow.go(FlowStage.amount),
          ),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Recent transactions',
            child: recent.isEmpty
                ? const Text(
                    'No transactions yet — your fuel payments will appear here.',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: FuelPayColors.textSecondary,
                    ),
                  )
                : Column(
                    children: [
                      for (final tx in recent) ...[
                        if (tx != recent.first) const Divider(height: 18),
                        _RecentTile(transaction: tx),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 24),
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
                        ? 'Backend connected: ${api.baseUrl}'
                        : 'Backend offline — continuing with local storage',
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
    final controller = TextEditingController(text: store.backendUrl);
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
      await store.setBackendUrl(controller.text);
      api.baseUrl = store.backendUrl;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backend set to ${store.backendUrl}')),
        );
        (context as Element).markNeedsBuild();
      }
    }
    controller.dispose();
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.flow, required this.transaction});

  final CustomerTransactionFlow flow;
  final FuelTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FuelPayColors.infoBackground,
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        border: Border.all(color: FuelPayColors.info.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: FuelPayColors.info, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Unfinished transaction',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: FuelPayColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${transaction.fuelType.label} · ₹${AmountValidator.format(transaction.amount)} · '
                  '${transaction.transactionId}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          StatusChip(transaction.status, compact: true),
          const SizedBox(width: 10),
          AppButton(
            label: 'Resume',
            expand: false,
            onPressed: () => flow.go(FlowStage.waiting),
          ),
        ],
      ),
    );
  }
}

class _FuelCard extends StatelessWidget {
  const _FuelCard({
    required this.type,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final FuelType type;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FuelPayColors.infoBackground : FuelPayColors.surface,
      borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        onTap: onTap,
        child: Container(
          height: 130,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
            border: Border.all(
              color: selected ? FuelPayColors.primary : FuelPayColors.border,
              width: selected ? 2.4 : 1.4,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const Spacer(),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: FuelPayColors.primary,
                      size: 26,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                type.label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: FuelPayColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.transaction});

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
                  '${transaction.fuelType.label} · ₹${AmountValidator.format(transaction.amount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: FuelPayColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${transaction.transactionId} · '
                  '${time.day}/${time.month}/${time.year} '
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

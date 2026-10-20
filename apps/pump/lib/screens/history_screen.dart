import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import '../widgets/shell.dart';

/// Full local transaction history (this pump's perspective).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.store});

  final LocalTransactionStore store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  TransactionStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final all = widget.store.transactions(status: _filter);
    return StageScaffold(
      title: 'Transaction history',
      onBack: () => Navigator.of(context).pop(),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final status in TransactionStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(status.label),
                      selected: _filter == status,
                      onSelected: (_) => setState(() => _filter = status),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No transactions match this filter yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: FuelPayColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    itemCount: all.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _HistoryCard(transaction: all[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.transaction});

  final FuelTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final time = tx.updatedAt;
    final stamp =
        '${time.day}/${time.month}/${time.year} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FuelPayColors.surface,
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        border: Border.all(color: FuelPayColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${tx.fuelType.label} · '
                      '₹${AmountValidator.format(tx.amount)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: FuelPayColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (tx.isDemo)
                      const Text(
                        'DEMO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: FuelPayColors.warning,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${tx.transactionId} · $stamp',
                  style: const TextStyle(
                    fontSize: 13,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
                if (tx.statusReason != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    tx.statusReason!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: FuelPayColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          StatusChip(tx.status, compact: true),
        ],
      ),
    );
  }
}

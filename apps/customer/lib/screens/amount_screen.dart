import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import '../services/transaction_flow.dart';
import '../widgets/shell.dart';

/// Stage 2: amount entry (predefined chips + custom input) and transaction
/// creation before scanning for a pump.
class AmountScreen extends StatefulWidget {
  const AmountScreen({super.key, required this.flow});

  final CustomerTransactionFlow flow;

  @override
  State<AmountScreen> createState() => _AmountScreenState();
}

class _AmountScreenState extends State<AmountScreen> {
  late final TextEditingController _controller;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.flow.amount == null
          ? ''
          : AmountValidator.format(widget.flow.amount!),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyPreset(int value) {
    _controller.text = AmountValidator.format(value);
    widget.flow.setAmount(value);
    setState(() => _localError = null);
  }

  Future<void> _confirm() async {
    final parsed = AmountValidator.tryParse(_controller.text);
    if (parsed == null) {
      setState(
        () => _localError =
            'Enter an amount between ₹${AmountValidator.minAmount} and '
            '₹${AmountValidator.maxAmount}',
      );
      return;
    }
    setState(() => _localError = null);
    widget.flow.setAmount(parsed);
    await widget.flow.createTransaction();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final amount = flow.amount;
    return StageScaffold(
      title: 'Fuel amount',
      onBack: () => flow.go(FlowStage.home),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (flow.error != null) ...[
            ErrorBanner(message: flow.error!, onDismiss: flow.clearError),
            const SizedBox(height: 16),
          ],
          SectionCard(
            title: 'How much would you like to fill?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${flow.fuel?.label ?? 'Fuel'} · integer rupees',
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: FuelPayColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8, top: 14),
                      child: Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: FuelPayColors.textSecondary,
                        ),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 0,
                      minHeight: 0,
                    ),
                    hintText: '500',
                    errorText: _localError,
                  ),
                  onChanged: (_) {
                    if (_localError != null) setState(() => _localError = null);
                  },
                  onSubmitted: (_) => _confirm(),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final preset in AmountValidator.predefinedAmounts)
                      ChoiceChip(
                        label: Text('₹${AmountValidator.format(preset)}'),
                        selected: amount == preset,
                        selectedColor: FuelPayColors.infoBackground,
                        onSelected: (_) => _applyPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Minimum ₹${AmountValidator.minAmount} · '
                  'Maximum ₹${AmountValidator.format(AmountValidator.maxAmount)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: FuelPayColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (amount != null) ...[
            Center(child: AmountDisplay(amount)),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'You will pay this amount via demo payment',
                style: TextStyle(
                  fontSize: 13.5,
                  color: FuelPayColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          AppButton(
            label: 'Find a pump',
            icon: Icons.bluetooth_searching,
            loading: flow.busy,
            onPressed: _confirm,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

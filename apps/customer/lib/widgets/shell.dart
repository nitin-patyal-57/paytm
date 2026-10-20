import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

/// Shared scaffold for every stage: consistent app bar with the DEMO badge
/// and an optional back action.
class StageScaffold extends StatelessWidget {
  const StageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final Widget body;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: onBack,
              ),
        actions: [
          ...actions,
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: DemoBadge(compact: true)),
          ),
        ],
        bottom: bottom,
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Dismissible red banner for flow errors.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FuelPayColors.errorBackground,
        borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
        border: Border.all(color: FuelPayColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: FuelPayColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: FuelPayColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(
                Icons.close,
                size: 18,
                color: FuelPayColors.error,
              ),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

/// Confirmation dialog used when backing out of an in-flight transaction.
/// Returns true when the user confirms (the caller then cancels/leaves).
Future<bool> confirmDiscard(BuildContext context, {String? message}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel this transaction?'),
      content: Text(
        message ??
            'The transaction will be marked as cancelled and the pump will '
                'be notified.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep waiting'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FuelPayColors.error,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Cancel transaction'),
        ),
      ],
    ),
  );
  return result ?? false;
}

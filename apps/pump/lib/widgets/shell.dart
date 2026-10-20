import 'package:flutter/material.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

/// Shared scaffold for pump screens with the DEMO badge in the app bar.
class StageScaffold extends StatelessWidget {
  const StageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? floatingActionButton;

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
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: body),
    );
  }
}

/// Dismissible banner for flow / BLE errors (red) or info (blue/teal).
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.kind = StatusBannerKind.error,
    this.onDismiss,
  });

  final String message;
  final StatusBannerKind kind;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (kind) {
      StatusBannerKind.error => (
        FuelPayColors.errorBackground,
        FuelPayColors.error,
        Icons.error_outline,
      ),
      StatusBannerKind.info => (
        FuelPayColors.infoBackground,
        FuelPayColors.info,
        Icons.info_outline,
      ),
      StatusBannerKind.success => (
        FuelPayColors.successBackground,
        FuelPayColors.success,
        Icons.check_circle_outline,
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
        border: Border.all(color: foreground.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: foreground,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: foreground),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

enum StatusBannerKind { error, info, success }

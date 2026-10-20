import 'package:flutter/material.dart';

import '../models/transaction_status.dart';
import '../theme/fuelpay_colors.dart';

/// Prominent "this is a simulation" label used on every payment-related UI.
class DemoBadge extends StatelessWidget {
  const DemoBadge({
    super.key,
    this.text = 'DEMO PAYMENT — NOT A REAL PAYMENT',
    this.compact = false,
  });

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: FuelPayColors.demoBadgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: FuelPayColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science_outlined,
              size: 16, color: FuelPayColors.demoBadgeFg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: FuelPayColors.demoBadgeFg,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 11.5 : 13,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Colored chip describing a transaction status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.compact = false});

  final TransactionStatus status;
  final bool compact;

  Color get _bg {
    switch (status) {
      case TransactionStatus.paymentSuccess:
        return FuelPayColors.successBackground;
      case TransactionStatus.paymentFailed:
      case TransactionStatus.expired:
        return FuelPayColors.errorBackground;
      case TransactionStatus.cancelled:
        return FuelPayColors.surfaceMuted;
      case TransactionStatus.paymentPending:
      case TransactionStatus.qrReady:
        return FuelPayColors.warningBackground;
      case TransactionStatus.created:
      case TransactionStatus.requestSent:
      case TransactionStatus.requestReceived:
      case TransactionStatus.accepted:
        return FuelPayColors.infoBackground;
    }
  }

  Color get _fg {
    switch (status) {
      case TransactionStatus.paymentSuccess:
        return FuelPayColors.success;
      case TransactionStatus.paymentFailed:
      case TransactionStatus.expired:
        return FuelPayColors.error;
      case TransactionStatus.cancelled:
        return FuelPayColors.textSecondary;
      case TransactionStatus.paymentPending:
      case TransactionStatus.qrReady:
        return FuelPayColors.warning;
      default:
        return FuelPayColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: _fg,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11.5 : 13,
        ),
      ),
    );
  }
}

/// Small pill showing a Bluetooth / link state.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({
    super.key,
    required this.connected,
    required this.label,
    this.busy = false,
  });

  final bool connected;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? FuelPayColors.success
        : busy
            ? FuelPayColors.warning
            : FuelPayColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Labeled detail row used on transaction cards.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.emphasized = false});

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 14.5, color: FuelPayColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasized ? 18 : 15.5,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                color: FuelPayColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White rounded card with an optional title, used across screens.
class SectionCard extends StatelessWidget {
  const SectionCard(
      {super.key, this.title, required this.child, this.trailing});

  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FuelPayColors.surface,
        borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
        border: Border.all(color: FuelPayColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: FuelPayColors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: FuelPaySpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}

/// Filled button with an integrated loading state and large touch target.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.style = AppButtonStyle.primary,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final AppButtonStyle style;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final Widget button = switch (style) {
      AppButtonStyle.primary => ElevatedButton(
          onPressed: enabled ? onPressed : null,
          child: _child(),
        ),
      AppButtonStyle.outlined => OutlinedButton(
          onPressed: enabled ? onPressed : null,
          child: _child(),
        ),
      AppButtonStyle.danger => ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FuelPayColors.error,
            foregroundColor: Colors.white,
          ),
          child: _child(),
        ),
      AppButtonStyle.success => ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FuelPayColors.success,
            foregroundColor: Colors.white,
          ),
          child: _child(),
        ),
    };
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  Widget _child() {
    if (loading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22),
          const SizedBox(width: 10),
        ],
        Text(label),
      ],
    );
  }
}

enum AppButtonStyle { primary, outlined, danger, success }

/// Big rupees amount display.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay(this.amount, {super.key, this.fontSize = 44, this.color});

  final int amount;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '₹${_format(amount)}',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
        color: color ?? FuelPayColors.textPrimary,
      ),
    );
  }

  static String _format(int amount) {
    final s = amount.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

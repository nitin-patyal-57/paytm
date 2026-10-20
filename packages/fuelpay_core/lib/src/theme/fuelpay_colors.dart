import 'package:flutter/material.dart';

/// FuelPay design tokens — light, modern, blue/teal digital-payment look.
/// Temporary branding; not affiliated with any real payment brand.
abstract final class FuelPayColors {
  // Brand
  static const Color primary = Color(0xFF0B63F6); // confident blue
  static const Color primaryDark = Color(0xFF0A4FCC);
  static const Color secondary = Color(0xFF00B39F); // teal accent
  static const Color secondaryDark = Color(0xFF008F80);

  // Surfaces
  static const Color background = Color(0xFFF6F8FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEEF2F8);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF5B6B7F);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Feedback
  static const Color success = Color(0xFF12B76A);
  static const Color successBackground = Color(0xFFE7F8F0);
  static const Color error = Color(0xFFEF4444);
  static const Color errorBackground = Color(0xFFFDECEC);
  static const Color warning = Color(0xFFF79009);
  static const Color warningBackground = Color(0xFFFFF4E5);
  static const Color info = Color(0xFF2E90FA);
  static const Color infoBackground = Color(0xFFEAF2FE);

  // Lines
  static const Color border = Color(0xFFE1E7F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  // Demo-mode accents (used for every "not a real payment" label)
  static const Color demoBadgeBg = Color(0xFFFFF4E5);
  static const Color demoBadgeFg = Color(0xFFB54708);
}

/// Spacing scale for consistent rhythm across screens.
abstract final class FuelPaySpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Minimum touch target for tablet use.
  static const double touchTarget = 56;
  static const double primaryButtonHeight = 64;
  static const double radius = 16;
  static const double radiusSmall = 10;
}

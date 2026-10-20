import 'package:flutter/material.dart';

import 'fuelpay_colors.dart';

/// Central theme builder so both apps look consistent and professional.
abstract final class FuelPayTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: FuelPayColors.background,
      colorScheme: const ColorScheme.light(
        primary: FuelPayColors.primary,
        onPrimary: FuelPayColors.textOnPrimary,
        secondary: FuelPayColors.secondary,
        onSecondary: FuelPayColors.textOnPrimary,
        surface: FuelPayColors.surface,
        onSurface: FuelPayColors.textPrimary,
        error: FuelPayColors.error,
        onError: FuelPayColors.textOnPrimary,
        outline: FuelPayColors.border,
      ),
      splashFactory: InkSparkle.splashFactory,
    );

    const textTheme = TextTheme(
      displaySmall: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: FuelPayColors.textPrimary,
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: FuelPayColors.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: FuelPayColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: FuelPayColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: FuelPayColors.textPrimary,
      ),
      bodyLarge: TextStyle(
          fontSize: 17, height: 1.4, color: FuelPayColors.textPrimary),
      bodyMedium: TextStyle(
          fontSize: 15, height: 1.45, color: FuelPayColors.textSecondary),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: FuelPayColors.textPrimary,
      ),
      labelSmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: FuelPayColors.textSecondary,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: FuelPayColors.surface,
        foregroundColor: FuelPayColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: FuelPayColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: FuelPayColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
          side: const BorderSide(color: FuelPayColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: FuelPayColors.primary,
          foregroundColor: FuelPayColors.textOnPrimary,
          disabledBackgroundColor: FuelPayColors.surfaceMuted,
          disabledForegroundColor: FuelPayColors.textSecondary,
          minimumSize: const Size(0, FuelPaySpacing.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: FuelPaySpacing.xl,
            vertical: FuelPaySpacing.lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FuelPayColors.primary,
          minimumSize: const Size(0, FuelPaySpacing.primaryButtonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: FuelPaySpacing.xl,
            vertical: FuelPaySpacing.lg,
          ),
          side: const BorderSide(color: FuelPayColors.primary, width: 1.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FuelPaySpacing.radius),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: FuelPayColors.primary,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FuelPayColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FuelPaySpacing.lg,
          vertical: FuelPaySpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
          borderSide: const BorderSide(color: FuelPayColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
          borderSide: const BorderSide(color: FuelPayColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
          borderSide: const BorderSide(color: FuelPayColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
          borderSide: const BorderSide(color: FuelPayColors.error),
        ),
        labelStyle: const TextStyle(color: FuelPayColors.textSecondary),
      ),
      dividerTheme:
          const DividerThemeData(color: FuelPayColors.border, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: FuelPayColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FuelPaySpacing.radiusSmall),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: FuelPayColors.primary,
      ),
    );
  }
}

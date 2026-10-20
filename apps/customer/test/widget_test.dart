import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'package:fuelpay_customer/screens/splash_screen.dart';

void main() {
  testWidgets('splash screen renders brand and loader', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.text('FuelPay'), findsOneWidget);
    expect(find.text('Drive. Pay. Go.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shared design system is wired into the app', (tester) async {
    expect(FuelPayColors.primary, isNotNull);
    expect(AmountValidator.isValid(500), isTrue);
    expect(AmountValidator.isValid(50), isFalse);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fuelpay_pump/screens/history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('history screen renders stored transactions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalTransactionStore.open();
    final tx = FuelTransaction.create(
      transactionId: 'FP100001',
      fuelType: FuelType.petrol,
      amount: 500,
    );
    await store.saveTransaction(tx);

    await tester.pumpWidget(MaterialApp(home: HistoryScreen(store: store)));

    expect(find.text('Transaction history'), findsOneWidget);
    expect(find.textContaining('FP100001'), findsOneWidget);
    expect(find.textContaining('₹500'), findsOneWidget);
  });

  testWidgets('history shows empty state with filters', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalTransactionStore.open();

    await tester.pumpWidget(MaterialApp(home: HistoryScreen(store: store)));

    expect(find.text('No transactions match this filter yet.'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
  });
}

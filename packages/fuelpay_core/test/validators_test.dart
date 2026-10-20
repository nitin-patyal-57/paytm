import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

void main() {
  group('AmountValidator', () {
    test('accepts boundaries and rejects out-of-range values', () {
      expect(AmountValidator.isValid(100), isTrue);
      expect(AmountValidator.isValid(10000), isTrue);
      expect(AmountValidator.isValid(99), isFalse);
      expect(AmountValidator.isValid(10001), isFalse);
      expect(AmountValidator.isValid(0), isFalse);
      expect(AmountValidator.isValid(-100), isFalse);
      expect(AmountValidator.isValid(null), isFalse);
    });

    test('predefined amounts are all valid', () {
      for (final a in AmountValidator.predefinedAmounts) {
        expect(AmountValidator.isValid(a), isTrue, reason: '₹$a');
      }
      expect(AmountValidator.predefinedAmounts,
          [100, 500, 1000, 2000, 5000, 10000]);
    });

    test('tryParse accepts plain and comma-grouped input', () {
      expect(AmountValidator.tryParse('500'), 500);
      expect(AmountValidator.tryParse(' 1,000 '), 1000);
      expect(AmountValidator.tryParse('10000'), 10000);
    });

    test('tryParse rejects junk, decimals, empties and out-of-range', () {
      expect(AmountValidator.tryParse(''), isNull);
      expect(AmountValidator.tryParse('abc'), isNull);
      expect(AmountValidator.tryParse('50.5'), isNull);
      expect(AmountValidator.tryParse('99'), isNull);
      expect(AmountValidator.tryParse('20000'), isNull);
      expect(AmountValidator.tryParse('-500'), isNull);
      expect(AmountValidator.tryParse('12a'), isNull);
    });

    test('parse throws FormatException with helpful message', () {
      expect(
        () => AmountValidator.parse('10'),
        throwsA(isA<FormatException>()),
      );
    });

    test('format groups thousands', () {
      expect(AmountValidator.format(100), '100');
      expect(AmountValidator.format(1000), '1,000');
      expect(AmountValidator.format(10000), '10,000');
      expect(AmountValidator.format(500), '500');
    });
  });

  group('TransactionId', () {
    test('generated ids match the wire pattern', () {
      for (var i = 0; i < 100; i++) {
        expect(TransactionId.isValid(TransactionId.generate()), isTrue);
      }
    });

    test('ids are unique across many generations', () {
      final ids = <String>{};
      for (var i = 0; i < 2000; i++) {
        ids.add(TransactionId.generate());
      }
      expect(ids.length, 2000);
    });

    test('isValid rejects malformed ids', () {
      expect(TransactionId.isValid('FP100001'), isTrue);
      expect(TransactionId.isValid('FP1'), isFalse);
      expect(TransactionId.isValid('XX100001'), isFalse);
      expect(TransactionId.isValid('FPabcdef'), isFalse);
      expect(TransactionId.isValid(null), isFalse);
      expect(TransactionId.isValid(''), isFalse);
      expect(TransactionId.isValid('FP100001 '), isFalse);
    });

    test('generateUnique skips taken ids', () {
      final taken = <String>{};
      for (var i = 0; i < 50; i++) {
        final id = TransactionId.generateUnique(taken.contains);
        expect(taken.contains(id), isFalse);
        taken.add(id);
      }
    });
  });
}

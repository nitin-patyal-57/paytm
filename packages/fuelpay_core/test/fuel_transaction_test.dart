import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

void main() {
  group('FuelTransaction', () {
    FuelTransaction sample(
        {TransactionStatus status = TransactionStatus.created}) {
      final tx = FuelTransaction.create(
        transactionId: 'FP100001',
        fuelType: FuelType.petrol,
        amount: 500,
        now: DateTime.utc(2026, 1, 1, 10),
      );
      return status == TransactionStatus.created
          ? tx
          : tx.copyWith(
              status: status, updatedAt: DateTime.utc(2026, 1, 1, 11));
    }

    test('create sets defaults matching the spec example', () {
      final tx = sample();
      expect(tx.transactionId, 'FP100001');
      expect(tx.fuelType, FuelType.petrol);
      expect(tx.amount, 500);
      expect(tx.currency, 'INR');
      expect(tx.status, TransactionStatus.created);
      expect(tx.mode, PaymentMode.demo);
      expect(tx.isDemo, isTrue);
    });

    test('json round trip preserves every field', () {
      final tx = sample(status: TransactionStatus.paymentSuccess).copyWith(
        paymentProvider: 'DEMO',
        statusReason: 'DEMO_SUCCESS',
        completedAt: DateTime.utc(2026, 1, 1, 12),
      );
      final restored = FuelTransaction.fromJson(tx.toJson());
      expect(restored.transactionId, tx.transactionId);
      expect(restored.fuelType, tx.fuelType);
      expect(restored.amount, tx.amount);
      expect(restored.currency, tx.currency);
      expect(restored.status, tx.status);
      expect(restored.mode, tx.mode);
      expect(restored.paymentProvider, 'DEMO');
      expect(restored.statusReason, 'DEMO_SUCCESS');
      expect(restored.createdAt, tx.createdAt);
      expect(restored.updatedAt, tx.updatedAt);
      expect(restored.completedAt, tx.completedAt);
    });

    test('json uses backend wire names', () {
      final json = sample().toJson();
      expect(
          json.keys,
          containsAll([
            'transactionId',
            'fuelType',
            'amount',
            'currency',
            'status',
            'mode'
          ]));
      expect(json['fuelType'], 'PETROL');
      expect(json['status'], 'CREATED');
      expect(json['mode'], 'DEMO');
      expect(json['amount'], 500);
    });

    test('fromJson rejects unknown statuses', () {
      expect(
        () => FuelTransaction.fromJson(sample().toJson()..['status'] = 'PAID'),
        throwsArgumentError,
      );
      expect(
        () => FuelTransaction.fromJson(sample().toJson()..['fuelType'] = 'JET'),
        throwsArgumentError,
      );
    });

    test('matchesIdentity catches amount/tampering/id mismatches', () {
      final a = sample();
      final same = FuelTransaction.create(
        transactionId: 'FP100001',
        fuelType: FuelType.petrol,
        amount: 500,
      );
      expect(a.matchesIdentity(same), isTrue);

      final differentAmount = FuelTransaction.create(
        transactionId: 'FP100001',
        fuelType: FuelType.petrol,
        amount: 1000,
      );
      expect(a.matchesIdentity(differentAmount), isFalse);

      final differentId = FuelTransaction.create(
        transactionId: 'FP999999',
        fuelType: FuelType.petrol,
        amount: 500,
      );
      expect(a.matchesIdentity(differentId), isFalse);

      final differentFuel = FuelTransaction.create(
        transactionId: 'FP100001',
        fuelType: FuelType.diesel,
        amount: 500,
      );
      expect(a.matchesIdentity(differentFuel), isFalse);
    });

    test('transaction QR payload is minimal and non-sensitive', () {
      final payload = sample().toQrPayload();
      expect(payload['kind'], 'fuelpay-transaction');
      expect(payload['v'], 1);
      expect(payload['tx'], 'FP100001');
      expect(payload['fuel'], 'PETROL');
      expect(payload['amt'], 500);
      expect(payload['cur'], 'INR');
      expect(payload['mode'], 'DEMO');
      // No unexpected keys (no credentials / personal data could hide here).
      expect(payload.keys.toSet(),
          {'v', 'kind', 'mode', 'tx', 'fuel', 'amt', 'cur'});
      final encoded = payload.toString().toLowerCase();
      expect(encoded.contains('password'), isFalse);
      expect(encoded.contains('secret'), isFalse);
      expect(encoded.contains('token'), isFalse);
      expect(encoded.contains('phone'), isFalse);
    });

    test('terminal status helpers', () {
      expect(TransactionStatus.paymentSuccess.isTerminal, isTrue);
      expect(TransactionStatus.paymentFailed.isTerminal, isTrue);
      expect(TransactionStatus.cancelled.isTerminal, isTrue);
      expect(TransactionStatus.expired.isTerminal, isTrue);
      expect(TransactionStatus.paymentPending.isTerminal, isFalse);
      expect(TransactionStatus.created.isTerminal, isFalse);

      expect(TransactionStatus.paymentSuccess.isPaymentOutcome, isTrue);
      expect(TransactionStatus.paymentFailed.isPaymentOutcome, isTrue);
      expect(TransactionStatus.cancelled.isPaymentOutcome, isFalse);
    });

    test('status labels are human friendly', () {
      expect(TransactionStatus.paymentSuccess.label.toLowerCase(),
          contains('paid'));
      expect(TransactionStatus.paymentPending.label.toLowerCase(),
          contains('awaiting'));
      expect(TransactionStatus.cancelled.label, 'Cancelled');
    });
  });
}

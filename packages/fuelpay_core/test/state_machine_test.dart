import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

void main() {
  group('TransactionStateMachine', () {
    test('allows the documented happy path', () {
      const path = [
        TransactionStatus.created,
        TransactionStatus.requestSent,
        TransactionStatus.requestReceived,
        TransactionStatus.accepted,
        TransactionStatus.qrReady,
        TransactionStatus.paymentPending,
        TransactionStatus.paymentSuccess,
      ];
      for (var i = 0; i < path.length - 1; i++) {
        expect(
          TransactionStateMachine.canTransition(path[i], path[i + 1]),
          isTrue,
          reason: '${path[i].wireName} -> ${path[i + 1].wireName}',
        );
      }
    });

    test('rejects skipping states and illegal jumps', () {
      expect(
        TransactionStateMachine.canTransition(
            TransactionStatus.created, TransactionStatus.paymentSuccess),
        isFalse,
      );
      expect(
        TransactionStateMachine.canTransition(
            TransactionStatus.requestSent, TransactionStatus.accepted),
        isFalse,
      );
      expect(
        TransactionStateMachine.canTransition(
            TransactionStatus.accepted, TransactionStatus.paymentSuccess),
        isFalse,
      );
      expect(
        TransactionStateMachine.canTransition(
            TransactionStatus.paymentPending, TransactionStatus.created),
        isFalse,
      );
    });

    test('terminal states have no exits', () {
      for (final terminal in [
        TransactionStatus.paymentSuccess,
        TransactionStatus.paymentFailed,
        TransactionStatus.cancelled,
        TransactionStatus.expired,
      ]) {
        expect(terminal.isTerminal, isTrue);
        for (final target in TransactionStatus.values) {
          expect(
            TransactionStateMachine.canTransition(terminal, target),
            isFalse,
            reason:
                '${terminal.wireName} -> ${target.wireName} must be rejected',
          );
        }
      }
    });

    test('failed payment cannot become successful without a new attempt', () {
      expect(
        TransactionStateMachine.canTransition(
            TransactionStatus.paymentFailed, TransactionStatus.paymentSuccess),
        isFalse,
      );
    });

    test('assertTransition throws InvalidTransitionException', () {
      expect(
        () => TransactionStateMachine.assertTransition(
          TransactionStatus.paymentSuccess,
          TransactionStatus.paymentFailed,
        ),
        throwsA(isA<InvalidTransitionException>()),
      );
      expect(
        () => TransactionStateMachine.assertTransition(
          TransactionStatus.created,
          TransactionStatus.requestSent,
        ),
        returnsNormally,
      );
    });

    test('status wire round-trip', () {
      for (final s in TransactionStatus.values) {
        expect(TransactionStatus.fromWire(s.wireName), s);
        expect(TransactionStatus.tryFromWire(s.wireName), s);
      }
      expect(TransactionStatus.tryFromWire('PAID'), isNull);
      expect(() => TransactionStatus.fromWire('PAID'), throwsArgumentError);
    });

    test('mirrors the backend transition table exactly', () {
      const backendTable = {
        'CREATED': ['REQUEST_SENT', 'CANCELLED', 'EXPIRED'],
        'REQUEST_SENT': ['REQUEST_RECEIVED', 'CANCELLED', 'EXPIRED'],
        'REQUEST_RECEIVED': ['ACCEPTED', 'CANCELLED', 'EXPIRED'],
        'ACCEPTED': ['QR_READY', 'CANCELLED', 'EXPIRED'],
        'QR_READY': [
          'PAYMENT_PENDING',
          'PAYMENT_SUCCESS',
          'PAYMENT_FAILED',
          'CANCELLED',
          'EXPIRED'
        ],
        'PAYMENT_PENDING': [
          'PAYMENT_SUCCESS',
          'PAYMENT_FAILED',
          'CANCELLED',
          'EXPIRED'
        ],
        'PAYMENT_SUCCESS': <String>[],
        'PAYMENT_FAILED': <String>[],
        'CANCELLED': <String>[],
        'EXPIRED': <String>[],
      };
      expect(backendTable.length, TransactionStatus.values.length);
      backendTable.forEach((from, targets) {
        final fromStatus = TransactionStatus.fromWire(from);
        final allowed = TransactionStateMachine.allowedTargets(fromStatus)
            .map((s) => s.wireName)
            .toSet();
        expect(allowed, targets.toSet(), reason: 'table mismatch for $from');
      });
    });
  });
}

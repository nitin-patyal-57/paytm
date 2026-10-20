import '../models/fuel_transaction.dart';
import '../models/transaction_status.dart';
import '../state/transaction_state_machine.dart';

/// Raised when a local demo payment simulation cannot be applied.
class LocalPaymentException implements Exception {
  LocalPaymentException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'LocalPaymentException($code): $message';
}

/// Result of a local demo payment simulation.
class LocalPaymentResult {
  const LocalPaymentResult(
      {required this.transaction, required this.alreadyProcessed});

  final FuelTransaction transaction;
  final bool alreadyProcessed;
}

/// Offline fallback of the backend's demo payment service.
///
/// Mirrors backend/src/services/paymentService.js rules exactly:
///  - only DEMO transactions can be simulated,
///  - identical replays are idempotent,
///  - conflicting outcomes on terminal transactions are rejected,
///  - only ACCEPTED / QR_READY / PAYMENT_PENDING are payable,
///  - all transitions go through the shared state machine.
class LocalDemoPayment {
  LocalDemoPayment._();

  static const _payable = [
    TransactionStatus.accepted,
    TransactionStatus.qrReady,
    TransactionStatus.paymentPending,
  ];

  static LocalPaymentResult simulate(FuelTransaction tx,
      {required bool success}) {
    if (tx.mode != PaymentMode.demo) {
      throw LocalPaymentException('NOT_DEMO_TRANSACTION',
          'Simulation applies only to DEMO mode transactions.');
    }

    final outcome = success
        ? TransactionStatus.paymentSuccess
        : TransactionStatus.paymentFailed;

    if (tx.status.isTerminal) {
      if (tx.status == outcome) {
        return LocalPaymentResult(transaction: tx, alreadyProcessed: true);
      }
      throw LocalPaymentException(
        'ALREADY_FINALIZED',
        'Transaction is already ${tx.status.wireName}; a different outcome cannot be applied.',
      );
    }

    if (!_payable.contains(tx.status)) {
      throw LocalPaymentException(
        'NOT_PAYABLE',
        'Transaction in status ${tx.status.wireName} cannot be paid.',
      );
    }

    var current = tx;
    // Fast-forward ACCEPTED -> QR_READY -> PAYMENT_PENDING.
    for (final step in const [
      TransactionStatus.qrReady,
      TransactionStatus.paymentPending,
    ]) {
      if (TransactionStateMachine.canTransition(current.status, step)) {
        current = current.copyWith(
          status: step,
          paymentProvider: 'DEMO',
          updatedAt: DateTime.now(),
        );
      }
    }

    if (current.status != TransactionStatus.paymentPending) {
      throw LocalPaymentException('CONFLICT',
          'Unexpected status ${current.status.wireName} before payment.');
    }

    final finalTx = current.copyWith(
      status: outcome,
      paymentProvider: 'DEMO',
      statusReason: success ? 'DEMO_SUCCESS' : 'DEMO_FAILED',
      updatedAt: DateTime.now(),
      completedAt: DateTime.now(),
    );
    return LocalPaymentResult(transaction: finalTx, alreadyProcessed: false);
  }
}

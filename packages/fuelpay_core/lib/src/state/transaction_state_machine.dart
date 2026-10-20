import '../models/transaction_status.dart';

/// Thrown when an illegal transaction state transition is attempted.
class InvalidTransitionException implements Exception {
  InvalidTransitionException(this.from, this.to);
  final TransactionStatus from;
  final TransactionStatus to;

  @override
  String toString() => 'Invalid transaction transition: '
      '${from.wireName} -> ${to.wireName}';
}

/// Transaction state machine — mirrors
/// backend/src/stateMachine.js EXACTLY. Keep both files in sync.
///
/// Only listed transitions are legal; terminal states have no exits.
class TransactionStateMachine {
  const TransactionStateMachine._();

  static const Map<TransactionStatus, List<TransactionStatus>> _allowed = {
    TransactionStatus.created: [
      TransactionStatus.requestSent,
      TransactionStatus.cancelled,
      TransactionStatus.expired,
    ],
    TransactionStatus.requestSent: [
      TransactionStatus.requestReceived,
      TransactionStatus.cancelled,
      TransactionStatus.expired,
    ],
    TransactionStatus.requestReceived: [
      TransactionStatus.accepted,
      TransactionStatus.cancelled,
      TransactionStatus.expired,
    ],
    TransactionStatus.accepted: [
      TransactionStatus.qrReady,
      TransactionStatus.cancelled,
      TransactionStatus.expired,
    ],
    TransactionStatus.qrReady: [
      TransactionStatus.paymentPending,
      TransactionStatus.paymentSuccess,
      TransactionStatus.paymentFailed,
      TransactionStatus.cancelled,
      TransactionStatus.expired,
    ],
    TransactionStatus.paymentPending: [
      TransactionStatus.paymentSuccess,
      TransactionStatus.paymentFailed,
      TransactionStatus.cancelled,
      TransactionStatus.expired,
    ],
    TransactionStatus.paymentSuccess: [],
    TransactionStatus.paymentFailed: [],
    TransactionStatus.cancelled: [],
    TransactionStatus.expired: [],
  };

  static bool canTransition(TransactionStatus from, TransactionStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  /// Throws [InvalidTransitionException] when the move is illegal.
  static void assertTransition(TransactionStatus from, TransactionStatus to) {
    if (!canTransition(from, to)) {
      throw InvalidTransitionException(from, to);
    }
  }

  static List<TransactionStatus> allowedTargets(TransactionStatus from) =>
      List.unmodifiable(_allowed[from] ?? const <TransactionStatus>[]);

  /// Applies a validated transition to [current].
  static TransactionStatus apply(
      TransactionStatus current, TransactionStatus target) {
    assertTransition(current, target);
    return target;
  }

  /// Shortest legal path from [from] to [to] (inclusive of [to]), or `null`
  /// when [to] is unreachable.
  ///
  /// Used when a Bluetooth message carries a status that skipped intermediate
  /// states (e.g. a dropped ACCEPTED notification): the receiver can replay
  /// the missing steps instead of rejecting the update. Terminal states and
  /// backwards moves yield `null` unless [to] == [from].
  static List<TransactionStatus>? path(
      TransactionStatus from, TransactionStatus to) {
    if (from == to) return const [];
    if (from.isTerminal) return null;
    final visited = <TransactionStatus>{from};
    final queue = <List<TransactionStatus>>[
      [from]
    ];
    while (queue.isNotEmpty) {
      final currentPath = queue.removeAt(0);
      final current = currentPath.last;
      for (final next in _allowed[current] ?? const <TransactionStatus>[]) {
        if (next == to) return [...currentPath, next];
        if (visited.add(next)) {
          queue.add([...currentPath, next]);
        }
      }
    }
    return null;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'ble_central_service.dart';

/// Coarse navigation stage for the customer app (single-activity state
/// machine — the root widget renders the stage's screen).
enum FlowStage { splash, home, amount, scan, qr, waiting, result, ad }

/// Orchestrates the customer-side demo flow:
///
/// fuel + amount -> create transaction (local + backend best effort)
/// -> scan/connect pump -> show transaction QR + send PAYMENT_REQUEST
/// -> waiting for pump ack/decision/payment status -> result
/// -> one 5-second advertisement on success.
///
/// Local persistence is authoritative; backend replication is best effort
/// and queued when the backend is unreachable.
class CustomerTransactionFlow extends ChangeNotifier {
  CustomerTransactionFlow({
    required this.api,
    required this.store,
    required this.ble,
  });

  final FuelPayApiClient api;
  final LocalTransactionStore store;
  final BleCentralService ble;

  StreamSubscription<ProtocolMessage>? _msgSub;
  StreamSubscription<ProtocolException>? _errSub;
  bool _started = false;
  bool _pendingResend = false;

  FlowStage stage = FlowStage.splash;
  FuelType? fuel;
  int? amount;
  FuelTransaction? active;
  String? error;
  bool busy = false;
  bool requestSent = false;
  bool pumpAcknowledged = false;

  /// Furthest non-terminal state reached — preserved when the transaction
  /// ends in a terminal state (so result screens can show real progress).
  TransactionStatus? furthestStatus;

  /// True when the most recent backend replication succeeded (hint only —
  /// the app keeps working without the backend).
  bool backendOnline = true;

  FuelTransaction? get recoveredTransaction => store.recoverActiveTransaction();

  String? get pumpName => ble.pumpDisplayName;

  bool get resultIsSuccess =>
      active?.status == TransactionStatus.paymentSuccess;

  /// True once the five-second advertisement already played for the active
  /// transaction (guards double playback after a restart).
  bool get advertisementPlayed =>
      active != null && store.hasPlayedAdvertisement(active!.transactionId);

  // ------------------------------------------------------------------ boot

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _msgSub = ble.messages.listen(_onMessage);
    _errSub = ble.protocolErrors.listen((e) {
      error = e.message;
      notifyListeners();
    });
    ble.addListener(_onBleChanged);

    final flushed = await flushSyncQueue(api, store).catchError((_) => 0);
    backendOnline = flushed >= 0; // queue drained or backend still down

    final recovered = store.recoverActiveTransaction();
    if (recovered != null) {
      active = recovered;
      furthestStatus = recovered.status;
      requestSent = recovered.status != TransactionStatus.created;
      pumpAcknowledged =
          recovered.status != TransactionStatus.created &&
          recovered.status != TransactionStatus.requestSent;
      stage = FlowStage.waiting;
    } else {
      stage = FlowStage.home;
    }
    notifyListeners();
  }

  void _onBleChanged() {
    if (!ble.isConnected) {
      if (active != null &&
          !active!.status.isTerminal &&
          (stage == FlowStage.qr || stage == FlowStage.waiting)) {
        _pendingResend = true;
      }
      notifyListeners();
      return;
    }
    if (_pendingResend) {
      _pendingResend = false;
      _sendRequest();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- selection

  void selectFuel(FuelType type) {
    fuel = type;
    notifyListeners();
  }

  void setAmount(int value) {
    amount = value;
    error = null;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ navigation

  void go(FlowStage next) {
    stage = next;
    error = null;
    notifyListeners();
  }

  // ----------------------------------------------------------- transaction

  Future<void> createTransaction() async {
    final selectedFuel = fuel;
    final selectedAmount = amount;
    if (selectedFuel == null || !AmountValidator.isValid(selectedAmount)) {
      error = 'Pick a fuel type and an amount first.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final id = TransactionId.generateUnique(store.hasTransaction);
      final tx = FuelTransaction.create(
        transactionId: id,
        fuelType: selectedFuel,
        amount: selectedAmount!,
      );
      await store.saveTransaction(tx);
      await store.setActiveTransactionId(id);
      active = tx;
      requestSent = false;
      pumpAcknowledged = false;
      furthestStatus = null;
      _pendingResend = false;

      try {
        await api.createTransaction(
          transactionId: id,
          fuelType: selectedFuel,
          amount: selectedAmount,
        );
        backendOnline = true;
      } on ApiException catch (e) {
        if (e.isNetwork) {
          backendOnline = false;
          await store.enqueueSync(
            SyncJob(
              method: 'POST',
              path: '/api/transactions',
              body: <String, dynamic>{
                'transactionId': id,
                'fuelType': selectedFuel.wireName,
                'amount': selectedAmount,
                'currency': 'INR',
                'mode': PaymentMode.demo.wireName,
              },
            ),
          );
        } else {
          // Duplicate/validation: local copy stays authoritative.
          backendOnline = false;
        }
      }
      stage = FlowStage.scan;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Called by the scan screen once the pump connection + handshake succeed.
  Future<void> onPumpConnected() async {
    stage = FlowStage.qr;
    notifyListeners();
    await _sendRequest();
  }

  Future<void> _sendRequest() async {
    final tx = active;
    if (tx == null || tx.status.isTerminal || !ble.isConnected) return;
    try {
      await ble.send(
        PaymentRequestMessage(
          transactionId: tx.transactionId,
          fuelType: tx.fuelType,
          amount: tx.amount,
        ),
      );
      requestSent = true;
      if (tx.status == TransactionStatus.created) {
        await _advance(TransactionStatus.requestSent);
      }
    } catch (e) {
      error = 'Could not send the request: $e';
      notifyListeners();
    }
  }

  /// User-initiated cancel: notify the pump (best effort), mark locally and
  /// replicate to the backend (best effort).
  Future<void> cancelActive({String? reason}) async {
    final tx = active;
    if (tx == null || tx.status.isTerminal) return;
    final why = reason ?? 'Cancelled by customer';
    if (ble.isConnected) {
      try {
        await ble.send(
          CancelTransactionMessage(
            transactionId: tx.transactionId,
            reason: why,
          ),
        );
      } catch (_) {
        // Pump may already be gone — local cancel still proceeds.
      }
    }
    await _advance(TransactionStatus.cancelled, reason: why);
  }

  /// Clears the finished transaction and returns home for the next customer.
  void resetTransaction() {
    active = null;
    fuel = null;
    amount = null;
    error = null;
    requestSent = false;
    pumpAcknowledged = false;
    furthestStatus = null;
    _pendingResend = false;
    stage = FlowStage.home;
    notifyListeners();
  }

  // ------------------------------------------------------- BLE messages

  Future<void> _onMessage(ProtocolMessage message) async {
    final tx = active;
    switch (message) {
      case HelloAckMessage():
        // Pump name refreshed inside the BLE service; repaint headers.
        notifyListeners();
      case RequestReceivedMessage():
        if (tx == null || message.transactionId != tx.transactionId) return;
        pumpAcknowledged = true;
        await _advance(TransactionStatus.requestReceived);
        if (stage == FlowStage.qr) {
          stage = FlowStage.waiting;
          notifyListeners();
        }
      case RequestDecisionMessage():
        if (tx == null || message.transactionId != tx.transactionId) return;
        if (message.isAccepted) {
          await _advance(TransactionStatus.accepted);
        } else {
          await _advance(
            TransactionStatus.cancelled,
            reason: message.reason ?? 'Rejected by pump',
          );
        }
      case PaymentStatusMessage():
        if (tx == null || message.transactionId != tx.transactionId) return;
        if (message.mode != tx.mode) {
          error = 'Ignoring status with a different payment mode.';
          notifyListeners();
          return;
        }
        await _advance(message.status);
        if (stage == FlowStage.qr && pumpAcknowledged) {
          stage = FlowStage.waiting;
        }
        if (active?.status.isTerminal == true) {
          stage = FlowStage.result;
        }
        notifyListeners();
      case CancelTransactionMessage():
        if (tx == null || message.transactionId != tx.transactionId) return;
        await _advance(
          TransactionStatus.cancelled,
          reason: message.reason ?? 'Cancelled by pump',
        );
      case ProtocolErrorMessage():
        if (message.transactionId != null &&
            tx != null &&
            message.transactionId != tx.transactionId) {
          return;
        }
        error = message.message;
        notifyListeners();
      case HelloMessage():
        break; // customers never receive HELLO
    }
  }

  // ------------------------------------------------------- state advance

  /// Moves the local transaction to [target], replaying any intermediate
  /// legal steps when a Bluetooth message skipped states (dropped notify).
  Future<void> _advance(TransactionStatus target, {String? reason}) async {
    final tx = active;
    if (tx == null) return;
    if (tx.status == target) {
      notifyListeners();
      return;
    }
    final path = TransactionStateMachine.path(tx.status, target);
    if (path == null || path.isEmpty) {
      // Unreachable (backwards move or already terminal) — ignore safely.
      return;
    }
    for (final step in path) {
      final isLast = step == path.last;
      await _apply(step, reason: isLast ? reason : null);
    }
    if (active?.status.isTerminal == true &&
        stage != FlowStage.result &&
        stage != FlowStage.ad) {
      stage = FlowStage.result;
    }
    notifyListeners();
  }

  Future<void> _apply(TransactionStatus next, {String? reason}) async {
    final tx = active;
    if (tx == null || tx.status == next) return;
    final now = DateTime.now();
    var updated = tx.copyWith(
      status: next,
      statusReason: reason ?? (next.isPaymentOutcome ? tx.statusReason : null),
      updatedAt: now,
      completedAt: next.isTerminal ? now : null,
    );
    if (updated.status == TransactionStatus.paymentSuccess) {
      updated = updated.copyWith(paymentProvider: 'DEMO');
    }
    furthestStatus = next.isTerminal ? (furthestStatus ?? tx.status) : next;
    active = updated;
    await store.saveTransaction(updated);
    if (updated.status.isTerminal) {
      await store.setActiveTransactionId(null);
    }
    await _syncStatus(updated);
    notifyListeners();
  }

  /// Best-effort backend replication. Payment outcomes are excluded: the
  /// backend only accepts them from its own demo-payment endpoint.
  Future<void> _syncStatus(FuelTransaction tx) async {
    if (tx.status.isPaymentOutcome) return;
    try {
      await api.transition(
        tx.transactionId,
        tx.status,
        reason: tx.statusReason,
      );
      backendOnline = true;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        backendOnline = false;
        await store.enqueueSync(
          SyncJob(
            method: 'POST',
            path: '/api/transactions/${tx.transactionId}/status',
            body: <String, dynamic>{
              'status': tx.status.wireName,
              if (tx.statusReason != null) 'reason': tx.statusReason,
            },
          ),
        );
      } else {
        // 4xx: backend state diverged — local store stays authoritative.
        backendOnline = false;
      }
    } catch (_) {
      backendOnline = false;
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _errSub?.cancel();
    ble.removeListener(_onBleChanged);
    super.dispose();
  }
}

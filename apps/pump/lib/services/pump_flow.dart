import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

import 'ble_peripheral_service.dart';

/// Pump-side orchestration: receives customer requests over BLE, applies the
/// shared state machine, replicates to the backend (best effort) and drives
/// demo payment simulation.
class PumpTransactionFlow extends ChangeNotifier {
  PumpTransactionFlow({
    required this.api,
    required this.store,
    required this.ble,
  });

  final FuelPayApiClient api;
  final LocalTransactionStore store;
  final BlePeripheralService ble;

  StreamSubscription<ProtocolMessage>? _msgSub;
  StreamSubscription<ProtocolException>? _errSub;
  bool _started = false;

  /// Transaction currently being served (non-terminal, or a just-finished
  /// outcome awaiting the attendant's acknowledgement).
  FuelTransaction? active;

  /// Set when a request needs a accept/reject decision (dashboard prompt).
  bool promptRequest = false;

  String? error;
  String? info;
  bool busy = false;
  bool backendOnline = true;

  List<FuelTransaction> history() => store.transactions();

  FuelTransaction? get decisionTransaction =>
      active != null && active!.status == TransactionStatus.requestReceived
      ? active
      : null;

  /// True while the payment QR is available / payment in flight.
  bool get paymentStage {
    final status = active?.status;
    return status == TransactionStatus.accepted ||
        status == TransactionStatus.qrReady ||
        status == TransactionStatus.paymentPending;
  }

  bool get outcomeVisible => active != null && active!.status.isPaymentOutcome;

  // ------------------------------------------------------------------ boot

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _msgSub = ble.messages.listen(_onMessage);
    _errSub = ble.protocolErrors.listen((e) {
      error = e.message;
      notifyListeners();
    });

    await flushSyncQueue(api, store).catchError((_) => 0);

    final recovered = store.recoverActiveTransaction();
    if (recovered != null) {
      active = recovered;
      if (recovered.status == TransactionStatus.requestReceived) {
        promptRequest = true;
      }
    }
    notifyListeners();
  }

  // ----------------------------------------------------------- BLE inbound

  Future<void> _onMessage(ProtocolMessage message) async {
    switch (message) {
      case HelloMessage():
        // Android drops notifies sent before the customer's CCC write lands;
        // wait for the subscription so the ack isn't silently refused.
        await ble.waitForNotifyEnabled(const Duration(seconds: 2));
        try {
          await ble.send(HelloAckMessage(pumpName: ble.displayName));
        } on Exception catch (e) {
          debugPrint('HELLO_ACK failed: $e'); // customer re-sends HELLO
        }
      case PaymentRequestMessage():
        await _handleRequest(message);
      case CancelTransactionMessage():
        await _handleCustomerCancel(message);
      case ProtocolErrorMessage():
        error = message.message;
        notifyListeners();
      case _:
        break; // customers never send decisions/statuses
    }
  }

  Future<void> _handleRequest(PaymentRequestMessage message) async {
    if (message.mode != PaymentMode.demo) {
      await ble.sendError(
        'NOT_DEMO',
        'This pump only serves DEMO mode transactions.',
        transactionId: message.transactionId,
      );
      return;
    }

    final existing = store.transaction(message.transactionId);
    FuelTransaction tx;
    if (existing == null) {
      // Created on the customer device — mirror it here for serving/history.
      tx = FuelTransaction.create(
        transactionId: message.transactionId,
        fuelType: message.fuelType,
        amount: message.amount,
      );
      await store.saveTransaction(tx);
    } else if (existing.amount != message.amount ||
        existing.fuelType != message.fuelType ||
        existing.currency != 'INR') {
      await ble.sendError(
        'VALIDATION_MISMATCH',
        'Transaction details do not match this pump\'s records.',
        transactionId: message.transactionId,
      );
      return;
    } else {
      tx = existing;
    }

    if (tx.status.isTerminal) {
      // Retry for a finished transaction — replay the final status.
      await _sendStateToCustomer(tx);
      return;
    }

    if (active != null &&
        active!.transactionId != tx.transactionId &&
        !active!.status.isTerminal) {
      await ble.sendError(
        'BUSY',
        'Another transaction is in progress on this pump.',
        transactionId: message.transactionId,
      );
      return;
    }

    if (tx.status == TransactionStatus.created ||
        tx.status == TransactionStatus.requestSent) {
      tx = await _advanceLocal(tx, TransactionStatus.requestReceived);
    }
    if (tx.status == TransactionStatus.requestReceived) {
      promptRequest = true;
    }
    active = tx;

    try {
      await ble.send(RequestReceivedMessage(transactionId: tx.transactionId));
      await _sendStateToCustomer(tx);
    } on Exception {
      error = 'Could not acknowledge the customer request.';
    }
    notifyListeners();
  }

  Future<void> _handleCustomerCancel(CancelTransactionMessage message) async {
    final tx = store.transaction(message.transactionId);
    if (tx == null || tx.status.isTerminal) return;
    final updated = await _advanceLocal(
      tx,
      TransactionStatus.cancelled,
      reason: message.reason ?? 'Cancelled by customer',
    );
    if (active?.transactionId == updated.transactionId) {
      active = null;
    }
    promptRequest = false;
    info = 'Customer cancelled ${updated.transactionId}.';
    notifyListeners();
  }

  /// Replays the current decision/status so a reconnecting customer catches
  /// up (identical messages it already processed are deduplicated there).
  Future<void> _sendStateToCustomer(FuelTransaction tx) async {
    switch (tx.status) {
      case TransactionStatus.requestReceived:
        break; // decision still pending — the ack alone is correct
      case TransactionStatus.accepted:
      case TransactionStatus.qrReady:
        await ble.send(
          RequestDecisionMessage(
            transactionId: tx.transactionId,
            decision: RequestDecisionMessage.accepted,
          ),
        );
      case TransactionStatus.paymentPending:
        await ble.send(
          RequestDecisionMessage(
            transactionId: tx.transactionId,
            decision: RequestDecisionMessage.accepted,
          ),
        );
        await ble.send(PaymentStatusMessage.fromTransaction(tx));
      case _:
        await _sendStatusToCustomer(tx);
    }
  }

  /// Sends PAYMENT_STATUS when [tx] carries a status the wire format allows
  /// (EXPIRED never travels over BLE).
  Future<void> _sendStatusToCustomer(FuelTransaction tx) async {
    final sendable =
        tx.status == TransactionStatus.paymentPending ||
        tx.status == TransactionStatus.paymentSuccess ||
        tx.status == TransactionStatus.paymentFailed ||
        tx.status == TransactionStatus.cancelled;
    if (!sendable) return;
    try {
      await ble.send(PaymentStatusMessage.fromTransaction(tx));
    } on Exception {
      // Customer left — local/backend state already reflects the outcome.
    }
  }

  // ------------------------------------------------------------- decisions

  /// Accepts the pending request: ACCEPTED -> QR_READY -> PAYMENT_PENDING
  /// locally (each step synced) and notifies the customer.
  Future<String?> acceptRequest() async {
    final tx = active;
    if (tx == null || tx.status.isTerminal) {
      return 'No request to accept.';
    }
    busy = true;
    error = null;
    notifyListeners();
    var updated = tx;
    try {
      if (updated.status == TransactionStatus.requestReceived) {
        updated = await _advanceLocal(updated, TransactionStatus.accepted);
      }
      if (updated.status == TransactionStatus.accepted) {
        updated = await _advanceLocal(updated, TransactionStatus.qrReady);
      }
      if (updated.status == TransactionStatus.qrReady) {
        updated = await _advanceLocal(
          updated,
          TransactionStatus.paymentPending,
        );
      }
      active = updated;
      promptRequest = false;
      if (ble.customerConnected) {
        try {
          await ble.send(
            RequestDecisionMessage(
              transactionId: updated.transactionId,
              decision: RequestDecisionMessage.accepted,
            ),
          );
          await ble.send(PaymentStatusMessage.fromTransaction(updated));
        } on Exception {
          info =
              'Customer link dropped — the decision will replay on '
              'reconnect.';
        }
      }
      notifyListeners();
      return null;
    } catch (e) {
      error = 'Could not accept the request: $e';
      notifyListeners();
      return error;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Rejects the pending request and cancels the transaction.
  Future<String?> rejectRequest({String? reason}) async {
    final tx = active;
    if (tx == null || tx.status.isTerminal) return 'No request to reject.';
    busy = true;
    notifyListeners();
    final why = reason ?? 'Rejected by pump';
    if (ble.customerConnected) {
      try {
        await ble.send(
          RequestDecisionMessage(
            transactionId: tx.transactionId,
            decision: RequestDecisionMessage.rejected,
            reason: why,
          ),
        );
      } on Exception {
        // Customer will see the local cancel via its own timeout/back path.
      }
    }
    await _advanceLocal(tx, TransactionStatus.cancelled, reason: why);
    active = null;
    promptRequest = false;
    info = 'Request rejected.';
    busy = false;
    notifyListeners();
    return null;
  }

  // -------------------------------------------------------------- payments

  /// Runs the demo payment simulation (backend first, local fallback when
  /// offline) and pushes the outcome to the customer.
  /// Returns `null` on success or a user-facing error message.
  Future<String?> simulatePayment({required bool success}) async {
    final tx = active;
    if (tx == null || tx.status.isTerminal) {
      return 'No payable transaction.';
    }
    if (!tx.isDemo) return 'Only DEMO transactions can be simulated.';
    busy = true;
    error = null;
    notifyListeners();

    FuelTransaction result;
    try {
      result = await api.simulateDemoPayment(
        tx.transactionId,
        success: success,
      );
      backendOnline = true;
    } on ApiException catch (e) {
      final handled = await _resolveSimulationError(tx, e, success: success);
      if (handled == null) {
        busy = false;
        notifyListeners();
        return error;
      }
      result = handled;
    }

    final updated = await _advanceLocal(
      tx,
      result.status,
      reason: result.statusReason,
    );
    active = updated;
    info = updated.status == TransactionStatus.paymentSuccess
        ? 'Demo payment succeeded for ${updated.transactionId}.'
        : 'Demo payment failed for ${updated.transactionId}.';

    if (ble.customerConnected) {
      try {
        await ble.send(PaymentStatusMessage.fromTransaction(updated));
      } on Exception {
        // Best effort — the customer replays status on reconnect.
      }
    }
    busy = false;
    notifyListeners();
    return null;
  }

  /// Maps backend failures to a resolved transaction (retry/offline) or
  /// `null` with `error` set when the simulation cannot proceed.
  Future<FuelTransaction?> _resolveSimulationError(
    FuelTransaction tx,
    ApiException e, {
    required bool success,
  }) async {
    final wanted = success
        ? TransactionStatus.paymentSuccess
        : TransactionStatus.paymentFailed;
    if (e.isNetwork) {
      backendOnline = false;
      try {
        final local = LocalDemoPayment.simulate(tx, success: success);
        if (!local.alreadyProcessed) {
          await store.enqueueSync(
            SyncJob(
              method: 'POST',
              path: '/api/demo-payments/${tx.transactionId}/simulate',
              body: <String, dynamic>{
                'outcome': success ? 'SUCCESS' : 'FAILED',
              },
            ),
          );
        }
        return local.transaction;
      } on LocalPaymentException catch (lp) {
        error = lp.message;
        return null;
      }
    }
    if (e.statusCode == 409 && e.code == 'ALREADY_FINALIZED') {
      try {
        final fresh = await api.getTransaction(tx.transactionId);
        if (fresh.status != wanted) {
          error =
              'Already finalized as ${fresh.status.label} — a different outcome cannot be applied.';
          return null;
        }
        return fresh;
      } on ApiException catch (fetchError) {
        error = fetchError.message;
        return null;
      }
    }
    if (e.statusCode == 409 && e.code == 'NOT_PAYABLE') {
      if (await _catchUpBackend(tx)) {
        try {
          final retried = await api.simulateDemoPayment(
            tx.transactionId,
            success: success,
          );
          backendOnline = true;
          return retried;
        } on ApiException catch (retryError) {
          error = retryError.message;
          return null;
        }
      }
      error = e.message;
      return null;
    }
    error = e.message;
    return null;
  }

  /// Replays this pump's non-outcome history so the backend reaches the
  /// payable PAYMENT_PENDING state (used after offline stretches).
  Future<bool> _catchUpBackend(FuelTransaction tx) async {
    try {
      final snapshot = await api.getStatus(tx.transactionId);
      final path = TransactionStateMachine.path(
        snapshot.status,
        TransactionStatus.paymentPending,
      );
      if (path == null) return false;
      for (final step in path.skip(1)) {
        await api.transition(tx.transactionId, step);
      }
      return true;
    } on ApiException {
      return false;
    }
  }

  // ------------------------------------------------------------- state ops

  /// Applies every legal step from the current status to [target], persisting
  /// and syncing each one (payment outcomes are excluded from generic sync —
  /// they belong exclusively to the demo-payment endpoint).
  Future<FuelTransaction> _advanceLocal(
    FuelTransaction tx,
    TransactionStatus target, {
    String? reason,
  }) async {
    if (tx.status == target) return tx;
    final path = TransactionStateMachine.path(tx.status, target);
    if (path == null || path.isEmpty) return tx;
    var updated = tx;
    for (final step in path) {
      final isLast = step == path.last;
      final now = DateTime.now();
      updated = updated.copyWith(
        status: step,
        statusReason: isLast && reason != null
            ? reason
            : (step.isPaymentOutcome ? updated.statusReason : null),
        paymentProvider:
            step.isPaymentOutcome || step == TransactionStatus.paymentPending
            ? 'DEMO'
            : updated.paymentProvider,
        updatedAt: now,
        completedAt: step.isTerminal ? now : null,
      );
      await store.saveTransaction(updated);
      if (!step.isPaymentOutcome) {
        await _syncStatus(updated);
      }
    }
    return updated;
  }

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
        backendOnline = false;
      }
    } catch (_) {
      backendOnline = false;
    }
  }

  // ------------------------------------------------------------------- UI

  void consumeRequestPrompt() {
    if (!promptRequest) return;
    promptRequest = false;
    notifyListeners();
  }

  void clearMessages() {
    error = null;
    info = null;
    notifyListeners();
  }

  /// Dismisses a finished outcome (called when leaving the payment screen).
  void acknowledgeOutcome() {
    if (active == null || !active!.status.isTerminal) return;
    active = null;
    info = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _errSub?.cancel();
    super.dispose();
  }
}

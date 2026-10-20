/**
 * Demo payment orchestration.
 *
 * The demo payment endpoint is the ONLY route in the API that may move a
 * transaction into PAYMENT_SUCCESS / PAYMENT_FAILED. It:
 *   - validates the transaction exists and is payable,
 *   - is idempotent for repeated identical outcomes,
 *   - rejects conflicting outcomes on terminal transactions,
 *   - prevents double-processing via compare-and-set status updates,
 *   - records an auditable DEMO_PAYMENT_RESULT event.
 */
import { TransactionStatus, isTerminal } from '../stateMachine.js';
import { ValidationError } from '../validation.js';

const PAYABLE_STATUSES = [
  TransactionStatus.QR_READY,
  TransactionStatus.PAYMENT_PENDING,
  // Allow simulating directly after acceptance for a faster demo path.
  TransactionStatus.ACCEPTED
];

export function createPaymentService({ repo, config, paymentProvider, transactionService }) {
  return {
    async simulate(id, outcome) {
      if (outcome !== 'SUCCESS' && outcome !== 'FAILED') {
        throw new ValidationError("outcome must be 'SUCCESS' or 'FAILED'", [
          { field: 'outcome', message: 'invalid outcome' }
        ]);
      }
      if (paymentProvider.name !== 'DEMO') {
        const err = new Error(
          'Demo simulation is only available when PAYMENT_PROVIDER=demo.'
        );
        err.code = 'DEMO_DISABLED';
        err.status = 501;
        throw err;
      }

      let tx = await transactionService.getTransaction(id);

      if (tx.mode !== 'DEMO') {
        const err = new Error('Simulation applies only to DEMO mode transactions.');
        err.code = 'NOT_DEMO_TRANSACTION';
        err.status = 409;
        throw err;
      }

      // Idempotent replay of the same outcome; conflicting replay rejected.
      if (isTerminal(tx.status)) {
        const sameOutcome =
          (outcome === 'SUCCESS' && tx.status === TransactionStatus.PAYMENT_SUCCESS) ||
          (outcome === 'FAILED' && tx.status === TransactionStatus.PAYMENT_FAILED);
        if (sameOutcome) {
          const events = await repo.getEvents(tx.transactionId);
          return { transaction: tx, alreadyProcessed: true, events };
        }
        const err = new Error(
          `Transaction is already ${tx.status}; a different outcome cannot be applied.`
        );
        err.code = 'ALREADY_FINALIZED';
        err.status = 409;
        throw err;
      }

      if (!PAYABLE_STATUSES.includes(tx.status)) {
        const err = new Error(
          `Transaction in status ${tx.status} cannot be paid. ` +
            'Accept the request and show the payment QR first.'
        );
        err.code = 'NOT_PAYABLE';
        err.status = 409;
        throw err;
      }

      // Step 1: ACCEPTED -> QR_READY -> PAYMENT_PENDING (fast-forward if needed).
      if (tx.status === TransactionStatus.ACCEPTED) {
        const toQr = await repo.compareAndSetStatus(
          tx.transactionId,
          [TransactionStatus.ACCEPTED],
          TransactionStatus.QR_READY,
          { paymentProvider: 'DEMO' }
        );
        if (toQr) tx = toQr;
      }
      if (tx.status === TransactionStatus.QR_READY) {
        const toPending = await repo.compareAndSetStatus(
          tx.transactionId,
          [TransactionStatus.QR_READY],
          TransactionStatus.PAYMENT_PENDING,
          { paymentProvider: 'DEMO' }
        );
        if (toPending) tx = toPending;
      }
      if (tx.status !== TransactionStatus.PAYMENT_PENDING) {
        const fresh = await repo.getById(tx.transactionId);
        const err = new Error(
          `Transaction concurrently moved to ${fresh?.status}; payment not applied.`
        );
        err.code = 'CONFLICT';
        err.status = 409;
        throw err;
      }

      // Step 2: ask the provider for the simulated outcome.
      const result = await paymentProvider.simulate(tx, outcome);
      const finalTx = await repo.compareAndSetStatus(
        tx.transactionId,
        [TransactionStatus.PAYMENT_PENDING],
        result.status,
        {
          paymentProvider: result.mode,
          statusReason: outcome === 'SUCCESS' ? 'DEMO_SUCCESS' : 'DEMO_FAILED'
        }
      );

      if (!finalTx) {
        // Lost a race — re-read and apply idempotency rules.
        const fresh = await repo.getById(tx.transactionId);
        const sameOutcome =
          (outcome === 'SUCCESS' && fresh?.status === TransactionStatus.PAYMENT_SUCCESS) ||
          (outcome === 'FAILED' && fresh?.status === TransactionStatus.PAYMENT_FAILED);
        if (sameOutcome) {
          const events = await repo.getEvents(tx.transactionId);
          return { transaction: fresh, alreadyProcessed: true, events };
        }
        const err = new Error(
          `Transaction concurrently moved to ${fresh?.status}; payment not applied.`
        );
        err.code = 'CONFLICT';
        err.status = 409;
        throw err;
      }

      await repo.appendEvent({
        transactionId: finalTx.transactionId,
        eventType: 'DEMO_PAYMENT_RESULT',
        fromStatus: TransactionStatus.PAYMENT_PENDING,
        toStatus: finalTx.status,
        provider: 'DEMO',
        detail: {
          outcome,
          providerRef: result.providerRef,
          simulated: true,
          note: 'SIMULATED PAYMENT — no real money transferred'
        }
      });

      const events = await repo.getEvents(finalTx.transactionId);
      return { transaction: finalTx, alreadyProcessed: false, events };
    }
  };
}

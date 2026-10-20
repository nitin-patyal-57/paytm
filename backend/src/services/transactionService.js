/**
 * Transaction domain service: creation, retrieval, history and validated
 * status transitions. Payment outcome statuses are deliberately NOT
 * reachable through the generic transition path — only through the demo
 * payment service (or a future verified gateway callback).
 */
import { TransactionStatus, assertTransition, isTerminal } from '../stateMachine.js';
import {
  ValidationError,
  validateAmount,
  validateCurrency,
  validateFuelType,
  validateMode,
  validateStatusFilter,
  validateTransactionId
} from '../validation.js';
import { generateTransactionId } from '../repositories/transactionRepository.js';

const OUTCOME_STATUSES = new Set([
  TransactionStatus.PAYMENT_SUCCESS,
  TransactionStatus.PAYMENT_FAILED
]);

export function createTransactionService({ repo, config, paymentProvider }) {
  function stale(tx) {
    if (isTerminal(tx.status) || tx.status === TransactionStatus.CREATED) return false;
    const ageMs = Date.now() - Date.parse(tx.createdAt);
    return ageMs > config.pendingTtlMinutes * 60 * 1000;
  }

  async function expireIfStale(tx) {
    if (!tx || !stale(tx)) return tx;
    const updated = await repo.compareAndSetStatus(
      tx.transactionId,
      [tx.status],
      TransactionStatus.EXPIRED,
      { statusReason: 'TTL exceeded' }
    );
    if (updated) {
      await repo.appendEvent({
        transactionId: tx.transactionId,
        eventType: 'EXPIRED',
        fromStatus: tx.status,
        toStatus: TransactionStatus.EXPIRED,
        provider: tx.paymentProvider,
        detail: { reason: 'ttl_exceeded' }
      });
      return updated;
    }
    return (await repo.getById(tx.transactionId)) ?? tx;
  }

  async function requireTx(id) {
    let tx;
    try {
      validateTransactionId(id);
    } catch {
      const err = new Error(`Transaction not found: ${id}`);
      err.status = 404;
      err.code = 'NOT_FOUND';
      throw err;
    }
    tx = await repo.getById(id);
    if (!tx) {
      const err = new Error(`Transaction not found: ${id}`);
      err.status = 404;
      err.code = 'NOT_FOUND';
      throw err;
    }
    return expireIfStale(tx);
  }

  return {
    async createTransaction(input = {}) {
      const fuelType = validateFuelType(input.fuelType);
      const amount = validateAmount(input.amount);
      const currency = validateCurrency(input.currency ?? 'INR');
      const mode = validateMode(input.mode ?? 'DEMO');

      if (mode === 'PRODUCTION' && paymentProvider.name !== 'PAYTM') {
        const err = new Error(
          'Production payment mode requires an approved Paytm merchant integration ' +
            '(PAYMENT_PROVIDER=paytm). This server runs in DEMO mode. ' +
            'See docs/paytm-integration.md.'
        );
        err.code = 'PRODUCTION_NOT_ENABLED';
        err.status = 501;
        throw err;
      }

      let transactionId = null;
      if (input.transactionId !== undefined && input.transactionId !== null && input.transactionId !== '') {
        transactionId = validateTransactionId(input.transactionId);
      }

      const record = {
        transactionId: transactionId ?? generateTransactionId(),
        fuelType,
        amount,
        currency,
        status: TransactionStatus.CREATED,
        mode,
        paymentProvider: mode === 'DEMO' ? 'DEMO' : null
      };

      try {
        return await repo.create(record);
      } catch (e) {
        if (e.code === 'DUPLICATE_TRANSACTION' && input.transactionId) {
          throw e; // client-supplied duplicate id
        }
        if (e.code === 'DUPLICATE_TRANSACTION') {
          // astronomically unlikely server-generated collision: retry a few times
          for (let i = 0; i < 3; i++) {
            record.transactionId = generateTransactionId();
            try {
              return await repo.create(record);
            } catch (inner) {
              if (inner.code !== 'DUPLICATE_TRANSACTION' || i === 2) throw inner;
            }
          }
        }
        throw e;
      }
    },

    async getTransaction(id) {
      return requireTx(id);
    },

    async getStatus(id) {
      const tx = await requireTx(id);
      return {
        transactionId: tx.transactionId,
        status: tx.status,
        mode: tx.mode,
        amount: tx.amount,
        fuelType: tx.fuelType,
        paymentProvider: tx.paymentProvider,
        statusReason: tx.statusReason,
        updatedAt: tx.updatedAt
      };
    },

    async listTransactions(query = {}) {
      const status = validateStatusFilter(query.status);
      const fuelType =
        query.fuelType === undefined || query.fuelType === ''
          ? undefined
          : validateFuelType(query.fuelType, 'fuelType');
      const limit = query.limit === undefined ? 50 : Number(query.limit);
      const offset = query.offset === undefined ? 0 : Number(query.offset);
      if (!Number.isInteger(limit) || limit < 1 || limit > 200) {
        throw new ValidationError('limit must be an integer between 1 and 200');
      }
      if (!Number.isInteger(offset) || offset < 0) {
        throw new ValidationError('offset must be a non-negative integer');
      }
      const order = query.order === 'ASC' ? 'ASC' : 'DESC';
      const rows = await repo.list({ status, fuelType, limit, offset, order });
      const out = [];
      for (const row of rows) out.push(await expireIfStale(row));
      return out;
    },

    /**
     * Generic validated transition (BLE-driven state sync).
     * Payment outcome statuses are rejected here on purpose.
     */
    async transition(id, { status, reason } = {}) {
      const tx = await requireTx(id);
      if (typeof status !== 'string' || !status) {
        throw new ValidationError('status is required');
      }
      if (OUTCOME_STATUSES.has(status)) {
        const err = new Error(
          `${status} can only be set through a verified payment callback ` +
            '(/api/demo-payments/:id/simulate in demo mode). Client-asserted ' +
            'payment results are never accepted.'
        );
        err.code = 'OUTCOME_NOT_ALLOWED';
        err.status = 403;
        throw err;
      }
      assertTransition(tx.status, status);
      const updated = await repo.compareAndSetStatus(tx.transactionId, [tx.status], status, {
        statusReason: typeof reason === 'string' ? reason.slice(0, 200) : null
      });
      if (!updated) {
        const fresh = await repo.getById(tx.transactionId);
        const err = new Error(
          `Concurrent modification: expected ${tx.status} but found ${fresh?.status}`
        );
        err.code = 'CONFLICT';
        err.status = 409;
        throw err;
      }
      await repo.appendEvent({
        transactionId: tx.transactionId,
        eventType: 'STATUS_CHANGE',
        fromStatus: tx.status,
        toStatus: status,
        provider: updated.paymentProvider,
        detail: reason ? { reason } : null
      });
      return updated;
    },

    async getEvents(id) {
      const tx = await requireTx(id);
      return repo.getEvents(tx.transactionId);
    }
  };
}

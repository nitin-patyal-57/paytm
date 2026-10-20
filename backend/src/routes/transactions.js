import { Router } from 'express';

export function createTransactionsRouter({ transactionService }) {
  const router = Router();

  // Create a transaction.
  router.post('/', async (req, res, next) => {
    try {
      const tx = await transactionService.createTransaction(req.body ?? {});
      res.status(201).json({ transaction: serialize(tx) });
    } catch (e) {
      next(e);
    }
  });

  // Transaction history with filtering.
  router.get('/', async (req, res, next) => {
    try {
      const rows = await transactionService.listTransactions(req.query ?? {});
      res.json({ transactions: rows.map(serialize), count: rows.length });
    } catch (e) {
      next(e);
    }
  });

  // Full transaction details.
  router.get('/:id', async (req, res, next) => {
    try {
      const tx = await transactionService.getTransaction(req.params.id);
      res.json({ transaction: serialize(tx) });
    } catch (e) {
      next(e);
    }
  });

  // Latest status (lightweight polling endpoint for the apps).
  router.get('/:id/status', async (req, res, next) => {
    try {
      const status = await transactionService.getStatus(req.params.id);
      res.json(status);
    } catch (e) {
      next(e);
    }
  });

  // Audit trail (no credentials or personal data stored).
  router.get('/:id/events', async (req, res, next) => {
    try {
      const events = await transactionService.getEvents(req.params.id);
      res.json({ events });
    } catch (e) {
      next(e);
    }
  });

  // Validated status transition driven by the Bluetooth workflow.
  // Payment outcome statuses are rejected here (see transactionService).
  router.post('/:id/status', async (req, res, next) => {
    try {
      const tx = await transactionService.transition(req.params.id, req.body ?? {});
      res.json({ transaction: serialize(tx) });
    } catch (e) {
      next(e);
    }
  });

  return router;
}

/** Public JSON shape — keeps DB details out of the API. */
function serialize(tx) {
  if (!tx) return tx;
  return {
    transactionId: tx.transactionId,
    fuelType: tx.fuelType,
    amount: tx.amount,
    currency: tx.currency,
    status: tx.status,
    mode: tx.mode,
    paymentProvider: tx.paymentProvider,
    statusReason: tx.statusReason,
    createdAt: tx.createdAt,
    updatedAt: tx.updatedAt,
    completedAt: tx.completedAt
  };
}

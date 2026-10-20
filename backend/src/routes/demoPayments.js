import { Router } from 'express';

/**
 * Demo payment simulation endpoints.
 * Clearly separated from real payment processing.
 */
export function createDemoPaymentsRouter({ paymentService }) {
  const router = Router();

  // Simulate an explicit demo outcome. Idempotent for identical outcomes.
  router.post('/:id/simulate', async (req, res, next) => {
    try {
      const outcome = req.body?.outcome;
      const result = await paymentService.simulate(req.params.id, outcome);
      res.status(result.alreadyProcessed ? 200 : 201).json({
        simulated: true,
        alreadyProcessed: result.alreadyProcessed,
        note: 'SIMULATED PAYMENT — no real money was transferred.',
        transaction: {
          transactionId: result.transaction.transactionId,
          fuelType: result.transaction.fuelType,
          amount: result.transaction.amount,
          currency: result.transaction.currency,
          status: result.transaction.status,
          mode: result.transaction.mode,
          paymentProvider: result.transaction.paymentProvider,
          statusReason: result.transaction.statusReason,
          createdAt: result.transaction.createdAt,
          updatedAt: result.transaction.updatedAt,
          completedAt: result.transaction.completedAt
        },
        events: result.events
      });
    } catch (e) {
      next(e);
    }
  });

  return router;
}

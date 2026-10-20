import express from 'express';
import cors from 'cors';
import { createTransactionsRouter } from './routes/transactions.js';
import { createDemoPaymentsRouter } from './routes/demoPayments.js';
import { createTransactionService } from './services/transactionService.js';
import { createPaymentService } from './services/paymentService.js';
import { HttpError } from './errors.js';

/**
 * Builds the Express application. Kept separate from server.js so tests can
 * instantiate the app with an in-memory repository.
 */
export function createApp({ config, repo, paymentProvider }) {
  const transactionService = createTransactionService({ repo, config, paymentProvider });
  const paymentService = createPaymentService({
    repo,
    config,
    paymentProvider,
    transactionService
  });

  const app = express();
  app.disable('x-powered-by');
  app.use(cors({ origin: config.corsOrigins === '*' ? true : config.corsOrigins }));
  app.use(express.json({ limit: '64kb' }));

  app.get('/api/health', (req, res) => {
    res.json({
      status: 'ok',
      environment: config.nodeEnv,
      paymentProvider: paymentProvider.name,
      demoPaymentsEnabled: config.demoPaymentsEnabled,
      mode: 'DEMO',
      note: 'FuelPay demo backend — simulated payments only.'
    });
  });

  app.get('/api/payment-provider', (req, res) => {
    res.json({
      provider: paymentProvider.name,
      capabilities: paymentProvider.capabilities,
      currency: 'INR',
      amountLimits: { min: config.minAmount, max: config.maxAmount }
    });
  });

  app.use('/api/transactions', createTransactionsRouter({ transactionService }));
  app.use('/api/demo-payments', createDemoPaymentsRouter({ paymentService }));

  app.use((req, res) => {
    res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Endpoint not found' } });
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof SyntaxError && 'body' in err) {
      res.status(400).json({ error: { code: 'INVALID_JSON', message: 'Request body is not valid JSON' } });
      return;
    }
    if (err instanceof HttpError || (err && err.status && err.code)) {
      res.status(err.status).json({
        error: {
          code: err.code ?? 'ERROR',
          message: err.message,
          ...(err.details ? { details: err.details } : {})
        }
      });
      return;
    }
    console.error('Unhandled error:', err);
    res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: 'Internal server error' } });
  });

  return { app, transactionService, paymentService };
}

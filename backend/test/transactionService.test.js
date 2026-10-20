import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { MemoryTransactionRepository } from '../src/repositories/transactionRepository.js';
import { createTransactionService } from '../src/services/transactionService.js';
import { createPaymentService } from '../src/services/paymentService.js';
import { DemoPaymentProvider } from '../src/providers/DemoPaymentProvider.js';
import { PaytmPaymentProvider } from '../src/providers/PaytmPaymentProvider.js';

function makeServices() {
  const config = loadConfig({ NODE_ENV: 'test' });
  const repo = new MemoryTransactionRepository();
  const provider = new DemoPaymentProvider(config);
  const transactionService = createTransactionService({ repo, config, paymentProvider: provider });
  const paymentService = createPaymentService({
    repo,
    config,
    paymentProvider: provider,
    transactionService
  });
  return { config, repo, provider, transactionService, paymentService };
}

test('creates a transaction with generated unique id', async () => {
  const { transactionService } = makeServices();
  const a = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  const b = await transactionService.createTransaction({ fuelType: 'diesel', amount: 100 });
  assert.match(a.transactionId, /^FP\d{6,16}$/);
  assert.notEqual(a.transactionId, b.transactionId);
  assert.equal(a.status, 'CREATED');
  assert.equal(a.mode, 'DEMO');
  assert.equal(a.currency, 'INR');
  assert.equal(b.fuelType, 'DIESEL');
});

test('generates unique ids across many creations', async () => {
  const { transactionService } = makeServices();
  const ids = new Set();
  for (let i = 0; i < 200; i++) {
    const tx = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
    ids.add(tx.transactionId);
  }
  assert.equal(ids.size, 200);
});

test('rejects invalid amounts', async () => {
  const { transactionService } = makeServices();
  for (const amount of [99, 10001, 0, -500, 500.5, '500', null, NaN]) {
    await assert.rejects(
      () => transactionService.createTransaction({ fuelType: 'PETROL', amount }),
      (err) => err.status === 400,
      `amount ${amount} should be rejected`
    );
  }
});

test('accepts amount boundaries 100 and 10000', async () => {
  const { transactionService } = makeServices();
  const min = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 100 });
  const max = await transactionService.createTransaction({ fuelType: 'DIESEL', amount: 10000 });
  assert.equal(min.amount, 100);
  assert.equal(max.amount, 10000);
});

test('rejects invalid fuel type and currency', async () => {
  const { transactionService } = makeServices();
  await assert.rejects(
    () => transactionService.createTransaction({ fuelType: 'KEROSENE', amount: 500 }),
    (err) => err.status === 400
  );
  await assert.rejects(
    () => transactionService.createTransaction({ fuelType: 'PETROL', amount: 500, currency: 'USD' }),
    (err) => err.status === 400
  );
});

test('rejects duplicate client-supplied transaction ids', async () => {
  const { transactionService } = makeServices();
  await transactionService.createTransaction({
    fuelType: 'PETROL',
    amount: 500,
    transactionId: 'FP100001'
  });
  await assert.rejects(
    () =>
      transactionService.createTransaction({
        fuelType: 'DIESEL',
        amount: 100,
        transactionId: 'FP100001'
      }),
    (err) => err.status === 409 && err.code === 'DUPLICATE_TRANSACTION'
  );
});

test('production mode is not enabled on the demo server', async () => {
  const { transactionService } = makeServices();
  await assert.rejects(
    () => transactionService.createTransaction({ fuelType: 'PETROL', amount: 500, mode: 'PRODUCTION' }),
    (err) => err.status === 501 && err.code === 'PRODUCTION_NOT_ENABLED'
  );
});

test('happy-path transitions succeed and illegal ones fail', async () => {
  const { transactionService } = makeServices();
  const tx = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  const steps = ['REQUEST_SENT', 'REQUEST_RECEIVED', 'ACCEPTED', 'QR_READY', 'PAYMENT_PENDING'];
  let current = tx;
  for (const status of steps) {
    current = await transactionService.transition(tx.transactionId, { status });
    assert.equal(current.status, status);
  }
  // Skipping a step must fail.
  await assert.rejects(
    () => transactionService.transition(tx.transactionId, { status: 'ACCEPTED' }),
    (err) => err.status === 409
  );
});

test('client cannot set payment outcome statuses directly', async () => {
  const { transactionService } = makeServices();
  const tx = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  await assert.rejects(
    () => transactionService.transition(tx.transactionId, { status: 'PAYMENT_SUCCESS' }),
    (err) => err.status === 403 && err.code === 'OUTCOME_NOT_ALLOWED'
  );
  await assert.rejects(
    () => transactionService.transition(tx.transactionId, { status: 'PAYMENT_FAILED' }),
    (err) => err.status === 403 && err.code === 'OUTCOME_NOT_ALLOWED'
  );
});

test('demo payment success flow with idempotent replay', async () => {
  const { transactionService, paymentService } = makeServices();
  const tx = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  for (const status of ['REQUEST_SENT', 'REQUEST_RECEIVED', 'ACCEPTED', 'QR_READY']) {
    await transactionService.transition(tx.transactionId, { status });
  }

  const first = await paymentService.simulate(tx.transactionId, 'SUCCESS');
  assert.equal(first.transaction.status, 'PAYMENT_SUCCESS');
  assert.equal(first.alreadyProcessed, false);
  assert.equal(first.transaction.mode, 'DEMO');
  assert.equal(first.transaction.paymentProvider, 'DEMO');

  // Duplicate success — idempotent, must NOT reprocess.
  const replay = await paymentService.simulate(tx.transactionId, 'SUCCESS');
  assert.equal(replay.alreadyProcessed, true);
  assert.equal(replay.transaction.status, 'PAYMENT_SUCCESS');

  // Conflicting outcome after success is rejected.
  await assert.rejects(
    () => paymentService.simulate(tx.transactionId, 'FAILED'),
    (err) => err.status === 409 && err.code === 'ALREADY_FINALIZED'
  );
});

test('demo payment failure flow', async () => {
  const { transactionService, paymentService } = makeServices();
  const tx = await transactionService.createTransaction({ fuelType: 'DIESEL', amount: 1000 });
  for (const status of ['REQUEST_SENT', 'REQUEST_RECEIVED', 'ACCEPTED', 'QR_READY']) {
    await transactionService.transition(tx.transactionId, { status });
  }
  const result = await paymentService.simulate(tx.transactionId, 'FAILED');
  assert.equal(result.transaction.status, 'PAYMENT_FAILED');
  const detail = result.events.find((e) => e.eventType === 'DEMO_PAYMENT_RESULT');
  assert.ok(detail, 'demo result event recorded');
  assert.equal(detail.detail.outcome, 'FAILED');
});

test('unpaid transactions cannot be simulated', async () => {
  const { transactionService, paymentService } = makeServices();
  const tx = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  await assert.rejects(
    () => paymentService.simulate(tx.transactionId, 'SUCCESS'),
    (err) => err.status === 409 && err.code === 'NOT_PAYABLE'
  );
  await transactionService.transition(tx.transactionId, { status: 'REQUEST_SENT' });
  await assert.rejects(
    () => paymentService.simulate(tx.transactionId, 'SUCCESS'),
    (err) => err.status === 409 && err.code === 'NOT_PAYABLE'
  );
});

test('cancelled transaction cannot be paid later', async () => {
  const { transactionService, paymentService } = makeServices();
  const tx = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  await transactionService.transition(tx.transactionId, { status: 'CANCELLED', reason: 'user' });
  await assert.rejects(
    () => paymentService.simulate(tx.transactionId, 'SUCCESS'),
    (err) => err.status === 409
  );
});

test('paytm provider methods are not implemented', async () => {
  const provider = new PaytmPaymentProvider({});
  assert.equal(provider.name, 'PAYTM');
  for (const method of ['initiatePayment', 'getPaymentStatus', 'verifyPayment', 'handlePaymentNotification']) {
    await assert.rejects(() => provider[method](), (err) => err.status === 501);
  }
});

test('status filtering returns matching rows only', async () => {
  const { transactionService } = makeServices();
  const a = await transactionService.createTransaction({ fuelType: 'PETROL', amount: 500 });
  await transactionService.createTransaction({ fuelType: 'DIESEL', amount: 100 });
  await transactionService.transition(a.transactionId, { status: 'REQUEST_SENT' });
  const pending = await transactionService.listTransactions({ status: 'CREATED' });
  assert.equal(pending.length, 1);
  assert.equal(pending[0].fuelType, 'DIESEL');
  const petrol = await transactionService.listTransactions({ fuelType: 'PETROL' });
  assert.equal(petrol.length, 1);
  assert.equal(petrol[0].status, 'REQUEST_SENT');
});

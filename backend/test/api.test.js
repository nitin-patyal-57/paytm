import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { MemoryTransactionRepository } from '../src/repositories/transactionRepository.js';
import { createPaymentProvider } from '../src/providers/index.js';

let server;
let base;

before(async () => {
  const config = loadConfig({ NODE_ENV: 'test', PORT: '0' });
  const repo = new MemoryTransactionRepository();
  const provider = createPaymentProvider(config);
  const { app } = createApp({ config, repo, paymentProvider: provider });
  await new Promise((resolve) => {
    server = app.listen(0, resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server?.close());

async function api(method, path, body) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const json = await res.json().catch(() => null);
  return { status: res.status, json };
}

test('GET /api/health reports demo mode', async () => {
  const { status, json } = await api('GET', '/api/health');
  assert.equal(status, 200);
  assert.equal(json.paymentProvider, 'DEMO');
  assert.equal(json.mode, 'DEMO');
});

test('POST /api/transactions creates and GET retrieves', async () => {
  const create = await api('POST', '/api/transactions', { fuelType: 'PETROL', amount: 500 });
  assert.equal(create.status, 201);
  const tx = create.json.transaction;
  assert.match(tx.transactionId, /^FP\d{6,16}$/);
  assert.equal(tx.status, 'CREATED');
  assert.equal(tx.amount, 500);
  assert.equal(tx.mode, 'DEMO');

  const get = await api('GET', `/api/transactions/${tx.transactionId}`);
  assert.equal(get.status, 200);
  assert.deepEqual(get.json.transaction.transactionId, tx.transactionId);

  const status = await api('GET', `/api/transactions/${tx.transactionId}/status`);
  assert.equal(status.status, 200);
  assert.equal(status.json.status, 'CREATED');
});

test('POST /api/transactions validates input', async () => {
  const badAmount = await api('POST', '/api/transactions', { fuelType: 'PETROL', amount: 50 });
  assert.equal(badAmount.status, 400);
  const badFuel = await api('POST', '/api/transactions', { fuelType: 'GAS', amount: 500 });
  assert.equal(badFuel.status, 400);
  const notJson = await fetch(`${base}/api/transactions`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{bad json'
  });
  assert.equal(notJson.status, 400);
});

test('GET /api/transactions supports filtering', async () => {
  const p = await api('POST', '/api/transactions', { fuelType: 'PETROL', amount: 1000 });
  await api('POST', '/api/transactions', { fuelType: 'DIESEL', amount: 2000 });
  const filter = await api('GET', '/api/transactions?fuelType=DIESEL');
  assert.equal(filter.status, 200);
  assert.ok(filter.json.transactions.every((t) => t.fuelType === 'DIESEL'));
  const badFilter = await api('GET', '/api/transactions?status=WHATEVER');
  assert.equal(badFilter.status, 400);
  assert.ok(p.status === 201);
});

test('workflow: create → transition → simulate success (idempotent) → status', async () => {
  const create = await api('POST', '/api/transactions', { fuelType: 'PETROL', amount: 500 });
  const id = create.json.transaction.transactionId;

  for (const status of ['REQUEST_SENT', 'REQUEST_RECEIVED', 'ACCEPTED', 'QR_READY', 'PAYMENT_PENDING']) {
    const res = await api('POST', `/api/transactions/${id}/status`, { status });
    assert.equal(res.status, 200, `transition to ${status}`);
    assert.equal(res.json.transaction.status, status);
  }

  const sim = await api('POST', `/api/demo-payments/${id}/simulate`, { outcome: 'SUCCESS' });
  assert.equal(sim.status, 201);
  assert.equal(sim.json.simulated, true);
  assert.equal(sim.json.transaction.status, 'PAYMENT_SUCCESS');
  assert.match(sim.json.note, /SIMULATED/i);

  const replay = await api('POST', `/api/demo-payments/${id}/simulate`, { outcome: 'SUCCESS' });
  assert.equal(replay.status, 200);
  assert.equal(replay.json.alreadyProcessed, true);

  const conflict = await api('POST', `/api/demo-payments/${id}/simulate`, { outcome: 'FAILED' });
  assert.equal(conflict.status, 409);

  const status = await api('GET', `/api/transactions/${id}/status`);
  assert.equal(status.json.status, 'PAYMENT_SUCCESS');

  const events = await api('GET', `/api/transactions/${id}/events`);
  assert.ok(events.json.events.some((e) => e.eventType === 'DEMO_PAYMENT_RESULT'));
});

test('workflow: simulate failure path', async () => {
  const create = await api('POST', '/api/transactions', { fuelType: 'DIESEL', amount: 1000 });
  const id = create.json.transaction.transactionId;
  for (const status of ['REQUEST_SENT', 'REQUEST_RECEIVED', 'ACCEPTED', 'QR_READY']) {
    await api('POST', `/api/transactions/${id}/status`, { status });
  }
  const sim = await api('POST', `/api/demo-payments/${id}/simulate`, { outcome: 'FAILED' });
  assert.equal(sim.status, 201);
  assert.equal(sim.json.transaction.status, 'PAYMENT_FAILED');
});

test('cannot mark success via generic status endpoint', async () => {
  const create = await api('POST', '/api/transactions', { fuelType: 'PETROL', amount: 500 });
  const id = create.json.transaction.transactionId;
  const res = await api('POST', `/api/transactions/${id}/status`, { status: 'PAYMENT_SUCCESS' });
  assert.equal(res.status, 403);
  assert.equal(res.json.error.code, 'OUTCOME_NOT_ALLOWED');
});

test('unknown transaction returns 404 and bad id too', async () => {
  assert.equal((await api('GET', '/api/transactions/FP99999999')).status, 404);
  assert.equal((await api('GET', '/api/transactions/not-an-id')).status, 404);
  assert.equal(
    (await api('POST', '/api/demo-payments/FP99999999/simulate', { outcome: 'SUCCESS' })).status,
    404
  );
});

test('invalid simulate outcome is rejected', async () => {
  const create = await api('POST', '/api/transactions', { fuelType: 'PETROL', amount: 500 });
  const id = create.json.transaction.transactionId;
  const res = await api('POST', `/api/demo-payments/${id}/simulate`, { outcome: 'MAYBE' });
  assert.equal(res.status, 400);
});

test('duplicate client id returns 409', async () => {
  const first = await api('POST', '/api/transactions', {
    fuelType: 'PETROL',
    amount: 500,
    transactionId: 'FP777777'
  });
  assert.equal(first.status, 201);
  const dup = await api('POST', '/api/transactions', {
    fuelType: 'DIESEL',
    amount: 100,
    transactionId: 'FP777777'
  });
  assert.equal(dup.status, 409);
});

test('payment provider endpoint exposes capabilities', async () => {
  const res = await api('GET', '/api/payment-provider');
  assert.equal(res.status, 200);
  assert.equal(res.json.provider, 'DEMO');
  assert.equal(res.json.capabilities.simulate, true);
  assert.equal(res.json.capabilities.production, false);
});

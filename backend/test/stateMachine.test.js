import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  TransactionStatus,
  canTransition,
  assertTransition,
  isTerminal,
  isKnownStatus
} from '../src/stateMachine.js';

const VALID = [
  ['CREATED', 'REQUEST_SENT'],
  ['CREATED', 'CANCELLED'],
  ['CREATED', 'EXPIRED'],
  ['REQUEST_SENT', 'REQUEST_RECEIVED'],
  ['REQUEST_RECEIVED', 'ACCEPTED'],
  ['ACCEPTED', 'QR_READY'],
  ['QR_READY', 'PAYMENT_PENDING'],
  ['QR_READY', 'PAYMENT_SUCCESS'],
  ['QR_READY', 'PAYMENT_FAILED'],
  ['PAYMENT_PENDING', 'PAYMENT_SUCCESS'],
  ['PAYMENT_PENDING', 'PAYMENT_FAILED'],
  ['PAYMENT_PENDING', 'CANCELLED'],
  ['ACCEPTED', 'CANCELLED']
];

const INVALID = [
  ['CREATED', 'PAYMENT_SUCCESS'], // cannot skip the whole flow
  ['CREATED', 'ACCEPTED'],
  ['REQUEST_SENT', 'ACCEPTED'],
  ['PAYMENT_SUCCESS', 'PAYMENT_FAILED'], // terminal
  ['PAYMENT_SUCCESS', 'PAYMENT_PENDING'], // terminal
  ['CANCELLED', 'PAYMENT_SUCCESS'], // terminal
  ['EXPIRED', 'PAYMENT_SUCCESS'], // terminal
  ['PAYMENT_FAILED', 'PAYMENT_SUCCESS'], // no auto-recovery
  ['PAYMENT_PENDING', 'REQUEST_SENT'],
  ['ACCEPTED', 'PAYMENT_SUCCESS'] // must go through QR/pending first? allowed? no
];

test('allows documented valid transitions', () => {
  for (const [from, to] of VALID) {
    assert.equal(canTransition(from, to), true, `${from} -> ${to} should be allowed`);
  }
});

test('rejects invalid transitions', () => {
  for (const [from, to] of INVALID) {
    assert.equal(canTransition(from, to), false, `${from} -> ${to} should be rejected`);
  }
});

test('terminal states have no outgoing transitions', () => {
  for (const terminal of [
    TransactionStatus.PAYMENT_SUCCESS,
    TransactionStatus.PAYMENT_FAILED,
    TransactionStatus.CANCELLED,
    TransactionStatus.EXPIRED
  ]) {
    assert.equal(isTerminal(terminal), true);
    for (const target of Object.values(TransactionStatus)) {
      assert.equal(canTransition(terminal, target), false, `${terminal} -> ${target}`);
    }
  }
});

test('assertTransition throws with 409 status on illegal move', () => {
  assert.throws(
    () => assertTransition('PAYMENT_SUCCESS', 'PAYMENT_FAILED'),
    (err) => err.code === 'INVALID_TRANSITION' && err.status === 409
  );
});

test('unknown statuses are never valid', () => {
  assert.equal(isKnownStatus('PAID'), false);
  assert.equal(canTransition('CREATED', 'PAID'), false);
  assert.equal(canTransition('PAID', 'CREATED'), false);
});

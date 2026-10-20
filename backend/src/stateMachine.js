/**
 * Transaction state machine — the single source of truth for allowed
 * status transitions. The Flutter apps mirror this exact table in
 * packages/fuelpay_core/lib/src/state/transaction_state_machine.dart.
 *
 * Rule: only listed transitions are legal. Terminal states have no exits.
 */

export const TransactionStatus = Object.freeze({
  CREATED: 'CREATED',
  REQUEST_SENT: 'REQUEST_SENT',
  REQUEST_RECEIVED: 'REQUEST_RECEIVED',
  ACCEPTED: 'ACCEPTED',
  QR_READY: 'QR_READY',
  PAYMENT_PENDING: 'PAYMENT_PENDING',
  PAYMENT_SUCCESS: 'PAYMENT_SUCCESS',
  PAYMENT_FAILED: 'PAYMENT_FAILED',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED'
});

export const TERMINAL_STATUSES = Object.freeze([
  TransactionStatus.PAYMENT_SUCCESS,
  TransactionStatus.PAYMENT_FAILED,
  TransactionStatus.CANCELLED,
  TransactionStatus.EXPIRED
]);

const ALLOWED = Object.freeze({
  CREATED: ['REQUEST_SENT', 'CANCELLED', 'EXPIRED'],
  REQUEST_SENT: ['REQUEST_RECEIVED', 'CANCELLED', 'EXPIRED'],
  REQUEST_RECEIVED: ['ACCEPTED', 'CANCELLED', 'EXPIRED'],
  ACCEPTED: ['QR_READY', 'CANCELLED', 'EXPIRED'],
  QR_READY: [
    TransactionStatus.PAYMENT_PENDING,
    TransactionStatus.PAYMENT_SUCCESS,
    TransactionStatus.PAYMENT_FAILED,
    TransactionStatus.CANCELLED,
    TransactionStatus.EXPIRED
  ],
  PAYMENT_PENDING: [
    TransactionStatus.PAYMENT_SUCCESS,
    TransactionStatus.PAYMENT_FAILED,
    TransactionStatus.CANCELLED,
    TransactionStatus.EXPIRED
  ],
  PAYMENT_SUCCESS: [],
  PAYMENT_FAILED: [],
  CANCELLED: [],
  EXPIRED: []
});

export function isKnownStatus(status) {
  return Object.prototype.hasOwnProperty.call(ALLOWED, status);
}

export function isTerminal(status) {
  return TERMINAL_STATUSES.includes(status);
}

export function canTransition(from, to) {
  if (!isKnownStatus(from) || !isKnownStatus(to)) return false;
  return ALLOWED[from].includes(to);
}

export function assertTransition(from, to) {
  if (!canTransition(from, to)) {
    const err = new Error(`Invalid transaction transition: ${from} -> ${to}`);
    err.code = 'INVALID_TRANSITION';
    err.status = 409;
    throw err;
  }
}

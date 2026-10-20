/**
 * Request validation helpers. Rejects malformed input early with
 * structured 400 responses.
 */

import { isKnownStatus } from './stateMachine.js';

export const FUEL_TYPES = Object.freeze(['PETROL', 'DIESEL']);
export const MODES = Object.freeze(['DEMO', 'PRODUCTION']);

// Mirrors the Flutter rule: integer rupees between 100 and 10000 inclusive.
export const MIN_AMOUNT = 100;
export const MAX_AMOUNT = 10000;

// Client-generated or server-generated ids: FP + 6..16 digits (e.g. FP100001).
export const TRANSACTION_ID_PATTERN = /^FP\d{6,16}$/;

export class ValidationError extends Error {
  constructor(message, details = []) {
    super(message);
    this.name = 'ValidationError';
    this.code = 'VALIDATION_ERROR';
    this.status = 400;
    this.details = details;
  }
}

export function validateFuelType(value, field = 'fuelType') {
  if (typeof value !== 'string' || !FUEL_TYPES.includes(value.toUpperCase())) {
    throw new ValidationError(`${field} must be one of: ${FUEL_TYPES.join(', ')}`, [
      { field, message: 'invalid fuel type' }
    ]);
  }
  return value.toUpperCase();
}

export function validateAmount(value, field = 'amount') {
  if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value)) {
    throw new ValidationError(`${field} must be an integer amount in INR`, [
      { field, message: 'amount must be an integer' }
    ]);
  }
  if (value < MIN_AMOUNT || value > MAX_AMOUNT) {
    throw new ValidationError(
      `${field} must be between ${MIN_AMOUNT} and ${MAX_AMOUNT} INR`,
      [{ field, message: 'amount out of range' }]
    );
  }
  return value;
}

export function validateCurrency(value = 'INR', field = 'currency') {
  if (typeof value !== 'string' || value.toUpperCase() !== 'INR') {
    throw new ValidationError(`${field} must be INR`, [{ field, message: 'unsupported currency' }]);
  }
  return 'INR';
}

export function validateMode(value = 'DEMO', field = 'mode') {
  if (typeof value !== 'string' || !MODES.includes(value.toUpperCase())) {
    throw new ValidationError(`${field} must be one of: ${MODES.join(', ')}`, [
      { field, message: 'invalid mode' }
    ]);
  }
  return value.toUpperCase();
}

export function validateTransactionId(value, field = 'transactionId') {
  if (typeof value !== 'string' || !TRANSACTION_ID_PATTERN.test(value)) {
    throw new ValidationError(
      `${field} must match ${TRANSACTION_ID_PATTERN.source} (e.g. FP100001)`,
      [{ field, message: 'invalid transaction id' }]
    );
  }
  return value;
}

export function validateStatusFilter(value) {
  if (value === undefined || value === '') return undefined;
  if (!isKnownStatus(value)) {
    throw new ValidationError(`Unknown status filter: ${value}`, [
      { field: 'status', message: 'unknown status' }
    ]);
  }
  return value;
}

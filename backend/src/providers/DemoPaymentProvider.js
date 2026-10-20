import crypto from 'node:crypto';
import { PaymentProvider } from './PaymentProvider.js';

/**
 * Simulated payment provider used for this demonstration.
 *
 * IMPORTANT: outcomes are simulated. No money moves. The demo must always
 * label results as DEMO / simulated — never as real payments.
 *
 * A success can ONLY be produced by an explicit simulate() call made by the
 * pump app through POST /api/demo-payments/:id/simulate — never by a
 * client-asserted "success" message over Bluetooth.
 */
export class DemoPaymentProvider extends PaymentProvider {
  get name() {
    return 'DEMO';
  }

  get capabilities() {
    return { simulate: true, production: false };
  }

  async initiatePayment(transaction) {
    return {
      providerRef: `demo_${transaction.transactionId}_${crypto.randomUUID().slice(0, 8)}`,
      status: 'PAYMENT_PENDING'
    };
  }

  async getPaymentStatus(transaction) {
    return { status: transaction.status };
  }

  /**
   * Demo verification: a terminal transaction is considered verified when a
   * DEMO_PAYMENT_RESULT event recorded server-side matches its status.
   * (A future production provider would verify with the payment gateway.)
   */
  async verifyPayment(transaction, events = []) {
    const terminal = ['PAYMENT_SUCCESS', 'PAYMENT_FAILED', 'CANCELLED', 'EXPIRED'];
    if (!terminal.includes(transaction.status)) {
      return { verified: false, status: transaction.status, reason: 'not_terminal' };
    }
    const resultEvent = events.find((e) => e.eventType === 'DEMO_PAYMENT_RESULT');
    if (transaction.status === 'PAYMENT_SUCCESS' || transaction.status === 'PAYMENT_FAILED') {
      if (!resultEvent) {
        return { verified: false, status: transaction.status, reason: 'missing_demo_result_event' };
      }
      const expected = transaction.status === 'PAYMENT_SUCCESS' ? 'SUCCESS' : 'FAILED';
      if (resultEvent.detail?.outcome !== expected) {
        return { verified: false, status: transaction.status, reason: 'outcome_mismatch' };
      }
    }
    return { verified: true, status: transaction.status, amount: transaction.amount };
  }

  /**
   * Not exposed as a public endpoint in the demo — reserved so the provider
   * interface stays symmetric with a future gateway webhook.
   * Payload shape: { transactionId, outcome: 'SUCCESS'|'FAILED' }
   */
  async handlePaymentNotification(payload) {
    if (!payload || typeof payload !== 'object') {
      const err = new Error('Invalid notification payload');
      err.status = 400;
      throw err;
    }
    const { transactionId, outcome } = payload;
    if (typeof transactionId !== 'string' || !['SUCCESS', 'FAILED'].includes(outcome)) {
      const err = new Error('notification requires transactionId and outcome in [SUCCESS, FAILED]');
      err.status = 400;
      throw err;
    }
    return {
      transactionId,
      status: outcome === 'SUCCESS' ? 'PAYMENT_SUCCESS' : 'PAYMENT_FAILED',
      mode: 'DEMO'
    };
  }

  /** Demo-only control: explicit simulation decision. */
  async simulate(transaction, outcome) {
    if (!['SUCCESS', 'FAILED'].includes(outcome)) {
      const err = new Error("outcome must be 'SUCCESS' or 'FAILED'");
      err.status = 400;
      throw err;
    }
    return {
      providerRef: `demo_${crypto.randomUUID().slice(0, 8)}`,
      status: outcome === 'SUCCESS' ? 'PAYMENT_SUCCESS' : 'PAYMENT_FAILED',
      mode: 'DEMO',
      outcome
    };
  }
}

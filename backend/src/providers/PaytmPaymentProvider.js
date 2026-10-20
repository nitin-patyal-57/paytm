import { PaymentProvider } from './PaymentProvider.js';

/**
 * RESERVED — future Paytm merchant integration.
 *
 * This class intentionally contains NO API calls, endpoints, or signatures.
 * Paytm merchant APIs must only be implemented after:
 *   1. Reviewing the official Paytm merchant documentation and obtaining
 *      merchant credentials through the approved onboarding process.
 *   2. Implementing server-side order creation, status verification, and
 *      webhook signature validation exactly as documented by Paytm.
 *
 * See docs/paytm-integration.md for the implementation checklist.
 *
 * Every method throws so no code path can silently pretend a real payment
 * happened.
 */
export class PaytmPaymentProvider extends PaymentProvider {
  get name() {
    return 'PAYTM';
  }

  get capabilities() {
    return { simulate: false, production: true };
  }

  #notImplemented(method) {
    const err = new Error(
      `PaytmPaymentProvider.${method} is not implemented. ` +
        'Follow docs/paytm-integration.md and the official Paytm merchant ' +
        'documentation before enabling production payments. ' +
        'Use PAYMENT_PROVIDER=demo for this demonstration.'
    );
    err.name = 'NotImplementedError';
    err.code = 'PROVIDER_NOT_IMPLEMENTED';
    err.status = 501;
    return err;
  }

  async initiatePayment() {
    throw this.#notImplemented('initiatePayment');
  }

  async getPaymentStatus() {
    throw this.#notImplemented('getPaymentStatus');
  }

  async verifyPayment() {
    throw this.#notImplemented('verifyPayment');
  }

  async handlePaymentNotification() {
    throw this.#notImplemented('handlePaymentNotification');
  }
}

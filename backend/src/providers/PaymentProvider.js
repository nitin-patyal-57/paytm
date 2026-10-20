/**
 * Payment provider abstraction.
 *
 * The backend is the ONLY place that decides a payment outcome.
 * Concrete providers:
 *   - DemoPaymentProvider  : simulated outcomes for this demonstration.
 *   - PaytmPaymentProvider : reserved for a future, approved Paytm merchant
 *                            integration (see docs/paytm-integration.md).
 *
 * Contract (all methods async):
 *   initiatePayment(transaction)          -> { providerRef, status }
 *   getPaymentStatus(transaction)         -> { status }
 *   verifyPayment(transaction)            -> { verified, status, amount, reason? }
 *   handlePaymentNotification(payload)    -> { transactionId, status, ... }
 *   capabilities                          -> { simulate: boolean, production: boolean }
 */

export class PaymentProvider {
  constructor(config) {
    this.config = config;
  }

  get name() {
    throw new Error('PaymentProvider.name not implemented');
  }

  get capabilities() {
    return { simulate: false, production: false };
  }

  async initiatePayment() {
    throw new Error('initiatePayment not implemented');
  }

  async getPaymentStatus() {
    throw new Error('getPaymentStatus not implemented');
  }

  async verifyPayment() {
    throw new Error('verifyPayment not implemented');
  }

  async handlePaymentNotification() {
    throw new Error('handlePaymentNotification not implemented');
  }
}

export class PaymentProviderNotConfiguredError extends Error {
  constructor(provider) {
    super(
      `Payment provider '${provider}' is not configured on this server. ` +
        'Set PAYMENT_PROVIDER=demo for the demonstration.'
    );
    this.name = 'PaymentProviderNotConfiguredError';
    this.code = 'PROVIDER_NOT_CONFIGURED';
    this.status = 501;
  }
}

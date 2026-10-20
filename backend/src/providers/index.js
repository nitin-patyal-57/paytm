import {
  PaymentProvider,
  PaymentProviderNotConfiguredError
} from './PaymentProvider.js';
import { DemoPaymentProvider } from './DemoPaymentProvider.js';
import { PaytmPaymentProvider } from './PaytmPaymentProvider.js';

/** Selects the active payment provider from configuration. */
export function createPaymentProvider(config) {
  switch (config.paymentProvider) {
    case 'demo':
      if (!config.demoPaymentsEnabled) {
        const err = new Error('Demo payments are disabled (DEMO_PAYMENTS_ENABLED=false).');
        err.code = 'DEMO_PAYMENTS_DISABLED';
        err.status = 501;
        throw err;
      }
      return new DemoPaymentProvider(config);
    case 'paytm':
      return new PaytmPaymentProvider(config);
    default:
      throw new PaymentProviderNotConfiguredError(config.paymentProvider);
  }
}

export { PaymentProvider, DemoPaymentProvider, PaytmPaymentProvider };

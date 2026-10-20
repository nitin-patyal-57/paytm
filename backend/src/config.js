/**
 * Central configuration. All values come from environment variables.
 * No secrets are stored in source code.
 */

function bool(value, fallback) {
  if (value === undefined || value === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

export function loadConfig(env = process.env) {
  const nodeEnv = env.NODE_ENV || 'development';
  const paymentProvider = (env.PAYMENT_PROVIDER || 'demo').toLowerCase();

  const config = {
    nodeEnv,
    port: Number(env.PORT || 3000),
    corsOrigins: env.CORS_ORIGINS ? env.CORS_ORIGINS.split(',').map((s) => s.trim()) : '*',
    // Database. When DATABASE_URL is absent the app uses the in-memory store
    // (fine for local demos; data is lost on restart).
    databaseUrl: env.DATABASE_URL || '',
    dbPoolMax: Number(env.DB_POOL_MAX || 5),
    // Payment provider selection: 'demo' (default) or 'paytm'.
    paymentProvider,
    demoPaymentsEnabled: bool(env.DEMO_PAYMENTS_ENABLED, true),
    // Reserved for a future approved Paytm merchant integration.
    // These MUST be provided via environment/secret manager, never in source.
    // Exact variables are confirmed against official Paytm docs before use.
    paytm: {
      mid: env.PAYTM_MID || '',
      key: env.PAYTM_KEY || '',
      baseUrl: env.PAYTM_BASE_URL || '',
      website: env.PAYTM_WEBSITE || '',
      callbackUrl: env.PAYTM_CALLBACK_URL || ''
    },
    // Amount bounds in INR (integer rupees) — mirrored by the Flutter apps.
    minAmount: 100,
    maxAmount: 10000,
    // A pending transaction older than this expires.
    pendingTtlMinutes: Number(env.PENDING_TTL_MINUTES || 30)
  };

  if (config.paymentProvider === 'paytm') {
    const required = [
      ['PAYTM_MID', config.paytm.mid],
      ['PAYTM_KEY', config.paytm.key],
      ['PAYTM_BASE_URL', config.paytm.baseUrl],
      ['PAYTM_WEBSITE', config.paytm.website],
      ['PAYTM_CALLBACK_URL', config.paytm.callbackUrl]
    ];
    const missing = required.filter(([, v]) => !v).map(([k]) => k);
    if (missing.length > 0) {
      throw new Error(
        `PAYMENT_PROVIDER=paytm requires: ${missing.join(', ')}. ` +
          'See docs/paytm-integration.md. For the demo use PAYMENT_PROVIDER=demo.'
      );
    }
  }

  return config;
}

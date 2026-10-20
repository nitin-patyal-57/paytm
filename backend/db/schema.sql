-- FuelPay demo backend — PostgreSQL schema
-- Apply with: npm run migrate   (or: psql "$DATABASE_URL" -f db/schema.sql)

CREATE TABLE IF NOT EXISTS transactions (
  transaction_id   TEXT PRIMARY KEY,
  fuel_type        TEXT NOT NULL CHECK (fuel_type IN ('PETROL', 'DIESEL')),
  amount           NUMERIC(10, 2) NOT NULL CHECK (amount >= 100 AND amount <= 10000),
  currency         TEXT NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
  status           TEXT NOT NULL CHECK (status IN (
                     'CREATED', 'REQUEST_SENT', 'REQUEST_RECEIVED', 'ACCEPTED',
                     'QR_READY', 'PAYMENT_PENDING', 'PAYMENT_SUCCESS',
                     'PAYMENT_FAILED', 'CANCELLED', 'EXPIRED')),
  mode             TEXT NOT NULL DEFAULT 'DEMO' CHECK (mode IN ('DEMO', 'PRODUCTION')),
  payment_provider TEXT,
  status_reason    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions (status);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions (created_at DESC);

-- Append-only audit trail of status changes and demo payment events.
-- No payment credentials or personal data are ever stored here.
CREATE TABLE IF NOT EXISTS payment_events (
  id             BIGSERIAL PRIMARY KEY,
  transaction_id TEXT NOT NULL REFERENCES transactions (transaction_id) ON DELETE CASCADE,
  event_type     TEXT NOT NULL,
  from_status    TEXT,
  to_status      TEXT,
  provider       TEXT,
  detail         JSONB,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_events_tx ON payment_events (transaction_id);

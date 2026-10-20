/**
 * FuelPay backend entry point.
 * Starts the HTTP server with either PostgreSQL (DATABASE_URL set) or the
 * in-memory store (lightweight local development option).
 */
import pg from 'pg';
import { loadConfig } from './config.js';
import { createApp } from './app.js';
import {
  MemoryTransactionRepository,
  PostgresTransactionRepository
} from './repositories/transactionRepository.js';
import { createPaymentProvider } from './providers/index.js';

async function main() {
  const config = loadConfig();

  let repo;
  let storeName;
  if (config.databaseUrl) {
    const pool = new pg.Pool({
      connectionString: config.databaseUrl,
      max: config.dbPoolMax
    });
    pool.on('error', (e) => console.error('Unexpected PG pool error:', e.message));
    repo = new PostgresTransactionRepository(pool);
    storeName = 'postgresql';
  } else {
    repo = new MemoryTransactionRepository();
    storeName = 'memory';
    console.warn(
      '[config] DATABASE_URL not set — using the in-memory store. ' +
        'Transactions are lost on restart. Set DATABASE_URL for PostgreSQL.'
    );
  }

  const paymentProvider = createPaymentProvider(config);
  const { app } = createApp({ config, repo, paymentProvider });

  const server = app.listen(config.port, () => {
    console.log(`FuelPay backend listening on port ${config.port}`);
    console.log(`  store: ${storeName}`);
    console.log(`  payment provider: ${paymentProvider.name}`);
    console.log(`  mode: DEMO (simulated payments — no real money transferred)`);
    console.log(`  health: http://localhost:${config.port}/api/health`);
    console.warn(
      '  NOTE: tablets must use your computer\'s LAN IP (e.g. http://192.168.1.5:3000), ' +
        'NOT localhost. See README.md → "Backend unreachable from a tablet".'
    );
  });

  async function shutdown(signal) {
    console.log(`\n${signal} received, shutting down...`);
    server.close(async () => {
      await repo.close();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 5000).unref();
  }
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('Failed to start backend:', err.message);
  process.exit(1);
});

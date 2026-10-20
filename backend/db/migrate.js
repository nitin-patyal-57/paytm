/**
 * Applies db/schema.sql to the database in DATABASE_URL.
 * Usage: DATABASE_URL=postgres://user:pass@host:5432/fuelpay npm run migrate
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import pg from 'pg';
import { loadConfig } from '../src/config.js';

const here = path.dirname(url.fileURLToPath(import.meta.url));

async function main() {
  const config = loadConfig();
  if (!config.databaseUrl) {
    console.error(
      'DATABASE_URL is not set.\n' +
        'Example: DATABASE_URL=postgres://localhost:5432/fuelpay npm run migrate'
    );
    process.exit(1);
  }
  const pool = new pg.Pool({ connectionString: config.databaseUrl });
  const sql = fs.readFileSync(path.join(here, 'schema.sql'), 'utf8');
  try {
    await pool.query(sql);
    console.log('Schema applied successfully.');
  } finally {
    await pool.end();
  }
}

main().catch((err) => {
  console.error('Migration failed:', err.message);
  process.exit(1);
});

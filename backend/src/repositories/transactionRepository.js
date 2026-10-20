/**
 * Transaction repositories.
 *
 * Two implementations behind one interface:
 *  - PostgresTransactionRepository (persistent, for integrated development)
 *  - MemoryTransactionRepository   (lightweight local option / tests)
 *
 * Interface:
 *   create(record)                      -> Transaction | throws 409 duplicate
 *   getById(id)                         -> Transaction | null
 *   list({status, fuelType, limit, offset, order}) -> Transaction[]
 *   compareAndSetStatus(id, expectedStatuses[], newStatus, patch)
 *                                        -> Transaction | null (null = lost race / wrong state)
 *   appendEvent(event)                  -> void
 *   close()                             -> void
 */

import crypto from 'node:crypto';
import { TransactionStatus } from '../stateMachine.js';

export function generateTransactionId() {
  // FP + 9-digit random number => matches /^FP\d{6,16}$/ and the FP100001 example style.
  let id;
  do {
    id = `FP${crypto.randomInt(100000000, 1000000000)}`;
  } while (false);
  return id;
}

function nowIso() {
  return new Date().toISOString();
}

export class MemoryTransactionRepository {
  constructor() {
    this.transactions = new Map();
    this.events = [];
  }

  async create(record) {
    if (this.transactions.has(record.transactionId)) {
      const err = new Error(`Transaction already exists: ${record.transactionId}`);
      err.code = 'DUPLICATE_TRANSACTION';
      err.status = 409;
      throw err;
    }
    const now = nowIso();
    const tx = {
      currency: 'INR',
      mode: 'DEMO',
      paymentProvider: null,
      statusReason: null,
      createdAt: now,
      updatedAt: now,
      completedAt: null,
      ...record
    };
    this.transactions.set(tx.transactionId, tx);
    await this.appendEvent({
      transactionId: tx.transactionId,
      eventType: 'CREATED',
      fromStatus: null,
      toStatus: tx.status,
      provider: tx.paymentProvider,
      detail: null
    });
    return { ...tx };
  }

  async getById(id) {
    const tx = this.transactions.get(id);
    return tx ? { ...tx } : null;
  }

  async list({ status, fuelType, limit = 50, offset = 0, order = 'DESC' } = {}) {
    let rows = [...this.transactions.values()];
    if (status) rows = rows.filter((t) => t.status === status);
    if (fuelType) rows = rows.filter((t) => t.fuelType === fuelType);
    rows.sort((a, b) =>
      order === 'ASC'
        ? a.createdAt.localeCompare(b.createdAt)
        : b.createdAt.localeCompare(a.createdAt)
    );
    return rows.slice(offset, offset + limit).map((t) => ({ ...t }));
  }

  async compareAndSetStatus(id, expectedStatuses, newStatus, patch = {}) {
    const tx = this.transactions.get(id);
    if (!tx) return null;
    if (!expectedStatuses.includes(tx.status)) return null;
    const now = nowIso();
    const updated = {
      ...tx,
      status: newStatus,
      updatedAt: now,
      ...patch,
      completedAt:
        newStatus === TransactionStatus.PAYMENT_SUCCESS ||
        newStatus === TransactionStatus.PAYMENT_FAILED ||
        newStatus === TransactionStatus.CANCELLED ||
        newStatus === TransactionStatus.EXPIRED
          ? now
          : tx.completedAt
    };
    this.transactions.set(id, updated);
    return { ...updated };
  }

  async appendEvent(event) {
    this.events.push({ id: this.events.length + 1, createdAt: nowIso(), ...event });
  }

  async getEvents(id) {
    return this.events.filter((e) => e.transactionId === id).map((e) => ({ ...e }));
  }

  async close() {}
}

export class PostgresTransactionRepository {
  constructor(pool) {
    this.pool = pool;
  }

  rowToTransaction(r) {
    return {
      transactionId: r.transaction_id,
      fuelType: r.fuel_type,
      amount: Number(r.amount),
      currency: r.currency,
      status: r.status,
      mode: r.mode,
      paymentProvider: r.payment_provider,
      statusReason: r.status_reason,
      createdAt: new Date(r.created_at).toISOString(),
      updatedAt: new Date(r.updated_at).toISOString(),
      completedAt: r.completed_at ? new Date(r.completed_at).toISOString() : null
    };
  }

  async create(record) {
    const now = new Date();
    try {
      const res = await this.pool.query(
        `INSERT INTO transactions
           (transaction_id, fuel_type, amount, currency, status, mode,
            payment_provider, status_reason, created_at, updated_at, completed_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9,$10)
         RETURNING *`,
        [
          record.transactionId,
          record.fuelType,
          record.amount,
          record.currency ?? 'INR',
          record.status,
          record.mode ?? 'DEMO',
          record.paymentProvider ?? null,
          record.statusReason ?? null,
          now,
          record.completedAt ?? null
        ]
      );
      const tx = this.rowToTransaction(res.rows[0]);
      await this.appendEvent({
        transactionId: tx.transactionId,
        eventType: 'CREATED',
        fromStatus: null,
        toStatus: tx.status,
        provider: tx.paymentProvider,
        detail: null
      });
      return tx;
    } catch (e) {
      if (e.code === '23505') {
        const err = new Error(`Transaction already exists: ${record.transactionId}`);
        err.code = 'DUPLICATE_TRANSACTION';
        err.status = 409;
        throw err;
      }
      throw e;
    }
  }

  async getById(id) {
    const res = await this.pool.query('SELECT * FROM transactions WHERE transaction_id = $1', [id]);
    return res.rows[0] ? this.rowToTransaction(res.rows[0]) : null;
  }

  async list({ status, fuelType, limit = 50, offset = 0, order = 'DESC' } = {}) {
    const where = [];
    const params = [];
    if (status) {
      params.push(status);
      where.push(`status = $${params.length}`);
    }
    if (fuelType) {
      params.push(fuelType);
      where.push(`fuel_type = $${params.length}`);
    }
    params.push(Math.min(Math.max(limit, 1), 200), Math.max(offset, 0));
    const dir = order === 'ASC' ? 'ASC' : 'DESC';
    const res = await this.pool.query(
      `SELECT * FROM transactions
       ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
       ORDER BY created_at ${dir}
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );
    return res.rows.map((r) => this.rowToTransaction(r));
  }

  async compareAndSetStatus(id, expectedStatuses, newStatus, patch = {}) {
    const params = [id, expectedStatuses, newStatus];
    let completedAtExpr = 'completed_at';
    if (
      newStatus === TransactionStatus.PAYMENT_SUCCESS ||
      newStatus === TransactionStatus.PAYMENT_FAILED ||
      newStatus === TransactionStatus.CANCELLED ||
      newStatus === TransactionStatus.EXPIRED
    ) {
      params.push(new Date());
      completedAtExpr = `$${params.length}`;
    }
    params.push(patch.paymentProvider ?? null, patch.statusReason ?? null);
    const res = await this.pool.query(
      `UPDATE transactions
         SET status = $3,
             updated_at = now(),
             completed_at = ${completedAtExpr},
             payment_provider = COALESCE($4, payment_provider),
             status_reason = COALESCE($5, status_reason)
       WHERE transaction_id = $1 AND status = ANY($2)
       RETURNING *`,
      params
    );
    return res.rows[0] ? this.rowToTransaction(res.rows[0]) : null;
  }

  async appendEvent(event) {
    await this.pool.query(
      `INSERT INTO payment_events (transaction_id, event_type, from_status, to_status, provider, detail)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [
        event.transactionId,
        event.eventType,
        event.fromStatus,
        event.toStatus,
        event.provider,
        event.detail ? JSON.stringify(event.detail) : null
      ]
    );
  }

  async getEvents(id) {
    const res = await this.pool.query(
      `SELECT id, transaction_id, event_type, from_status, to_status, provider, detail, created_at
       FROM payment_events WHERE transaction_id = $1 ORDER BY id ASC`,
      [id]
    );
    return res.rows.map((r) => ({
      id: r.id,
      transactionId: r.transaction_id,
      eventType: r.event_type,
      fromStatus: r.from_status,
      toStatus: r.to_status,
      provider: r.provider,
      detail: r.detail,
      createdAt: new Date(r.created_at).toISOString()
    }));
  }

  async close() {
    await this.pool.end();
  }
}

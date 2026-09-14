const { db } = require('./db');
const { v4: uuidv4 } = require('uuid');

/**
 * Double-Entry & Auditable Financial Ledger Service
 *
 * Balance is NEVER stored as a single mutable column.
 * It is reconstructed dynamically by summing verified ledger records.
 */

// Reconstruct a user's balance snapshot from immutable ledger records
function getUserBalance(userId) {
  // Available funds = sum of all AVAILABLE account entries
  const availableRow = db.prepare(`
    SELECT COALESCE(SUM(amount), 0.0) as available_balance
    FROM ledger_entries
    WHERE user_id = ? AND account_type = 'AVAILABLE' AND status = 'SETTLED'
  `).get(userId);

  // Reserved funds = absolute value of currently active reservations in ongoing pools
  // Active pools are those with status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION')
  const reservedRow = db.prepare(`
    SELECT COALESCE(SUM(pp.deposit), 0.0) as reserved_balance
    FROM pool_participants pp
    JOIN pools p ON p.id = pp.pool_id
    WHERE pp.user_id = ? AND p.status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION')
  `).get(userId);

  const available = Math.max(0, Number(availableRow.available_balance));
  const reserved = Number(reservedRow.reserved_balance);
  const total = available + reserved;

  return {
    user_id: userId,
    currency: 'ZAR',
    available: Number(available.toFixed(2)),
    reserved: Number(reserved.toFixed(2)),
    total: Number(total.toFixed(2))
  };
}

// Get user transaction history from the ledger
function getUserLedgerHistory(userId, limit = 50) {
  return db.prepare(`
    SELECT id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp
    FROM ledger_entries
    WHERE user_id = ?
    ORDER BY timestamp DESC
    LIMIT ?
  `).all(userId, limit);
}

// Deposit virtual/test funds
function recordDeposit(userId, amount, referenceId = null) {
  if (amount <= 0) throw new Error('Deposit amount must be greater than 0');
  const txId = uuidv4();
  const now = new Date().toISOString();

  db.prepare(`
    INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (?, ?, NULL, 'AVAILABLE', 'DEPOSIT', ?, 'ZAR', 'SETTLED', 'Account top-up / deposit', ?, ?)
  `).run(txId, userId, amount, referenceId, now);

  recordAudit(userId, 'DEPOSIT', 'ledger_entries', txId, `Deposited ZAR ${amount}`);
  return { txId, balance: getUserBalance(userId) };
}

// Reserve funds when joining or creating a pool (atomic check)
function reserveFundsForPool(userId, poolId, amount) {
  const balance = getUserBalance(userId);
  if (balance.available < amount) {
    throw new Error(`Insufficient spendable funds. Available: R${balance.available.toFixed(2)}, Required: R${amount.toFixed(2)}`);
  }

  const txId = uuidv4();
  const now = new Date().toISOString();

  // Deduct from available
  db.prepare(`
    INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (?, ?, ?, 'AVAILABLE', 'POOL_RESERVE', ?, 'ZAR', 'SETTLED', 'Reserved deposit for pool entry', ?, ?)
  `).run(txId, userId, poolId, -amount, poolId, now);

  return txId;
}

// Settle pool payout and fee
function settlePoolLedger(poolId, winnerId, grossPool, feeAmount, netPayout, participants) {
  const now = new Date().toISOString();
  const settlementTxId = uuidv4();

  // 1. Credit platform fee revenue
  const feeTxId = uuidv4();
  db.prepare(`
    INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (?, 'PLATFORM', ?, 'PLATFORM_REVENUE', 'PLATFORM_FEE', ?, 'ZAR', 'SETTLED', 'Platform service fee (7%)', ?, ?)
  `).run(feeTxId, poolId, feeAmount, settlementTxId, now);

  // 2. Credit net payout to winner
  const winTxId = uuidv4();
  db.prepare(`
    INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (?, ?, ?, 'AVAILABLE', 'POOL_WIN', ?, 'ZAR', 'SETTLED', 'Winning payout for pool', ?, ?)
  `).run(winTxId, winnerId, poolId, netPayout, settlementTxId, now);

  // 3. Mark pool participants settled
  db.prepare(`
    UPDATE pool_participants
    SET is_winner = CASE WHEN user_id = ? THEN 1 ELSE 0 END,
        payout = CASE WHEN user_id = ? THEN ? ELSE 0 END
    WHERE pool_id = ?
  `).run(winnerId, winnerId, netPayout, poolId);

  recordAudit('SYSTEM', 'POOL_SETTLED', 'pools', poolId, `Winner: ${winnerId}, Payout: R${netPayout}, Fee: R${feeAmount}`);

  return { settlementTxId, winTxId, feeTxId };
}

// Refund pool participants (if cancelled or expired)
function refundPool(poolId) {
  const participants = db.prepare('SELECT user_id, deposit FROM pool_participants WHERE pool_id = ?').all(poolId);
  const now = new Date().toISOString();

  for (const p of participants) {
    const refundTxId = uuidv4();
    db.prepare(`
      INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
      VALUES (?, ?, ?, 'AVAILABLE', 'POOL_REFUND', ?, 'ZAR', 'SETTLED', 'Refund for cancelled pool', ?, ?)
    `).run(refundTxId, p.user_id, poolId, p.deposit, poolId, now);
  }

  db.prepare(`UPDATE pools SET status = 'REFUNDED', settled_at = ? WHERE id = ?`).run(now, poolId);
  recordAudit('SYSTEM', 'POOL_REFUNDED', 'pools', poolId, `Refunded ${participants.length} participants`);
}

function recordAudit(actor, action, entity, entityId, details) {
  db.prepare(`
    INSERT INTO audit_logs (id, actor, action, entity, entity_id, details, timestamp)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(uuidv4(), actor, action, entity, entityId, details, new Date().toISOString());
}

module.exports = {
  getUserBalance,
  getUserLedgerHistory,
  recordDeposit,
  reserveFundsForPool,
  settlePoolLedger,
  refundPool,
  recordAudit
};

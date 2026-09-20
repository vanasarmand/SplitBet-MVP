const express = require('express');
const cors = require('cors');
const http = require('http');
const path = require('path');
const { WebSocketServer, WebSocket } = require('ws');
const { v4: uuidv4 } = require('uuid');

const { db, initDatabase } = require('./db');
const { getUserBalance, getUserLedgerHistory, recordDeposit, reserveFundsForPool, settlePoolLedger, recordAudit } = require('./ledger');
const { selectWinnerCryptographically } = require('./rng');

// Initialize DB schema & seed data
initDatabase();

const app = express();
app.use(cors());
app.use(express.json());

// Serve Flutter Web App
const staticPath = path.join(__dirname, '..', 'flutter_app', 'build', 'web');
app.use(express.static(staticPath));

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

// Connected WebSocket clients
const clients = new Set();
wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcast(data) {
  const payload = JSON.stringify(data);
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  }
}

// Probability helper
function calculateProbability(playerCount) {
  if (!playerCount || playerCount < 2) return 'Waiting for players';
  return `${(100 / playerCount).toFixed(2)}%`;
}

// Helper to compute user game statistics dynamically
function getUserStats(userId) {
  const activePoolsCount = db.prepare(`
    SELECT COUNT(DISTINCT pp.pool_id) as count
    FROM pool_participants pp
    JOIN pools p ON p.id = pp.pool_id
    WHERE pp.user_id = ? AND p.status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION')
  `).get(userId).count;

  const completedPoolsCount = db.prepare(`
    SELECT COUNT(DISTINCT pp.pool_id) as count
    FROM pool_participants pp
    JOIN pools p ON p.id = pp.pool_id
    WHERE pp.user_id = ? AND p.status = 'SETTLED'
  `).get(userId).count;

  const winsCount = db.prepare(`
    SELECT COUNT(DISTINCT pp.pool_id) as count
    FROM pool_participants pp
    JOIN pools p ON p.id = pp.pool_id
    WHERE pp.user_id = ? AND (pp.is_winner = 1 OR p.winner_id = ?) AND p.status = 'SETTLED'
  `).get(userId, userId).count;

  const totalWon = db.prepare(`
    SELECT COALESCE(SUM(CASE WHEN pp.payout > 0 THEN pp.payout ELSE p.net_payout END), 0.0) as total
    FROM pool_participants pp
    JOIN pools p ON p.id = pp.pool_id
    WHERE pp.user_id = ? AND (pp.is_winner = 1 OR p.winner_id = ?) AND p.status = 'SETTLED'
  `).get(userId, userId).total;

  const lossesCount = Math.max(0, completedPoolsCount - winsCount);
  const winRate = completedPoolsCount > 0 ? `${((winsCount / completedPoolsCount) * 100).toFixed(1)}%` : '0.0%';

  return {
    active_pools: activePoolsCount,
    completed_pools: completedPoolsCount,
    wins: winsCount,
    losses: lossesCount,
    win_rate: winRate,
    total_won: Number(totalWon.toFixed(2))
  };
}

// ----------------- USERS API -----------------

// List all available demo users
app.get('/api/users', (req, res) => {
  const users = db.prepare('SELECT * FROM users ORDER BY created_at ASC').all();
  const result = users.map(u => ({
    ...u,
    balance: getUserBalance(u.id),
    stats: getUserStats(u.id)
  }));
  res.json(result);
});

// Get user profile & stats
app.get('/api/users/:id', (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.params.id);
  if (!user) return res.status(404).json({ error: 'User not found' });

  res.json({
    ...user,
    balance: getUserBalance(user.id),
    stats: getUserStats(user.id)
  });
});

// Register new user
app.post('/api/users', (req, res) => {
  const { username, display_name, phone, email, avatar_url } = req.body;
  if (!username || !display_name) {
    return res.status(400).json({ error: 'Username and display name are required' });
  }

  const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
  if (existing) {
    return res.status(400).json({ error: 'Username already taken' });
  }

  const id = `usr_${uuidv4().substring(0, 8)}`;
  const now = new Date().toISOString();
  const final_avatar = (avatar_url && avatar_url.trim().length > 0)
    ? avatar_url.trim()
    : `https://api.dicebear.com/7.x/bottts/png?seed=${username}`;

  db.prepare(`
    INSERT INTO users (id, username, display_name, avatar_url, phone, email, verified, first_pool_created, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 1, 0, ?)
  `).run(id, username, display_name, final_avatar, phone || '+27 82 000 0000', email || `${username}@example.com`, now);

  // Initial welcome funding
  recordDeposit(id, 1000.0, 'WELCOME_BONUS');
  recordAudit(id, 'REGISTER_USER', 'users', id, `Registered user @${username} (${display_name}) with R1,000 welcome bonus`);

  const newUser = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
  res.status(201).json({
    ...newUser,
    balance: getUserBalance(id),
    stats: getUserStats(id)
  });
});

// Update user avatar
app.patch('/api/users/:id/avatar', (req, res) => {
  const { avatar_url } = req.body;
  if (!avatar_url) {
    return res.status(400).json({ error: 'avatar_url is required' });
  }

  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.params.id);
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  db.prepare('UPDATE users SET avatar_url = ? WHERE id = ?').run(avatar_url, req.params.id);
  const updated = db.prepare('SELECT * FROM users WHERE id = ?').get(req.params.id);

  res.json({
    ...updated,
    balance: getUserBalance(updated.id),
    stats: getUserStats(updated.id)
  });
});

// Delete user
app.delete('/api/users/:id', (req, res) => {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.params.id);
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  const deleteTx = db.transaction(() => {
    // Delete ledger entries for this user
    db.prepare('DELETE FROM ledger_entries WHERE user_id = ?').run(req.params.id);
    // Delete pool participant entries
    db.prepare('DELETE FROM pool_participants WHERE user_id = ?').run(req.params.id);
    // Clean up pools where user was creator
    const createdPools = db.prepare('SELECT id FROM pools WHERE creator_id = ?').all(req.params.id);
    for (const p of createdPools) {
      db.prepare('DELETE FROM pool_participants WHERE pool_id = ?').run(p.id);
      db.prepare('DELETE FROM ledger_entries WHERE pool_id = ?').run(p.id);
      db.prepare('DELETE FROM pools WHERE id = ?').run(p.id);
    }
    // Remove as winner from any pools
    db.prepare('UPDATE pools SET winner_id = NULL WHERE winner_id = ?').run(req.params.id);
    // Delete user row
    db.prepare('DELETE FROM users WHERE id = ?').run(req.params.id);
  });

  deleteTx();
  res.json({ success: true, deleted_id: req.params.id });
});

// Mark first pool onboarding completed
app.post('/api/users/:id/complete-first-pool', (req, res) => {
  db.prepare('UPDATE users SET first_pool_created = 1 WHERE id = ?').run(req.params.id);
  recordAudit(req.params.id, 'COMPLETE_ONBOARDING', 'users', req.params.id, 'Completed first pool creation onboarding');
  res.json({ success: true });
});

// ----------------- POOLS API -----------------

// Helper to fetch pool with full participant details
function getPoolDetails(poolId) {
  const pool = db.prepare('SELECT * FROM pools WHERE id = ?').get(poolId);
  if (!pool) return null;

  const participants = db.prepare(`
    SELECT pp.user_id, pp.deposit, pp.joined_at, pp.is_winner, pp.payout,
           u.username, u.display_name, u.avatar_url
    FROM pool_participants pp
    JOIN users u ON u.id = pp.user_id
    WHERE pp.pool_id = ?
    ORDER BY pp.joined_at ASC
  `).all(poolId);

  const creator = db.prepare('SELECT id, username, display_name, avatar_url FROM users WHERE id = ?').get(pool.creator_id);

  let winner = null;
  if (pool.winner_id) {
    winner = db.prepare('SELECT id, username, display_name, avatar_url FROM users WHERE id = ?').get(pool.winner_id);
  }

  return {
    ...pool,
    creator,
    winner,
    participants,
    odds_to_win: calculateProbability(pool.max_players),
    slots_remaining: pool.max_players - pool.current_players,
    is_full: pool.current_players >= pool.max_players,
    share_url: `https://splitbet.co.za/pool/${pool.id}`,
    whatsapp_share_text: `Hey! Join my SplitBet pool: Bet R${pool.deposit_amount} to win R${pool.net_payout} (${pool.max_players} players, equal chance)! Tap here: https://splitbet.co.za/pool/${pool.id}`
  };
}

// List all pools with optional filter
app.get('/api/pools', (req, res) => {
  const { filter, user_id } = req.query;

  let query = 'SELECT id FROM pools';
  const conditions = [];
  const params = [];

  if (filter === '1v1') {
    conditions.push('max_players = 2');
  } else if (filter === '3-4') {
    conditions.push('max_players IN (3, 4)');
  } else if (filter === '5-8') {
    conditions.push('max_players >= 5');
  } else if (filter === 'open') {
    conditions.push("status = 'OPEN'");
  } else if (filter === 'settled') {
    conditions.push("status = 'SETTLED'");
  }

  if (filter === 'my_pools' && user_id) {
    conditions.push(`id IN (SELECT pool_id FROM pool_participants WHERE user_id = ?)`);
    params.push(user_id);
  }

  if (conditions.length > 0) {
    query += ' WHERE ' + conditions.join(' AND ');
  }

  query += " ORDER BY CASE status WHEN 'OPEN' THEN 1 WHEN 'FULL' THEN 2 WHEN 'LOCKED' THEN 3 ELSE 4 END, created_at DESC";

  const rows = db.prepare(query).all(...params);
  const pools = rows.map(r => getPoolDetails(r.id));

  res.json({
    total_count: pools.length,
    open_count: pools.filter(p => p.status === 'OPEN').length,
    pools
  });
});

// Single pool details
app.get('/api/pools/:id', (req, res) => {
  const pool = getPoolDetails(req.params.id);
  if (!pool) return res.status(404).json({ error: 'Pool not found' });
  res.json(pool);
});

// Create new pool (Atomic creator reservation & publish)
app.post('/api/pools', (req, res) => {
  const { creator_id, deposit_amount, max_players, description } = req.body;

  if (!creator_id || !deposit_amount || !max_players) {
    return res.status(400).json({ error: 'creator_id, deposit_amount, and max_players are required' });
  }

  const deposit = Number(deposit_amount);
  const players = parseInt(max_players, 10);

  if (players < 2 || players > 8) {
    return res.status(400).json({ error: 'Max players must be between 2 and 8' });
  }
  if (deposit <= 0) {
    return res.status(400).json({ error: 'Deposit must be greater than zero' });
  }

  const poolId = `pool_${uuidv4().substring(0, 8)}`;
  const grossPool = deposit * players;
  const feePercent = 7.0;
  const feeAmount = Math.round(grossPool * (feePercent / 100));
  const netPayout = grossPool - feeAmount;
  const now = new Date().toISOString();

  // Atomic creation & creator reservation
  const createTx = db.transaction(() => {
    // 1. Reserve creator funds
    reserveFundsForPool(creator_id, poolId, deposit);

    // 2. Insert pool record
    db.prepare(`
      INSERT INTO pools (id, creator_id, deposit_amount, max_players, current_players, gross_pool, platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at)
      VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, 'OPEN', ?, ?)
    `).run(poolId, creator_id, deposit, players, grossPool, feePercent, feeAmount, netPayout, description || '', now);

    // 3. Add creator as first participant
    db.prepare(`
      INSERT INTO pool_participants (pool_id, user_id, deposit, joined_at)
      VALUES (?, ?, ?, ?)
    `).run(poolId, creator_id, deposit, now);

    // 4. Mark user's first pool created flag
    db.prepare('UPDATE users SET first_pool_created = 1 WHERE id = ?').run(creator_id);

    recordAudit(creator_id, 'CREATE_POOL', 'pools', poolId, `Created pool for R${deposit}, max players: ${players}`);
  });

  try {
    createTx();
    const createdPool = getPoolDetails(poolId);
    broadcast({ type: 'POOL_CREATED', pool: createdPool });
    broadcast({ type: 'WALLET_UPDATE', userId: creator_id, balance: getUserBalance(creator_id) });
    res.status(201).json(createdPool);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// Atomic Join Pool with Concurrency Lock (PDF Section 7 & 20)
app.post('/api/pools/:id/join', (req, res) => {
  const poolId = req.params.id;
  const { user_id } = req.body;

  if (!user_id) {
    return res.status(400).json({ error: 'user_id is required' });
  }

  let shouldTriggerSettlement = false;
  let finalPool = null;

  // Run in an atomic immediate transaction: guarantees no race condition on final slot!
  const joinTx = db.transaction(() => {
    // 1. Authoritative lock & check on pool state
    const pool = db.prepare('SELECT * FROM pools WHERE id = ?').get(poolId);
    if (!pool) throw new Error('Pool not found');

    if (pool.status !== 'OPEN') {
      throw new Error(`Cannot join pool. Current status is ${pool.status}`);
    }

    if (pool.current_players >= pool.max_players) {
      throw new Error('Pool is already full');
    }

    // 2. Check if user already joined
    const alreadyJoined = db.prepare('SELECT 1 FROM pool_participants WHERE pool_id = ? AND user_id = ?').get(poolId, user_id);
    if (alreadyJoined) {
      throw new Error('You have already joined this pool');
    }

    // 3. Reserve user funds atomically
    reserveFundsForPool(user_id, poolId, pool.deposit_amount);

    // 4. Insert participant
    const now = new Date().toISOString();
    db.prepare(`
      INSERT INTO pool_participants (pool_id, user_id, deposit, joined_at)
      VALUES (?, ?, ?, ?)
    `).run(poolId, user_id, pool.deposit_amount, now);

    // 5. Increment current player count
    const updatedPlayers = pool.current_players + 1;
    let newStatus = pool.status;

    if (updatedPlayers >= pool.max_players) {
      newStatus = 'FULL';
      shouldTriggerSettlement = true;
    }

    db.prepare(`
      UPDATE pools
      SET current_players = ?, status = ?
      WHERE id = ?
    `).run(updatedPlayers, newStatus, poolId);

    recordAudit(user_id, 'JOIN_POOL', 'pools', poolId, `Joined slot ${updatedPlayers}/${pool.max_players}`);
  });

  try {
    joinTx();
    finalPool = getPoolDetails(poolId);

    // Broadcast updated pool and user wallet
    broadcast({ type: 'POOL_UPDATE', pool: finalPool });
    broadcast({ type: 'WALLET_UPDATE', userId: user_id, balance: getUserBalance(user_id) });

    res.json(finalPool);

    // If pool just reached FULL capacity, trigger server-side lock, cryptographic RNG, and settlement!
    if (shouldTriggerSettlement) {
      executeServerSettlement(poolId);
    }
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// Server-Side Settlement Flow (PDF Section 8, 9 & 20)
function executeServerSettlement(poolId) {
  // Step 1: Transition to LOCKED
  db.prepare("UPDATE pools SET status = 'LOCKED' WHERE id = ?").run(poolId);
  broadcast({ type: 'POOL_LOCKED', poolId });

  // Brief suspense pause (1.5s) for UI animation
  setTimeout(() => {
    // Step 2: Transition to RANDOM_SELECTION
    db.prepare("UPDATE pools SET status = 'RANDOM_SELECTION' WHERE id = ?").run(poolId);
    broadcast({ type: 'RANDOM_SELECTION_START', poolId });

    setTimeout(() => {
      // Step 3: Cryptographic Winner Selection
      const participants = db.prepare('SELECT user_id FROM pool_participants WHERE pool_id = ? ORDER BY joined_at ASC').all(poolId).map(p => p.user_id);
      const pool = db.prepare('SELECT * FROM pools WHERE id = ?').get(poolId);

      const rngResult = selectWinnerCryptographically(poolId, participants);
      const winnerId = rngResult.winnerId;

      // Step 4: Atomic Settlement in Ledger
      const settlementTx = db.transaction(() => {
        settlePoolLedger(poolId, winnerId, pool.gross_pool, pool.platform_fee_amount, pool.net_payout, participants);

        db.prepare(`
          UPDATE pools
          SET status = 'SETTLED',
              winner_id = ?,
              random_selection_proof = ?,
              settled_at = ?
          WHERE id = ?
        `).run(winnerId, JSON.stringify(rngResult.proof), new Date().toISOString(), poolId);
      });

      settlementTx();

      const settledPool = getPoolDetails(poolId);
      const winner = db.prepare('SELECT * FROM users WHERE id = ?').get(winnerId);

      // Broadcast settlement & updated winner balance
      broadcast({
        type: 'POOL_SETTLED',
        poolId,
        pool: settledPool,
        winner: {
          id: winner.id,
          display_name: winner.display_name,
          avatar_url: winner.avatar_url
        },
        net_payout: settledPool.net_payout,
        proof: rngResult.proof
      });

      // Update all participant balances in real time
      for (const pId of participants) {
        broadcast({ type: 'WALLET_UPDATE', userId: pId, balance: getUserBalance(pId) });
      }
    }, 2000); // 2 second suspense wheel
  }, 1500);
}

// ----------------- WALLET & LEDGER API -----------------

// Get wallet balance & ledger breakdown
app.get('/api/wallet/:userId', (req, res) => {
  const balance = getUserBalance(req.params.userId);
  const history = getUserLedgerHistory(req.params.userId);
  res.json({
    balance,
    transactions: history
  });
});

// Top-up wallet deposit
app.post('/api/wallet/:userId/deposit', (req, res) => {
  const { amount } = req.body;
  try {
    const result = recordDeposit(req.params.userId, Number(amount));
    broadcast({ type: 'WALLET_UPDATE', userId: req.params.userId, balance: result.balance });
    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ----------------- ADMIN DASHBOARD API -----------------

app.get('/api/admin/overview', (req, res) => {
  const totalUsers = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
  const totalPools = db.prepare('SELECT COUNT(*) as count FROM pools').get().count;
  const activePools = db.prepare("SELECT COUNT(*) as count FROM pools WHERE status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION')").get().count;
  const settledPools = db.prepare("SELECT COUNT(*) as count FROM pools WHERE status = 'SETTLED'").get().count;

  // Financial reconciliation: platform revenue (ledger + settled pools fallback)
  let platformRevenue = db.prepare("SELECT COALESCE(SUM(amount), 0.0) as revenue FROM ledger_entries WHERE account_type = 'PLATFORM_REVENUE' AND status = 'SETTLED'").get().revenue;
  if (!platformRevenue || platformRevenue === 0) {
    platformRevenue = db.prepare("SELECT COALESCE(SUM(platform_fee_amount), 0.0) as revenue FROM pools WHERE status = 'SETTLED'").get().revenue;
  }

  // Total gross volume
  const totalVolume = db.prepare("SELECT COALESCE(SUM(gross_pool), 0.0) as volume FROM pools WHERE status = 'SETTLED'").get().volume;

  // Recent audit logs
  const auditLogs = db.prepare('SELECT * FROM audit_logs ORDER BY timestamp DESC LIMIT 50').all();

  res.json({
    metrics: {
      total_users: totalUsers,
      total_pools: totalPools,
      active_pools: activePools,
      settled_pools: settledPools,
      platform_revenue_zar: Number(platformRevenue.toFixed(2)),
      gross_volume_zar: Number(totalVolume.toFixed(2))
    },
    audit_logs: auditLogs
  });
});

// Fallback for Flutter SPA routing
app.use((req, res, next) => {
  if (req.path.startsWith('/api') || req.path.startsWith('/ws')) return next();
  res.sendFile(path.join(staticPath, 'index.html'));
});

const PORT = process.env.PORT || 4000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`⚡ SplitBet Backend API & WebSocket running on port ${PORT}`);
  console.log(`   - Local:   http://localhost:${PORT}`);
  console.log(`   - Network: http://192.168.1.134:${PORT}`);
});

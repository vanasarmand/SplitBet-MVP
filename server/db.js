const Database = require('better-sqlite3');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const dbPath = path.join(__dirname, 'splitbet.db');
const db = new Database(dbPath);

// Enable WAL mode for optimal concurrency
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

function initDatabase() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      avatar_url TEXT,
      phone TEXT,
      email TEXT,
      verified INTEGER DEFAULT 1,
      subscription_tier TEXT DEFAULT 'Standard',
      first_pool_created INTEGER DEFAULT 0,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS ledger_entries (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      pool_id TEXT,
      account_type TEXT NOT NULL, -- 'AVAILABLE', 'RESERVED', 'PLATFORM_REVENUE'
      type TEXT NOT NULL, -- 'DEPOSIT', 'POOL_RESERVE', 'POOL_ENTRY', 'POOL_WIN', 'PLATFORM_FEE', 'POOL_REFUND', 'WITHDRAWAL'
      amount REAL NOT NULL,
      currency TEXT DEFAULT 'ZAR',
      status TEXT DEFAULT 'SETTLED',
      description TEXT,
      reference_id TEXT,
      timestamp TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS pools (
      id TEXT PRIMARY KEY,
      creator_id TEXT NOT NULL,
      deposit_amount REAL NOT NULL,
      max_players INTEGER NOT NULL,
      current_players INTEGER NOT NULL DEFAULT 1,
      gross_pool REAL NOT NULL,
      platform_fee_percent REAL NOT NULL DEFAULT 7.0,
      platform_fee_amount REAL NOT NULL,
      net_payout REAL NOT NULL,
      status TEXT NOT NULL, -- 'DRAFT', 'OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION', 'SETTLED', 'CANCELLED', 'REFUNDED'
      description TEXT,
      winner_id TEXT,
      random_selection_proof TEXT,
      created_at TEXT NOT NULL,
      settled_at TEXT,
      FOREIGN KEY (creator_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS pool_participants (
      pool_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      deposit REAL NOT NULL,
      joined_at TEXT NOT NULL,
      is_winner INTEGER DEFAULT 0,
      payout REAL DEFAULT 0,
      PRIMARY KEY (pool_id, user_id),
      FOREIGN KEY (pool_id) REFERENCES pools(id),
      FOREIGN KEY (user_id) REFERENCES users(id)
    );

    CREATE TABLE IF NOT EXISTS audit_logs (
      id TEXT PRIMARY KEY,
      actor TEXT NOT NULL,
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      details TEXT,
      timestamp TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS platform_config (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  `);

  // Set default config
  const configStmt = db.prepare('INSERT OR IGNORE INTO platform_config (key, value) VALUES (?, ?)');
  configStmt.run('platform_fee_percent', '7.0');
  configStmt.run('min_deposit', '10.0');
  configStmt.run('max_deposit', '10000.0');
  configStmt.run('min_players', '2');
  configStmt.run('max_players', '8');
  configStmt.run('maintenance_mode', 'false');

  // Seed default demo users if not present
  seedDefaultData();
}

function seedDefaultData() {
  const userCount = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
  if (userCount > 0) return;

  const now = new Date().toISOString();

  const seedUsers = [
    {
      id: 'usr_deric',
      username: 'deric',
      display_name: 'Deric',
      avatar_url: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      phone: '+27 82 123 4567',
      email: 'deric@splitbet.co.za',
      initial_balance: 1250.00
    },
    {
      id: 'usr_sarah',
      username: 'sarah_j',
      display_name: 'Sarah Jenkins',
      avatar_url: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
      phone: '+27 83 234 5678',
      email: 'sarah@splitbet.co.za',
      initial_balance: 2000.00
    },
    {
      id: 'usr_marcus',
      username: 'marcus_k',
      display_name: 'Marcus Krause',
      avatar_url: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      phone: '+27 84 345 6789',
      email: 'marcus@splitbet.co.za',
      initial_balance: 1500.00
    },
    {
      id: 'usr_thabo',
      username: 'thabo_m',
      display_name: 'Thabo Molefe',
      avatar_url: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
      phone: '+27 85 456 7890',
      email: 'thabo@splitbet.co.za',
      initial_balance: 1800.00
    },
    {
      id: 'usr_elena',
      username: 'elena_v',
      display_name: 'Elena Vance',
      avatar_url: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150',
      phone: '+27 86 567 8901',
      email: 'elena@splitbet.co.za',
      initial_balance: 3000.00
    }
  ];

  const insertUser = db.prepare(`
    INSERT INTO users (id, username, display_name, avatar_url, phone, email, verified, first_pool_created, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 1, 1, ?)
  `);

  const insertLedger = db.prepare(`
    INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, timestamp)
    VALUES (?, ?, NULL, 'AVAILABLE', 'DEPOSIT', ?, 'ZAR', 'SETTLED', 'Initial verified test deposit', ?)
  `);

  for (const u of seedUsers) {
    insertUser.run(u.id, u.username, u.display_name, u.avatar_url, u.phone, u.email, now);
    insertLedger.run(uuidv4(), u.id, u.initial_balance, now);
  }

  // Seed initial live pools matching the user's screenshot
  // Pool 1: Bet R155 | Win R280 | X2 Players | 50% ODDS TO WIN (1/2 filled, creator: Sarah)
  createSeedPool({
    id: 'pool_155_1v1',
    creator_id: 'usr_sarah',
    deposit_amount: 155.0,
    max_players: 2,
    description: '1v1 Quick Draw! Winner takes R280.',
    created_at: new Date(Date.now() - 1000 * 60 * 15).toISOString(),
    participants: ['usr_sarah']
  });

  // Pool 2: Bet R300 | Win R830 | X4 Players | 25% ODDS TO WIN (3/4 filled)
  createSeedPool({
    id: 'pool_300_4p',
    creator_id: 'usr_marcus',
    deposit_amount: 300.0,
    max_players: 4,
    description: '4-Player Weekend Dash! 1 spot remaining.',
    created_at: new Date(Date.now() - 1000 * 60 * 30).toISOString(),
    participants: ['usr_marcus', 'usr_thabo', 'usr_elena']
  });

  // Pool 3: Bet R300 | Win R830 | X3 Players | 33.33% ODDS TO WIN (2/3 filled)
  createSeedPool({
    id: 'pool_300_3p',
    creator_id: 'usr_thabo',
    deposit_amount: 300.0,
    max_players: 3,
    description: 'Triple threat pool. High excitement.',
    created_at: new Date(Date.now() - 1000 * 60 * 45).toISOString(),
    participants: ['usr_thabo', 'usr_sarah']
  });

  // Pool 4: High stakes 1v1: Bet R500 | Win R930 | X2 Players (1/2 filled)
  createSeedPool({
    id: 'pool_500_1v1',
    creator_id: 'usr_elena',
    deposit_amount: 500.0,
    max_players: 2,
    description: 'High stakes 1v1. Are you ready?',
    created_at: new Date(Date.now() - 1000 * 60 * 5).toISOString(),
    participants: ['usr_elena']
  });
}

function createSeedPool({ id, creator_id, deposit_amount, max_players, description, created_at, participants }) {
  const current_players = participants.length;
  const gross_pool = deposit_amount * max_players;
  const feePercent = 7.0;
  const feeAmount = Math.round(gross_pool * (feePercent / 100));
  const netPayout = gross_pool - feeAmount;

  db.prepare(`
    INSERT INTO pools (id, creator_id, deposit_amount, max_players, current_players, gross_pool, platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'OPEN', ?, ?)
  `).run(id, creator_id, deposit_amount, max_players, current_players, gross_pool, feePercent, feeAmount, netPayout, description, created_at);

  const insertParticipant = db.prepare(`
    INSERT INTO pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES (?, ?, ?, ?)
  `);

  const insertLedger = db.prepare(`
    INSERT INTO ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, timestamp)
    VALUES (?, ?, ?, 'RESERVED', 'POOL_RESERVE', ?, 'ZAR', 'SETTLED', 'Committed to pool deposit', ?)
  `);

  for (const userId of participants) {
    insertParticipant.run(id, userId, deposit_amount, created_at);
    // Deduct from available and place into reserved
    insertLedger.run(uuidv4(), userId, id, -deposit_amount, created_at);
  }
}

module.exports = {
  db,
  initDatabase
};

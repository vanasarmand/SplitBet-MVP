/**
 * SplitBet MVP - Automated Backend, Ledger & RNG Test Suite
 * Runs against the live backend API and verifies financial integrity.
 */

const http = require('http');

const BASE_URL = 'http://localhost:4000/api';

// Helper for making JSON HTTP requests
function request(method, path, data = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(BASE_URL + path);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        let parsed = null;
        try {
          parsed = body ? JSON.parse(body) : null;
        } catch (e) {
          parsed = body;
        }
        resolve({ status: res.statusCode, data: parsed });
      });
    });

    req.on('error', reject);

    if (data) {
      req.write(JSON.stringify(data));
    }
    req.end();
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    console.log(`  ✓ ${message}`);
    passed++;
  } else {
    console.error(`  ✗ FAIL: ${message}`);
    failed++;
  }
}

async function runTests() {
  console.log('====================================================');
  console.log('🧪 Starting SplitBet Backend & Ledger Test Suite');
  console.log('====================================================\n');

  const uniqueSuffix = Date.now().toString().slice(-5);

  // ----------------------------------------------------
  // TEST SUITE 1: User Lifecycle & Welcome Bonus
  // ----------------------------------------------------
  console.log('--- 1. User Lifecycle & Welcome Bonus ---');
  const userARes = await request('POST', '/users', {
    username: `test_user_a_${uniqueSuffix}`,
    display_name: `Alice ${uniqueSuffix}`,
    phone: '+27 82 111 0001',
    email: `alice_${uniqueSuffix}@example.com`
  });

  assert(userARes.status === 201, 'Alice successfully created (201)');
  const userA = userARes.data;
  assert(userA.balance.available === 1000, 'Alice received ZAR 1,000 welcome bonus available');
  assert(userA.balance.reserved === 0, 'Alice has 0 reserved balance initially');
  assert(userA.balance.total === 1000, 'Alice total balance is ZAR 1,000');

  const userBRes = await request('POST', '/users', {
    username: `test_user_b_${uniqueSuffix}`,
    display_name: `Bob ${uniqueSuffix}`,
    phone: '+27 82 111 0002',
    email: `bob_${uniqueSuffix}@example.com`
  });
  assert(userBRes.status === 201, 'Bob successfully created (201)');
  const userB = userBRes.data;

  // ----------------------------------------------------
  // TEST SUITE 2: Edge Cases & Validation Guards
  // ----------------------------------------------------
  console.log('\n--- 2. Pool Validation & Guard Rails ---');

  // Guard: max players < 2
  const badPlayersRes = await request('POST', '/pools', {
    creator_id: userA.id,
    deposit_amount: 50,
    max_players: 1
  });
  assert(badPlayersRes.status === 400, 'Rejects pool with max_players < 2');

  // Guard: max players > 8
  const badPlayersHighRes = await request('POST', '/pools', {
    creator_id: userA.id,
    deposit_amount: 50,
    max_players: 9
  });
  assert(badPlayersHighRes.status === 400, 'Rejects pool with max_players > 8');

  // Guard: negative deposit
  const badDepositRes = await request('POST', '/pools', {
    creator_id: userA.id,
    deposit_amount: -10,
    max_players: 2
  });
  assert(badDepositRes.status === 400, 'Rejects pool with negative deposit');

  // Guard: deposit exceeds available funds
  const overdrawRes = await request('POST', '/pools', {
    creator_id: userA.id,
    deposit_amount: 5000,
    max_players: 2
  });
  assert(overdrawRes.status === 400, 'Rejects pool when deposit exceeds user balance');

  // ----------------------------------------------------
  // TEST SUITE 3: Atomic Pool Creation & Fund Reservation
  // ----------------------------------------------------
  console.log('\n--- 3. Pool Creation & Double-Entry Reservation ---');
  const createPoolRes = await request('POST', '/pools', {
    creator_id: userA.id,
    deposit_amount: 200,
    max_players: 2,
    description: `Test 1v1 Pool ${uniqueSuffix}`
  });

  assert(createPoolRes.status === 201, 'Pool successfully created (201)');
  const pool = createPoolRes.data;
  assert(pool.status === 'OPEN', 'Initial pool status is OPEN');
  assert(pool.deposit_amount === 200, 'Deposit amount is R200');
  assert(pool.gross_pool === 400, 'Gross pool is R400 (2 x 200)');
  assert(pool.platform_fee_percent === 7, 'Platform fee is 7%');
  assert(pool.platform_fee_amount === 28, 'Platform fee amount is R28 (7% of 400)');
  assert(pool.net_payout === 372, 'Net winner payout is R372 (400 - 28)');
  assert(pool.current_players === 1, 'Current players is 1 (creator joined)');
  assert(pool.odds_to_win === '50.00%', 'Odds to win correctly calculated as 50.00%');

  // Verify Alice's balance after reservation
  const userABalanceRes = await request('GET', `/wallet/${userA.id}`);
  const userABal = userABalanceRes.data.balance;
  assert(userABal.available === 800, 'Alice available balance reduced by R200 (800)');
  assert(userABal.reserved === 200, 'Alice reserved balance increased to R200');
  assert(userABal.total === 1000, 'Alice total balance remains invariant at R1,000');

  // ----------------------------------------------------
  // TEST SUITE 4: Joining & Concurrency Safeguards
  // ----------------------------------------------------
  console.log('\n--- 4. Join Integrity & Duplicate Prevention ---');

  // Creator cannot rejoin their own pool
  const rejoinRes = await request('POST', `/pools/${pool.id}/join`, { user_id: userA.id });
  assert(rejoinRes.status === 400, 'Creator cannot rejoin the same pool');

  // Bob joins
  const bobJoinRes = await request('POST', `/pools/${pool.id}/join`, { user_id: userB.id });
  assert(bobJoinRes.status === 200, 'Bob successfully joined the pool');
  assert(bobJoinRes.data.current_players === 2, 'Pool player count reached 2/2');

  // Bob attempts duplicate join
  const bobDuplicateRes = await request('POST', `/pools/${pool.id}/join`, { user_id: userB.id });
  assert(bobDuplicateRes.status === 400, 'Prevent duplicate join from the same user');

  // ----------------------------------------------------
  // TEST SUITE 5: Settlement, Cryptographic RNG & Proof
  // ----------------------------------------------------
  console.log('\n--- 5. Settlement Cycle & Cryptographic Fair-Play Proof ---');
  console.log('  Waiting 4.2 seconds for server-side settlement animation & RNG...');
  await sleep(4200);

  const settledPoolRes = await request('GET', `/pools/${pool.id}`);
  const settledPool = settledPoolRes.data;
  assert(settledPool.status === 'SETTLED', `Pool reached SETTLED status (was: ${settledPool.status})`);
  assert(settledPool.winner_id !== null, `Winner is assigned: ${settledPool.winner_id}`);
  assert([userA.id, userB.id].includes(settledPool.winner_id), 'Winner is one of the pool participants');

  // Verify Cryptographic Proof
  const proof = JSON.parse(settledPool.random_selection_proof);
  assert(proof.mechanism === 'NODE_CRYPTO_RANDOM_INT_UNBIASED', 'Proof mechanism uses unbiased crypto.randomInt');
  assert(proof.server_seed && proof.server_seed.length === 64, 'Proof has 32-byte (64 hex) cryptographic server seed');
  assert(proof.entropy_hash && proof.entropy_hash.length === 64, 'Proof has SHA-256 entropy hash');
  assert(proof.winning_index === 0 || proof.winning_index === 1, 'Winning index is within bounds [0, 1]');
  assert(proof.equal_probability === '50.00%', 'Equal probability stated as 50.00%');

  // ----------------------------------------------------
  // TEST SUITE 6: Ledger Conservation of Funds
  // ----------------------------------------------------
  console.log('\n--- 6. Financial Ledger Double-Entry Conservation ---');
  const winnerBalRes = await request('GET', `/wallet/${settledPool.winner_id}`);
  const winnerBal = winnerBalRes.data.balance;
  const loserId = settledPool.winner_id === userA.id ? userB.id : userA.id;
  const loserBalRes = await request('GET', `/wallet/${loserId}`);
  const loserBal = loserBalRes.data.balance;

  assert(loserBal.available === 800, 'Loser has R800 available (lost R200 deposit)');
  assert(loserBal.reserved === 0, 'Loser has R0 reserved after settlement');
  assert(loserBal.total === 800, 'Loser total balance is R800');

  assert(winnerBal.available === 1172, `Winner has R1172 available (800 + 372 net payout)`);
  assert(winnerBal.reserved === 0, 'Winner has R0 reserved after settlement');
  assert(winnerBal.total === 1172, 'Winner total balance is R1172');

  // Mathematical Conservation:
  // Initial total = 1000 + 1000 = 2000
  // Loser total (800) + Winner total (1172) + Platform Fee (28) = 2000.00!
  const systemTotal = loserBal.total + winnerBal.total + settledPool.platform_fee_amount;
  assert(systemTotal === 2000, `Complete conservation of funds: ${loserBal.total} + ${winnerBal.total} + ${settledPool.platform_fee_amount} == 2000 ZAR`);

  // ----------------------------------------------------
  // TEST SUITE 7: Admin Overview & Financial Audit
  // ----------------------------------------------------
  console.log('\n--- 7. Admin Dashboard & Audit Trail ---');
  const adminRes = await request('GET', '/admin/overview');
  assert(adminRes.status === 200, 'Admin overview returned 200');
  const admin = adminRes.data;
  assert(admin.metrics.platform_revenue_zar >= 28, `Platform revenue accurately accounts for fees (Current: R${admin.metrics.platform_revenue_zar})`);
  assert(admin.metrics.settled_pools >= 1, `Settled pools count recorded: ${admin.metrics.settled_pools}`);
  assert(admin.audit_logs && admin.audit_logs.length > 0, `Audit logs stream active with ${admin.audit_logs.length} entries`);
  assert(admin.audit_logs.some(l => l.action === 'REGISTER_USER'), 'Audit trail includes REGISTER_USER activity');

  // ----------------------------------------------------
  // TEST SUITE 8: User Game Statistics Verification
  // ----------------------------------------------------
  console.log('\n--- 8. User Game Statistics Verification ---');
  const winnerUserRes = await request('GET', `/users/${settledPool.winner_id}`);
  assert(winnerUserRes.status === 200, 'Winner user profile fetched');
  const winnerStats = winnerUserRes.data.stats;
  assert(winnerStats !== undefined, 'Winner profile has stats object');
  assert(winnerStats.wins >= 1, `Winner has recorded win (wins: ${winnerStats.wins})`);
  assert(winnerStats.completed_pools >= 1, `Winner has recorded completed pool (completed: ${winnerStats.completed_pools})`);
  assert(winnerStats.total_won >= 372, `Winner total_won reflects payout (total_won: ${winnerStats.total_won})`);

  const loserUserRes = await request('GET', `/users/${loserId}`);
  assert(loserUserRes.status === 200, 'Loser user profile fetched');
  const loserStats = loserUserRes.data.stats;
  assert(loserStats !== undefined, 'Loser profile has stats object');
  assert(loserStats.losses >= 1, `Loser has recorded loss (losses: ${loserStats.losses})`);
  assert(loserStats.completed_pools >= 1, `Loser has recorded completed pool (completed: ${loserStats.completed_pools})`);

  const allUsersRes = await request('GET', '/users');
  assert(allUsersRes.status === 200, 'All users endpoint returned 200');
  assert(allUsersRes.data.every(u => u.stats !== undefined), 'All users in list have hydrated stats object');

  console.log('\n====================================================');
  console.log(`🏁 Test Results: ${passed} Passed, ${failed} Failed`);
  console.log('====================================================');

  if (failed > 0) {
    process.exit(1);
  } else {
    process.exit(0);
  }
}

runTests().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});

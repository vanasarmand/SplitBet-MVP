const crypto = require('crypto');

/**
 * Server-Side Cryptographically Secure Random Winner Selection
 *
 * Requirements (PDF Section 9):
 * - Server-side only. Client applications never generate or influence RNG.
 * - Cryptographically secure randomness (crypto.randomInt).
 * - Equal probability for every participant: P = 1 / N.
 * - Immutable, auditable proof recording seed, timestamp, participants, index, and result.
 */

function selectWinnerCryptographically(poolId, participants) {
  if (!participants || participants.length < 2) {
    throw new Error('A pool must have at least 2 participants for winner selection');
  }

  const serverSeed = crypto.randomBytes(32).toString('hex');
  const timestamp = new Date().toISOString();

  // Fair selection using cryptographically secure random integer in range [0, N)
  // crypto.randomInt ensures uniform distribution without modulo bias
  const winningIndex = crypto.randomInt(0, participants.length);
  const selectedWinner = participants[winningIndex];

  // Hash proof of selection for auditability
  const entropyInput = `${poolId}:${timestamp}:${serverSeed}:${participants.join(',')}`;
  const proofHash = crypto.createHash('sha256').update(entropyInput).digest('hex');

  const auditProof = {
    mechanism: 'NODE_CRYPTO_RANDOM_INT_UNBIASED',
    pool_id: poolId,
    timestamp: timestamp,
    total_participants: participants.length,
    participants: participants,
    winning_index: winningIndex,
    winner_id: selectedWinner,
    server_seed: serverSeed,
    entropy_hash: proofHash,
    equal_probability: `${(100 / participants.length).toFixed(2)}%`
  };

  return {
    winnerId: selectedWinner,
    winningIndex: winningIndex,
    proof: auditProof
  };
}

module.exports = {
  selectWinnerCryptographically
};

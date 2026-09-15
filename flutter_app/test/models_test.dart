import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/user.dart';
import 'package:flutter_app/models/pool.dart';

void main() {
  group('User Models Tests', () {
    test('UserBalance correctly deserializes and calculates', () {
      final json = {
        'user_id': 'usr_test_1',
        'currency': 'ZAR',
        'available': 850.5,
        'reserved': 149.5,
        'total': 1000.0,
      };

      final balance = UserBalance.fromJson(json);
      expect(balance.userId, 'usr_test_1');
      expect(balance.currency, 'ZAR');
      expect(balance.available, 850.5);
      expect(balance.reserved, 149.5);
      expect(balance.total, 1000.0);
    });

    test('UserStats correctly parses win rate and counts', () {
      final json = {
        'active_pools': 2,
        'completed_pools': 8,
        'wins': 4,
        'losses': 4,
        'win_rate': '50.0%',
        'total_won': 1488.0,
      };

      final stats = UserStats.fromJson(json);
      expect(stats.activePools, 2);
      expect(stats.completedPools, 8);
      expect(stats.wins, 4);
      expect(stats.losses, 4);
      expect(stats.winRate, '50.0%');
      expect(stats.totalWon, 1488.0);
    });

    test('AppUser parses verified and firstPoolCreated integer/boolean flags', () {
      final jsonWithInts = {
        'id': 'usr_deric',
        'username': 'deric',
        'display_name': 'Deric King',
        'avatar_url': 'https://example.com/avatar.png',
        'phone': '+27 82 123 4567',
        'email': 'deric@splitbet.co.za',
        'verified': 1,
        'subscription_tier': 'Gold',
        'first_pool_created': 1,
        'balance': {
          'user_id': 'usr_deric',
          'currency': 'ZAR',
          'available': 1200,
          'reserved': 300,
          'total': 1500,
        },
      };

      final user = AppUser.fromJson(jsonWithInts);
      expect(user.id, 'usr_deric');
      expect(user.displayName, 'Deric King');
      expect(user.verified, true);
      expect(user.firstPoolCreated, true);
      expect(user.balance.available, 1200.0);
      expect(user.balance.reserved, 300.0);
      expect(user.balance.total, 1500.0);
    });
  });

  group('Pool Models Tests', () {
    test('Pool correctly parses financial fields and participants', () {
      final json = {
        'id': 'pool_test_123',
        'creator_id': 'usr_alice',
        'deposit_amount': 100.0,
        'max_players': 4,
        'current_players': 2,
        'gross_pool': 400.0,
        'platform_fee_percent': 7.0,
        'platform_fee_amount': 28.0,
        'net_payout': 372.0,
        'status': 'OPEN',
        'description': 'Weekend SplitBet pool',
        'created_at': '2026-09-14T12:00:00Z',
        'creator': {
          'id': 'usr_alice',
          'username': 'alice',
          'display_name': 'Alice',
          'avatar_url': 'https://example.com/alice.png',
        },
        'participants': [
          {
            'user_id': 'usr_alice',
            'deposit': 100.0,
            'joined_at': '2026-09-14T12:00:00Z',
            'is_winner': 0,
            'payout': 0.0,
            'username': 'alice',
            'display_name': 'Alice',
            'avatar_url': 'https://example.com/alice.png',
          },
          {
            'user_id': 'usr_bob',
            'deposit': 100.0,
            'joined_at': '2026-09-14T12:05:00Z',
            'is_winner': 0,
            'payout': 0.0,
            'username': 'bob',
            'display_name': 'Bob',
            'avatar_url': 'https://example.com/bob.png',
          }
        ],
        'odds_to_win': '25.00%',
        'slots_remaining': 2,
        'is_full': false,
        'share_url': 'https://splitbet.co.za/pool/pool_test_123',
        'whatsapp_share_text': 'Hey! Join my SplitBet pool: Bet R100 to win R372',
      };

      final pool = Pool.fromJson(json);
      expect(pool.id, 'pool_test_123');
      expect(pool.depositAmount, 100.0);
      expect(pool.maxPlayers, 4);
      expect(pool.currentPlayers, 2);
      expect(pool.grossPool, 400.0);
      expect(pool.platformFeeAmount, 28.0);
      expect(pool.netPayout, 372.0);
      expect(pool.status, 'OPEN');
      expect(pool.oddsToWin, '25.00%');
      expect(pool.slotsRemaining, 2);
      expect(pool.isFull, false);
      expect(pool.participants.length, 2);
      expect(pool.participants[0].displayName, 'Alice');
      expect(pool.participants[1].displayName, 'Bob');
      expect(pool.whatsappShareText, contains('Bet R100 to win R372'));
    });

    test('Settled Pool parses winner details and proof', () {
      final json = {
        'id': 'pool_settled_99',
        'creator_id': 'usr_alice',
        'deposit_amount': 50.0,
        'max_players': 2,
        'current_players': 2,
        'gross_pool': 100.0,
        'platform_fee_percent': 7.0,
        'platform_fee_amount': 7.0,
        'net_payout': 93.0,
        'status': 'SETTLED',
        'description': 'Head to head',
        'winner_id': 'usr_bob',
        'winner': {
          'id': 'usr_bob',
          'username': 'bob',
          'display_name': 'Bob Winner',
          'avatar_url': 'https://example.com/bob.png',
        },
        'created_at': '2026-09-14T10:00:00Z',
        'settled_at': '2026-09-14T10:02:00Z',
        'participants': [
          {
            'user_id': 'usr_alice',
            'deposit': 50.0,
            'joined_at': '2026-09-14T10:00:00Z',
            'is_winner': 0,
            'payout': 0.0,
            'username': 'alice',
            'display_name': 'Alice',
            'avatar_url': '',
          },
          {
            'user_id': 'usr_bob',
            'deposit': 50.0,
            'joined_at': '2026-09-14T10:01:00Z',
            'is_winner': 1,
            'payout': 93.0,
            'username': 'bob',
            'display_name': 'Bob Winner',
            'avatar_url': '',
          }
        ],
        'odds_to_win': '50.00%',
        'slots_remaining': 0,
        'is_full': true,
        'share_url': 'https://splitbet.co.za/pool/pool_settled_99',
        'whatsapp_share_text': '',
      };

      final pool = Pool.fromJson(json);
      expect(pool.status, 'SETTLED');
      expect(pool.winnerId, 'usr_bob');
      expect(pool.winner?.displayName, 'Bob Winner');
      expect(pool.isFull, true);
      expect(pool.slotsRemaining, 0);
      expect(pool.participants[1].isWinner, true);
      expect(pool.participants[1].payout, 93.0);
    });
  });
}

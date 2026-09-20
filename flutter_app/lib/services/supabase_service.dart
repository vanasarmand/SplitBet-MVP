import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user.dart';
import '../models/pool.dart';
import 'supabase_config.dart';

class SupabaseService {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  static Future<bool> init() async {
    if (!SupabaseConfig.isConfigured) return false;
    try {
      if (!_isInitialized) {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          // ignore: deprecated_member_use
          anonKey: SupabaseConfig.anonKey,
          realtimeClientOptions: const RealtimeClientOptions(
            eventsPerSecond: 10,
          ),
        );
        _isInitialized = true;
      }
      return true;
    } catch (e) {
      debugPrint('Supabase initialize error: $e');
      return false;
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  void listenToRealtime() {
    if (!_isInitialized) return;
    try {
      _client
          .channel('public:pools')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pools',
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord['status'] == 'SETTLED') {
                final winnerId = newRecord['winner_id'];
                if (winnerId != null) {
                  _client
                      .from('users')
                      .select('id, username, display_name, avatar_url')
                      .eq('id', winnerId)
                      .maybeSingle()
                      .then((winnerUser) {
                    _eventController.add({
                      'type': 'POOL_SETTLED',
                      'poolId': newRecord['id'],
                      'winner': winnerUser ?? {'id': winnerId},
                      'net_payout': newRecord['net_payout'],
                      'proof': newRecord['random_selection_proof'],
                    });
                  }).catchError((_) {
                    _eventController.add({
                      'type': 'POOL_SETTLED',
                      'poolId': newRecord['id'],
                      'winner': {'id': winnerId},
                      'net_payout': newRecord['net_payout'],
                      'proof': newRecord['random_selection_proof'],
                    });
                  });
                } else {
                  _eventController.add({
                    'type': 'POOL_SETTLED',
                    'poolId': newRecord['id'],
                    'winner': null,
                    'net_payout': newRecord['net_payout'],
                    'proof': newRecord['random_selection_proof'],
                  });
                }
              } else {
                _eventController.add({
                  'type': 'POOL_UPDATE',
                  'poolId': newRecord['id'],
                });
              }
            },
          )
          .subscribe();

      _client
          .channel('public:ledger_entries')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'ledger_entries',
            callback: (payload) {
              final record = payload.newRecord;
              _eventController.add({
                'type': 'WALLET_UPDATE',
                'userId': record['user_id'],
              });
            },
          )
          .subscribe();

      _client
          .channel('public:audit_logs')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'audit_logs',
            callback: (payload) {
              final record = payload.newRecord;
              _eventController.add({
                'type': 'AUDIT_LOG_INSERT',
                'record': record,
              });
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Supabase Realtime subscription error: $e');
    }
  }

  Future<bool> testConnection([String? testUrl, String? testKey]) async {
    final targetUrl = testUrl ?? SupabaseConfig.url;
    final targetKey = testKey ?? SupabaseConfig.anonKey;
    if (targetUrl.isEmpty || targetKey.isEmpty) return false;

    try {
      final client = SupabaseClient(targetUrl, targetKey);
      await client.from('users').select('id').limit(1);
      return true;
    } catch (e) {
      debugPrint('Supabase test connection failed: $e');
      return false;
    }
  }

  // 1. Fetch all users
  Future<List<AppUser>> getUsers() async {
    final res = await _client.rpc('get_all_users');
    if (res is List) {
      return res
          .map((u) => AppUser.fromJson(Map<String, dynamic>.from(u)))
          .toList();
    }
    // Fallback: query users table directly
    final direct = await _client.from('users').select();
    final users = <AppUser>[];
    for (final item in (direct as List)) {
      final map = Map<String, dynamic>.from(item);
      final bRes = await _client.rpc('get_user_balance', params: {'p_user_id': map['id']});
      map['balance'] = bRes;
      try {
        final sRes = await _client.rpc('get_user_stats', params: {'p_user_id': map['id']});
        map['stats'] = sRes;
      } catch (_) {}
      users.add(AppUser.fromJson(map));
    }
    return users;
  }

  // 2. Fetch single user
  Future<AppUser> getUser(String userId) async {
    final res = await _client.rpc('get_single_user', params: {'p_user_id': userId});
    if (res != null && res is Map) {
      return AppUser.fromJson(Map<String, dynamic>.from(res));
    }
    throw Exception('User not found in Supabase');
  }

  // 3. Register user
  Future<AppUser> registerUser({
    required String username,
    required String displayName,
    String? phone,
    String? email,
    String? avatarUrl,
  }) async {
    final id = 'usr_${username.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}';
    final avatarSeed = username;
    final finalAvatar = (avatarUrl != null && avatarUrl.trim().isNotEmpty)
        ? avatarUrl.trim()
        : 'https://api.dicebear.com/7.x/bottts/png?seed=$avatarSeed';

    await _client.from('users').insert({
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': finalAvatar,
      'phone': phone ?? '+27 82 000 0000',
      'email': email ?? '$username@example.com',
      'verified': 1,
      'first_pool_created': 0,
    });

    // Credit initial test deposit of R1,000.00
    await _client.rpc('record_deposit', params: {
      'p_user_id': id,
      'p_amount': 1000.00,
    });

    // Record audit log for user registration
    try {
      await _client.from('audit_logs').insert({
        'actor': id,
        'action': 'REGISTER_USER',
        'entity': 'users',
        'entity_id': id,
        'details': 'Registered user @$username ($displayName) with R1,000 welcome bonus',
      });
    } catch (_) {}

    return getUser(id);
  }

  // Update user avatar
  Future<AppUser> updateUserAvatar(String userId, String avatarUrl) async {
    await _client.from('users').update({'avatar_url': avatarUrl}).eq('id', userId);
    return getUser(userId);
  }

  // Delete user
  Future<void> deleteUser(String userId) async {
    // Delete ledger entries
    await _client.from('ledger_entries').delete().eq('user_id', userId);
    // Delete pool participants
    await _client.from('pool_participants').delete().eq('user_id', userId);
    // Nullify winner_id in pools
    await _client.from('pools').update({'winner_id': null}).eq('winner_id', userId);
    // Clean up pools where user was creator
    final created = await _client.from('pools').select('id').eq('creator_id', userId);
    for (final p in (created as List)) {
      final pid = p['id'];
      await _client.from('pool_participants').delete().eq('pool_id', pid);
      await _client.from('ledger_entries').delete().eq('pool_id', pid);
      await _client.from('pools').delete().eq('id', pid);
    }
    // Delete user row
    await _client.from('users').delete().eq('id', userId);
  }

  // 4. Complete first pool onboarding
  Future<void> completeFirstPool(String userId) async {
    await _client.from('users').update({'first_pool_created': 1}).eq('id', userId);
    try {
      await _client.from('audit_logs').insert({
        'actor': userId,
        'action': 'COMPLETE_ONBOARDING',
        'entity': 'users',
        'entity_id': userId,
        'details': 'Completed first pool creation onboarding',
      });
    } catch (_) {}
  }

  // 5. Fetch pools
  Future<Map<String, dynamic>> getPools({String? filter, String? userId}) async {
    final res = await _client.rpc('get_all_pools', params: {
      'p_filter': (filter == null || filter == 'all') ? null : filter,
      'p_user_id': userId,
    });

    if (res is Map) {
      final rawPools = res['pools'] as List? ?? [];
      final pools = rawPools.map((p) => Pool.fromJson(Map<String, dynamic>.from(p))).toList();
      return {
        'total_count': res['total_count'] ?? 0,
        'open_count': res['open_count'] ?? 0,
        'pools': pools,
      };
    }
    return {'total_count': 0, 'open_count': 0, 'pools': <Pool>[]};
  }

  // 6. Create pool (Atomic RPC)
  Future<Pool> createPool({
    required String creatorId,
    required double depositAmount,
    required int maxPlayers,
    String? description,
  }) async {
    final res = await _client.rpc('create_pool', params: {
      'p_creator_id': creatorId,
      'p_deposit_amount': depositAmount,
      'p_max_players': maxPlayers,
      'p_description': description,
    });

    return Pool.fromJson(Map<String, dynamic>.from(res));
  }

  // 7. Join pool (Atomic RPC with Auto-settlement)
  Future<Pool> joinPool({
    required String poolId,
    required String userId,
  }) async {
    final res = await _client.rpc('join_pool', params: {
      'p_pool_id': poolId,
      'p_user_id': userId,
    });

    return Pool.fromJson(Map<String, dynamic>.from(res));
  }

  // 8. Get wallet & transactions
  Future<Map<String, dynamic>> getWallet(String userId) async {
    final balanceRes = await _client.rpc('get_user_balance', params: {'p_user_id': userId});
    final txRes = await _client
        .from('ledger_entries')
        .select()
        .eq('user_id', userId)
        .order('timestamp', ascending: false)
        .limit(50);

    return {
      'balance': UserBalance.fromJson(Map<String, dynamic>.from(balanceRes)),
      'transactions': txRes as List? ?? [],
    };
  }

  // 9. Deposit funds
  Future<void> depositFunds(String userId, double amount) async {
    await _client.rpc('record_deposit', params: {
      'p_user_id': userId,
      'p_amount': amount,
    });
  }

  // 10. Admin Overview & Financials
  Future<Map<String, dynamic>> getAdminOverview() async {
    try {
      final res = await _client.rpc('get_admin_overview');
      if (res != null && res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('Supabase get_admin_overview RPC error: $e');
    }

    // Direct query fallback if RPC is unreachable
    final totalUsers = await _client.from('users').count();
    final totalPools = await _client.from('pools').count();
    final activePools = await _client.from('pools').count(CountOption.exact).filter('status', 'in', '("OPEN","FULL","LOCKED","RANDOM_SELECTION")');
    final settledPools = await _client.from('pools').count(CountOption.exact).eq('status', 'SETTLED');
    final auditLogs = await _client.from('audit_logs').select().order('timestamp', ascending: false).limit(50);

    double platformRevenue = 0.0;
    try {
      final revRes = await _client
          .from('ledger_entries')
          .select('amount')
          .eq('account_type', 'PLATFORM_REVENUE')
          .eq('status', 'SETTLED');
      for (final r in (revRes as List)) {
        platformRevenue += ((r['amount'] as num?)?.toDouble() ?? 0.0);
      }
    } catch (_) {}

    double grossVolume = 0.0;
    try {
      final volRes = await _client
          .from('pools')
          .select('gross_pool')
          .eq('status', 'SETTLED');
      for (final v in (volRes as List)) {
        grossVolume += ((v['gross_pool'] as num?)?.toDouble() ?? 0.0);
      }
    } catch (_) {}

    return {
      'metrics': {
        'total_users': totalUsers,
        'total_pools': totalPools,
        'active_pools': activePools,
        'settled_pools': settledPools,
        'platform_revenue_zar': platformRevenue,
        'gross_volume_zar': grossVolume,
      },
      'audit_logs': auditLogs,
    };
  }

  void dispose() {
    _eventController.close();
  }
}

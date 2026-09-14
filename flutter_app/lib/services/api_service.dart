import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/user.dart';
import '../models/pool.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:4000/api';
  static const String wsUrl = 'ws://localhost:4000/ws';

  WebSocketChannel? _wsChannel;
  final StreamController<Map<String, dynamic>> _wsEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get wsEvents => _wsEventController.stream;

  void connectWebSocket() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen(
        (data) {
          try {
            final parsed = jsonDecode(data as String) as Map<String, dynamic>;
            _wsEventController.add(parsed);
          } catch (e) {
            debugPrint('WebSocket parse error: $e');
          }
        },
        onError: (err) {
          debugPrint('WebSocket error: $err');
          _reconnectWebSocket();
        },
        onDone: () {
          debugPrint('WebSocket closed, reconnecting in 3s...');
          _reconnectWebSocket();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    Timer(const Duration(seconds: 3), () {
      connectWebSocket();
    });
  }

  void dispose() {
    _wsChannel?.sink.close();
    _wsEventController.close();
  }

  // Fetch all demo users
  Future<List<AppUser>> getUsers() async {
    final res = await http.get(Uri.parse('$baseUrl/users'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((u) => AppUser.fromJson(u)).toList();
    }
    throw Exception('Failed to load users: ${res.body}');
  }

  // Fetch single user with stats
  Future<AppUser> getUser(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/users/$userId'));
    if (res.statusCode == 200) {
      return AppUser.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to load user: ${res.body}');
  }

  // Register new user
  Future<AppUser> registerUser({
    required String username,
    required String displayName,
    String? phone,
    String? email,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'display_name': displayName,
        'phone': phone,
        'email': email,
      }),
    );
    if (res.statusCode == 201) {
      return AppUser.fromJson(jsonDecode(res.body));
    }
    throw Exception(jsonDecode(res.body)['error'] ?? 'Registration failed');
  }

  // Complete first pool onboarding
  Future<void> completeFirstPool(String userId) async {
    await http.post(Uri.parse('$baseUrl/users/$userId/complete-first-pool'));
  }

  // Fetch pools with filter
  Future<Map<String, dynamic>> getPools({String? filter, String? userId}) async {
    String url = '$baseUrl/pools';
    List<String> queryParams = [];
    if (filter != null && filter.isNotEmpty) {
      queryParams.add('filter=$filter');
    }
    if (userId != null && userId.isNotEmpty) {
      queryParams.add('user_id=$userId');
    }
    if (queryParams.isNotEmpty) {
      url += '?${queryParams.join('&')}';
    }

    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final rawPools = json['pools'] as List? ?? [];
      final pools = rawPools.map((p) => Pool.fromJson(p)).toList();
      return {
        'total_count': json['total_count'] ?? 0,
        'open_count': json['open_count'] ?? 0,
        'pools': pools,
      };
    }
    throw Exception('Failed to load pools: ${res.body}');
  }

  // Create new pool
  Future<Pool> createPool({
    required String creatorId,
    required double depositAmount,
    required int maxPlayers,
    String? description,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/pools'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'creator_id': creatorId,
        'deposit_amount': depositAmount,
        'max_players': maxPlayers,
        'description': description,
      }),
    );
    if (res.statusCode == 201) {
      return Pool.fromJson(jsonDecode(res.body));
    }
    throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to create pool');
  }

  // Join pool (atomic)
  Future<Pool> joinPool({
    required String poolId,
    required String userId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/pools/$poolId/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (res.statusCode == 200) {
      return Pool.fromJson(jsonDecode(res.body));
    }
    throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to join pool');
  }

  // Get wallet details & ledger transactions
  Future<Map<String, dynamic>> getWallet(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/wallet/$userId'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return {
        'balance': UserBalance.fromJson(data['balance']),
        'transactions': data['transactions'] as List? ?? [],
      };
    }
    throw Exception('Failed to load wallet');
  }

  // Deposit test funds
  Future<void> depositFunds(String userId, double amount) async {
    final res = await http.post(
      Uri.parse('$baseUrl/wallet/$userId/deposit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'amount': amount}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Deposit failed');
    }
  }

  // Get admin overview
  Future<Map<String, dynamic>> getAdminOverview() async {
    final res = await http.get(Uri.parse('$baseUrl/admin/overview'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Failed to load admin overview');
  }
}

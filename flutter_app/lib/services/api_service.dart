import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/user.dart';
import '../models/pool.dart';

import 'web_storage.dart';
import 'supabase_config.dart';
import 'supabase_service.dart';

class ApiService {
  static bool isSecure = false;
  static String host = kIsWeb ? 'localhost:4000' : '192.168.1.134:4000';

  static final SupabaseService supabaseService = SupabaseService();
  static bool get isUsingSupabase => SupabaseService.isInitialized && SupabaseConfig.isConfigured;

  static String get httpScheme => isSecure ? 'https' : 'http';
  static String get wsScheme => isSecure ? 'wss' : 'ws';

  static String get baseUrl => '$httpScheme://$host/api';
  static String get wsUrl => '$wsScheme://$host/ws';
  static String get fullHostDisplay => isUsingSupabase
      ? 'Supabase (${SupabaseConfig.url.replaceFirst('https://', '')})'
      : '$httpScheme://$host';

  static Future<void> initHost() async {
    // 0. Check Supabase Configuration first (Cloud 24/7 priority)
    SupabaseConfig.initConfig();
    if (SupabaseConfig.isConfigured) {
      final ok = await SupabaseService.init();
      if (ok) {
        supabaseService.listenToRealtime();
        _subscribeToSupabaseEvents();
        return;
      }
    }

    // 1. Check URL query params (e.g. ?api=https://xyz.trycloudflare.com or ?server=...)
    try {
      if (kIsWeb) {
        final queryParams = Uri.base.queryParameters;
        final paramUrl = queryParams['api'] ?? queryParams['server'];
        if (paramUrl != null && paramUrl.trim().isNotEmpty) {
          final clean = paramUrl.trim();
          if (!clean.toUpperCase().contains('YOUR_') &&
              !clean.contains('example.com') &&
              !clean.contains('vercel.app')) {
            updateHost(clean);
            return;
          }
        }
      }
    } catch (_) {}

    // 2. Check local web storage
    final savedHost = readWebStorage('splitbet_host');
    if (savedHost != null && savedHost.trim().isNotEmpty) {
      final clean = savedHost.trim();
      if (!clean.toUpperCase().contains('YOUR_') &&
          !clean.contains('example.com') &&
          !clean.contains('vercel.app')) {
        updateHost(clean, persist: false);
        return;
      } else {
        resetToDefaultHost();
        return;
      }
    }

    // 3. Default behavior
    resetToDefaultHost();
  }

  static void resetToDefaultHost() {
    isSecure = false;
    host = kIsWeb ? 'localhost:4000' : '192.168.1.134:4000';
    writeWebStorage('splitbet_host', '');
  }

  static void updateHost(String newHost, {bool persist = true}) {
    String clean = newHost.trim();
    if (clean.isEmpty) return;

    if (clean.toUpperCase().contains('YOUR_') || clean.contains('vercel.app')) {
      resetToDefaultHost();
      return;
    }

    if (clean.startsWith('https://') || clean.startsWith('wss://')) {
      isSecure = true;
    } else if (clean.startsWith('http://') || clean.startsWith('ws://')) {
      isSecure = false;
    } else {
      if (clean.contains('.onrender.com') ||
          clean.contains('.ngrok') ||
          clean.contains('.loca.lt') ||
          clean.contains('.railway.app') ||
          clean.contains('.fly.dev') ||
          clean.contains('.trycloudflare.com') ||
          (kIsWeb &&
              Uri.base.scheme == 'https' &&
              !clean.startsWith('localhost') &&
              !clean.startsWith('127.0.0.1') &&
              !clean.startsWith('192.168.'))) {
        isSecure = true;
      } else {
        isSecure = false;
      }
    }

    clean = clean.replaceFirst(RegExp(r'^https?:\/\/'), '');
    clean = clean.replaceFirst(RegExp(r'^wss?:\/\/'), '');
    clean = clean.replaceAll('/api', '').replaceAll('/ws', '');
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.contains(':') && !clean.contains('.')) {
      clean = '$clean:4000';
    }
    host = clean;

    if (persist) {
      writeWebStorage('splitbet_host', '$httpScheme://$host');
    }
  }

  Future<bool> testConnection([String? testUrl, String? testKey]) async {
    if (testUrl != null && (testUrl.contains('.supabase.co') || testKey != null)) {
      return supabaseService.testConnection(testUrl, testKey);
    }
    if (isUsingSupabase && (testUrl == null || testUrl.isEmpty)) {
      return supabaseService.testConnection();
    }

    try {
      String targetUrl;
      if (testUrl != null && testUrl.trim().isNotEmpty) {
        String clean = testUrl.trim();
        if (clean.toUpperCase().contains('YOUR_') || clean.contains('vercel.app')) {
          return false;
        }
        final secure = clean.startsWith('https://') ||
            clean.startsWith('wss://') ||
            clean.contains('.onrender.com') ||
            clean.contains('.ngrok') ||
            clean.contains('.loca.lt') ||
            clean.contains('.railway.app') ||
            clean.contains('.fly.dev') ||
            clean.contains('.trycloudflare.com');
        final scheme = secure ? 'https' : 'http';
        clean = clean.replaceFirst(RegExp(r'^https?:\/\/'), '');
        clean = clean.replaceFirst(RegExp(r'^wss?:\/\/'), '');
        clean = clean.replaceAll('/api', '').replaceAll('/ws', '');
        if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
        if (!clean.contains(':') && !clean.contains('.')) clean = '$clean:4000';
        targetUrl = '$scheme://$clean/api/users';
      } else {
        targetUrl = '$baseUrl/users';
      }
      final res = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 4));
      final contentType = res.headers['content-type'] ?? '';
      if (contentType.contains('text/html') || res.body.trim().startsWith('<!DOCTYPE')) {
        return false;
      }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  WebSocketChannel? _wsChannel;
  static final StreamController<Map<String, dynamic>> _wsEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get wsEvents => _wsEventController.stream;

  static void _subscribeToSupabaseEvents() {
    supabaseService.events.listen((evt) {
      _wsEventController.add(evt);
    });
  }

  void connectWebSocket() {
    if (isUsingSupabase) {
      supabaseService.listenToRealtime();
      return;
    }

    try {
      _wsChannel?.sink.close();
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
          debugPrint('WebSocket closed, reconnecting in 5s...');
          _reconnectWebSocket();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    if (isUsingSupabase) return;
    Timer(const Duration(seconds: 5), () {
      connectWebSocket();
    });
  }

  void dispose() {
    _wsChannel?.sink.close();
  }

  dynamic _safeJsonDecode(http.Response res, {String fallbackMessage = 'Request failed'}) {
    final contentType = res.headers['content-type'] ?? '';
    if (contentType.contains('text/html') ||
        res.body.trim().startsWith('<!DOCTYPE') ||
        res.body.trim().startsWith('<html')) {
      throw Exception('Backend offline. Server returned HTML instead of API data.');
    }
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw Exception('$fallbackMessage (Status ${res.statusCode})');
    }
  }

  // Fetch all users
  Future<List<AppUser>> getUsers() async {
    if (isUsingSupabase) {
      return supabaseService.getUsers();
    }

    final res = await http
        .get(Uri.parse('$baseUrl/users'))
        .timeout(const Duration(seconds: 4));
    final data = _safeJsonDecode(res, fallbackMessage: 'Failed to load users');
    if (res.statusCode == 200 && data is List) {
      return data.map((u) => AppUser.fromJson(u)).toList();
    }
    throw Exception('Failed to load users: ${res.body}');
  }

  // Fetch single user with stats
  Future<AppUser> getUser(String userId) async {
    if (isUsingSupabase) {
      return supabaseService.getUser(userId);
    }

    final res = await http.get(Uri.parse('$baseUrl/users/$userId'));
    final data = _safeJsonDecode(res, fallbackMessage: 'Failed to load user');
    if (res.statusCode == 200 && data is Map<String, dynamic>) {
      return AppUser.fromJson(data);
    }
    throw Exception('Failed to load user: ${res.body}');
  }

  // Register new user
  Future<AppUser> registerUser({
    required String username,
    required String displayName,
    String? phone,
    String? email,
    String? avatarUrl,
  }) async {
    if (isUsingSupabase) {
      return supabaseService.registerUser(
        username: username,
        displayName: displayName,
        phone: phone,
        email: email,
        avatarUrl: avatarUrl,
      );
    }

    final res = await http.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'display_name': displayName,
        'phone': phone,
        'email': email,
        'avatar_url': avatarUrl,
      }),
    );
    final data = _safeJsonDecode(res, fallbackMessage: 'Registration failed');
    if (res.statusCode == 201 && data is Map<String, dynamic>) {
      return AppUser.fromJson(data);
    }
    final errorMsg = (data is Map && data['error'] != null) ? data['error'] : 'Registration failed';
    throw Exception(errorMsg);
  }

  // Update user avatar
  Future<AppUser> updateUserAvatar(String userId, String avatarUrl) async {
    if (isUsingSupabase) {
      return supabaseService.updateUserAvatar(userId, avatarUrl);
    }

    final res = await http.patch(
      Uri.parse('$baseUrl/users/$userId/avatar'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'avatar_url': avatarUrl}),
    );
    final data = _safeJsonDecode(res, fallbackMessage: 'Failed to update avatar');
    if (res.statusCode == 200 && data is Map<String, dynamic>) {
      return AppUser.fromJson(data);
    }
    final errorMsg = (data is Map && data['error'] != null) ? data['error'] : 'Failed to update avatar';
    throw Exception(errorMsg);
  }

  // Delete user
  Future<void> deleteUser(String userId) async {
    if (isUsingSupabase) {
      return supabaseService.deleteUser(userId);
    }

    final res = await http.delete(Uri.parse('$baseUrl/users/$userId'));
    if (res.statusCode != 200) {
      final data = _safeJsonDecode(res, fallbackMessage: 'Failed to delete user');
      final errorMsg = (data is Map && data['error'] != null) ? data['error'] : 'Failed to delete user';
      throw Exception(errorMsg);
    }
  }

  // Complete first pool onboarding
  Future<void> completeFirstPool(String userId) async {
    if (isUsingSupabase) {
      return supabaseService.completeFirstPool(userId);
    }
    await http.post(Uri.parse('$baseUrl/users/$userId/complete-first-pool'));
  }

  // Fetch pools with filter
  Future<Map<String, dynamic>> getPools({String? filter, String? userId}) async {
    if (isUsingSupabase) {
      return supabaseService.getPools(filter: filter, userId: userId);
    }

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

    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
    final json = _safeJsonDecode(res, fallbackMessage: 'Failed to load pools');
    if (res.statusCode == 200 && json is Map<String, dynamic>) {
      final rawPools = json['pools'] as List? ?? [];
      final pools = rawPools.map((p) => Pool.fromJson(p)).toList();
      return {
        'total_count': json['total_count'] ?? 0,
        'open_count': json['open_count'] ?? 0,
        'pools': pools,
      };
    }
    throw Exception('Failed to load pools');
  }

  // Create new pool
  Future<Pool> createPool({
    required String creatorId,
    required double depositAmount,
    required int maxPlayers,
    String? description,
  }) async {
    if (isUsingSupabase) {
      return supabaseService.createPool(
        creatorId: creatorId,
        depositAmount: depositAmount,
        maxPlayers: maxPlayers,
        description: description,
      );
    }

    final res = await http.post(
      Uri.parse('$baseUrl/pools'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'creator_id': creatorId,
        'deposit_amount': depositAmount,
        'max_players': maxPlayers,
        'description': description,
      }),
    ).timeout(const Duration(seconds: 5));
    final data = _safeJsonDecode(res, fallbackMessage: 'Failed to create pool');
    if (res.statusCode == 201 && data is Map<String, dynamic>) {
      return Pool.fromJson(data);
    }
    final errorMsg = (data is Map && data['error'] != null) ? data['error'] : 'Failed to create pool';
    throw Exception(errorMsg);
  }

  // Join pool (atomic)
  Future<Pool> joinPool({
    required String poolId,
    required String userId,
  }) async {
    if (isUsingSupabase) {
      return supabaseService.joinPool(poolId: poolId, userId: userId);
    }

    final res = await http.post(
      Uri.parse('$baseUrl/pools/$poolId/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    ).timeout(const Duration(seconds: 5));
    final data = _safeJsonDecode(res, fallbackMessage: 'Failed to join pool');
    if (res.statusCode == 200 && data is Map<String, dynamic>) {
      return Pool.fromJson(data);
    }
    final errorMsg = (data is Map && data['error'] != null) ? data['error'] : 'Failed to join pool';
    throw Exception(errorMsg);
  }

  // Get wallet details & ledger transactions
  Future<Map<String, dynamic>> getWallet(String userId) async {
    if (isUsingSupabase) {
      return supabaseService.getWallet(userId);
    }

    final res = await http.get(Uri.parse('$baseUrl/wallet/$userId')).timeout(const Duration(seconds: 4));
    final data = _safeJsonDecode(res, fallbackMessage: 'Failed to load wallet');
    if (res.statusCode == 200 && data is Map<String, dynamic>) {
      return {
        'balance': UserBalance.fromJson(data['balance']),
        'transactions': data['transactions'] as List? ?? [],
      };
    }
    throw Exception('Failed to load wallet');
  }

  // Deposit test funds
  Future<void> depositFunds(String userId, double amount) async {
    if (isUsingSupabase) {
      return supabaseService.depositFunds(userId, amount);
    }

    final res = await http.post(
      Uri.parse('$baseUrl/wallet/$userId/deposit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'amount': amount}),
    ).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      final data = _safeJsonDecode(res, fallbackMessage: 'Deposit failed');
      final errorMsg = (data is Map && data['error'] != null) ? data['error'] : 'Deposit failed';
      throw Exception(errorMsg);
    }
  }

  // Get admin overview
  Future<Map<String, dynamic>> getAdminOverview() async {
    if (isUsingSupabase) {
      return supabaseService.getAdminOverview();
    }

    try {
      final res = await http.get(Uri.parse('$baseUrl/admin/overview')).timeout(const Duration(seconds: 4));
      final data = _safeJsonDecode(res, fallbackMessage: 'Failed to load admin overview');
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {
      // Fallback for offline demo mode or when server is temporarily unreachable
    }

    final mock = Pool.mockPools();
    final settled = mock.where((p) => p.status == 'SETTLED').toList();
    final active = mock.where((p) => p.status == 'OPEN' || p.status == 'FULL' || p.status == 'LOCKED').toList();
    final rev = settled.fold<double>(0.0, (acc, p) => acc + p.platformFeeAmount);
    final vol = settled.fold<double>(0.0, (acc, p) => acc + p.grossPool);

    return {
      'metrics': {
        'total_users': 5,
        'total_pools': mock.length,
        'active_pools': active.length,
        'settled_pools': settled.length,
        'platform_revenue_zar': rev,
        'gross_volume_zar': vol,
      },
      'audit_logs': [
        {
          'action': 'POOL_SETTLED',
          'details': 'Winner: usr_sarah, Payout: R288.00',
          'actor': 'SYSTEM',
          'entity': 'pools',
          'timestamp': DateTime.now().subtract(const Duration(minutes: 4)).toIso8601String(),
        },
        {
          'action': 'JOIN_POOL',
          'details': 'Joined slot 2/2',
          'actor': 'usr_sarah',
          'entity': 'pools',
          'timestamp': DateTime.now().subtract(const Duration(minutes: 6)).toIso8601String(),
        },
        {
          'action': 'CREATE_POOL',
          'details': 'Created 1v1 pool deposit R155',
          'actor': 'usr_sarah',
          'entity': 'pools',
          'timestamp': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
        },
      ],
    };
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user.dart';
import '../models/pool.dart';
import '../services/api_service.dart';
import '../services/supabase_config.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wallet_card.dart';
import '../widgets/pool_card.dart';
import '../widgets/winner_dialog.dart';
import '../widgets/user_avatar.dart';
import '../services/camera_service.dart';
import 'create_pool_sheet.dart';
import 'profile_sheet.dart';
import 'admin_dialog.dart';
import 'first_pool_onboarding.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;

  const HomeScreen({super.key, required this.apiService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AppUser> _allUsers = [AppUser.mockUser()];
  AppUser _currentUser = AppUser.mockUser();
  List<Pool> _pools = [];
  int _openCount = 0;
  bool _isLoading = true;
  bool _isServerConnected = false;
  String _selectedFilter =
      'all'; // 'all', '1v1', '3-4', '5-8', 'my_pools', 'settled'

  @override
  void initState() {
    super.initState();
    _initApp();
    _listenToWebSocket();
  }

  Future<void> _initApp() async {
    try {
      final users = await widget.apiService.getUsers();
      if (users.isNotEmpty && mounted) {
        final initialUser = users.firstWhere(
          (u) => u.username == 'deric',
          orElse: () => users.first,
        );
        setState(() {
          _allUsers = users;
          _currentUser = initialUser;
          _isServerConnected = true;
        });
        _refreshCurrentUser();
        await _loadPools();
      }
    } catch (e) {
      debugPrint('Init app error: $e');
      if (mounted) {
        setState(() {
          _isServerConnected = false;
          _allUsers = [AppUser.mockUser()];
          _currentUser = AppUser.mockUser();
          if (_pools.isEmpty) {
            _pools = Pool.mockPools();
            _openCount = _pools.where((p) => p.status == 'OPEN').length;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToWebSocket() {
    widget.apiService.wsEvents.listen((event) {
      final type = event['type'];
      if (!mounted) return;

      if (type == 'POOL_CREATED' || type == 'POOL_UPDATE') {
        _loadPools(showSpinner: false);
      } else if (type == 'WALLET_UPDATE') {
        if (event['userId'] == _currentUser.id) {
          _refreshCurrentUser();
        }
      } else if (type == 'POOL_SETTLED') {
        _loadPools(showSpinner: false);
        _refreshCurrentUser();

        // If current user is involved or viewing, show celebration
        final winner = event['winner'];
        final netPayout = (event['net_payout'] as num?)?.toDouble() ?? 0.0;
        final poolId = event['poolId'] ?? '';
        final proof = event['proof'] as Map<String, dynamic>?;

        final isUserWinner = winner != null && winner['id'] == _currentUser.id;

        // Check if current user was a participant in the settled pool
        final poolData = event['pool'] as Map<String, dynamic>?;
        bool isParticipant = false;
        if (poolData != null && poolData['participants'] is List) {
          final participants = poolData['participants'] as List;
          isParticipant = participants.any((p) => (p is Map && p['user_id'] == _currentUser.id));
        } else {
          // Fallback: search existing pools list
          final matchingPool = _pools.where((p) => p.id == poolId).firstOrNull;
          if (matchingPool != null) {
            isParticipant = matchingPool.participants.any((p) => p.userId == _currentUser.id);
          }
        }

        final hasUserLost = isParticipant && !isUserWinner;

        showDialog(
          context: context,
          builder: (ctx) => WinnerCelebrationDialog(
            poolId: poolId,
            winnerName: winner?['display_name'] ?? 'Winner',
            winnerAvatar:
                winner?['avatar_url'] ??
                'https://api.dicebear.com/7.x/bottts/png?seed=winner',
            netPayout: netPayout,
            proof: proof,
            isCurrentUserWinner: isUserWinner,
            hasUserLost: hasUserLost,
          ),
        );
      }
    });
  }

  Future<void> _loadPools({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getPools(
        filter: _selectedFilter == 'all' ? null : _selectedFilter,
        userId: _currentUser.id,
      );
      if (mounted) {
        setState(() {
          _pools = res['pools'] as List<Pool>;
          _openCount = res['open_count'] ?? 0;
          _isLoading = false;
          _isServerConnected = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!_isServerConnected && _pools.isEmpty) {
            _pools = Pool.mockPools();
            _openCount = _pools.where((p) => p.status == 'OPEN').length;
          }
        });
      }
    }
  }

  Future<void> _refreshCurrentUser() async {
    try {
      final updated = await widget.apiService.getUser(_currentUser.id);
      if (mounted) {
        setState(() {
          _currentUser = updated;
          _isServerConnected = true;
        });
      }
    } catch (e) {
      debugPrint('Refresh user error: $e');
    }
  }

  void _switchUser(AppUser user) async {
    setState(() {
      _currentUser = user;
    });
    await _refreshCurrentUser();
    await _loadPools();
  }

  Future<void> _handleJoinPool(Pool pool) async {
    if (_currentUser.balance.available < pool.depositAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Insufficient funds. You have R${_currentUser.balance.available.toStringAsFixed(0)}, pool requires R${pool.depositAmount.toStringAsFixed(0)}. Please top-up via your Wallet.',
          ),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    // Join confirmation bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm Pool Entry',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You are joining with ${pool.maxPlayers} players. Each participant has an equal ${pool.oddsToWin} chance to win R${pool.netPayout.toStringAsFixed(0)}.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Required Deposit',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  Text(
                    'R ${pool.depositAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppTheme.electricLime,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (_isServerConnected) {
                    try {
                      await widget.apiService.joinPool(
                        poolId: pool.id,
                        userId: _currentUser.id,
                      );
                      await _refreshCurrentUser();
                      await _loadPools(showSpinner: false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Successfully joined pool! Deposit of R${pool.depositAmount.toStringAsFixed(0)} reserved.',
                            ),
                            backgroundColor: AppTheme.surfaceElevated,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to join: $e'),
                            backgroundColor: AppTheme.error,
                          ),
                        );
                      }
                    }
                  } else {
                    // Offline Demo Mode: simulate joining locally
                    setState(() {
                      final newAvail =
                          (_currentUser.balance.available - pool.depositAmount)
                              .clamp(0, double.infinity);
                      final newRes =
                          _currentUser.balance.reserved + pool.depositAmount;
                      final currentStats = _currentUser.stats;
                      final updatedStats = currentStats != null
                          ? UserStats(
                              activePools: currentStats.activePools + 1,
                              completedPools: currentStats.completedPools,
                              wins: currentStats.wins,
                              losses: currentStats.losses,
                              winRate: currentStats.winRate,
                              totalWon: currentStats.totalWon,
                            )
                          : UserStats(
                              activePools: 1,
                              completedPools: 0,
                              wins: 0,
                              losses: 0,
                              winRate: '0.0%',
                              totalWon: 0.0,
                            );
                      _currentUser = _currentUser.copyWith(
                        balance: _currentUser.balance.copyWith(
                          available: newAvail.toDouble(),
                          reserved: newRes.toDouble(),
                        ),
                        stats: updatedStats,
                      );
                      pool.participants.add(
                        PoolParticipant(
                          userId: _currentUser.id,
                          username: _currentUser.username,
                          displayName: _currentUser.displayName,
                          avatarUrl: _currentUser.avatarUrl,
                          deposit: pool.depositAmount,
                          payout: 0.0,
                          isWinner: false,
                          joinedAt: DateTime.now().toIso8601String(),
                        ),
                      );
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Joined pool in Demo Mode! R${pool.depositAmount.toStringAsFixed(0)} reserved.',
                          ),
                          backgroundColor: AppTheme.surfaceElevated,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.electricLime,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Confirm & Reserve Deposit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _openCreatePoolSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreatePoolSheet(
        currentUser: _currentUser,
        apiService: widget.apiService,
        onPoolCreated: () {
          _refreshCurrentUser();
          _loadPools();
        },
      ),
    );
  }

  void _openProfile() {
    _refreshCurrentUser();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProfileSheet(
        user: _currentUser,
        apiService: widget.apiService,
        onLogout: () {},
        onUserUpdated: (updated) {
          setState(() {
            _currentUser = updated;
            _allUsers = _allUsers.map((u) => u.id == updated.id ? updated : u).toList();
          });
        },
      ),
    );
  }

  void _openAdminDashboard() {
    showDialog(
      context: context,
      builder: (ctx) => AdminDashboardDialog(apiService: widget.apiService),
    );
  }

  void _showServerConfigDialog() {
    int selectedTab = ApiService.isUsingSupabase ? 0 : 1;
    final sbUrlCtrl = TextEditingController(text: SupabaseConfig.url);
    final sbKeyCtrl = TextEditingController(text: SupabaseConfig.anonKey);
    final ipCtrl = TextEditingController(text: ApiService.fullHostDisplay);
    String? testStatus; // 'testing', 'success', 'failed'
    String testMsg = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_sync_outlined, color: AppTheme.electricLime),
              SizedBox(width: 10),
              Text(
                'Backend Settings',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mode Selector: Supabase 24/7 vs Node Server
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() {
                            selectedTab = 0;
                            testStatus = null;
                          }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedTab == 0 ? AppTheme.electricLime.withValues(alpha: 0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedTab == 0 ? AppTheme.electricLime : Colors.transparent,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bolt, size: 16, color: selectedTab == 0 ? AppTheme.electricLime : AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  'Supabase 24/7',
                                  style: TextStyle(
                                    color: selectedTab == 0 ? AppTheme.textPrimary : AppTheme.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() {
                            selectedTab = 1;
                            testStatus = null;
                          }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selectedTab == 1 ? AppTheme.electricLime.withValues(alpha: 0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedTab == 1 ? AppTheme.electricLime : Colors.transparent,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.dns_outlined, size: 16, color: selectedTab == 1 ? AppTheme.electricLime : AppTheme.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  'Node.js / Tunnel',
                                  style: TextStyle(
                                    color: selectedTab == 1 ? AppTheme.textPrimary : AppTheme.textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (selectedTab == 0) ...[
                  const Text('Supabase Project URL:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: sbUrlCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://xyzcompany.supabase.co',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.surfaceElevated,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Supabase Anon / Public Key:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: sbKeyCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.surfaceElevated,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '💡 Run `server/supabase_schema.sql` in your Supabase SQL Editor once to initialize all tables and logic.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ] else ...[
                  const Text('Node.js Server / Tunnel URL:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: ipCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://xxx.trycloudflare.com or 192.168.1.134:4000',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.surfaceElevated,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '💡 Run `server/start-live.bat` on your PC to start local server & tunnel.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],

                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: testStatus == 'testing'
                          ? null
                          : () async {
                              setDialogState(() {
                                testStatus = 'testing';
                                testMsg = '';
                              });
                              bool ok = false;
                              if (selectedTab == 0) {
                                ok = await widget.apiService.testConnection(
                                  sbUrlCtrl.text.trim(),
                                  sbKeyCtrl.text.trim(),
                                );
                              } else {
                                ok = await widget.apiService.testConnection(ipCtrl.text.trim());
                              }
                              setDialogState(() {
                                testStatus = ok ? 'success' : 'failed';
                                testMsg = ok ? 'Connection successful!' : 'Could not reach server';
                              });
                            },
                      icon: testStatus == 'testing'
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.electricLime))
                          : Icon(
                              testStatus == 'success'
                                  ? Icons.check_circle
                                  : testStatus == 'failed'
                                      ? Icons.error_outline
                                      : Icons.network_check,
                              size: 16,
                              color: testStatus == 'success'
                                  ? AppTheme.success
                                  : testStatus == 'failed'
                                      ? AppTheme.error
                                      : AppTheme.textSecondary,
                            ),
                      label: Text(
                        testStatus == 'testing'
                            ? 'Testing...'
                            : testStatus == 'success'
                                ? 'Online!'
                                : testStatus == 'failed'
                                    ? 'Unreachable'
                                    : 'Test Connection',
                        style: TextStyle(
                          fontSize: 12,
                          color: testStatus == 'success'
                              ? AppTheme.success
                              : testStatus == 'failed'
                                  ? AppTheme.error
                                  : AppTheme.textSecondary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: testStatus == 'success'
                              ? AppTheme.success
                              : testStatus == 'failed'
                                  ? AppTheme.error
                                  : AppTheme.border,
                        ),
                      ),
                    ),
                    if (testMsg.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          testMsg,
                          style: TextStyle(
                            fontSize: 11,
                            color: testStatus == 'success' ? AppTheme.success : AppTheme.error,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                SupabaseConfig.resetToDefaultConfig();
                await SupabaseService.init();
                widget.apiService.connectWebSocket();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() => _isLoading = true);
                  await _initApp();
                }
              },
              child: const Text('Default 24/7 Cloud', style: TextStyle(color: AppTheme.electricLime)),
            ),
            TextButton(
              onPressed: () async {
                SupabaseConfig.clearConfig();
                ApiService.resetToDefaultHost();
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                await _initApp();
              },
              child: const Text('Reset to Demo', style: TextStyle(color: Colors.amber)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedTab == 0) {
                  final url = sbUrlCtrl.text.trim();
                  final key = sbKeyCtrl.text.trim();
                  if (url.isNotEmpty && key.isNotEmpty) {
                    SupabaseConfig.saveConfig(url, key);
                    await SupabaseService.init();
                    widget.apiService.connectWebSocket();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      setState(() => _isLoading = true);
                      await _initApp();
                    }
                  }
                } else {
                  final newHost = ipCtrl.text.trim();
                  if (newHost.isNotEmpty) {
                    SupabaseConfig.clearConfig();
                    ApiService.updateHost(newHost);
                    widget.apiService.connectWebSocket();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      setState(() => _isLoading = true);
                      await _initApp();
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.electricLime,
                foregroundColor: Colors.black,
              ),
              child: const Text('Save & Connect'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewUserDialog() {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    String? capturedAvatar;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final bool hasValidPhoto = capturedAvatar != null && capturedAvatar!.isNotEmpty;
          final bool canCreate = hasValidPhoto &&
              nameCtrl.text.trim().isNotEmpty &&
              userCtrl.text.trim().isNotEmpty &&
              !isSubmitting;

          return AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text(
              'Register New User',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Camera Profile Photo Section (Mandatory requirement!)
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final picked = await CameraService.showPhotoSourceSheet(
                              ctx,
                              title: 'Take Profile Picture',
                            );
                            if (picked != null) {
                              setDialogState(() => capturedAvatar = picked);
                            }
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: hasValidPhoto
                                        ? AppTheme.electricLime
                                        : AppTheme.border,
                                    width: hasValidPhoto ? 2.5 : 1.5,
                                  ),
                                  color: AppTheme.surfaceLight,
                                ),
                                child: ClipOval(
                                  child: hasValidPhoto
                                      ? UserAvatar(
                                          avatarUrl: capturedAvatar,
                                          radius: 44,
                                        )
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: const [
                                            Icon(
                                              Icons.camera_alt,
                                              size: 32,
                                              color: AppTheme.electricLime,
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Photo *',
                                              style: TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: hasValidPhoto ? AppTheme.electricLime : AppTheme.surfaceElevated,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppTheme.surface, width: 2),
                                  ),
                                  child: Icon(
                                    hasValidPhoto ? Icons.check : Icons.add_a_photo,
                                    size: 14,
                                    color: hasValidPhoto ? Colors.black : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await CameraService.showPhotoSourceSheet(
                              ctx,
                              title: 'Take Profile Picture',
                            );
                            if (picked != null) {
                              setDialogState(() => capturedAvatar = picked);
                            }
                          },
                          icon: Icon(
                            hasValidPhoto ? Icons.refresh : Icons.camera_alt,
                            size: 15,
                            color: AppTheme.electricLime,
                          ),
                          label: Text(
                            hasValidPhoto ? 'Retake Photo' : 'Take Photo (Required)',
                            style: const TextStyle(
                              color: AppTheme.electricLime,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!hasValidPhoto)
                          const Text(
                            '* Camera photo required to create account',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      hintText: 'e.g. Lerato Khumalo',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.textSecondary, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.electricLime),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'e.g. lerato_k',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      labelStyle: const TextStyle(color: AppTheme.textSecondary),
                      prefixIcon: const Icon(Icons.alternate_email, color: AppTheme.textSecondary, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.electricLime),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: canCreate
                    ? () async {
                        setDialogState(() => isSubmitting = true);
                        final nav = Navigator.of(ctx);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          AppUser newUser;
                          if (_isServerConnected) {
                            try {
                              newUser = await widget.apiService.registerUser(
                                username: userCtrl.text.trim(),
                                displayName: nameCtrl.text.trim(),
                                avatarUrl: capturedAvatar,
                              );
                              final updatedUsers = await widget.apiService.getUsers();
                              if (mounted) setState(() => _allUsers = updatedUsers);
                            } catch (e) {
                              newUser = AppUser.createDemoUser(
                                username: userCtrl.text.trim(),
                                displayName: nameCtrl.text.trim(),
                                avatarUrl: capturedAvatar,
                              );
                              if (mounted) {
                                setState(() {
                                  _allUsers = [..._allUsers, newUser];
                                });
                              }
                            }
                          } else {
                            newUser = AppUser.createDemoUser(
                              username: userCtrl.text.trim(),
                              displayName: nameCtrl.text.trim(),
                              avatarUrl: capturedAvatar,
                            );
                            if (mounted) {
                              setState(() {
                                _allUsers = [..._allUsers, newUser];
                              });
                            }
                          }

                          nav.pop();
                          if (!mounted) return;
                          setState(() => _currentUser = newUser);

                          // Launch First Pool Onboarding if required
                          if (!newUser.firstPoolCreated && mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => FirstPoolOnboardingScreen(
                                  user: newUser,
                                  apiService: widget.apiService,
                                  onCompleted: () {
                                    Navigator.pop(c);
                                    if (_isServerConnected) {
                                      _refreshCurrentUser();
                                      _loadPools();
                                    } else {
                                      setState(() {
                                        _currentUser = _currentUser.copyWith(
                                          firstPoolCreated: true,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Registration error: $e'),
                              backgroundColor: AppTheme.error,
                            ),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.electricLime,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: AppTheme.surfaceLight,
                  disabledForegroundColor: AppTheme.textMuted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Create User', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // Confirm delete user popup on long press
  void _confirmDeleteUser(AppUser userToDelete) {
    if (_allUsers.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete account: At least one user account must remain.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 26),
            SizedBox(width: 8),
            Text('Delete Account?', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              avatarUrl: userToDelete.avatarUrl,
              radius: 36,
              displayName: userToDelete.displayName,
              showBorder: true,
              borderColor: AppTheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              userToDelete.displayName,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              '@${userToDelete.username}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              'Are you sure you want to delete this user account?\n\nThis will remove @${userToDelete.username}, their wallet balance, and pool entries. This action cannot be undone.',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (_isServerConnected) {
                  try {
                    await widget.apiService.deleteUser(userToDelete.id);
                  } catch (_) {}
                }

                if (!mounted) return;
                final remaining = _allUsers.where((u) => u.id != userToDelete.id).toList();

                setState(() {
                  _allUsers = remaining;
                  if (_currentUser.id == userToDelete.id) {
                    _currentUser = remaining.first;
                  }
                });

                await _refreshCurrentUser();
                await _loadPools();

                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Account @${userToDelete.username} deleted successfully.'),
                    backgroundColor: AppTheme.surfaceElevated,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete user: $e'),
                    backgroundColor: AppTheme.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top App Bar matching screenshot
            _buildTopHeader(),

            // Demo User Quick Switcher Bar
            _buildDemoUserSwitcher(),

            // Offline / Demo Warning Banner
            if (!_isServerConnected)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Demo Mode • Backend offline (${ApiService.fullHostDisplay})',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _showServerConfigDialog,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          'Connect Backend',
                          style: TextStyle(
                            color: AppTheme.electricLime,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Main Scrollable Area
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _refreshCurrentUser();
                  await _loadPools(showSpinner: false);
                },
                color: AppTheme.electricLime,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 90),
                  children: [
                    const SizedBox(height: 12),

                    // Prominent Wallet Card matching screenshot
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: WalletCard(
                        balance: _currentUser.balance,
                        apiService: widget.apiService,
                        onRefresh: () {
                          _refreshCurrentUser();
                          _loadPools(showSpinner: false);
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Sub-Bar: Open Bets Count, Friends +, and Filter v
                    _buildSubHeader(),
                    const SizedBox(height: 8),

                    // Pool Feed in ListView
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                            color: AppTheme.electricLime,
                          ),
                        ),
                      )
                    else if (_pools.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(
                                Icons.sports_esports_outlined,
                                size: 48,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No open pools matching filter',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _openCreatePoolSheet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.electricLime,
                                  foregroundColor: Colors.black,
                                ),
                                child: const Text('Create the First Pool'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._pools.map(
                        (pool) => PoolCard(
                          key: ValueKey(pool.id),
                          pool: pool,
                          currentUser: _currentUser,
                          onJoinPool: _handleJoinPool,
                          onWhatsAppShare: () {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // Floating Action Buttons: Create Pool & Admin Toggle
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Admin Inspector Button
          FloatingActionButton.small(
            heroTag: 'admin_btn',
            backgroundColor: AppTheme.surfaceElevated,
            foregroundColor: AppTheme.electricLime,
            onPressed: _openAdminDashboard,
            child: const Icon(Icons.shield_outlined),
          ),
          const SizedBox(width: 12),
          // Main Create Pool FAB
          FloatingActionButton.extended(
            heroTag: 'create_pool_btn',
            backgroundColor: AppTheme.electricLime,
            foregroundColor: Colors.black,
            elevation: 8,
            onPressed: _openCreatePoolSheet,
            icon: const Icon(Icons.add, fontWeight: FontWeight.w900),
            label: const Text(
              'Create Pool',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // Top Header: SplitBet Logo on left, Hello [Name] / Good Day! + Avatar on right
  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Brand Logo: SplitBet with status indicator
          Row(
            children: [
              const Text(
                'Split',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Text(
                'Bet',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _showServerConfigDialog,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (ApiService.isUsingSupabase || _isServerConnected)
                        ? AppTheme.electricLime.withValues(alpha: 0.15)
                        : Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (ApiService.isUsingSupabase || _isServerConnected)
                          ? AppTheme.electricLime
                          : Colors.amber,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: (ApiService.isUsingSupabase || _isServerConnected)
                            ? AppTheme.electricLime
                            : Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ApiService.isUsingSupabase
                            ? 'Supabase 24/7'
                            : (_isServerConnected ? 'Live' : 'Demo'),
                        style: TextStyle(
                          color: (ApiService.isUsingSupabase || _isServerConnected)
                              ? AppTheme.electricLime
                              : Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // User info: Hello Deric • Good Day! + Avatar
          InkWell(
            onTap: _openProfile,
            borderRadius: BorderRadius.circular(16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Hello ${_currentUser.displayName}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Text(
                      'Good Day!',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                UserAvatar(
                  avatarUrl: _currentUser.avatarUrl,
                  radius: 22,
                  displayName: _currentUser.displayName,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Multi-User Quick Switcher Bar (For Seamless Multi-Account Testing & Management)
  Widget _buildDemoUserSwitcher() {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            child: const Text(
              'Switch Account:',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._allUsers.map((u) {
            final isCurrent = _currentUser.id == u.id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: isCurrent
                    ? 'Active account (Hold to delete)'
                    : 'Tap to switch • Hold to delete',
                child: Material(
                  color: isCurrent ? AppTheme.electricLime : AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _switchUser(u),
                    onLongPress: () => _confirmDeleteUser(u),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isCurrent ? AppTheme.electricLime : AppTheme.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UserAvatar(
                            avatarUrl: u.avatarUrl,
                            radius: 9,
                            displayName: u.displayName,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            u.displayName.split(' ')[0],
                            style: TextStyle(
                              color: isCurrent ? Colors.black : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          ActionChip(
            label: const Text('+ New User'),
            backgroundColor: AppTheme.surfaceElevated,
            labelStyle: const TextStyle(
              color: AppTheme.electricLime,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            onPressed: _showNewUserDialog,
          ),
        ],
      ),
    );
  }

  // Sub-Header: Friends +, Open Bets count, and Filter dropdown
  Widget _buildSubHeader() {
    // Aligns exactly with the text inside PoolCard (16 card margin + 20 card padding = 36)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          // Friends + row on top right matching screenshot
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () {
                  Clipboard.setData(
                    const ClipboardData(
                      text: 'https://splitbet.co.za/invite?ref=deric',
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invite link copied! Send to friends to play 1v1.',
                      ),
                      backgroundColor: AppTheme.surfaceElevated,
                    ),
                  );
                },
                child: const Text(
                  'Friends +',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 46 Open Bets & Filter v
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Open Bets Count
              Text(
                '$_openCount ${_openCount == 1 ? "Open Bet" : "Open Bets"}',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),

              // Filter Dropdown with green chevron
              PopupMenuButton<String>(
                onSelected: (val) {
                  setState(() => _selectedFilter = val);
                  _loadPools();
                },
                color: AppTheme.surfaceElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppTheme.border),
                ),
                itemBuilder: (ctx) => [
                  _buildPopupItem('all', 'All Pools'),
                  _buildPopupItem('1v1', '1v1 Showdowns (50% Odds)'),
                  _buildPopupItem('3-4', '3–4 Players'),
                  _buildPopupItem('5-8', '5–8 Players'),
                  _buildPopupItem('my_pools', 'My Joined Pools'),
                  _buildPopupItem('settled', 'Completed / Settled History'),
                ],
                child: Row(
                  children: [
                    Text(
                      _getFilterLabel(_selectedFilter),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppTheme.electricLime,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, String text) {
    final isSel = _selectedFilter == value;
    return PopupMenuItem<String>(
      value: value,
      child: Text(
        text,
        style: TextStyle(
          color: isSel ? AppTheme.electricLime : AppTheme.textPrimary,
          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  String _getFilterLabel(String filter) {
    switch (filter) {
      case '1v1':
        return '1v1 Filter';
      case '3-4':
        return '3-4 Players';
      case '5-8':
        return '5-8 Players';
      case 'my_pools':
        return 'My Pools';
      case 'settled':
        return 'History';
      default:
        return 'Filter';
    }
  }
}

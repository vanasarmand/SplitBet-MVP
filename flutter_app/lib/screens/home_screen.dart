import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user.dart';
import '../models/pool.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wallet_card.dart';
import '../widgets/pool_card.dart';
import '../widgets/winner_dialog.dart';
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
  List<AppUser> _allUsers = [];
  AppUser? _currentUser;
  List<Pool> _pools = [];
  int _openCount = 0;
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all', '1v1', '3-4', '5-8', 'my_pools', 'settled'

  @override
  void initState() {
    super.initState();
    _initApp();
    _listenToWebSocket();
  }

  Future<void> _initApp() async {
    try {
      final users = await widget.apiService.getUsers();
      setState(() {
        _allUsers = users;
        _currentUser = users.firstWhere((u) => u.username == 'deric', orElse: () => users.first);
      });
      await _loadPools();
    } catch (e) {
      debugPrint('Init app error: $e');
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
        if (_currentUser != null && event['userId'] == _currentUser!.id) {
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

        final isUserWinner = _currentUser != null && winner != null && winner['id'] == _currentUser!.id;

        showDialog(
          context: context,
          builder: (ctx) => WinnerCelebrationDialog(
            poolId: poolId,
            winnerName: winner?['display_name'] ?? 'Winner',
            winnerAvatar: winner?['avatar_url'] ?? 'https://api.dicebear.com/7.x/bottts/png?seed=winner',
            netPayout: netPayout,
            proof: proof,
            isCurrentUserWinner: isUserWinner,
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
        userId: _currentUser?.id,
      );
      if (mounted) {
        setState(() {
          _pools = res['pools'] as List<Pool>;
          _openCount = res['open_count'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final updated = await widget.apiService.getUser(_currentUser!.id);
      if (mounted) {
        setState(() {
          _currentUser = updated;
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
    if (_currentUser == null) return;

    if (_currentUser!.balance.available < pool.depositAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient funds. You have R${_currentUser!.balance.available.toStringAsFixed(0)}, pool requires R${pool.depositAmount.toStringAsFixed(0)}. Please top-up via your Wallet.'),
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
            const Text('Confirm Pool Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(
              'You are joining with ${pool.maxPlayers} players. Each participant has an equal ${pool.oddsToWin} chance to win R${pool.netPayout.toStringAsFixed(0)}.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
                  const Text('Required Deposit', style: TextStyle(color: AppTheme.textSecondary)),
                  Text('R ${pool.depositAmount.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.electricLime, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await widget.apiService.joinPool(poolId: pool.id, userId: _currentUser!.id);
                    await _refreshCurrentUser();
                    await _loadPools(showSpinner: false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Successfully joined pool! Deposit of R${pool.depositAmount.toStringAsFixed(0)} reserved.'),
                          backgroundColor: AppTheme.surfaceElevated,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to join: $e'), backgroundColor: AppTheme.error),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.electricLime,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Confirm & Reserve Deposit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _openCreatePoolSheet() {
    if (_currentUser == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreatePoolSheet(
        currentUser: _currentUser!,
        apiService: widget.apiService,
        onPoolCreated: () {
          _refreshCurrentUser();
          _loadPools();
        },
      ),
    );
  }

  void _openProfile() {
    if (_currentUser == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProfileSheet(
        user: _currentUser!,
        onLogout: () {},
      ),
    );
  }

  void _openAdminDashboard() {
    showDialog(
      context: context,
      builder: (ctx) => AdminDashboardDialog(apiService: widget.apiService),
    );
  }

  void _showNewUserDialog() {
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Register New User', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Full Name', labelStyle: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextField(
              controller: userCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Username', labelStyle: TextStyle(color: AppTheme.textSecondary)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || userCtrl.text.isEmpty) return;
              final nav = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              try {
                final newUser = await widget.apiService.registerUser(username: userCtrl.text.trim(), displayName: nameCtrl.text.trim());
                nav.pop();
                final updatedUsers = await widget.apiService.getUsers();
                if (!mounted) return;
                setState(() {
                  _allUsers = updatedUsers;
                  _currentUser = newUser;
                });
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
                          _refreshCurrentUser();
                          _loadPools();
                        },
                      ),
                    ),
                  );
                }
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.electricLime, foregroundColor: Colors.black),
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null && _isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.electricLime)),
      );
    }

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
                        balance: _currentUser!.balance,
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
                          child: CircularProgressIndicator(color: AppTheme.electricLime),
                        ),
                      )
                    else if (_pools.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.sports_esports_outlined, size: 48, color: AppTheme.textMuted),
                              const SizedBox(height: 12),
                              const Text('No open pools matching filter', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
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
                      ..._pools.map((pool) => PoolCard(
                            key: ValueKey(pool.id),
                            pool: pool,
                            currentUser: _currentUser!,
                            onJoinPool: _handleJoinPool,
                            onWhatsAppShare: () {},
                          )),
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
            label: const Text('Create Pool', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
          // Brand Logo: SplitBet
          const Row(
            children: [
              Text(
                'Split',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Bet',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
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
                      'Hello ${_currentUser?.displayName ?? ''}',
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.surfaceLight,
                  backgroundImage: NetworkImage(_currentUser?.avatarUrl ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Multi-User Quick Switcher Bar (For Seamless Multi-Account Testing!)
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
            child: const Text('Switch Account:', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          ..._allUsers.map((u) {
            final isCurrent = _currentUser?.id == u.id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(u.displayName.split(' ')[0]),
                selected: isCurrent,
                selectedColor: AppTheme.electricLime,
                backgroundColor: AppTheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                labelStyle: TextStyle(
                  color: isCurrent ? Colors.black : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (sel) {
                  if (sel) _switchUser(u);
                },
              ),
            );
          }),
          ActionChip(
            label: const Text('+ New User'),
            backgroundColor: AppTheme.surfaceElevated,
            labelStyle: const TextStyle(color: AppTheme.electricLime, fontSize: 11, fontWeight: FontWeight.bold),
            onPressed: _showNewUserDialog,
          ),
        ],
      ),
    );
  }

  // Sub-Header: Friends +, Open Bets count, and Filter dropdown
  Widget _buildSubHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Friends + row on top right matching screenshot
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'https://splitbet.co.za/invite?ref=deric'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invite link copied! Send to friends to play 1v1.'),
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
                '$_openCount Open Bets',
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

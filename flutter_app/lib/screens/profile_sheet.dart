import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/camera_service.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';

class ProfileSheet extends StatefulWidget {
  final AppUser user;
  final ApiService? apiService;
  final VoidCallback onLogout;
  final Function(AppUser)? onUserUpdated;

  const ProfileSheet({
    super.key,
    required this.user,
    this.apiService,
    required this.onLogout,
    this.onUserUpdated,
  });

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  late AppUser _currentUser;
  bool _isRefreshing = false;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _fetchLatestStats();
    _listenToRealtime();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  void _listenToRealtime() {
    if (widget.apiService == null) return;
    _wsSub = widget.apiService!.wsEvents.listen((event) {
      final type = event['type'];
      if (!mounted) return;

      if (type == 'POOL_SETTLED' ||
          type == 'WALLET_UPDATE' ||
          type == 'POOL_UPDATE' ||
          type == 'POOL_CREATED') {
        _fetchLatestStats(showSpinner: false);
      }
    });
  }

  Future<void> _fetchLatestStats({bool showSpinner = true}) async {
    if (widget.apiService == null) return;
    if (showSpinner) {
      setState(() => _isRefreshing = true);
    }
    try {
      final updated = await widget.apiService!.getUser(_currentUser.id);
      if (mounted) {
        setState(() {
          _currentUser = updated;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _editProfilePhoto() async {
    try {
      final newPhoto = await CameraService.showPhotoSourceSheet(
        context,
        title: 'Change Profile Picture',
      );
      if (newPhoto == null || !mounted) return;

      setState(() => _isRefreshing = true);

      AppUser updatedUser;
      if (widget.apiService != null) {
        try {
          updatedUser = await widget.apiService!.updateUserAvatar(_currentUser.id, newPhoto);
        } catch (e) {
          // Local fallback
          updatedUser = _currentUser.copyWith(avatarUrl: newPhoto);
        }
      } else {
        updatedUser = _currentUser.copyWith(avatarUrl: newPhoto);
      }

      if (mounted) {
        setState(() {
          _currentUser = updatedUser;
          _isRefreshing = false;
        });
        widget.onUserUpdated?.call(updatedUser);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            backgroundColor: AppTheme.surfaceElevated,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating photo: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _currentUser.stats;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'User Profile & Stats',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isRefreshing)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.electricLime,
                          ),
                        ),
                      )
                    else if (widget.apiService != null)
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        tooltip: 'Refresh Stats',
                        onPressed: () => _fetchLatestStats(showSpinner: true),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // Avatar & Name Card
                Center(
                  child: Column(
                    children: [
                      UserAvatar(
                        avatarUrl: _currentUser.avatarUrl,
                        radius: 44,
                        displayName: _currentUser.displayName,
                        showBorder: true,
                        borderColor: AppTheme.electricLime,
                        borderWidth: 2,
                        showEditBadge: true,
                        onTap: _editProfilePhoto,
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _editProfilePhoto,
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt, size: 13, color: AppTheme.electricLime),
                              SizedBox(width: 4),
                              Text(
                                'Change Photo',
                                style: TextStyle(
                                  color: AppTheme.electricLime,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _currentUser.displayName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${_currentUser.username} • Verified Member',
                        style: const TextStyle(
                          color: AppTheme.electricLime,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tier: ${_currentUser.subscriptionTier}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Statistics Grid (PDF Section 14)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Game Statistics',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.electricLime,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Live Synced',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile(
                        'Win Rate',
                        stats?.winRate ?? '0%',
                        isAccent: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatTile(
                        'Total Wins',
                        '${stats?.wins ?? 0}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatTile(
                        'Completed',
                        '${stats?.completedPools ?? 0}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile(
                        'Gross Won',
                        'R ${stats?.totalWon.toStringAsFixed(0) ?? '0'}',
                        isAccent: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatTile(
                        'Active Pools',
                        '${stats?.activePools ?? 0}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatTile(
                        'Losses',
                        '${stats?.losses ?? 0}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Responsible Gambling (PDF Section 15 & 21)
                const Text(
                  'Responsible Gambling Controls',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      _buildSwitchRow('Daily Deposit Limit (R 2,000)', true),
                      const Divider(color: AppTheme.border, height: 18),
                      _buildSwitchRow('Cooling-off Period (Disabled)', false),
                      const Divider(color: AppTheme.border, height: 18),
                      _buildSwitchRow('Self-Exclusion Lock', false),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: isAccent ? AppTheme.electricLime : AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String title, bool val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        ),
        Icon(
          val ? Icons.check_circle : Icons.circle_outlined,
          color: val ? AppTheme.electricLime : AppTheme.textMuted,
          size: 20,
        ),
      ],
    );
  }
}

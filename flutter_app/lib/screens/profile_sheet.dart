import 'package:flutter/material.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';

class ProfileSheet extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;

  const ProfileSheet({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final stats = user.stats;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('User Profile & Stats', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                IconButton(icon: const Icon(Icons.close, color: AppTheme.textSecondary), onPressed: () => Navigator.pop(context)),
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
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppTheme.surfaceLight,
                        backgroundImage: NetworkImage(user.avatarUrl),
                      ),
                      const SizedBox(height: 12),
                      Text(user.displayName, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('@${user.username} • Verified Member', style: const TextStyle(color: AppTheme.electricLime, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Tier: ${user.subscriptionTier}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Statistics Grid (PDF Section 14)
                const Text('Game Statistics', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildStatTile('Win Rate', stats?.winRate ?? '0%', isAccent: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatTile('Total Wins', '${stats?.wins ?? 0}')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatTile('Completed', '${stats?.completedPools ?? 0}')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildStatTile('Gross Won', 'R ${stats?.totalWon.toStringAsFixed(0) ?? '0'}', isAccent: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatTile('Active Pools', '${stats?.activePools ?? 0}')),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatTile('Losses', '${stats?.losses ?? 0}')),
                  ],
                ),
                const SizedBox(height: 24),

                // Responsible Gambling (PDF Section 15 & 21)
                const Text('Responsible Gambling Controls', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
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
          Text(value, style: TextStyle(color: isAccent ? AppTheme.electricLime : AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String title, bool val) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        Icon(val ? Icons.check_circle : Icons.circle_outlined, color: val ? AppTheme.electricLime : AppTheme.textMuted, size: 20),
      ],
    );
  }
}

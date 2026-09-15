import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/pool.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';

class PoolCard extends StatefulWidget {
  final Pool pool;
  final AppUser currentUser;
  final Function(Pool) onJoinPool;
  final VoidCallback onWhatsAppShare;

  const PoolCard({
    super.key,
    required this.pool,
    required this.currentUser,
    required this.onJoinPool,
    required this.onWhatsAppShare,
  });

  @override
  State<PoolCard> createState() => _PoolCardState();
}

class _PoolCardState extends State<PoolCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final pool = widget.pool;
    final currencyFmt = NumberFormat.currency(symbol: 'R', decimalDigits: 0);
    final isJoined = pool.participants.any((p) => p.userId == widget.currentUser.id);
    final isSettled = pool.status == 'SETTLED';
    final isLocked = pool.status == 'LOCKED' || pool.status == 'FULL' || pool.status == 'RANDOM_SELECTION';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isExpanded ? AppTheme.electricLime.withValues(alpha: 0.5) : AppTheme.border,
          width: _isExpanded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (_isExpanded)
            BoxShadow(
              color: AppTheme.electricLime.withValues(alpha: 0.06),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Bet R155 | Win R280
                  Row(
                    children: [
                      const Text(
                        'Bet ',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        currencyFmt.format(pool.depositAmount),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        '  |  ',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 18,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const Text(
                        'Win ',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        currencyFmt.format(pool.netPayout),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      // Status Badge
                      if (isSettled)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'SETTLED',
                            style: TextStyle(color: AppTheme.gold, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else if (isLocked)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'LOCKED',
                            style: TextStyle(color: AppTheme.warning, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Middle Row: X2 Players | 50% ODDS TO WIN
                  Text(
                    'X${pool.maxPlayers} Players | ${pool.oddsToWin} ODDS TO WIN',
                    style: const TextStyle(
                      color: AppTheme.electricLime,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Bottom Row: Overlapping Avatars + Expand indicator
                  Row(
                    children: [
                      // Avatar row (joined + empty slots)
                      _buildAvatarSlots(pool),
                      const Spacer(),
                      // Indicator Dot or Chevron
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _isExpanded ? AppTheme.electricLime : Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // EXPANDED CONTENT (In-place Accordion)
                  if (_isExpanded) ...[
                    const SizedBox(height: 16),
                    const Divider(color: AppTheme.border, height: 1),
                    const SizedBox(height: 16),

                    // Creator info & description
                    if (pool.creator != null)
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundImage: NetworkImage(pool.creator!.avatarUrl),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Created by ${pool.creator!.displayName}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    if (pool.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        pool.description,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Mathematical Transparency Breakdown (PDF Section 12)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow('Deposit per Player', 'R ${pool.depositAmount.toStringAsFixed(2)}'),
                          const SizedBox(height: 6),
                          _buildDetailRow('Filled Slots', '${pool.currentPlayers} / ${pool.maxPlayers} (${pool.slotsRemaining} needed)'),
                          const SizedBox(height: 6),
                          _buildDetailRow('Equal Probability', pool.oddsToWin),
                          const SizedBox(height: 6),
                          _buildDetailRow('Gross Total Pool', 'R ${pool.grossPool.toStringAsFixed(2)}'),
                          const SizedBox(height: 6),
                          _buildDetailRow('Platform Fee (${pool.platformFeePercent}%)', '- R ${pool.platformFeeAmount.toStringAsFixed(2)}'),
                          const Divider(color: AppTheme.border, height: 14),
                          _buildDetailRow('Net Winner Payout', 'R ${pool.netPayout.toStringAsFixed(2)}', isBold: true, highlight: true),
                        ],
                      ),
                    ),

                    if (isSettled && pool.winner != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events, color: AppTheme.gold, size: 24),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('WINNER SELECTED', style: TextStyle(color: AppTheme.gold, fontSize: 11, fontWeight: FontWeight.bold)),
                                Text(
                                  '${pool.winner!.displayName} won R${pool.netPayout.toStringAsFixed(0)}!',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Action Buttons: Join & WhatsApp Share
                    Row(
                      children: [
                        // Main Action (Join / Status)
                        Expanded(
                          flex: 3,
                          child: ElevatedButton(
                            onPressed: (pool.status == 'OPEN' && !isJoined)
                                ? () => widget.onJoinPool(pool)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.electricLime,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: AppTheme.surfaceLight,
                              disabledForegroundColor: AppTheme.textMuted,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              isSettled
                                  ? 'Pool Settled'
                                  : isJoined
                                      ? 'You Joined • Waiting...'
                                      : pool.status != 'OPEN'
                                          ? 'Pool Full / Locked'
                                          : 'Join Pool (Deposit R${pool.depositAmount.toStringAsFixed(0)})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // WhatsApp Share Button (PDF Section 13)
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: pool.whatsappShareText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('WhatsApp deep link copied to clipboard!'),
                                backgroundColor: Color(0xFF25D366),
                              ),
                            );
                            widget.onWhatsAppShare();
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.5)),
                            ),
                            child: const Icon(
                              Icons.share_outlined,
                              color: Color(0xFF25D366),
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSlots(Pool pool) {
    List<Widget> avatarWidgets = [];

    // Joined participants
    for (int i = 0; i < pool.participants.length; i++) {
      final p = pool.participants[i];
      avatarWidgets.add(
        Transform.translate(
          offset: Offset(-i * 10.0, 0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.surface, width: 2),
            ),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.surfaceLight,
              backgroundImage: NetworkImage(p.avatarUrl),
            ),
          ),
        ),
      );
    }

    // Remaining empty slots
    final remaining = pool.maxPlayers - pool.participants.length;
    for (int i = 0; i < remaining; i++) {
      final idx = pool.participants.length + i;
      avatarWidgets.add(
        Transform.translate(
          offset: Offset(-idx * 10.0, 0),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceLight.withValues(alpha: 0.5),
              border: Border.all(
                color: AppTheme.borderLight,
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.add,
              size: 14,
              color: AppTheme.textMuted,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: avatarWidgets,
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: highlight ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlight ? AppTheme.electricLime : AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

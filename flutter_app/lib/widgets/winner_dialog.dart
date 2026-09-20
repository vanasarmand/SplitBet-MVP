import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

class WinnerCelebrationDialog extends StatefulWidget {
  final String poolId;
  final String winnerName;
  final String winnerAvatar;
  final double netPayout;
  final Map<String, dynamic>? proof;
  final bool isCurrentUserWinner;
  final bool hasUserLost;

  const WinnerCelebrationDialog({
    super.key,
    required this.poolId,
    required this.winnerName,
    required this.winnerAvatar,
    required this.netPayout,
    this.proof,
    required this.isCurrentUserWinner,
    this.hasUserLost = false,
  });

  @override
  State<WinnerCelebrationDialog> createState() => _WinnerCelebrationDialogState();
}

class _WinnerCelebrationDialogState extends State<WinnerCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  bool _showProof = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _animController.forward();
  }


  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isWinner = widget.isCurrentUserWinner;
    final bool isLoser = widget.hasUserLost;

    final Color accentColor = isWinner
        ? AppTheme.electricLime
        : (isLoser ? const Color(0xFFFF5252) : AppTheme.gold);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: accentColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Badge Icon
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWinner
                      ? Icons.celebration
                      : (isLoser ? Icons.sentiment_dissatisfied_outlined : Icons.emoji_events),
                  size: 38,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                isWinner
                    ? 'YOU WON!'
                    : (isLoser ? 'BETTER LUCK NEXT TIME!' : 'WINNER SELECTED!'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),

              // Subtitle for Loser or Observer
              if (isLoser)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'You lost this pool round. Here is the winner:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              else if (!isWinner)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Pool has settled. Verified winner:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),

              // Winner Profile Pic (Prominently displayed!)
              UserAvatar(
                avatarUrl: widget.winnerAvatar,
                radius: 42,
                displayName: widget.winnerName,
                showBorder: true,
                borderColor: AppTheme.gold,
                borderWidth: 2.5,
                showWinnerCrown: true,
              ),
              const SizedBox(height: 12),

              // Winner Name & Status
              Text(
                isWinner ? '${widget.winnerName} (You)' : widget.winnerName,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isLoser)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'WINNER',
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),

              // Payout Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    Text(
                      isWinner
                          ? 'YOUR NET WINNING PAYOUT'
                          : 'WINNER TOTAL PAYOUT',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R ${widget.netPayout.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isWinner ? AppTheme.electricLime : AppTheme.gold,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // RNG Audit Proof Accordion
              InkWell(
                onTap: () => setState(() => _showProof = !_showProof),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showProof
                            ? 'Hide Cryptographic Audit'
                            : 'View Provably Fair Proof',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      Icon(
                        _showProof
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              if (_showProof && widget.proof != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProofRow('Mechanism', widget.proof!['mechanism'] ?? 'crypto.randomInt'),
                      _buildProofRow('Entropy Hash', '${(widget.proof!['entropy_hash'] ?? '').toString().substring(0, 16)}...'),
                      _buildProofRow('Fair Odds', widget.proof!['equal_probability'] ?? '50%'),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isWinner ? AppTheme.electricLime : AppTheme.surfaceLight,
                    foregroundColor: isWinner ? Colors.black : AppTheme.textPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Back to Pools', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProofRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          Text(value, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

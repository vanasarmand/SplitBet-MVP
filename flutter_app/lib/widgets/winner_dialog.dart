import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WinnerCelebrationDialog extends StatefulWidget {
  final String poolId;
  final String winnerName;
  final String winnerAvatar;
  final double netPayout;
  final Map<String, dynamic>? proof;
  final bool isCurrentUserWinner;

  const WinnerCelebrationDialog({
    super.key,
    required this.poolId,
    required this.winnerName,
    required this.winnerAvatar,
    required this.netPayout,
    this.proof,
    required this.isCurrentUserWinner,
  });

  @override
  State<WinnerCelebrationDialog> createState() => _WinnerCelebrationDialogState();
}

class _WinnerCelebrationDialogState extends State<WinnerCelebrationDialog> with SingleTickerProviderStateMixin {
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
            border: Border.all(
              color: widget.isCurrentUserWinner ? AppTheme.electricLime : AppTheme.gold,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (widget.isCurrentUserWinner ? AppTheme.electricLime : AppTheme.gold).withValues(alpha: 0.2),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Trophy / Crown
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: (widget.isCurrentUserWinner ? AppTheme.electricLime : AppTheme.gold).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.isCurrentUserWinner ? Icons.celebration : Icons.emoji_events,
                  size: 38,
                  color: widget.isCurrentUserWinner ? AppTheme.electricLime : AppTheme.gold,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.isCurrentUserWinner ? 'YOU WON!' : 'WINNER SELECTED!',
                style: TextStyle(
                  color: widget.isCurrentUserWinner ? AppTheme.electricLime : AppTheme.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 14),

              // Winner avatar
              CircleAvatar(
                radius: 36,
                backgroundColor: AppTheme.surfaceLight,
                backgroundImage: NetworkImage(widget.winnerAvatar),
              ),
              const SizedBox(height: 10),

              Text(
                widget.winnerName,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Payout Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    const Text(
                      'NET WINNING PAYOUT',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R ${widget.netPayout.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.electricLime,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // RNG Audit Proof Accordion
              InkWell(
                onTap: () => setState(() => _showProof = !_showProof),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        _showProof ? 'Hide Cryptographic Audit' : 'View Cryptographic Audit Proof',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      Icon(
                        _showProof ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              if (_showProof && widget.proof != null) ...[
                const SizedBox(height: 10),
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

              const SizedBox(height: 20),

              // Close button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isCurrentUserWinner ? AppTheme.electricLime : AppTheme.surfaceLight,
                    foregroundColor: widget.isCurrentUserWinner ? Colors.black : AppTheme.textPrimary,
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

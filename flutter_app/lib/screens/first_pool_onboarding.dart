import 'package:flutter/material.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class FirstPoolOnboardingScreen extends StatefulWidget {
  final AppUser user;
  final ApiService apiService;
  final VoidCallback onCompleted;

  const FirstPoolOnboardingScreen({
    super.key,
    required this.user,
    required this.apiService,
    required this.onCompleted,
  });

  @override
  State<FirstPoolOnboardingScreen> createState() => _FirstPoolOnboardingScreenState();
}

class _FirstPoolOnboardingScreenState extends State<FirstPoolOnboardingScreen> {
  int _step = 0; // 0: Welcome & Wallet, 1: Create First Pool
  double _deposit = 155.0;
  int _players = 2;
  bool _isCreating = false;

  Future<void> _createFirstPool() async {
    setState(() => _isCreating = true);
    try {
      await widget.apiService.createPool(
        creatorId: widget.user.id,
        depositAmount: _deposit,
        maxPlayers: _players,
        description: 'My very first SplitBet pool! 🎯',
      );
      await widget.apiService.completeFirstPool(widget.user.id);
      widget.onCompleted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: _step == 0 ? _buildWelcomeStep() : _buildCreateStep(),
        ),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Spacer(),
        // Brand logo
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.electricLime, width: 2),
            boxShadow: const [
              BoxShadow(color: AppTheme.electricLimeGlow, blurRadius: 20, spreadRadius: 2),
            ],
          ),
          child: const Center(
            child: Text('SB', style: TextStyle(color: AppTheme.electricLime, fontSize: 32, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 24),

        Text(
          'Welcome, ${widget.user.displayName}!',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        const Text(
          'SplitBet is social pooled betting with 100% fair equal probability. The creator has zero preferential advantage.',
          style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Virtual Wallet Credited Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.electricLime.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet, color: AppTheme.electricLime, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Test Wallet Funded', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text('R 1,000.00 ZAR ready to play', style: TextStyle(color: AppTheme.electricLime, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),

        // Onboarding rule notice
        const Text(
          'Step 1 of 2: Create your first pool to activate your full marketplace feed',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.electricLime,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Setup My First Pool &rarr;', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateStep() {
    final gross = _deposit * _players;
    final fee = (gross * 0.07).roundToDouble();
    final net = gross - fee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => setState(() => _step = 0),
        ),
        const SizedBox(height: 12),
        const Text(
          'Launch Your First Pool',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        const Text(
          'Set your fixed deposit and player count. Once full, a fair random winner takes the pot!',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),

        // Deposit Selector
        const Text('Choose Your Entry Deposit', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          children: [100.0, 155.0, 300.0].map((amt) {
            final isSel = _deposit == amt;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('R ${amt.toStringAsFixed(0)}'),
                selected: isSel,
                selectedColor: AppTheme.electricLime,
                backgroundColor: AppTheme.surfaceLight,
                labelStyle: TextStyle(color: isSel ? Colors.black : AppTheme.textPrimary, fontWeight: FontWeight.bold),
                onSelected: (val) => setState(() => _deposit = amt),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // 1v1 or 4 Players
        const Text('Player Format', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildFormatCard(2, '1v1 Showdown', '50.0% Odds'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormatCard(4, '4-Player Dash', '25.0% Odds'),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Preview Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              _buildRow('Your Deposit', 'R ${_deposit.toStringAsFixed(0)}'),
              const SizedBox(height: 6),
              _buildRow('Total Pool', 'R ${gross.toStringAsFixed(0)}'),
              const SizedBox(height: 6),
              _buildRow('Platform Fee (7%)', '- R ${fee.toStringAsFixed(0)}'),
              const Divider(color: AppTheme.border, height: 16),
              _buildRow('Net Winner Payout', 'R ${net.toStringAsFixed(0)}', isLime: true),
            ],
          ),
        ),

        const Spacer(),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isCreating ? null : _createFirstPool,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.electricLime,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isCreating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Publish First Pool & Enter Home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildFormatCard(int players, String title, String odds) {
    final isSel = _players == players;
    return InkWell(
      onTap: () => setState(() => _players = players),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSel ? AppTheme.surfaceElevated : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSel ? AppTheme.electricLime : AppTheme.border, width: isSel ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: isSel ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(odds, style: TextStyle(color: isSel ? AppTheme.electricLime : AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String val, {bool isLime = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        Text(
          val,
          style: TextStyle(
            color: isLime ? AppTheme.electricLime : AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: isLime ? 16 : 14,
          ),
        ),
      ],
    );
  }
}

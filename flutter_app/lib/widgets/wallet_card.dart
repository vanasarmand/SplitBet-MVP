import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class WalletCard extends StatelessWidget {
  final UserBalance balance;
  final ApiService apiService;
  final VoidCallback onRefresh;

  const WalletCard({
    super.key,
    required this.balance,
    required this.apiService,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final formattedBalance = formatter.format(balance.available);

    return InkWell(
      onTap: () => _showWalletSheet(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Money displayed in user wallet aligned to the left
            Text(
              formattedBalance,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            // Rest kept to the right
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Wallet',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 14),
                // Electric Lime Vertical Glowing Accent Pill
                Container(
                  width: 5,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.electricLime,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                        color: AppTheme.electricLimeGlow,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showWalletSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WalletDetailSheet(
        userId: balance.userId,
        initialBalance: balance,
        apiService: apiService,
        onDepositSuccess: onRefresh,
      ),
    );
  }
}

class _WalletDetailSheet extends StatefulWidget {
  final String userId;
  final UserBalance initialBalance;
  final ApiService apiService;
  final VoidCallback onDepositSuccess;

  const _WalletDetailSheet({
    required this.userId,
    required this.initialBalance,
    required this.apiService,
    required this.onDepositSuccess,
  });

  @override
  State<_WalletDetailSheet> createState() => _WalletDetailSheetState();
}

class _WalletDetailSheetState extends State<_WalletDetailSheet> {
  late UserBalance _balance;
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  bool _isDepositing = false;

  @override
  void initState() {
    super.initState();
    _balance = widget.initialBalance;
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    try {
      final res = await widget.apiService.getWallet(widget.userId);
      if (mounted) {
        setState(() {
          _balance = res['balance'] as UserBalance;
          _transactions = res['transactions'] as List;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deposit(double amount) async {
    setState(() => _isDepositing = true);
    try {
      await widget.apiService.depositFunds(widget.userId, amount);
      await _loadWalletData();
      widget.onDepositSuccess();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully deposited R${amount.toStringAsFixed(0)}'),
            backgroundColor: AppTheme.surfaceElevated,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deposit failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isDepositing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(symbol: 'R ', decimalDigits: 2);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
                const Text(
                  'Wallet & Financial Ledger',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // Balances Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      _buildBalanceRow('Available Balance', currencyFmt.format(_balance.available), isHighlighted: true),
                      const Divider(color: AppTheme.border, height: 24),
                      _buildBalanceRow('In Active Pools (Reserved)', currencyFmt.format(_balance.reserved)),
                      const Divider(color: AppTheme.border, height: 24),
                      _buildBalanceRow('Total Aggregate Balance', currencyFmt.format(_balance.total), isBold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Fast Top-Up Virtual Funds
                Row(
                  children: [
                    const Text('Test Top-Up:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(width: 8),
                    _buildTopUpChip(250),
                    const SizedBox(width: 8),
                    _buildTopUpChip(500),
                    const SizedBox(width: 8),
                    _buildTopUpChip(1000),
                  ],
                ),
                const SizedBox(height: 24),

                // Double-Entry Ledger Transactions Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Auditable Ledger History',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '${_transactions.length} events',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
                else if (_transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('No transaction history yet', style: TextStyle(color: AppTheme.textMuted)),
                    ),
                  )
                else
                  ..._transactions.map((tx) => _buildTransactionItem(tx, currencyFmt)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(String label, String value, {bool isHighlighted = false, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isHighlighted ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isHighlighted ? AppTheme.electricLime : AppTheme.textPrimary,
            fontSize: isHighlighted ? 18 : 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTopUpChip(double amount) {
    return ActionChip(
      label: Text('+ R${amount.toStringAsFixed(0)}'),
      labelStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
      backgroundColor: AppTheme.electricLime,
      onPressed: _isDepositing ? null : () => _deposit(amount),
    );
  }

  Widget _buildTransactionItem(dynamic tx, NumberFormat fmt) {
    final type = tx['type'] ?? '';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final isPositive = amount > 0;
    final timestamp = tx['timestamp'] ?? '';
    String timeStr = '';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      timeStr = DateFormat('dd MMM, HH:mm').format(dt);
    } catch (_) {
      timeStr = timestamp;
    }

    IconData icon;
    Color iconColor;
    if (type == 'DEPOSIT') {
      icon = Icons.arrow_downward;
      iconColor = AppTheme.success;
    } else if (type == 'POOL_WIN') {
      icon = Icons.emoji_events;
      iconColor = AppTheme.gold;
    } else if (type == 'POOL_RESERVE') {
      icon = Icons.lock_clock;
      iconColor = AppTheme.warning;
    } else {
      icon = Icons.sync_alt;
      iconColor = AppTheme.textSecondary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx['description'] ?? type,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '$timeStr • ${tx['status'] ?? 'SETTLED'}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}${fmt.format(amount)}',
            style: TextStyle(
              color: isPositive ? AppTheme.electricLime : AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

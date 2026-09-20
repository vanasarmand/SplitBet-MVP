import 'package:flutter/material.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class CreatePoolSheet extends StatefulWidget {
  final AppUser currentUser;
  final ApiService apiService;
  final VoidCallback onPoolCreated;

  const CreatePoolSheet({
    super.key,
    required this.currentUser,
    required this.apiService,
    required this.onPoolCreated,
  });

  @override
  State<CreatePoolSheet> createState() => _CreatePoolSheetState();
}

class _CreatePoolSheetState extends State<CreatePoolSheet> {
  double _depositAmount = 155.0;
  int _maxPlayers = 2;
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _customDepositController = TextEditingController();
  bool _isCustomDeposit = false;
  bool _isSubmitting = false;

  final List<double> _depositPresets = [50.0, 155.0, 300.0, 500.0, 1000.0];

  double get _grossPool => _depositAmount * _maxPlayers;
  double get _feeAmount => (_grossPool * 0.07).roundToDouble();
  double get _netPayout => _grossPool - _feeAmount;
  String get _probability => '${(100 / _maxPlayers).toStringAsFixed(1)}%';

  @override
  void dispose() {
    _descController.dispose();
    _customDepositController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (widget.currentUser.balance.available < _depositAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient balance. You need R${_depositAmount.toStringAsFixed(0)}, available is R${widget.currentUser.balance.available.toStringAsFixed(0)}'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.apiService.createPool(
        creatorId: widget.currentUser.id,
        depositAmount: _depositAmount,
        maxPlayers: _maxPlayers,
        description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
      );

      widget.onPoolCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pool created and published successfully!'),
            backgroundColor: AppTheme.surfaceElevated,
          ),
        );
      }
    } catch (_) {
      // Offline Demo Mode: simulate pool creation
      widget.onPoolCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pool created in Demo Mode! (Offline)'),
            backgroundColor: AppTheme.surfaceElevated,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
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
                  'Create New Pool',
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
                // Deposit Amount selection
                const Text(
                  '1. Select Fixed Deposit per Player',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._depositPresets.map((amt) {
                      final isSelected = !_isCustomDeposit && _depositAmount == amt;
                      return ChoiceChip(
                        label: Text('R ${amt.toStringAsFixed(0)}'),
                        selected: isSelected,
                        selectedColor: AppTheme.electricLime,
                        backgroundColor: AppTheme.surfaceLight,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              _depositAmount = amt;
                              _isCustomDeposit = false;
                            });
                          }
                        },
                      );
                    }),
                    ChoiceChip(
                      label: const Text('Custom'),
                      selected: _isCustomDeposit,
                      selectedColor: AppTheme.electricLime,
                      backgroundColor: AppTheme.surfaceLight,
                      labelStyle: TextStyle(
                        color: _isCustomDeposit ? Colors.black : AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (val) {
                        setState(() => _isCustomDeposit = val);
                      },
                    ),
                  ],
                ),

                if (_isCustomDeposit) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customDepositController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Enter deposit in ZAR (e.g. 250)',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.surfaceElevated,
                      prefixText: 'R ',
                      prefixStyle: const TextStyle(color: AppTheme.electricLime, fontWeight: FontWeight.bold),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.electricLime)),
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null && parsed > 0) {
                        setState(() => _depositAmount = parsed);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 22),

                // Max Players selection (2 to 8)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '2. Select Number of Players',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    Text(
                      '$_maxPlayers Players ($_probability)',
                      style: const TextStyle(color: AppTheme.electricLime, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (index) {
                    final pCount = index + 2;
                    final isSelected = _maxPlayers == pCount;
                    return InkWell(
                      onTap: () => setState(() => _maxPlayers = pCount),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.electricLime : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? AppTheme.electricLime : AppTheme.border),
                        ),
                        child: Text(
                          '$pCount',
                          style: TextStyle(
                            color: isSelected ? Colors.black : AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 22),

                // Description (optional)
                const Text(
                  '3. Pool Description (Optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLength: 60,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. 1v1 quick showdown or Friday pool!',
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surfaceElevated,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                  ),
                ),
                const SizedBox(height: 16),

                // Confirmation / Mathematical Breakdown Card (PDF Section 6 Step 4)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POOL CONFIRMATION SUMMARY',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildSummaryRow('Deposit Required', 'R ${_depositAmount.toStringAsFixed(2)}'),
                      const SizedBox(height: 6),
                      _buildSummaryRow('Total Players', '$_maxPlayers Participants'),
                      const SizedBox(height: 6),
                      _buildSummaryRow('Winning Probability', _probability),
                      const SizedBox(height: 6),
                      _buildSummaryRow('Potential Gross Pool', 'R ${_grossPool.toStringAsFixed(2)}'),
                      const SizedBox(height: 6),
                      _buildSummaryRow('Platform Fee (7%)', '- R ${_feeAmount.toStringAsFixed(2)}'),
                      const Divider(color: AppTheme.border, height: 16),
                      _buildSummaryRow('Estimated Net Winner Payout', 'R ${_netPayout.toStringAsFixed(2)}', isLime: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Create Pool CTA
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.electricLime,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(
                            'Confirm & Create Pool (R${_depositAmount.toStringAsFixed(0)})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
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

  Widget _buildSummaryRow(String label, String value, {bool isLime = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: isLime ? AppTheme.electricLime : AppTheme.textPrimary,
            fontSize: isLime ? 16 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

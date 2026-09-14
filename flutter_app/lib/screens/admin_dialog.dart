import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AdminDashboardDialog extends StatefulWidget {
  final ApiService apiService;

  const AdminDashboardDialog({super.key, required this.apiService});

  @override
  State<AdminDashboardDialog> createState() => _AdminDashboardDialogState();
}

class _AdminDashboardDialogState extends State<AdminDashboardDialog> {
  Map<String, dynamic>? _overview;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    try {
      final res = await widget.apiService.getAdminOverview();
      if (mounted) {
        setState(() {
          _overview = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _overview?['metrics'] as Map<String, dynamic>?;
    final auditLogs = _overview?['audit_logs'] as List? ?? [];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: AppTheme.electricLime, size: 22),
                      SizedBox(width: 8),
                      Text('SplitBet Admin Dashboard', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close, color: AppTheme.textSecondary), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Metric Cards
                        const Text('System Overview & Financials', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildMetricCard('Platform Revenue', 'R ${metrics?['platform_revenue_zar'] ?? '0.00'}', isAccent: true)),
                            const SizedBox(width: 10),
                            Expanded(child: _buildMetricCard('Settled Volume', 'R ${metrics?['gross_volume_zar'] ?? '0.00'}')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildMetricCard('Total Pools', '${metrics?['total_pools'] ?? 0}')),
                            const SizedBox(width: 10),
                            Expanded(child: _buildMetricCard('Active Pools', '${metrics?['active_pools'] ?? 0}')),
                            const SizedBox(width: 10),
                            Expanded(child: _buildMetricCard('Registered Users', '${metrics?['total_users'] ?? 0}')),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // System Audit Trail (PDF Section 17 & 18)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Audit & Concurrency Log', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                            Text('${auditLogs.length} entries', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        ...auditLogs.map((log) => _buildAuditTile(log)),
                        const SizedBox(height: 20),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: isAccent ? AppTheme.electricLime : AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAuditTile(dynamic log) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(log['action'] ?? '', style: const TextStyle(color: AppTheme.electricLime, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log['details'] ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                const SizedBox(height: 2),
                Text('Actor: ${log['actor']} • Entity: ${log['entity']}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

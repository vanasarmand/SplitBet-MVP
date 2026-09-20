import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  StreamSubscription? _wsSub;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadAdminData();
    _listenToRealtime();
    // Auto-refresh every 3 seconds while dialog is open to ensure platform revenue & volume are always fresh
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadAdminData(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  void _listenToRealtime() {
    _wsSub = widget.apiService.wsEvents.listen((event) {
      if (!mounted) return;
      _loadAdminData(showSpinner: false);
    });
  }

  Future<void> _loadAdminData({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _isLoading = true);
    }
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

  String _formatCurrency(dynamic value) {
    if (value == null) return '0.00';
    final numVal = (value is num)
        ? value.toDouble()
        : double.tryParse(value.toString()) ?? 0.0;
    return NumberFormat('#,##0.00', 'en_US').format(numVal);
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 45) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp.toString().split('T').last.split('.').first;
    }
  }

  Color _getActionColor(String action) {
    switch (action.toUpperCase()) {
      case 'POOL_SETTLED':
        return Colors.amberAccent;
      case 'JOIN_POOL':
        return Colors.cyanAccent;
      case 'CREATE_POOL':
        return Colors.deepPurpleAccent.shade100;
      case 'DEPOSIT':
        return AppTheme.electricLime;
      case 'REGISTER_USER':
        return Colors.tealAccent;
      case 'COMPLETE_ONBOARDING':
        return Colors.orangeAccent;
      default:
        return AppTheme.electricLime;
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
                      Text(
                        'SplitBet Admin Dashboard',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
                        tooltip: 'Refresh Metrics',
                        onPressed: () => _loadAdminData(showSpinner: true),
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
            const Divider(color: AppTheme.border, height: 1),

            Expanded(
              child: _isLoading && _overview == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Metric Cards
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'System Overview & Financials',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
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
                                    'Real-time Active',
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
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                'Platform Revenue (7%)',
                                'R ${_formatCurrency(metrics?['platform_revenue_zar'])}',
                                isAccent: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildMetricCard(
                                'Settled Volume',
                                'R ${_formatCurrency(metrics?['gross_volume_zar'])}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildMetricCard('Total Pools', '${metrics?['total_pools'] ?? 0}')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMetricCard('Active Pools', '${metrics?['active_pools'] ?? 0}')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMetricCard('Settled Pools', '${metrics?['settled_pools'] ?? 0}')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMetricCard('Users', '${metrics?['total_users'] ?? 0}')),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // System Audit Trail (PDF Section 17 & 18)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Audit & Concurrency Log',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${auditLogs.length} activity entries',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (auditLogs.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            alignment: Alignment.center,
                            child: const Text(
                              'No audit activity logged yet.',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                          )
                        else
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
          Text(
            value,
            style: TextStyle(
              color: isAccent ? AppTheme.electricLime : AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTile(dynamic log) {
    final action = (log['action'] ?? '').toString();
    final actionColor = _getActionColor(action);
    final timeStr = _formatTimestamp(log['timestamp']);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: actionColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              action,
              style: TextStyle(
                color: actionColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        log['details'] ?? '',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: Text(
                          timeStr,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Actor: ${log['actor']} • Entity: ${log['entity']}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

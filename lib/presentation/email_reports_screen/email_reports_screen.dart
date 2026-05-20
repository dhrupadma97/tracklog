import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';

import '../../core/app_export.dart';
import '../../services/email_report_service.dart';
import '../../services/supabase_service.dart';

class EmailReportsScreen extends StatefulWidget {
  const EmailReportsScreen({super.key});

  @override
  State<EmailReportsScreen> createState() => _EmailReportsScreenState();
}

class _EmailReportsScreenState extends State<EmailReportsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<EmailReportSubscription> _subscriptions = [];
  List<EmailSendLog> _logs = [];

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subs = await EmailReportService.instance.getSubscriptions();
      final logs = await EmailReportService.instance.getRecentLogs(limit: 15);
      setState(() {
        _subscriptions = subs;
        _logs = logs;
        _loading = false;
      });
      _animController.forward(from: 0);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<Map<String, dynamic>> _fetchPoAndSessionData(String reportType) async {
    final client = SupabaseService.instance.client;

    // PO data
    final poData = await client
        .from('po_trackers')
        .select()
        .eq('po_number', '8242348442')
        .maybeSingle();

    final totalPoValue = (poData?['total_po_value'] as num?)?.toDouble() ?? 0;
    final taxAmount = (poData?['tax_amount'] as num?)?.toDouble() ?? 0;
    final totalPoWithTax = totalPoValue + taxAmount;

    // Sessions
    final sessionsData = await client
        .from('engineer_sessions')
        .select(
          'track_name, duration_minutes, total_cost, session_status, started_at',
        )
        .eq('session_status', 'completed')
        .order('started_at', ascending: false);

    double trackTotal = 0;
    int sessionCount = 0;
    final List<Map<String, dynamic>> sessionList = [];

    final now = DateTime.now();
    final cutoff = reportType == 'daily'
        ? DateTime(now.year, now.month, now.day)
        : now.subtract(const Duration(days: 7));

    for (final s in sessionsData as List) {
      final cost = (s['total_cost'] as num?)?.toDouble() ?? 0;
      trackTotal += cost;
      sessionCount++;

      final startedAt = DateTime.tryParse(s['started_at'] as String? ?? '');
      if (startedAt != null && startedAt.isAfter(cutoff)) {
        sessionList.add({
          'trackName': s['track_name'],
          'durationMinutes': s['duration_minutes'],
          'totalCost': cost,
          'sessionStatus': s['session_status'],
        });
      }
    }

    // Additional services
    final servicesData = await client
        .from('session_additional_services')
        .select('total_cost');
    double servicesTotal = 0;
    for (final s in servicesData as List) {
      servicesTotal += (s['total_cost'] as num?)?.toDouble() ?? 0;
    }

    const workshopSpend = 100000.0;
    final totalSpend = trackTotal + servicesTotal + workshopSpend;

    return {
      'poData': {
        'poNumber': poData?['po_number'] ?? '8242348442',
        'totalPoValue': totalPoValue,
        'taxAmount': taxAmount,
        'totalPoWithTax': totalPoWithTax,
        'totalSpend': totalSpend,
        'remainingBalance': totalPoWithTax - totalSpend,
      },
      'spendBreakdown': {
        'trackSessions': trackTotal,
        'additionalServices': servicesTotal,
        'workshopRent': workshopSpend,
        'totalSessions': sessionCount,
      },
      'sessionSummary': sessionList,
    };
  }

  Future<void> _sendNow(String reportType) async {
    if (_sending) return;
    setState(() => _sending = true);

    try {
      final data = await _fetchPoAndSessionData(reportType);
      final result = await EmailReportService.instance.sendToAllActive(
        reportType: reportType,
        poData: data['poData'] as Map<String, dynamic>,
        spendBreakdown: data['spendBreakdown'] as Map<String, dynamic>,
        sessionSummary: data['sessionSummary'] as List<Map<String, dynamic>>,
      );

      if (mounted) {
        final sent = result['sent'] as int;
        final failed = result['failed'] as int;
        final total = result['total'] as int;

        if (total == 0) {
          _showSnack('No active subscribers found', isError: true);
        } else if (failed == 0) {
          _showSnack('✓ Report sent to $sent manager${sent > 1 ? "s" : ""}');
        } else {
          _showSnack(
            'Sent: $sent, Failed: $failed of $total',
            isError: failed > 0,
          );
        }
        await _loadData();
      }
    } catch (e) {
      if (mounted) _showSnack('Failed: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isError
            ? Colors.redAccent.withAlpha(220)
            : const Color(0xFF4CAF50).withAlpha(220),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showAddSubscriberSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddSubscriberSheet(
        onAdded: () {
          Navigator.pop(context);
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
            : _error != null
            ? _buildError()
            : FadeTransition(
                opacity: _fadeAnim,
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppTheme.primary,
                  backgroundColor: const Color(0xFF1A2236),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 20),
                              _buildSendNowCard(),
                              const SizedBox(height: 16),
                              _buildSubscribersSection(),
                              const SizedBox(height: 16),
                              _buildRecentLogsSection(),
                              const SizedBox(height: 100),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Failed to load report data',
            style: GoogleFonts.manrope(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadData,
            child: Text(
              'Retry',
              style: GoogleFonts.manrope(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF4CAF50).withAlpha(77)),
          ),
          child: const Icon(
            Icons.email_outlined,
            color: Color(0xFF4CAF50),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Email Reports',
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'PO Spend & Session Summaries',
                style: GoogleFonts.manrope(
                  color: const Color(0xFF6B7490),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _loadData,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2236).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
            ),
            child: const Icon(
              Icons.refresh,
              color: Color(0xFF6B7490),
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSendNowCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SEND REPORT NOW',
                style: GoogleFonts.manrope(
                  color: const Color(0xFF6B7490),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildSendButton(
                      label: 'Daily Report',
                      icon: Icons.today_outlined,
                      color: AppTheme.primary,
                      onTap: _sending ? null : () => _sendNow('daily'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSendButton(
                      label: 'Weekly Report',
                      icon: Icons.date_range_outlined,
                      color: const Color(0xFF9C88FF),
                      onTap: _sending ? null : () => _sendNow('weekly'),
                    ),
                  ),
                ],
              ),
              if (_sending) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Sending report to all active subscribers…',
                      style: GoogleFonts.manrope(
                        color: const Color(0xFF8A94B0),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppTheme.primary.withAlpha(180),
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reports include PO spend summary, balance, utilisation, and session logs for the selected period.',
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF8A94B0),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubscribersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MANAGER SUBSCRIBERS',
              style: GoogleFonts.manrope(
                color: const Color(0xFF6B7490),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            GestureDetector(
              onTap: _showAddSubscriberSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, color: AppTheme.primary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Add',
                      style: GoogleFonts.manrope(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_subscriptions.isEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2236).withAlpha(200),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF3A4460).withAlpha(120),
                  ),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        color: const Color(0xFF3A4460),
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No subscribers yet',
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF6B7490),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add manager emails to receive daily/weekly reports',
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF4A5470),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2236).withAlpha(200),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF3A4460).withAlpha(120),
                  ),
                ),
                child: Column(
                  children: List.generate(_subscriptions.length, (i) {
                    final sub = _subscriptions[i];
                    return _buildSubscriberRow(
                      sub,
                      i < _subscriptions.length - 1,
                    );
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSubscriberRow(EmailReportSubscription sub, bool showDivider) {
    final typeColor = sub.reportType == 'daily'
        ? AppTheme.primary
        : sub.reportType == 'weekly'
        ? const Color(0xFF9C88FF)
        : const Color(0xFF4CAF50);

    final typeLabel = sub.reportType == 'daily'
        ? 'Daily'
        : sub.reportType == 'weekly'
        ? 'Weekly'
        : 'Daily + Weekly';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: typeColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    sub.managerName.isNotEmpty
                        ? sub.managerName[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.manrope(
                      color: typeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.managerName,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub.email,
                      style: GoogleFonts.manrope(
                        color: const Color(0xFF6B7490),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub.lastSentAt != null)
                      Text(
                        'Last sent: ${_formatDate(sub.lastSentAt!)}',
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF4A5470),
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: typeColor.withAlpha(60)),
                ),
                child: Text(
                  typeLabel,
                  style: GoogleFonts.manrope(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: sub.isActive,
                onChanged: (val) async {
                  await EmailReportService.instance.toggleSubscription(
                    sub.id,
                    val,
                  );
                  _loadData();
                },
                activeColor: const Color(0xFF4CAF50),
                inactiveThumbColor: const Color(0xFF4A5470),
                inactiveTrackColor: const Color(0xFF2A3450),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              GestureDetector(
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1A2236),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: Text(
                        'Remove Subscriber',
                        style: GoogleFonts.manrope(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      content: Text(
                        'Remove ${sub.managerName} from report subscribers?',
                        style: GoogleFonts.manrope(
                          color: const Color(0xFF8A94B0),
                          fontSize: 13,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.manrope(
                              color: const Color(0xFF6B7490),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'Remove',
                            style: GoogleFonts.manrope(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await EmailReportService.instance.deleteSubscription(
                      sub.id,
                    );
                    _loadData();
                  }
                },
                child: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFF4A5470),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            color: Color(0xFF2A3450),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }

  Widget _buildRecentLogsSection() {
    if (_logs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECENT SEND LOG',
          style: GoogleFonts.manrope(
            color: const Color(0xFF6B7490),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A2236).withAlpha(200),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF3A4460).withAlpha(120),
                ),
              ),
              child: Column(
                children: List.generate(_logs.length, (i) {
                  final log = _logs[i];
                  return _buildLogRow(log, i < _logs.length - 1);
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogRow(EmailSendLog log, bool showDivider) {
    final isSent = log.status == 'sent';
    final statusColor = isSent ? const Color(0xFF4CAF50) : Colors.redAccent;
    final typeColor = log.reportType == 'daily'
        ? AppTheme.primary
        : const Color(0xFF9C88FF);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isSent ? Icons.check_circle_outline : Icons.error_outline,
                color: statusColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.recipientEmail,
                      style: GoogleFonts.manrope(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatDate(log.sentAt),
                      style: GoogleFonts.manrope(
                        color: const Color(0xFF4A5470),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  log.reportType,
                  style: GoogleFonts.manrope(
                    color: typeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isSent ? 'Sent' : 'Failed',
                  style: GoogleFonts.manrope(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            color: Color(0xFF2A3450),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day.toString().padLeft(2, '0')} ${_monthName(dt.month)} ${dt.year}';
  }

  String _monthName(int m) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[m - 1];
  }
}

// ── Add Subscriber Bottom Sheet ───────────────────────────────────────────────

class _AddSubscriberSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddSubscriberSheet({required this.onAdded});

  @override
  State<_AddSubscriberSheet> createState() => _AddSubscriberSheetState();
}

class _AddSubscriberSheetState extends State<_AddSubscriberSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _reportType = 'both';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Name and email are required');
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await EmailReportService.instance.addSubscription(
        managerName: name,
        email: email,
        reportType: _reportType,
      );
      widget.onAdded();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: const BoxDecoration(
              color: Color(0xFF1A2236),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A4460),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add Manager Subscriber',
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This manager will receive PO spend & session reports',
                  style: GoogleFonts.manrope(
                    color: const Color(0xFF6B7490),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 20),
                _buildField(
                  controller: _nameCtrl,
                  label: 'Manager Name',
                  hint: 'e.g. Rajesh Kumar',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _emailCtrl,
                  label: 'Email Address',
                  hint: 'e.g. manager@goodyear.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                Text(
                  'Report Frequency',
                  style: GoogleFonts.manrope(
                    color: const Color(0xFF8A94B0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildTypeChip('daily', 'Daily', AppTheme.primary),
                    const SizedBox(width: 8),
                    _buildTypeChip('weekly', 'Weekly', const Color(0xFF9C88FF)),
                    const SizedBox(width: 8),
                    _buildTypeChip('both', 'Both', const Color(0xFF4CAF50)),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: GoogleFonts.manrope(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: AnimatedOpacity(
                      opacity: _saving ? 0.6 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Add Subscriber',
                                  style: GoogleFonts.manrope(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            color: const Color(0xFF8A94B0),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1421),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A3450)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.manrope(
                color: const Color(0xFF4A5470),
                fontSize: 13,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFF4A5470), size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String value, String label, Color color) {
    final selected = _reportType == value;
    return GestureDetector(
      onTap: () => setState(() => _reportType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(40) : const Color(0xFF0D1421),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFF2A3450),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            color: selected ? color : const Color(0xFF6B7490),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/email_report_service.dart';
import '../../services/supabase_service.dart';
import '../../services/project_manager.dart';

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
    final pm = ProjectManager.instance;
    final activeProjName = pm.activeProject;
    final isMahindraEV = activeProjName.toLowerCase() == 'mahindra ev poc';

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
          'id, track_name, duration_minutes, total_cost, session_status, started_at, project_name',
        )
        .eq('session_status', 'completed')
        .order('started_at', ascending: false);

    // Additional services
    final servicesData = await client
        .from('session_additional_services')
        .select('session_id, total_cost');

    final Map<String, double> svcCostMap = {};
    for (final s in servicesData as List) {
      final sid = s['session_id'] as String;
      final cost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
      svcCostMap[sid] = (svcCostMap[sid] ?? 0.0) + cost;
    }

    double trackTotal = 0;
    double servicesTotal = 0;
    int sessionCount = 0;
    final List<Map<String, dynamic>> sessionList = [];

    final now = DateTime.now();
    final cutoff = reportType == 'monthly'
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, 1, 1);

    for (final s in sessionsData as List) {
      final rawProj = (s['project_name'] as String?)?.trim() ?? '';
      if (!pm.sessionBelongsToProject(rawProj)) continue;

      final sid = s['id'] as String;
      final track = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
      final svc = svcCostMap[sid] ?? 0.0;
      final startedAt = DateTime.tryParse(s['started_at'] as String? ?? '');

      sessionCount++;

      if (startedAt != null) {
        final isHistorical = isMahindraEV &&
            startedAt.year == 2026 &&
            (startedAt.month == 3 || startedAt.month == 4 || startedAt.month == 5);
        if (!isHistorical) {
          trackTotal += track;
          servicesTotal += svc;
        }

        if (startedAt.isAfter(cutoff)) {
          sessionList.add({
            'trackName': s['track_name'],
            'durationMinutes': s['duration_minutes'],
            'totalCost': track,
            'sessionStatus': s['session_status'],
          });
        }
      } else {
        trackTotal += track;
        servicesTotal += svc;
      }
    }

    double workshopSpend = 0.0;
    if (isMahindraEV) {
      // Add historical overrides (Track = 1,263,500, Accessories = 215,219, Workshop = 245,000)
      trackTotal += 1263500.0;
      servicesTotal += 215219.0;
      workshopSpend = 245000.0;
    }

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
          style: GoogleFonts.spaceGrotesk(
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
                  backgroundColor: const Color(0xFF0A1025),
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
                              _buildNatraxReportCard(),
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
            style: GoogleFonts.spaceGrotesk(
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
              style: GoogleFonts.spaceGrotesk(color: AppTheme.primary),
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
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'PO Spend & Session Summaries — ${ProjectManager.instance.activeProject}',
                style: GoogleFonts.spaceGrotesk(
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
              color: const Color(0xFF0A1025).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
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

  // ── NATRAX VBA-style Expense Report Card ─────────────────────────────────

  Widget _buildNatraxReportCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFB547).withAlpha(100)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB547).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFB547).withAlpha(80)),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFFB547), size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('NATRAX Expense Update',
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('Weekly / Monthly — mirrors VBA macro format',
                        style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF6B7490), fontSize: 11)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              // Recipient preview
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1421),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A3450)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _recipientRow('To', 'Harsh · praharshithkumar_komaragiri@goodyear.com'),
                  const SizedBox(height: 4),
                  _recipientRow('CC', 'v_vimal, ashish_pandit, yeswanth_golla, niranjan_poloju'),
                ]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () => _showNatraxComposeSheet(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB547),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF0F172A), size: 18),
                  label: Text('Compose & Send Report',
                      style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recipientRow(String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 24,
        child: Text(label,
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF6B7490), fontSize: 10, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(value,
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF8A94B0), fontSize: 10)),
      ),
    ]);
  }

  void _showNatraxComposeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NatraxComposeSheet(
        onSent: () {
          Navigator.pop(context);
          _loadData();
        },
      ),
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
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SEND REPORT NOW',
                style: GoogleFonts.spaceGrotesk(
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
                      label: 'Monthly Report',
                      icon: Icons.calendar_month_outlined,
                      color: AppTheme.primary,
                      onTap: _sending ? null : () => _sendNow('monthly'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSendButton(
                      label: 'Yearly Report',
                      icon: Icons.calendar_today_outlined,
                      color: const Color(0xFF9C88FF),
                      onTap: _sending ? null : () => _sendNow('yearly'),
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
                      style: GoogleFonts.spaceGrotesk(
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
                        style: GoogleFonts.spaceGrotesk(
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
                style: GoogleFonts.spaceGrotesk(
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
              style: GoogleFonts.spaceGrotesk(
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
                      style: GoogleFonts.spaceGrotesk(
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
                  color: const Color(0xFF0A1025).withAlpha(200),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF849495).withAlpha(120),
                  ),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.group_outlined,
                        color: const Color(0xFF849495),
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No subscribers yet',
                        style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF6B7490),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add manager emails to receive monthly/yearly reports',
                        style: GoogleFonts.spaceGrotesk(
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
                  color: const Color(0xFF0A1025).withAlpha(200),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF849495).withAlpha(120),
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
    final typeColor = sub.reportType == 'monthly'
        ? AppTheme.primary
        : sub.reportType == 'yearly'
        ? const Color(0xFF9C88FF)
        : const Color(0xFF4CAF50);

    final typeLabel = sub.reportType == 'monthly'
        ? 'Monthly'
        : sub.reportType == 'yearly'
        ? 'Yearly'
        : 'Monthly + Yearly';

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
                    style: GoogleFonts.spaceGrotesk(
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
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub.email,
                      style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub.lastSentAt != null)
                      Text(
                        'Last sent: ${_formatDate(sub.lastSentAt!)}',
                        style: GoogleFonts.spaceGrotesk(
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
                  style: GoogleFonts.spaceGrotesk(
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
                      backgroundColor: const Color(0xFF0A1025),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: Text(
                        'Remove Subscriber',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      content: Text(
                        'Remove ${sub.managerName} from report subscribers?',
                        style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF8A94B0),
                          fontSize: 13,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.spaceGrotesk(
                              color: const Color(0xFF6B7490),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            'Remove',
                            style: GoogleFonts.spaceGrotesk(
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
          style: GoogleFonts.spaceGrotesk(
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
                color: const Color(0xFF0A1025).withAlpha(200),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF849495).withAlpha(120),
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
    final typeColor = log.reportType == 'monthly'
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
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatDate(log.sentAt),
                      style: GoogleFonts.spaceGrotesk(
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
                  style: GoogleFonts.spaceGrotesk(
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
                  style: GoogleFonts.spaceGrotesk(
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

// ── NATRAX Compose Sheet ──────────────────────────────────────────────────────

class _NatraxComposeSheet extends StatefulWidget {
  final VoidCallback onSent;
  const _NatraxComposeSheet({required this.onSent});

  @override
  State<_NatraxComposeSheet> createState() => _NatraxComposeSheetState();
}

class _NatraxComposeSheetState extends State<_NatraxComposeSheet> {
  String _reportType = 'monthly'; // 'weekly' | 'monthly'
  final _vehicleCtrl = TextEditingController(text: 'Mahindra XEV 9e');
  final _toCtrl = TextEditingController(text: 'praharshithkumar_komaragiri@goodyear.com');
  final _ccCtrl = TextEditingController(text: 'v_vimal@goodyear.com, ashish_pandit@goodyear.com, yeswanth_golla@goodyear.com, niranjan_poloju@goodyear.com');
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  bool _previewing = false;
  bool _loadingBody = false;
  String? _error;

  DateTime _periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _periodEnd = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
  final DateTime _overallStart = DateTime(2026, 3, 22);

  final _inrFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadDefaultBody();
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => DateFormat('dd-MMM-yy').format(d);
  String _monthYear(DateTime d) => DateFormat('MMMM yyyy').format(d).toUpperCase();

  Future<void> _loadDefaultBody() async {
    if (_vehicleCtrl.text.trim().isEmpty) return;
    setState(() {
      _loadingBody = true;
      _error = null;
    });
    try {
      final data = await EmailReportService.instance.generateNatraxReportData(
        reportType: _reportType,
        vehicleName: _vehicleCtrl.text.trim(),
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        overallStart: _overallStart,
        overallEnd: _periodEnd,
      );
      final rawHtml = data['html'] as String? ?? '';
      // Strip HTML tags for clean text editing
      final cleanText = rawHtml
          .replaceAll('<br>', '\n')
          .replaceAll('<br/>', '\n')
          .replaceAll('<br />', '\n')
          .replaceAll('<b>', '')
          .replaceAll('</b>', '')
          .replaceAll(RegExp(r'<table[^>]*>'), '\n')
          .replaceAll(RegExp(r'</table[^>]*>'), '\n')
          .replaceAll(RegExp(r'<tr[^>]*>'), '')
          .replaceAll(RegExp(r'</tr[^>]*>'), '\n')
          .replaceAll(RegExp(r'<td[^>]*>'), ' | ')
          .replaceAll(RegExp(r'</td[^>]*>'), '')
          .replaceAll(RegExp(r'<th[^>]*>'), ' | ')
          .replaceAll(RegExp(r'</th[^>]*>'), '')
          .replaceAll(RegExp(r'<p[^>]*>'), '\n')
          .replaceAll(RegExp(r'</p[^>]*>'), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '');

      setState(() {
        _bodyCtrl.text = cleanText.trim();
        _loadingBody = false;
      });
    } catch (e) {
      setState(() {
        _loadingBody = false;
        _error = 'Failed to generate default report content: $e';
      });
    }
  }

  void _onTypeChanged(String type) {
    setState(() {
      _reportType = type;
      final now = DateTime.now();
      if (type == 'weekly') {
        final weekday = now.weekday;
        _periodStart = now.subtract(Duration(days: weekday - 1));
        _periodEnd = now;
      } else {
        _periodStart = DateTime(now.year, now.month, 1);
        _periodEnd = DateTime(now.year, now.month + 1, 0);
      }
    });
    _loadDefaultBody();
  }

  Future<void> _send() async {
    if (_vehicleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a vehicle name');
      return;
    }
    setState(() { _sending = true; _error = null; });
    try {
      final ccList = _ccCtrl.text.split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // Convert edit body newlines to HTML breaks for email delivery
      final bodyHtml = _bodyCtrl.text.trim().replaceAll('\n', '<br>');

      final result = await EmailReportService.instance.sendNatraxExpenseReport(
        reportType: _reportType,
        vehicleName: _vehicleCtrl.text.trim(),
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        overallStart: _overallStart,
        overallEnd: _periodEnd,
        customToEmail: _toCtrl.text.trim(),
        customCcEmails: ccList,
        customHtmlBody: bodyHtml,
      );
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('✓ Report sent successfully', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
            backgroundColor: const Color(0xFF4CAF50).withAlpha(220),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
          widget.onSent();
        }
      } else {
        setState(() => _error = result['error']?.toString() ?? 'Send failed');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _preview() async {
    if (_vehicleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a vehicle name');
      return;
    }

    final previewData = {
      'subject': _reportType == 'weekly'
          ? 'Weekly Test track costs - ${_vehicleCtrl.text.trim()} (${_fmtDate(_periodStart)} to ${_fmtDate(_periodEnd)})'
          : 'Monthly Test track costs - ${_vehicleCtrl.text.trim()} (${_monthYear(_periodStart)})',
      'vehicleName': _vehicleCtrl.text.trim(),
      'periodLabel': _reportType == 'weekly'
          ? 'WEEKLY UPDATE (${_fmtDate(_periodStart)} to ${_fmtDate(_periodEnd)})'
          : 'MONTHLY UPDATE — ${_monthYear(_periodStart)}',
      'toEmail': _toCtrl.text.trim(),
      'ccEmails': _ccCtrl.text.trim(),
      'body': _bodyCtrl.text.trim(),
    };

    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(190),
      builder: (_) => _NatraxEmailPreviewDialog(
        data: previewData,
        onSend: () {
          Navigator.pop(context);
          _send();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: const Color(0xFF0A1025),
            child: ListView(
              controller: ctrl,
              padding: EdgeInsets.fromLTRB(24, 0, 24,
                  MediaQuery.of(context).viewInsets.bottom + 32),
              children: [
                const SizedBox(height: 12),
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFF849495),
                      borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 20),
                Text('Compose NATRAX Report',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Edit details, recipients and body content before sending',
                    style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490), fontSize: 12)),
                const SizedBox(height: 20),

                // Report type
                Text('Report Type', style: _labelStyle()),
                const SizedBox(height: 8),
                Row(children: [
                  _typeChip('weekly', 'Weekly', const Color(0xFF4A9EFF)),
                  const SizedBox(width: 8),
                  _typeChip('monthly', 'Monthly', const Color(0xFFFFB547)),
                ]),
                const SizedBox(height: 16),

                // Vehicle name
                Text('Vehicle Name / Model', style: _labelStyle()),
                const SizedBox(height: 6),
                _field(controller: _vehicleCtrl, hint: 'e.g. Mahindra XEV 9e',
                    icon: Icons.directions_car_outlined),
                const SizedBox(height: 16),

                // Recipients (Editable)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recipients', style: _labelStyle()),
                    Text(
                      'Editable',
                      style: GoogleFonts.spaceGrotesk(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _field(
                  controller: _toCtrl,
                  hint: 'To: manager@goodyear.com',
                  icon: Icons.email_outlined,
                ),
                const SizedBox(height: 8),
                _field(
                  controller: _ccCtrl,
                  hint: 'CC: email1@goodyear.com, email2@goodyear.com',
                  icon: Icons.copy_all_outlined,
                ),
                const SizedBox(height: 16),

                // Date range display
                Text('Period', style: _labelStyle()),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1421),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A3450)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.date_range_outlined, color: Color(0xFF4A5470), size: 18),
                    const SizedBox(width: 10),
                    Text('${dateFmt.format(_periodStart)}  →  ${dateFmt.format(_periodEnd)}',
                        style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 4),
                Text('Overall project start: ${dateFmt.format(_overallStart)}',
                    style: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 11)),
                const SizedBox(height: 16),

                // Email Body
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Email Body', style: _labelStyle()),
                    if (_loadingBody)
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primary))
                    else
                      GestureDetector(
                        onTap: _loadDefaultBody,
                        child: Text(
                          'Reset to Autogenerated',
                          style: GoogleFonts.spaceGrotesk(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1421),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2A3450)),
                  ),
                  child: TextField(
                    controller: _bodyCtrl,
                    maxLines: 8,
                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 13, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'Email body content...',
                      hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Info warning
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB547).withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFB547).withAlpha(40)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: Color(0xFFFFB547), size: 14),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Workshop rental is pre-calculated at ₹5,000/day. '
                      'Editing the body text allows overriding the final presentation before dispatch.',
                      style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF8A94B0), fontSize: 11, height: 1.5),
                    )),
                  ]),
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
                    child: Text(_error!,
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.redAccent, fontSize: 12)),
                  ),
                ],

                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _previewing ? null : _preview,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF4A9EFF)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _previewing
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A9EFF)))
                          : const Icon(Icons.preview_rounded, color: Color(0xFF4A9EFF), size: 16),
                      label: Text('Preview',
                          style: GoogleFonts.spaceGrotesk(
                              color: const Color(0xFF4A9EFF), fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB547),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _sending
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                          : const Icon(Icons.send_rounded, color: Color(0xFF0F172A), size: 16),
                      label: Text(_sending ? 'Sending…' : 'Send Report',
                          style: GoogleFonts.spaceGrotesk(
                              color: const Color(0xFF0F172A), fontWeight: FontWeight.w800)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle() => GoogleFonts.spaceGrotesk(
      color: const Color(0xFF8A94B0), fontSize: 12, fontWeight: FontWeight.w600);

  Widget _typeChip(String value, String label, Color color) {
    final sel = _reportType == value;
    return GestureDetector(
      onTap: () => _onTypeChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? color.withAlpha(40) : const Color(0xFF0D1421),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : const Color(0xFF2A3450),
              width: sel ? 1.5 : 1),
        ),
        child: Text(label, style: GoogleFonts.spaceGrotesk(
            color: sel ? color : const Color(0xFF6B7490),
            fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _field({required TextEditingController controller,
      required String hint, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1421),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3450)),
      ),
      child: TextField(
        controller: controller,
        style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF4A5470), size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _recipientLine(String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 24,
          child: Text(label, style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF6B7490), fontSize: 10, fontWeight: FontWeight.w700))),
      const SizedBox(width: 6),
      Expanded(child: Text(value, style: GoogleFonts.spaceGrotesk(
          color: const Color(0xFF8A94B0), fontSize: 10))),
    ]);
  }
}

// ── NATRAX Email Preview Dialog ───────────────────────────────────────────────

class _NatraxEmailPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onSend;
  const _NatraxEmailPreviewDialog({required this.data, required this.onSend});

  static const _from = 'dhrupad_ma@goodyear.com';

  @override
  Widget build(BuildContext context) {
    final subject  = data['subject']  as String? ?? '';
    final toEmail  = data['toEmail']  as String? ?? '';
    final ccEmails = data['ccEmails'] as String? ?? '';
    final body     = data['body']     as String? ?? '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 720,
            constraints: const BoxConstraints(maxHeight: 740),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFB547).withAlpha(80)),
            ),
            child: Column(children: [
              // ── Header ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 18, 14),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withAlpha(12))),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB547).withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.preview_rounded, color: Color(0xFFFFB547), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Email Preview',
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('Review before sending report',
                        style: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 11)),
                  ])),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close_rounded, color: Colors.white.withAlpha(100), size: 20),
                  ),
                ]),
              ),

              // ── Email metadata ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Column(children: [
                  _meta('From',    _from,    const Color(0xFF94A3B8)),
                  _meta('To',      toEmail,  AppTheme.primary),
                  _meta('CC',      ccEmails, const Color(0xFF94A3B8)),
                  _meta('Subject', subject,  Colors.white),
                  const SizedBox(height: 10),
                  Container(height: 1, color: Colors.white.withAlpha(8)),
                ]),
              ),

              // ── Body preview ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email chrome header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF00416A), Color(0xFF003d5c)]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Text('NATRAX TrackLog · Expense Update',
                              style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text('dhrupad_ma@goodyear.com',
                              style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white60, fontSize: 9)),
                        ]),
                      ),

                      SelectableText(
                        body,
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Actions ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white.withAlpha(8)))),
                child: Row(children: [
                  _channelChip(Icons.email_rounded, 'Email', AppTheme.primary),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Edit', style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490), fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onSend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB547),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.send_rounded, color: Color(0xFF0F172A), size: 15),
                    label: Text('Confirm & Send',
                        style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _meta(String label, String value, Color col) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 56, child: Text(label,
          style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF4A5470), fontSize: 10, fontWeight: FontWeight.w600))),
      const SizedBox(width: 6),
      Expanded(child: Text(value,
          style: GoogleFonts.spaceGrotesk(color: col, fontSize: 11),
          overflow: TextOverflow.ellipsis, maxLines: 2)),
    ]),
  );

  Widget _channelChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(label, style: GoogleFonts.spaceGrotesk(
            color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
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
  String _reportType = 'monthly';
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
              color: Color(0xFF0A1025),
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
                      color: const Color(0xFF849495),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add Manager Subscriber',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This manager will receive PO spend & session reports',
                  style: GoogleFonts.spaceGrotesk(
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
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF8A94B0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildTypeChip('monthly', 'Monthly', AppTheme.primary),
                    const SizedBox(width: 8),
                    _buildTypeChip('yearly', 'Yearly', const Color(0xFF9C88FF)),
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
                            style: GoogleFonts.spaceGrotesk(
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
                                  style: GoogleFonts.spaceGrotesk(
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
          style: GoogleFonts.spaceGrotesk(
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
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.spaceGrotesk(
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
          style: GoogleFonts.spaceGrotesk(
            color: selected ? color : const Color(0xFF6B7490),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

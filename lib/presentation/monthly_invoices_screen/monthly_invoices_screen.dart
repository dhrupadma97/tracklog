import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/project_manager.dart';
import '../../theme/app_theme.dart';

// ─── Data models ──────────────────────────────────────────────────────────────
class _Session {
  final String id;
  final String trackName;
  final String trackCode;
  final DateTime date;
  final int durationMinutes;
  final double trackCostExcl;
  final double svcCostExcl;
  final String? projectName;
  final String? notes;

  double get subtotalExcl => trackCostExcl + svcCostExcl;
  double get gst => subtotalExcl * 0.18;
  double get totalIncl => subtotalExcl * 1.18;

  const _Session({
    required this.id,
    required this.trackName,
    required this.trackCode,
    required this.date,
    required this.durationMinutes,
    required this.trackCostExcl,
    required this.svcCostExcl,
    this.projectName,
    this.notes,
  });
}

class _MonthGroup {
  final String monthKey; // 'YYYY-MM'
  final String label;    // 'April 2026'
  final List<_Session> sessions;
  final double workshopRental;
  final double? overriddenTrack;
  final double? overriddenAccessories;

  double get trackCost =>
      overriddenTrack ?? sessions.fold(0.0, (s, e) => s + e.trackCostExcl);
  double get accessoriesCost =>
      overriddenAccessories ?? sessions.fold(0.0, (s, e) => s + e.svcCostExcl);

  double get trackAcc => trackCost + accessoriesCost;
  double get subtotalExcl => trackAcc + workshopRental;
  double get gst => subtotalExcl * 0.18;
  double get totalIncl => subtotalExcl * 1.18;
  int get totalMinutes =>
      sessions.fold(0, (s, e) => s + e.durationMinutes);

  _MonthGroup({
    required this.monthKey,
    required this.label,
    required this.sessions,
    required this.workshopRental,
    this.overriddenTrack,
    this.overriddenAccessories,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class MonthlyInvoicesScreen extends StatefulWidget {
  const MonthlyInvoicesScreen({super.key});
  @override
  State<MonthlyInvoicesScreen> createState() => _MonthlyInvoicesScreenState();
}

class _MonthlyInvoicesScreenState extends State<MonthlyInvoicesScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  List<_MonthGroup> _months = [];
  int _selectedMonthIdx = 0;
  String _activeProject = '';

  late TabController _tabController;

  // Formatters
  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final _usd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

  String _fmtUsd(double inr) => _usd.format(inr / 83.0);

  // Workshop rental breakdown (from excel_data.json)
  static const _workshopByMonth = {
    '2026-03': 55000.0,
    '2026-04': 150000.0,
    '2026-05': 40000.0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _activeProject = ProjectManager.instance.activeProject;
    ProjectManager.instance.addListener(_onProjectChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    ProjectManager.instance.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted && _activeProject != ProjectManager.instance.activeProject) {
      setState(() {
        _activeProject = ProjectManager.instance.activeProject;
        _selectedMonthIdx = 0;
      });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;

      final sessionsRaw = await client
          .from('engineer_sessions')
          .select(
              'id, track_name, track_code, started_at, duration_minutes, total_cost, session_status, project_name, notes')
          .eq('session_status', 'completed')
          .order('started_at', ascending: false);

      final sessionIds = (sessionsRaw as List).map((s) => s['id'] as String).toList();
      List<dynamic> svcsRaw = [];
      if (sessionIds.isNotEmpty) {
        svcsRaw = await client
            .from('session_additional_services')
            .select('session_id, total_cost')
            .inFilter('session_id', sessionIds);
      }

      final Map<String, double> svcMap = {};
      for (final svc in svcsRaw) {
        final sid = svc['session_id'] as String;
        final c = (svc['total_cost'] as num?)?.toDouble() ?? 0.0;
        svcMap[sid] = (svcMap[sid] ?? 0) + c;
      }

      // Map raw session to _Session
      final allSessions = <_Session>[];
      for (final s in sessionsRaw) {
        final rawProj = (s['project_name'] as String?)?.trim() ?? '';
        final projName = (rawProj.isEmpty || rawProj.toLowerCase() == 'general')
            ? 'Mahindra EV PoC'
            : rawProj;

        // Filter by active project
        final pm = ProjectManager.instance;
        if (!pm.sessionBelongsToProject(rawProj)) continue;

        final date = DateTime.tryParse(s['started_at'] as String? ?? '') ?? DateTime.now();
        allSessions.add(_Session(
          id: s['id'] as String,
          trackName: s['track_name'] as String? ?? '—',
          trackCode: s['track_code'] as String? ?? '',
          date: date,
          durationMinutes: s['duration_minutes'] as int? ?? 0,
          trackCostExcl: (s['total_cost'] as num?)?.toDouble() ?? 0.0,
          svcCostExcl: svcMap[s['id'] as String] ?? 0.0,
          projectName: projName,
          notes: s['notes'] as String?,
        ));
      }

      // Group by month
      final Map<String, List<_Session>> byMonth = {};
      for (final s in allSessions) {
        final mk = s.date.toIso8601String().substring(0, 7);
        byMonth.putIfAbsent(mk, () => []).add(s);
      }

      final monthGroups = byMonth.entries.map((e) {
        final dt = DateTime.parse('${e.key}-01');
        final label = DateFormat('MMMM yyyy').format(dt);
        // Only attach workshop rental to Mahindra EV PoC
        final isMahindraEV = _activeProject.toLowerCase() == 'mahindra ev poc';
        final rental = isMahindraEV
            ? (_workshopByMonth[e.key] ?? 0.0)
            : 0.0;
            
        // Separate overrides for Track and Accessories from Excel sheet for Mahindra EV PoC
        const historicalTrack = {
          '2026-03': 133000.0,
          '2026-04': 966000.0,
          '2026-05': 164500.0,
        };
        const historicalAccessories = {
          '2026-03': 5605.0,
          '2026-04': 36375.0,
          '2026-05': 173239.0,
        };
        final double? overriddenTrack = isMahindraEV ? historicalTrack[e.key] : null;
        final double? overriddenAccessories = isMahindraEV ? historicalAccessories[e.key] : null;

        return _MonthGroup(
          monthKey: e.key,
          label: label,
          sessions: e.value..sort((a, b) => a.date.compareTo(b.date)),
          workshopRental: rental,
          overriddenTrack: overriddenTrack,
          overriddenAccessories: overriddenAccessories,
        );
      }).toList()
        ..sort((a, b) => b.monthKey.compareTo(a.monthKey));

      if (mounted) {
        setState(() {
          _months = monthGroups;
          _selectedMonthIdx = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  _MonthGroup? get _selected =>
      _months.isEmpty ? null : _months[_selectedMonthIdx];

  double get _grandTotalIncl =>
      _months.fold(0.0, (s, m) => s + m.totalIncl);
  double get _grandTotalExcl =>
      _months.fold(0.0, (s, m) => s + m.subtotalExcl);
  int get _totalSessions =>
      _months.fold(0, (s, m) => s + m.sessions.length);

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: Stack(
        children: [
          // Ambient glows
          Positioned(
            top: -120, left: -100,
            child: Container(
              width: 480, height: 380,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [
                  AppTheme.primary.withOpacity(0.07),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: -80, right: -60,
            child: Container(
              width: 360, height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [
                  const Color(0xFF4A9EFF).withOpacity(0.06),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 1.5))
                : Column(
                    children: [
                      _buildHeader(),
                      _buildKpiSummaryRow(),
                      _buildMonthTabs(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildBreakdownTab(),
                            _buildSessionHistoryTab(),
                            _buildChartTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final pm = ProjectManager.instance;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('EXPENSE ANALYSER',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppTheme.primary, letterSpacing: 3)),
              const SizedBox(height: 4),
              Text(_activeProject,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('NATRAX Proving Ground · All Sessions',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: const Color(0xFF94A3B8))),
            ]),
          ),
          // Project badge
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.layers_rounded, color: AppTheme.primary, size: 14),
                const SizedBox(width: 6),
                Text(_activeProject.split(' ').first,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSummaryRow() {
    final kpis = [
      _KpiData('TOTAL INCL. GST', _compact.format(_grandTotalIncl), AppTheme.primary,
          sub: _fmtUsd(_grandTotalIncl)),
      _KpiData('EXCL. GST', _compact.format(_grandTotalExcl), const Color(0xFF94A3B8)),
      _KpiData('SESSIONS', '$_totalSessions', const Color(0xFF4A9EFF)),
      _KpiData('MONTHS', '${_months.length}', const Color(0xFFA855F7)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520).withOpacity(0.8),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: kpis.map((k) => Expanded(child: _buildKpi(k))).toList(),
      ),
    );
  }

  Widget _buildKpi(_KpiData k) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(k.label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 8, fontWeight: FontWeight.w700,
              color: k.color.withOpacity(0.7), letterSpacing: 1.5)),
      const SizedBox(height: 3),
      Text(k.value,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
      if (k.sub != null)
        Text(k.sub!,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10, color: const Color(0xFF94A3B8))),
    ]);
  }

  Widget _buildMonthTabs() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _months.length + 1,
        itemBuilder: (_, i) {
          if (i == _months.length) {
            // "All" tab
            final isSelected = false; // no-op for now
            return const SizedBox.shrink();
          }
          final m = _months[i];
          final isSelected = _selectedMonthIdx == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedMonthIdx = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary.withOpacity(0.5)
                      : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(m.label,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: isSelected ? AppTheme.primary : const Color(0xFF94A3B8))),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBreakdownTab() {
    if (_selected == null || _months.isEmpty) {
      return _emptyState('No data available for this project');
    }
    final m = _selected!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // Section tabs (overview | sessions | chart)
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1520).withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: const Color(0xFF94A3B8),
            indicatorColor: AppTheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Breakdown'),
              Tab(text: 'Sessions'),
              Tab(text: 'Trend Chart'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Monthly summary card
        _buildMonthSummaryCard(m),
        const SizedBox(height: 16),
        // Cost breakdown bars
        _buildCostBreakdownBars(m),
        const SizedBox(height: 16),
        // Workshop rental card (if any)
        if (m.workshopRental > 0) _buildWorkshopCard(m),
      ],
    );
  }

  Widget _buildMonthSummaryCard(_MonthGroup m) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withOpacity(0.08),
            const Color(0xFF0D1520).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.06), blurRadius: 24)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(m.label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
              ),
              child: Text('${m.sessions.length} sessions',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ),
          ]),
          const SizedBox(height: 16),

          // Main total (INR + USD)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_compact.format(m.totalIncl),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.primary)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('(${_fmtUsd(m.totalIncl)} USD)',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, color: const Color(0xFF94A3B8))),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Incl. 18% GST', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8))),

          const SizedBox(height: 20),
          _divider(),
          const SizedBox(height: 16),

          // Breakdown
          _rowItem('Track Access', m.trackCost, m.trackCost * 1.18, AppTheme.primary),
          const SizedBox(height: 8),
          _rowItem('Accessories & Services', m.accessoriesCost, m.accessoriesCost * 1.18, const Color(0xFF10B981)),
          const SizedBox(height: 8),
          if (m.workshopRental > 0) ...[
            _rowItem('Workshop Rental', m.workshopRental, m.workshopRental * 1.18, const Color(0xFFF59E0B)),
            const SizedBox(height: 8),
          ],
          _rowItem('Subtotal (Excl. GST)', m.subtotalExcl, null, Colors.white),
          _divider(),
          const SizedBox(height: 8),
          _rowItem('GST @ 18%', m.gst, null, const Color(0xFF94A3B8)),
          const SizedBox(height: 8),
          _rowItem('TOTAL PAYABLE', m.totalIncl, null, AppTheme.primary, bold: true),
        ],
      ),
    );
  }

  Widget _rowItem(String label, double val, double? inclVal, Color color, {bool bold = false}) {
    return Row(children: [
      Text(label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 11, color: color.withOpacity(bold ? 1.0 : 0.8),
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      const Spacer(),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(_inr.format(val),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 12, color: color,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        if (inclVal != null)
          Text('${_fmtUsd(inclVal)} incl.',
              style: GoogleFonts.spaceGrotesk(fontSize: 9, color: const Color(0xFF6B7490))),
      ]),
    ]);
  }

  Widget _buildCostBreakdownBars(_MonthGroup m) {
    final total = m.subtotalExcl;
    if (total == 0) return const SizedBox.shrink();
    final trackPct = (m.trackCost / total).clamp(0.0, 1.0);
    final accPct = (m.accessoriesCost / total).clamp(0.0, 1.0);
    final rentalPct = m.workshopRental > 0 ? (m.workshopRental / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520).withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COST COMPOSITION',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            if (trackPct > 0)
              Flexible(
                flex: (trackPct * 100).round(),
                child: Container(height: 10, color: AppTheme.primary),
              ),
            if (accPct > 0)
              Flexible(
                flex: (accPct * 100).round(),
                child: Container(height: 10, color: const Color(0xFF10B981)),
              ),
            if (rentalPct > 0)
              Flexible(
                flex: (rentalPct * 100).round(),
                child: Container(height: 10, color: const Color(0xFFF59E0B)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(AppTheme.primary),
                const SizedBox(width: 6),
                Text('Track Access  ${(trackPct * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8))),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendDot(const Color(0xFF10B981)),
                const SizedBox(width: 6),
                Text('Accessories & Services  ${(accPct * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8))),
              ],
            ),
            if (rentalPct > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _legendDot(const Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Text('Workshop Rental  ${(rentalPct * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8))),
                ],
              ),
          ],
        ),
      ]),
    );
  }

  Widget _legendDot(Color c) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _buildWorkshopCard(_MonthGroup m) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.warehouse_rounded, color: Color(0xFFF59E0B), size: 24),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Workshop Rental',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('NATRAX Workshop Facility',
              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_inr.format(m.workshopRental),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFF59E0B))),
          Text('Excl. GST',
              style: GoogleFonts.spaceGrotesk(fontSize: 9, color: const Color(0xFF94A3B8))),
        ]),
      ]),
    );
  }

  Widget _buildSessionHistoryTab() {
    if (_selected == null || _months.isEmpty) {
      return _emptyState('No sessions found');
    }
    final sessions = _selected!.sessions;
    if (sessions.isEmpty) return _emptyState('No sessions this month');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final s = sessions[i];
        final dayStr = DateFormat('d MMM').format(s.date);
        final timeStr = DateFormat('HH:mm').format(s.date);
        final hrs = s.durationMinutes ~/ 60;
        final mins = s.durationMinutes % 60;
        final durationLabel = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1520).withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date bubble
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(dayStr.split(' ').first,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                  Text(dayStr.split(' ').last,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 8, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(s.trackName,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(_inr.format(s.trackCostExcl * 1.18),
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    _badge(s.trackCode.toUpperCase(), const Color(0xFF4A9EFF)),
                    const SizedBox(width: 6),
                    _badge('$timeStr · $durationLabel', const Color(0xFF94A3B8)),
                  ]),
                  if (s.notes != null && s.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(s.notes!,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10, color: const Color(0xFF6B7490)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  if (s.svcCostExcl > 0) ...[
                    const SizedBox(height: 6),
                    Text('+ ${_inr.format(s.svcCostExcl * 1.18)} accessories/services (incl. GST)',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10, color: const Color(0xFF10B981))),
                  ],
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChartTab() {
    if (_months.isEmpty) return _emptyState('No chart data');

    // Reverse to show oldest → newest
    final chartMonths = _months.reversed.toList();
    final maxVal = chartMonths.fold(0.0, (m, g) => g.totalIncl > m ? g.totalIncl : m);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          height: 280,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1520).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: BarChart(
            BarChartData(
              maxY: maxVal * 1.15,
              barGroups: chartMonths.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.totalIncl,
                      width: 28,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      rodStackItems: [
                        BarChartRodStackItem(
                          0,
                          e.value.trackCost * 1.18,
                          AppTheme.primary,
                        ),
                        BarChartRodStackItem(
                          e.value.trackCost * 1.18,
                          (e.value.trackCost + e.value.accessoriesCost) * 1.18,
                          const Color(0xFF10B981),
                        ),
                        if (e.value.workshopRental > 0)
                          BarChartRodStackItem(
                            (e.value.trackCost + e.value.accessoriesCost) * 1.18,
                            e.value.totalIncl,
                            const Color(0xFFF59E0B),
                          ),
                      ],
                    ),
                  ],
                );
              }).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) {
                      final idx = val.toInt();
                      if (idx < 0 || idx >= chartMonths.length) return const SizedBox.shrink();
                      final label = DateFormat('MMM').format(
                        DateTime.parse('${chartMonths[idx].monthKey}-01'),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(label,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10, color: const Color(0xFF94A3B8))),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    getTitlesWidget: (val, meta) {
                      if (val == 0) return const SizedBox.shrink();
                      return Text(_compact.format(val),
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, color: const Color(0xFF6B7490)));
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) {
                    final m = chartMonths[group.x];
                    return BarTooltipItem(
                      '${m.label}\n',
                      GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                      children: [
                        TextSpan(
                          text: 'Track: ${_inr.format(m.trackCost * 1.18)}\n',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, color: AppTheme.primary, fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: 'Accessories: ${_inr.format(m.accessoriesCost * 1.18)}\n',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                        ),
                        if (m.workshopRental > 0)
                          TextSpan(
                            text: 'Workshop: ${_inr.format(m.workshopRental * 1.18)}\n',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 9, color: const Color(0xFFF59E0B), fontWeight: FontWeight.w600),
                          ),
                        TextSpan(
                          text: 'Total: ${_inr.format(m.totalIncl)}',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Monthly summary table
        Text('MONTHLY BREAKDOWN',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: const Color(0xFF94A3B8), letterSpacing: 1.5)),
        const SizedBox(height: 12),

        ...chartMonths.asMap().entries.map((e) {
          final m = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1520).withOpacity(0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: e.key == chartMonths.length - 1
                    ? AppTheme.primary.withOpacity(0.3)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.label,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text('${m.sessions.length} sessions · ${_compact.format(m.subtotalExcl)} excl.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8))),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_compact.format(m.totalIncl),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                Text(_fmtUsd(m.totalIncl),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, color: const Color(0xFF6B7490))),
              ]),
            ]),
          );
        }),

        // Grand total
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.primary.withOpacity(0.12),
              AppTheme.primary.withOpacity(0.04),
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GRAND TOTAL — $_activeProject',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary, letterSpacing: 1)),
              Text('All months · incl. 18% GST',
                  style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_compact.format(_grandTotalIncl),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primary)),
              Text(_fmtUsd(_grandTotalIncl),
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF94A3B8))),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _divider() =>
      Container(height: 1, color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.symmetric(vertical: 4));

  Widget _emptyState(String msg) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.analytics_outlined, color: Colors.white.withOpacity(0.15), size: 48),
        const SizedBox(height: 12),
        Text(msg,
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFF6B7490))),
      ]),
    );
  }
}

class _KpiData {
  final String label;
  final String value;
  final Color color;
  final String? sub;
  const _KpiData(this.label, this.value, this.color, {this.sub});
}

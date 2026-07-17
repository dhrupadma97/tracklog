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
  final double? trackAccOverride;

  double get trackAcc =>
      trackAccOverride ?? sessions.fold(0.0, (s, e) => s + e.subtotalExcl);
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
    this.trackAccOverride,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class MonthlyInvoicesScreen extends StatefulWidget {
  const MonthlyInvoicesScreen({super.key});
  @override
  State<MonthlyInvoicesScreen> createState() => _MonthlyInvoicesScreenState();
}

class _MonthlyInvoicesScreenState extends State<MonthlyInvoicesScreen> {
  bool _isLoading = true;
  List<_MonthGroup> _months = [];
  int _selectedMonthIdx = 0;
  String _activeProject = '';

  // Formatters
  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final _usd = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

  String _fmtUsd(double inr) => _usd.format(inr / 83.0);

  Color get primaryColor => AppTheme.primary;

  Color _getTrackColor(String trackKey) {
    final key = trackKey.toUpperCase();
    if (key.contains('T1') || key.contains('HST')) {
      return const Color(0xFF00F3FF); // Cyan
    } else if (key.contains('T2') || key.contains('DYN')) {
      return const Color(0xFFFFB547); // Orange/Yellow
    } else if (key.contains('T3') || key.contains('BRK') || key.contains('WET')) {
      return const Color(0xFFFF4D6A); // Red
    } else if (key.contains('T7') || key.contains('HDL')) {
      return const Color(0xFFA855F7); // Purple
    } else if (key.contains('T8') || key.contains('CMF')) {
      return const Color(0xFF4ADE80); // Green
    } else if (key.contains('T11') || key.contains('WSP')) {
      return const Color(0xFF38BDF8); // Light Blue
    }
    return const Color(0xFFFF6B00); // Proving Ground Orange fallback
  }

  // ── Canonical Excel data: NATRAX_Comprehensive_Billing_Final_V15 ──────────
  static const _workshopByMonth = {
    '2026-03': 55000.0,
    '2026-04': 150000.0,
    '2026-05': 40000.0,
  };

  static const _trackAccByMonth = {
    '2026-03': 138605.0,
    '2026-04': 1002375.0,
    '2026-05': 337739.0,
  };

  @override
  void initState() {
    super.initState();
    _activeProject = ProjectManager.instance.activeProject;
    ProjectManager.instance.addListener(_onProjectChanged);
    _loadData();
  }

  @override
  void dispose() {
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

      final allSessions = <_Session>[];
      for (final s in sessionsRaw) {
        final rawProj = (s['project_name'] as String?)?.trim() ?? '';
        final projName = (rawProj.isEmpty || rawProj.toLowerCase() == 'general')
            ? 'Mahindra EV PoC'
            : rawProj;

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

      final Map<String, List<_Session>> byMonth = {};
      for (final s in allSessions) {
        final mk = s.date.toIso8601String().substring(0, 7);
        byMonth.putIfAbsent(mk, () => []).add(s);
      }

      final isMahindraEV = _activeProject.toLowerCase() == 'mahindra ev poc';

      final monthGroups = byMonth.entries.map((e) {
        final dt = DateTime.parse('${e.key}-01');
        final label = DateFormat('MMMM yyyy').format(dt);
        final rental = isMahindraEV ? (_workshopByMonth[e.key] ?? 0.0) : 0.0;
        final trackAccOverride = isMahindraEV ? _trackAccByMonth[e.key] : null;
        return _MonthGroup(
          monthKey: e.key,
          label: label,
          sessions: e.value..sort((a, b) => a.date.compareTo(b.date)),
          workshopRental: rental,
          trackAccOverride: trackAccOverride,
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

  _MonthGroup? get _allMonthsGroup {
    if (_months.isEmpty) return null;
    final allSessions = _months.expand((m) => m.sessions).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final totalWorkshop = _months.fold(0.0, (s, m) => s + m.workshopRental);
    final totalTrackAccOverride = _months.any((m) => m.trackAccOverride != null)
        ? _months.fold(0.0, (s, m) => s + (m.trackAccOverride ?? m.trackAcc))
        : null;
    return _MonthGroup(
      monthKey: 'all',
      label: 'All Months',
      sessions: allSessions,
      workshopRental: totalWorkshop,
      trackAccOverride: totalTrackAccOverride,
    );
  }

  _MonthGroup? get _selected {
    if (_months.isEmpty) return null;
    if (_selectedMonthIdx == _months.length) {
      return _allMonthsGroup;
    }
    return _months[_selectedMonthIdx];
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF042024), // Premium deep teal-green gradient start
              const Color(0xFF030712), // Dark space black gradient end
            ],
            stops: const [0.0, 0.7],
          ),
        ),
        child: Stack(
          children: [
            // Ambient glows
            Positioned(
              top: -120, left: -100,
              child: Container(
                width: 480, height: 380,
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [
                    primaryColor.withOpacity(0.07),
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
                  ? Center(
                      child: CircularProgressIndicator(
                          color: primaryColor, strokeWidth: 1.5))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;
                        if (isWide) {
                          return _buildWideLayout();
                        } else {
                          return _buildMobileLayout();
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    final Map<String, double> trackHrs = {};
    final activeSessions = _selected?.sessions ?? [];
    for (final s in activeSessions) {
      final code = s.trackCode.isNotEmpty ? s.trackCode : s.trackName;
      trackHrs[code] = (trackHrs[code] ?? 0) + s.durationMinutes / 60.0;
    }
    final sortedTracks = trackHrs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalHrs = trackHrs.values.fold(0.0, (a, b) => a + b);

    final m = _selected;

    return Column(
      children: [
        _buildHeader(),
        _buildMonthTabs(),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            child: Column(
              children: [
                if (sortedTracks.isNotEmpty)
                  _buildLargeDoughnutCard(sortedTracks, totalHrs, isWide: false),
                const SizedBox(height: 16),
                _buildTrendChartCardOnly(),
                const SizedBox(height: 16),
                if (m != null)
                  _buildInvoiceSummaryCard(m),
                const SizedBox(height: 16),
                if (m != null && m.sessions.isNotEmpty)
                  _buildSessionHistoryCardOnly(m),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout() {
    final Map<String, double> trackHrs = {};
    final activeSessions = _selected?.sessions ?? [];
    for (final s in activeSessions) {
      final code = s.trackCode.isNotEmpty ? s.trackCode : s.trackName;
      trackHrs[code] = (trackHrs[code] ?? 0) + s.durationMinutes / 60.0;
    }
    final sortedTracks = trackHrs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalHrs = trackHrs.values.fold(0.0, (a, b) => a + b);

    final m = _selected;

    return Column(
      children: [
        _buildHeader(),
        _buildMonthTabs(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT COLUMN: Charts & Utilisation
                Expanded(
                  flex: 11,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        if (sortedTracks.isNotEmpty)
                          _buildLargeDoughnutCard(sortedTracks, totalHrs, isWide: true),
                        const SizedBox(height: 16),
                        _buildTrendChartCardOnly(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // RIGHT COLUMN: Finances & Logs
                Expanded(
                  flex: 9,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        if (m != null)
                          _buildInvoiceSummaryCard(m),
                        const SizedBox(height: 16),
                        if (m != null && m.sessions.isNotEmpty)
                          _buildSessionHistoryCardOnly(m),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── NATRAX banner ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                const Color(0xFF021D20), // Deep green/teal matching theme background
                const Color(0xFF06101F), // Deep black-blue
              ],
            ),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: primaryColor.withOpacity(0.5), width: 1.5),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/NATRAX LOGO.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.business, color: primaryColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PROVING GROUND BILLING',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: primaryColor, letterSpacing: 1.5)),
              Row(children: [
                Text(_activeProject,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFdfe2f0))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('NATRAX',
                      style: GoogleFonts.spaceGrotesk(fontSize: 8, color: Colors.white70, fontWeight: FontWeight.w600)),
                ),
              ]),
            ])),
            const SizedBox(width: 12),
            Image.asset(
              'assets/images/goodyear_sightline_logo.png',
              height: 18,
              color: Colors.white70,
              fit: BoxFit.contain,
            ),
          ]),
        ),
      ]),
    );
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
          final isAllTab = i == _months.length;
          final isSelected = _selectedMonthIdx == i;
          final label = isAllTab ? 'All Months' : _months[i].label;

          return GestureDetector(
            onTap: () => setState(() => _selectedMonthIdx = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? primaryColor.withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? primaryColor.withOpacity(0.5)
                      : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? primaryColor : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _legendDot(Color c) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

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

  Widget _buildLargeDoughnutCard(List<MapEntry<String, double>> sortedTracks, double totalHrs, {bool isWide = true}) {
    final List<double> values = sortedTracks.map((e) => e.value).toList();
    final List<Color> colors = sortedTracks.map((e) => _getTrackColor(e.key)).toList();

    final chartSize = isWide ? 200.0 : 160.0;
    final strokeWidth = isWide ? 18.0 : 14.0;

    final halfLength = (sortedTracks.length / 2).ceil();
    final col1Tracks = sortedTracks.take(halfLength).toList();
    final col2Tracks = sortedTracks.skip(halfLength).toList();

    Widget buildLegendColumn(List<MapEntry<String, double>> tracks) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: tracks.map((e) {
          final color = _getTrackColor(e.key);
          final pct = totalHrs > 0 ? (e.value / totalHrs) * 100 : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withOpacity(0.12),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${e.value.toStringAsFixed(1)}h',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '(${pct.toStringAsFixed(0)}%)',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              color: const Color(0xFF6B7490),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    final legendWidget = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: buildLegendColumn(col1Tracks)),
        const SizedBox(width: 16),
        Expanded(child: buildLegendColumn(col2Tracks)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.08),
            const Color(0xFF0D1520).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_rounded, color: Color(0xFFFF6B00), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TRACK UTILISATION SHARE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Image.asset(
                'assets/images/goodyear_sightline_logo.png',
                height: 12,
                color: Colors.white70,
                fit: BoxFit.contain,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Large Doughnut Chart
                SizedBox(
                  width: chartSize,
                  height: chartSize,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(chartSize, chartSize),
                        painter: DoughnutChartPainter(
                          values: values,
                          colors: colors,
                          strokeWidth: strokeWidth,
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              totalHrs.toStringAsFixed(1),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'hours total',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF6B7490),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                // 2. Legend
                Expanded(child: legendWidget),
              ],
            )
          else
            Column(
              children: [
                // 1. Large Doughnut Chart (Centered)
                Center(
                  child: SizedBox(
                    width: chartSize,
                    height: chartSize,
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: Size(chartSize, chartSize),
                          painter: DoughnutChartPainter(
                            values: values,
                            colors: colors,
                            strokeWidth: strokeWidth,
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                totalHrs.toStringAsFixed(1),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'hours total',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF6B7490),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // 2. Legend (2 columns list below)
                legendWidget,
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTrendChartCardOnly() {
    if (_months.isEmpty) return const SizedBox.shrink();
    final chartMonths = _months.reversed.toList();
    final maxVal = chartMonths.fold(0.0, (m, g) => g.totalIncl > m ? g.totalIncl : m);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.08),
            const Color(0xFF0D1520).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'TREND CHART — MONTHLY TOTALS',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Image.asset(
                'assets/images/goodyear_sightline_logo.png',
                height: 12,
                color: Colors.white70,
                fit: BoxFit.contain,
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
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
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            primaryColor.withOpacity(0.6),
                            primaryColor,
                          ],
                        ),
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
                        final label = DateFormat('MMM yyyy').format(
                          DateTime.parse('${chartMonths[idx].monthKey}-01'),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(label,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
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
                            fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w700),
                        children: [
                          TextSpan(
                            text: _compact.format(rod.toY),
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 13, color: primaryColor, fontWeight: FontWeight.w800),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceSummaryCard(_MonthGroup m) {
    final subtotal = m.subtotalExcl;
    final gst = subtotal * 0.18;
    final total = m.totalIncl;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.08),
            const Color(0xFF0D1520).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                m.label.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.3)),
                ),
                child: Text(
                  '${m.sessions.length} sessions',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 20),
          _invoiceRow('Track Access + Accessories', _inr.format(m.trackAcc)),
          const SizedBox(height: 10),
          if (m.workshopRental > 0) ...[
            _invoiceRow('Workshop Rental', _inr.format(m.workshopRental)),
            const SizedBox(height: 10),
          ],
          _invoiceRow('Subtotal (Excl. GST)', _inr.format(subtotal)),
          const SizedBox(height: 10),
          _invoiceRow('GST (18%)', _inr.format(gst)),
          const SizedBox(height: 20),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inr.format(total),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: primaryColor,
                    ),
                  ),
                  Text(
                    '${_fmtUsd(total)} USD',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7490),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 20),
          _buildCostBreakdownBarsOnly(m),
        ],
      ),
    );
  }

  Widget _invoiceRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primaryColor.withOpacity(0.12),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              color: const Color(0xFFDFE2F0).withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostBreakdownBarsOnly(_MonthGroup m) {
    final total = m.subtotalExcl;
    if (total == 0) return const SizedBox.shrink();
    final trackPct = (m.trackAcc / total).clamp(0.0, 1.0);
    final rentalPct = m.workshopRental > 0 ? (m.workshopRental / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COST COMPOSITION',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF94A3B8),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              Flexible(
                flex: (trackPct * 100).round(),
                child: Container(height: 10, color: primaryColor),
              ),
              if (rentalPct > 0)
                Flexible(
                  flex: (rentalPct * 100).round(),
                  child: Container(height: 10, color: const Color(0xFFF59E0B)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _legendDot(primaryColor),
            const SizedBox(width: 6),
            Text(
              'Track + Accessories  ${(trackPct * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: const Color(0xFF94A3B8),
              ),
            ),
            if (rentalPct > 0) ...[
              const SizedBox(width: 16),
              _legendDot(const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                'Workshop Rental  ${(rentalPct * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSessionHistoryCardOnly(_MonthGroup m) {
    final sessions = m.sessions;
    if (sessions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor.withOpacity(0.08),
            const Color(0xFF0D1520).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'SESSIONS LOG',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sessions.length,
              physics: const BouncingScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = sessions[i];
                final dayStr = DateFormat('d MMM').format(s.date);
                final timeStr = DateFormat('HH:mm').format(s.date);
                final hrs = s.durationMinutes ~/ 60;
                final mins = s.durationMinutes % 60;
                final durationLabel = hrs > 0 ? '${hrs}h ${mins}m' : '${mins}m';
                final trackColor = _getTrackColor(s.trackCode.isNotEmpty ? s.trackCode : s.trackName);

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: trackColor.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: trackColor.withOpacity(0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: trackColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: trackColor.withOpacity(0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayStr.split(' ').first,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: trackColor,
                              ),
                            ),
                            Text(
                              dayStr.split(' ').last,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 7,
                                fontWeight: FontWeight.w600,
                                color: trackColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.trackName,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  _inr.format(s.totalIncl),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: trackColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                _badge(s.trackCode.toUpperCase(), trackColor),
                                const SizedBox(width: 6),
                                _badge('$timeStr · $durationLabel', const Color(0xFF94A3B8)),
                              ],
                            ),
                            if (s.notes != null && s.notes!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                s.notes!,
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 9, color: const Color(0xFF6B7490)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DoughnutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double strokeWidth;

  DoughnutChartPainter({
    required this.values,
    required this.colors,
    this.strokeWidth = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -3.141592653589793 / 2; // start from top
    final total = values.fold(0.0, (sum, val) => sum + val);

    if (total == 0) {
      paint.color = Colors.white.withOpacity(0.05);
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.white.withOpacity(0.03);
    canvas.drawCircle(center, radius, bgPaint);

    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweepAngle = (values[i] / total) * 3.141592653589793 * 2;
      final gap = sweepAngle > 0.15 ? 0.04 : 0.0;
      paint.color = colors[i % colors.length];
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap,
        sweepAngle - (gap * 2),
        false,
        paint,
      );
      
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DoughnutChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}


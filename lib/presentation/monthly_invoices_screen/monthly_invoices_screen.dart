import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/billing_baseline.dart';
import '../../services/muster_service.dart';
import '../../services/project_catalog.dart';
import '../../services/project_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/session_status.dart';

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
  final double workshopRental;   // from BillingBaseline (pinned months only)
  final double? trackAccOverride;
  final double manpowerCost;      // sum of head_count × rate from manpower_muster (kind=manpower)
  final double workshopMusterCost; // sum of workshop days × ₹5,000 from manpower_muster (kind=workshop)

  double get trackAcc =>
      trackAccOverride ?? sessions.fold(0.0, (s, e) => s + e.subtotalExcl);

  /// Total ex-GST for the month: track + workshop rental (baseline) +
  /// manpower (muster) + workshop muster. Workshop rental and workshopMusterCost
  /// are never both non-zero for the same month — pinned months use the baseline
  /// rental, computed months use the muster.
  double get subtotalExcl => trackAcc + workshopRental + manpowerCost + workshopMusterCost;
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
    this.manpowerCost = 0.0,
    this.workshopMusterCost = 0.0,
  });
}

/// Where sessions are actually filed, as opposed to where they are being
/// looked for.
///
/// A session carries whichever `project_name` was globally selected when it was
/// entered — manual entry seeds its dropdown from [ProjectManager] — so work
/// done on one programme while another was selected is filed under the wrong
/// one. Nothing in the app said so: the Analyser simply showed fewer sessions
/// than expected, or none, and the reason was invisible without database
/// access the app's own users do not have.
///
/// Counted across every completed session BEFORE the project filter, so it
/// describes the table rather than the current view.
class _ProjectTally {
  final String label;
  int count = 0;
  double cost = 0;
  /// Rows with an empty or 'General' project_name, folded into Mahindra EV PoC
  /// by convention. Worth stating separately — they are filed by default, not
  /// by anybody's choice.
  int untagged = 0;
  DateTime? first;
  DateTime? last;
  _ProjectTally({required this.label});
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

  /// Every programme present in the session table, with what is filed to it.
  /// Independent of [_activeProject] — this is the ground truth the view is
  /// a filtered slice of.
  List<_ProjectTally> _tallies = [];

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
  // Single source of truth, shared with the PO Tracker so the two screens
  // cannot report different figures for the same month.
  Map<String, double> get _workshopByMonth => {
        for (final m in BillingBaseline.forProject(_activeProject))
          m.month: m.workshopRental,
      };

  /// Only months carrying a fixed figure. A month absent from this map falls
  /// through to the summed session costs, which is exactly what a
  /// session-costed month should do.
  Map<String, double> get _trackAccByMonth => {
        for (final m in BillingBaseline.forProject(_activeProject))
          if (m.trackAndAccessories != null)
            m.month: m.trackAndAccessories!,
      };

  @override
  void initState() {
    super.initState();
    // The Analyser is vehicle-scoped and INDEPENDENT of the globally selected
    // project — default to the active one, then ask which vehicle to analyse as
    // soon as the screen opens.
    _activeProject = ProjectManager.instance.activeProject;
    // Workshop rental and manpower cost on this screen are priced off the
    // muster, so a day marked there changes figures here. Without this the
    // Analyser kept whatever it read when it opened.
    MusterService.instance.addListener(_onMusterChanged);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pickVehicle();
    });
  }

  @override
  void dispose() {
    MusterService.instance.removeListener(_onMusterChanged);
    super.dispose();
  }

  void _onMusterChanged() {
    if (mounted) _loadData();
  }

  // Vehicles the Analyser can scope to. Read from the catalogue so a new
  // programme appears here without a second edit, but still held separately
  // from ProjectManager so the Analyser selection stays independent of the
  // globally selected project.
  static List<Programme> get _analyserVehicles => ProjectCatalog.all;

  /// Ask which vehicle's expenses to analyse. Shown on open and via "Change".
  Future<void> _pickVehicle() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
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
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Text('Analyse which vehicle?',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            const SizedBox(height: 2),
            Text('Pick the vehicle whose expenses you want to review.',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 14),
            ..._analyserVehicles.map((v) {
              final sel = v.displayName == _activeProject;
              final isIce = v.powertrain.isIce;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, v.displayName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: sel
                          ? primaryColor.withOpacity(0.12)
                          : Colors.white.withOpacity(0.04),
                      border: Border.all(
                          color: sel ? primaryColor : Colors.white24,
                          width: sel ? 1.4 : 1),
                    ),
                    child: Row(children: [
                      Icon(
                          isIce
                              ? Icons.local_fire_department
                              : Icons.electric_bolt,
                          size: 18,
                          color: sel ? primaryColor : Colors.white54),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.vehicle,
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              Text('${v.displayName} · ${v.powertrain.label}',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10.5, color: Colors.white54)),
                            ]),
                      ),
                      if (sel)
                        Icon(Icons.check_circle,
                            size: 18, color: primaryColor),
                    ]),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != _activeProject) {
      setState(() {
        _activeProject = chosen;
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
          .inFilter('session_status', kBillableSessionStatuses)
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

      // Tally every session by the programme it is filed under, BEFORE the
      // scope filter below drops the ones this view is not showing. Costs
      // nothing extra — these are the rows already fetched.
      final tallyMap = <String, _ProjectTally>{};
      for (final s in sessionsRaw) {
        final raw = (s['project_name'] as String?)?.trim() ?? '';
        final defaulted = raw.isEmpty || raw.toLowerCase() == 'general';
        final label =
            defaulted ? 'Mahindra EV PoC' : ProjectCatalog.displayName(raw);
        final t = tallyMap.putIfAbsent(label, () => _ProjectTally(label: label));
        t.count++;
        t.cost += (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        if (defaulted) t.untagged++;
        final d = DateTime.tryParse(s['started_at'] as String? ?? '');
        if (d != null) {
          if (t.first == null || d.isBefore(t.first!)) t.first = d;
          if (t.last == null || d.isAfter(t.last!)) t.last = d;
        }
      }
      final tallies = tallyMap.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      final allSessions = <_Session>[];
      for (final s in sessionsRaw) {
        final rawProj = (s['project_name'] as String?)?.trim() ?? '';
        final projName = (rawProj.isEmpty || rawProj.toLowerCase() == 'general')
            ? 'Mahindra EV PoC'
            : rawProj;

        // Scoped to the vehicle the Analyser is showing, NOT to the globally
        // selected project. They are two independent selections by design —
        // _pickVehicle deliberately never calls ProjectManager.setProject —
        // and consulting the global one here put another programme's sessions
        // under this heading, while the muster below was correctly scoped to
        // _activeProject. The screen reported one project's track time over
        // another's manpower.
        if (!ProjectManager.sessionBelongsTo(rawProj, _activeProject)) continue;

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

      // ── Muster data: manpower + workshop charges ─────────────────────────
      // Fetch all muster rows for this project.
      final musterRaw = await client
          .from('manpower_muster')
          .select('muster_date, head_count, kind, po_number, project_name')
          .eq('project_name', _activeProject);

      // Fetch PO rates: rate = total_po_value / manpower_days.
      final posRaw = await client
          .from('po_trackers')
          .select('po_number, total_po_value, manpower_days')
          .eq('category', 'manpower');

      final Map<String, double> poRateByNumber = {};
      for (final p in (posRaw as List)) {
        final poNum = (p['po_number'] as String? ?? '').trim();
        final value = (p['total_po_value'] as num?)?.toDouble() ?? 0.0;
        final days  = (p['manpower_days'] as num?)?.toDouble() ?? 0.0;
        poRateByNumber[poNum] = days > 0 ? value / days : 0.0;
      }

      // Group muster costs by month.
      final Map<String, double> manpowerByMonth    = {};
      final Map<String, double> workshopMusterByMonth = {};
      for (final row in (musterRaw as List)) {
        final kind    = (row['kind'] as String? ?? 'manpower').trim();
        final dateStr = row['muster_date'] as String? ?? '';
        if (dateStr.length < 7) continue;
        final monthKey = dateStr.substring(0, 7); // 'YYYY-MM'

        if (kind == 'workshop') {
          // One workshop day = ₹5,000 flat.
          workshopMusterByMonth[monthKey] =
              (workshopMusterByMonth[monthKey] ?? 0) + kWorkshopRatePerDay;
        } else {
          // Manpower: head_count man-days × PO rate.
          final poNum   = (row['po_number'] as String? ?? '').trim();
          final heads   = (row['head_count'] as int? ?? 0);
          final rate    = poRateByNumber[poNum] ?? 0.0;
          manpowerByMonth[monthKey] =
              (manpowerByMonth[monthKey] ?? 0) + (heads * rate);
        }
      }

      final Map<String, List<_Session>> byMonth = {};
      for (final s in allSessions) {
        final mk = s.date.toIso8601String().substring(0, 7);
        byMonth.putIfAbsent(mk, () => []).add(s);
      }

      final isMahindraEV = BillingBaseline.isMahindraEv(_activeProject);

      final monthGroups = byMonth.entries.map((e) {
        final dt = DateTime.parse('${e.key}-01');
        final label = DateFormat('MMMM yyyy').format(dt);
        final rental = isMahindraEV ? (_workshopByMonth[e.key] ?? 0.0) : 0.0;
        final trackAccOverride = isMahindraEV ? _trackAccByMonth[e.key] : null;
        // Only use muster workshop cost for months not already pinned in
        // BillingBaseline — pinned months carry an invoice-backed workshop
        // rental and adding the muster on top would double-count it.
        final useBaselineWorkshop = rental > 0;
        return _MonthGroup(
          monthKey: e.key,
          label: label,
          sessions: e.value..sort((a, b) => a.date.compareTo(b.date)),
          workshopRental: rental,
          trackAccOverride: trackAccOverride,
          manpowerCost: manpowerByMonth[e.key] ?? 0.0,
          workshopMusterCost: useBaselineWorkshop
              ? 0.0
              : (workshopMusterByMonth[e.key] ?? 0.0),
        );
      }).toList()
        ..sort((a, b) => b.monthKey.compareTo(a.monthKey));

      // Also add months that have muster data but no track sessions yet.
      final existingKeys = monthGroups.map((m) => m.monthKey).toSet();
      final allMusterMonths = {
        ...manpowerByMonth.keys,
        ...workshopMusterByMonth.keys,
      };
      for (final mk in allMusterMonths) {
        if (existingKeys.contains(mk)) continue;
        final dt = DateTime.parse('$mk-01');
        final label = DateFormat('MMMM yyyy').format(dt);
        final rental = isMahindraEV ? (_workshopByMonth[mk] ?? 0.0) : 0.0;
        final useBaselineWorkshop = rental > 0;
        monthGroups.add(_MonthGroup(
          monthKey: mk,
          label: label,
          sessions: [],
          workshopRental: rental,
          manpowerCost: manpowerByMonth[mk] ?? 0.0,
          workshopMusterCost: useBaselineWorkshop
              ? 0.0
              : (workshopMusterByMonth[mk] ?? 0.0),
        ));
      }
      monthGroups.sort((a, b) => b.monthKey.compareTo(a.monthKey));

      if (mounted) {
        setState(() {
          _months = monthGroups;
          _tallies = tallies;
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
    final totalManpower = _months.fold(0.0, (s, m) => s + m.manpowerCost);
    final totalWorkshopMuster = _months.fold(0.0, (s, m) => s + m.workshopMusterCost);
    final totalTrackAccOverride = _months.any((m) => m.trackAccOverride != null)
        ? _months.fold(0.0, (s, m) => s + (m.trackAccOverride ?? m.trackAcc))
        : null;
    return _MonthGroup(
      monthKey: 'all',
      label: 'All Months',
      sessions: allSessions,
      workshopRental: totalWorkshop,
      trackAccOverride: totalTrackAccOverride,
      manpowerCost: totalManpower,
      workshopMusterCost: totalWorkshopMuster,
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
                _buildAttributionCard(),
                if (_tallies.isNotEmpty) const SizedBox(height: 16),
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
                        _buildAttributionCard(),
                        if (_tallies.isNotEmpty) const SizedBox(height: 16),
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

  /// Where every completed session is filed, regardless of what is being
  /// viewed.
  ///
  /// Shown whenever more than one programme carries sessions, and always when
  /// the programme on screen carries none — that second case is the one that
  /// used to look like a broken screen. A session is filed under whatever
  /// project was globally selected at entry time, so work logged while another
  /// programme was selected lands there and the Analyser, correctly scoped,
  /// shows nothing. Stating the distribution turns that from a mystery into a
  /// fact you can act on. Tapping a row switches the view to that programme.
  Widget _buildAttributionCard() {
    if (_tallies.isEmpty) return const SizedBox.shrink();
    final activeKey = _activeProject.toLowerCase().trim();
    final here = _tallies.where((t) => t.label.toLowerCase().trim() == activeKey);
    final hereCount = here.isEmpty ? 0 : here.first.count;
    // One programme holding everything, and it is the one being viewed, is
    // simply a correct screen. Nothing to explain.
    if (_tallies.length == 1 && hereCount > 0) return const SizedBox.shrink();

    final df = DateFormat('d MMM yyyy');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: .85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hereCount == 0
                ? const Color(0xFFFFB547).withValues(alpha: .55)
                : primaryColor.withValues(alpha: .30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hereCount == 0 ? Icons.info_outline : Icons.folder_open,
              size: 14,
              color: hereCount == 0 ? const Color(0xFFFFB547) : primaryColor),
          const SizedBox(width: 8),
          Text('WHERE SESSIONS ARE FILED',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: hereCount == 0
                      ? const Color(0xFFFFB547)
                      : primaryColor)),
        ]),
        const SizedBox(height: 6),
        Text(
            hereCount == 0
                ? 'No session is filed under $_activeProject. A session is '
                    'recorded against whichever project was selected when it '
                    'was entered, so the work is likely sitting under one of '
                    'these instead. Tap a row to view it there.'
                : 'Every completed session, by the programme recorded on it. '
                    'Tap a row to view that programme.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, height: 1.45, color: const Color(0xFF94A3B8))),
        const SizedBox(height: 12),
        ..._tallies.map((t) {
          final isHere = t.label.toLowerCase().trim() == activeKey;
          return InkWell(
            onTap: t.label == _activeProject
                ? null
                : () {
                    setState(() {
                      _activeProject = t.label;
                      _selectedMonthIdx = 0;
                    });
                    _loadData();
                  },
            borderRadius: BorderRadius.circular(9),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: isHere
                    ? primaryColor.withValues(alpha: .13)
                    : const Color(0xFF1E293B).withValues(alpha: .55),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: isHere
                        ? primaryColor.withValues(alpha: .55)
                        : Colors.transparent),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isHere
                                    ? primaryColor
                                    : const Color(0xFFdfe2f0))),
                        const SizedBox(height: 2),
                        Text(
                            [
                              if (t.first != null && t.last != null)
                                '${df.format(t.first!)} — ${df.format(t.last!)}',
                              if (t.untagged > 0)
                                '${t.untagged} with no project set',
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                color: const Color(0xFF64748B))),
                      ]),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${t.count}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isHere
                              ? primaryColor
                              : const Color(0xFFdfe2f0))),
                  Text(t.count == 1 ? 'session' : 'sessions',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9, color: const Color(0xFF64748B))),
                ]),
              ]),
            ),
          );
        }),
      ]),
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
                Flexible(
                  child: Text(_activeProject,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFdfe2f0))),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('NATRAX',
                      style: GoogleFonts.spaceGrotesk(fontSize: 8, color: Colors.white70, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _pickVehicle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: primaryColor.withOpacity(0.5)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.directions_car_filled, size: 11, color: primaryColor),
                      const SizedBox(width: 4),
                      Text('Change',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, fontWeight: FontWeight.w700, color: primaryColor)),
                    ]),
                  ),
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
          if (m.manpowerCost > 0) ...[
            const SizedBox(height: 10),
            _invoiceRow('Manpower', _inr.format(m.manpowerCost),
                accent: const Color(0xFFA855F7)),
          ],
          if (m.workshopMusterCost > 0) ...[
            const SizedBox(height: 10),
            _invoiceRow('Workshop Charges', _inr.format(m.workshopMusterCost),
                accent: const Color(0xFFF59E0B)),
          ],
          if (m.workshopRental > 0) ...[
            const SizedBox(height: 10),
            _invoiceRow('Workshop Rental', _inr.format(m.workshopRental),
                accent: const Color(0xFFF59E0B)),
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

  Widget _invoiceRow(String label, String value, {Color? accent}) {
    final rowAccent = accent ?? primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rowAccent.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rowAccent.withOpacity(0.14),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (accent != null) ...[
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: const Color(0xFFDFE2F0).withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
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
    final trackPct     = (m.trackAcc / total).clamp(0.0, 1.0);
    final manpowerPct  = m.manpowerCost > 0 ? (m.manpowerCost / total).clamp(0.0, 1.0) : 0.0;
    final wsMusterPct  = m.workshopMusterCost > 0 ? (m.workshopMusterCost / total).clamp(0.0, 1.0) : 0.0;
    final rentalPct    = m.workshopRental > 0 ? (m.workshopRental / total).clamp(0.0, 1.0) : 0.0;

    const manpowerColor = Color(0xFFA855F7);
    const workshopColor = Color(0xFFF59E0B);

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
              if ((trackPct * 100).round() > 0)
                Flexible(
                  flex: (trackPct * 100).round(),
                  child: Container(height: 10, color: primaryColor),
                ),
              if (manpowerPct > 0)
                Flexible(
                  flex: (manpowerPct * 100).round(),
                  child: Container(height: 10, color: manpowerColor),
                ),
              if (wsMusterPct > 0)
                Flexible(
                  flex: (wsMusterPct * 100).round(),
                  child: Container(height: 10, color: workshopColor),
                ),
              if (rentalPct > 0)
                Flexible(
                  flex: (rentalPct * 100).round(),
                  child: Container(height: 10, color: workshopColor),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              _legendDot(primaryColor),
              const SizedBox(width: 6),
              Text(
                'Track + Accessories  ${(trackPct * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ]),
            if (manpowerPct > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _legendDot(manpowerColor),
                const SizedBox(width: 6),
                Text(
                  'Manpower  ${(manpowerPct * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ]),
            if (wsMusterPct > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _legendDot(workshopColor),
                const SizedBox(width: 6),
                Text(
                  'Workshop  ${(wsMusterPct * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ]),
            if (rentalPct > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _legendDot(workshopColor),
                const SizedBox(width: 6),
                Text(
                  'Workshop Rental  ${(rentalPct * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8)),
                ),
              ]),
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


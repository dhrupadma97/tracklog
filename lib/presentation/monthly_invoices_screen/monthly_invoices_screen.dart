import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/billing_baseline.dart';
import '../../services/muster_service.dart';
import '../../services/natrax_invoice_parser.dart';
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

/// One `session_additional_services` row, kept whole.
///
/// Summing these into the session cost was enough while the panel showed a
/// single "Track Access + Accessories" line. An invoice names them one by one
/// — EV charger, weighment pad, refreshment, water — so the quantity and the
/// name have to survive the journey.
class _ServiceRow {
  final String name;
  final double quantity;
  final double cost;
  const _ServiceRow({
    required this.name,
    required this.quantity,
    required this.cost,
  });
}

/// One row of the invoice-versus-us comparison.
///
/// [saveKey] is null when the line cannot be filled in without guessing —
/// nothing of ours matches it, or it covers a track that more than one
/// programme used and the invoice does not say how to split it.
class _CompareRow {
  final ParsedInvoiceLine line;
  final double ours;
  final String? saveKey;
  final String note;
  const _CompareRow({
    required this.line,
    required this.ours,
    this.saveKey,
    this.note = '',
  });
}

/// What NATRAX invoiced for one line, beside what we recorded.
///
/// Neither side is edited into the other. Our register and the invoice
/// disagree in both directions — NATRAX under-billed High Speed in September
/// while our own record carried nearly 100 extra EV units and somebody else's
/// weighing pad — and correcting one to match the other destroys the evidence
/// of both.
class _InvoicedLine {
  final double invoiced;
  final String note;
  const _InvoicedLine({required this.invoiced, this.note = ''});
}

/// One entry behind a line, so a figure can be opened up and accounted for.
///
/// "278 units" is not a number anybody can check. The six dated entries that
/// add up to it are.
class _LineEntry {
  final DateTime date;
  final String detail;
  final double cost;
  const _LineEntry({
    required this.date,
    required this.detail,
    required this.cost,
  });
}

/// A service summed across a month, as it would appear on an invoice line.
class _ServiceLine {
  final String name;
  double quantity;
  double cost;
  final List<_LineEntry> entries = [];
  _ServiceLine({required this.name, this.quantity = 0, this.cost = 0});
}

/// One track, summed across a month for a single programme.
class _TrackLine {
  final String code;
  final String name;
  int minutes;
  double cost;
  _TrackLine({required this.code, required this.name, this.minutes = 0, this.cost = 0});
}

class _MonthGroup {
  final String monthKey; // 'YYYY-MM'
  final String label;    // 'April 2026'
  final List<_Session> sessions;
  final double workshopRental;   // from BillingBaseline (pinned months only)
  final double? trackAccOverride;
  final double manpowerCost;      // sum of head_count × rate from manpower_muster (kind=manpower)
  final double workshopMusterCost; // sum of workshop days × ₹5,000 from manpower_muster (kind=workshop)

  /// Track + accessories split by the programme each session is filed under.
  /// Only filled on the all-programmes groups the invoice panel shows; the
  /// vehicle-scoped groups behind the charts leave it empty.
  final Map<String, double> programmeSplit;

  /// Every additional service in the month, summed by name, so each one gets
  /// its own invoice line.
  final List<_ServiceLine> serviceLines;

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
    this.programmeSplit = const {},
    this.serviceLines = const [],
  });

  /// Track time only — the services are listed separately on the invoice
  /// panel, so showing them inside the track figure would count them twice.
  double get trackOnly =>
      trackAcc - serviceLines.fold<double>(0.0, (s, e) => s + e.cost);

  /// Each programme's track lines for the month, summed per track.
  Map<String, List<_TrackLine>> get trackLinesByProgramme {
    final out = <String, Map<String, _TrackLine>>{};
    for (final s in sessions) {
      final p = s.projectName ?? 'Mahindra EV PoC';
      final key = s.trackCode.isEmpty ? s.trackName : s.trackCode;
      final line = out
          .putIfAbsent(p, () => {})
          .putIfAbsent(key, () => _TrackLine(code: s.trackCode, name: s.trackName));
      line.minutes += s.durationMinutes;
      line.cost += s.trackCostExcl;
    }
    return {
      for (final e in out.entries)
        e.key: e.value.values.toList()
          ..sort((a, b) => b.cost.compareTo(a.cost)),
    };
  }
}

/// A hand-entered correction putting a month onto the invoice that actually
/// arrived.
///
/// What the sessions compute and what NATRAX bills can differ by a few hundred
/// rupees — a part-hour rounded their way, a support line priced on the day, a
/// round-off at the foot of the invoice. The figure of record is the invoice,
/// so the month can be nudged onto it; [reason] is required so the nudge is
/// never an unexplained number.
class _MonthAdjustment {
  final String month; // 'YYYY-MM'
  final double amount; // signed — negative brings the total down
  final String reason;
  const _MonthAdjustment({
    required this.month,
    required this.amount,
    required this.reason,
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
  /// The same months totalled across every programme, keyed by 'YYYY-MM'.
  /// The invoice panel reads these; the charts read [_months].
  Map<String, _MonthGroup> _monthsAll = {};
  /// Hand-entered corrections onto the real invoice, keyed by 'YYYY-MM'.
  Map<String, _MonthAdjustment> _adjustments = {};

  /// What NATRAX invoiced, per line, keyed 'YYYY-MM|line_key'. A line with no
  /// entry has not been checked against the invoice yet.
  Map<String, _InvoicedLine> _invoiced = {};

  String _lineKey(String month, String key) => '$month|$key';
  _InvoicedLine? _invoicedFor(String month, String key) =>
      _invoiced[_lineKey(month, key)];
  int _selectedMonthIdx = 0;
  String _activeProject = '';

  /// Every programme present in the session table, with what is filed to it.
  /// Independent of [_activeProject] — this is the ground truth the view is
  /// a filtered slice of.
  List<_ProjectTally> _tallies = [];

  /// Man-days worked against a PO that carries no day rate yet, so they price
  /// at nothing. Real days; shown rather than left to read as free.
  int _unpricedManDays = 0;

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
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(child: Container(
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
      )),
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
            .select('session_id, service_name, quantity, total_cost')
            .inFilter('session_id', sessionIds);
      }

      final Map<String, double> svcMap = {};
      // The same rows again, kept whole rather than summed, so the invoice
      // panel can show "EV charger 181 units" and "Refreshment 46 Nos" as
      // their own lines instead of one lump called Accessories.
      final Map<String, List<_ServiceRow>> svcRowsBySession = {};
      for (final svc in svcsRaw) {
        final sid = svc['session_id'] as String;
        final c = (svc['total_cost'] as num?)?.toDouble() ?? 0.0;
        svcMap[sid] = (svcMap[sid] ?? 0) + c;
        svcRowsBySession.putIfAbsent(sid, () => []).add(_ServiceRow(
              name: (svc['service_name'] as String?)?.trim() ?? 'Other service',
              quantity: (svc['quantity'] as num?)?.toDouble() ?? 0.0,
              cost: c,
            ));
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
      // Every session, whatever programme it is filed under. NATRAX invoices
      // the account, not one programme, so the invoice panel has to total them
      // all or it can never match the bill that arrives. The charts stay on
      // `allSessions`, which is still scoped to the vehicle being analysed.
      final everySession = <_Session>[];
      for (final s in sessionsRaw) {
        final rawProj = (s['project_name'] as String?)?.trim() ?? '';
        final projName = (rawProj.isEmpty || rawProj.toLowerCase() == 'general')
            ? 'Mahindra EV PoC'
            : rawProj;

        final date = DateTime.tryParse(s['started_at'] as String? ?? '') ?? DateTime.now();
        final session = _Session(
          id: s['id'] as String,
          trackName: s['track_name'] as String? ?? '—',
          trackCode: s['track_code'] as String? ?? '',
          date: date,
          durationMinutes: s['duration_minutes'] as int? ?? 0,
          trackCostExcl: (s['total_cost'] as num?)?.toDouble() ?? 0.0,
          svcCostExcl: svcMap[s['id'] as String] ?? 0.0,
          projectName: projName,
          notes: s['notes'] as String?,
        );
        everySession.add(session);

        // Scoped to the vehicle the Analyser is showing, NOT to the globally
        // selected project. They are two independent selections by design —
        // _pickVehicle deliberately never calls ProjectManager.setProject —
        // and consulting the global one here put another programme's sessions
        // under this heading, while the muster below was correctly scoped to
        // _activeProject. The screen reported one project's track time over
        // another's manpower.
        if (!ProjectManager.sessionBelongsTo(rawProj, _activeProject)) continue;
        allSessions.add(session);
      }

      // ── Muster data: manpower + workshop charges ─────────────────────────
      // One shared call rather than a second copy of the rules here. This
      // used to fetch the muster itself and match project_name exactly in
      // SQL, which dropped every row with an empty or 'General' project — the
      // rows the session path above folds into Mahindra EV PoC by convention —
      // so those days were invisible to every project, and the History panel,
      // which normalises them, reported different manpower for the same
      // programme.
      final charges =
          await MusterService.instance.chargesForProject(_activeProject);
      final Map<String, double> manpowerByMonth = charges.manpowerByMonth;
      final Map<String, double> workshopMusterByMonth = charges.workshopByMonth;
      // Days sitting on a PO with no rate yet are counted but not priced —
      // surfaced so they do not silently read as free.
      _unpricedManDays = charges.manpowerUnpricedDays;

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

      // ── All-programmes months, for the invoice panel ─────────────────────
      // One NATRAX invoice covers every programme on the account, so the panel
      // that is meant to read like that invoice totals every programme too.
      // Passing null here totals them in one call instead of asking per
      // programme and adding the answers up.
      final chargesAll = await MusterService.instance.chargesForProject(null);

      const evLabel = 'Mahindra EV PoC';
      final evBaseline = BillingBaseline.forProject(evLabel);
      final evTrackByMonth = <String, double>{
        for (final b in evBaseline)
          if (b.trackAndAccessories != null) b.month: b.trackAndAccessories!,
      };
      final evRentalByMonth = <String, double>{
        for (final b in evBaseline) b.month: b.workshopRental,
      };
      // Only needed to keep a pinned month honest: the rental already carries
      // Mahindra EV's workshop, so that programme's mustered workshop has to
      // come back out while every other programme's stays in.
      final evCharges = evRentalByMonth.values.any((v) => v > 0)
          ? await MusterService.instance.chargesForProject(evLabel)
          : null;

      final Map<String, List<_Session>> everyByMonth = {};
      for (final s in everySession) {
        everyByMonth
            .putIfAbsent(s.date.toIso8601String().substring(0, 7), () => [])
            .add(s);
      }

      final monthsAll = <String, _MonthGroup>{};
      final everyKey = <String>{
        ...everyByMonth.keys,
        ...chargesAll.manpowerByMonth.keys,
        ...chargesAll.workshopByMonth.keys,
      };
      for (final mk in everyKey) {
        final rows = (everyByMonth[mk] ?? const <_Session>[]).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final split = <String, double>{};
        for (final s in rows) {
          final p = s.projectName ?? evLabel;
          split[p] = (split[p] ?? 0) + s.subtotalExcl;
        }
        // A pinned Mahindra EV month is invoice-backed. It replaces that
        // programme's own sessions for the month; it is never added on top.
        final evPinned = evTrackByMonth[mk];
        if (evPinned != null) split[evLabel] = evPinned;

        final rental = evRentalByMonth[mk] ?? 0.0;
        final musterWorkshop = chargesAll.workshopByMonth[mk] ?? 0.0;
        final double workshopMuster;
        if (rental > 0) {
          final rest = musterWorkshop - (evCharges?.workshopByMonth[mk] ?? 0.0);
          workshopMuster = rest > 0 ? rest : 0.0;
        } else {
          workshopMuster = musterWorkshop;
        }

        // Services for the month, summed by name so each gets its own line.
        final svcByName = <String, _ServiceLine>{};
        for (final s in rows) {
          for (final r in (svcRowsBySession[s.id] ?? const <_ServiceRow>[])) {
            final line =
                svcByName.putIfAbsent(r.name, () => _ServiceLine(name: r.name));
            line.quantity += r.quantity;
            line.cost += r.cost;
            line.entries.add(_LineEntry(
              date: s.date,
              detail: r.quantity > 0
                  ? '${r.quantity % 1 == 0 ? r.quantity.toStringAsFixed(0) : r.quantity.toStringAsFixed(2)} x ${s.trackName}'
                  : s.trackName,
              cost: r.cost,
            ));
          }
        }

        monthsAll[mk] = _MonthGroup(
          monthKey: mk,
          label: DateFormat('MMMM yyyy').format(DateTime.parse('$mk-01')),
          sessions: rows,
          workshopRental: rental,
          trackAccOverride: split.values.fold<double>(0.0, (a, b) => a + b),
          manpowerCost: chargesAll.manpowerByMonth[mk] ?? 0.0,
          workshopMusterCost: workshopMuster,
          programmeSplit: split,
          serviceLines: svcByName.values.toList()
            ..sort((a, b) => b.cost.compareTo(a.cost)),
        );
      }

      // Adjustments are optional. An older database has no `month_adjustments`
      // table and the Analyser still has to open, so a failure here means "no
      // adjustments recorded", never a broken screen.
      final adjustments = <String, _MonthAdjustment>{};
      try {
        final adjRaw =
            await client.from('month_adjustments').select('month, amount, reason');
        for (final a in adjRaw) {
          final mk = (a['month'] as String?)?.trim();
          if (mk == null || mk.isEmpty) continue;
          adjustments[mk] = _MonthAdjustment(
            month: mk,
            amount: (a['amount'] as num?)?.toDouble() ?? 0.0,
            reason: (a['reason'] as String?)?.trim() ?? '',
          );
        }
      } catch (_) {
        // Table not there yet — leave the map empty.
      }

      // Same posture for the per-line invoiced figures: optional, and a
      // database without the table must still open the screen.
      final invoiced = <String, _InvoicedLine>{};
      try {
        final rows = await client
            .from('invoice_lines')
            .select('month, line_key, invoiced, note');
        for (final r in rows) {
          final mk = (r['month'] as String?)?.trim();
          final lk = (r['line_key'] as String?)?.trim();
          if (mk == null || lk == null || mk.isEmpty || lk.isEmpty) continue;
          invoiced['$mk|$lk'] = _InvoicedLine(
            invoiced: (r['invoiced'] as num?)?.toDouble() ?? 0.0,
            note: (r['note'] as String?)?.trim() ?? '',
          );
        }
      } catch (_) {
        // No table yet — every line simply shows our figure alone.
      }

      if (mounted) {
        setState(() {
          _months = monthGroups;
          _monthsAll = monthsAll;
          _adjustments = adjustments;
          _invoiced = invoiced;
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

  /// What the invoice panel shows for the selected month: every programme on
  /// the account, because that is what one NATRAX invoice covers. Falls back
  /// to the vehicle-scoped group if a month somehow has no all-programmes
  /// twin, so the panel shows a real figure rather than nothing.
  _MonthGroup? get _selectedAllProgrammes {
    final sel = _selected;
    if (sel == null) return null;
    if (sel.monthKey == 'all') return _allProgrammesAllMonths ?? sel;
    return _monthsAll[sel.monthKey] ?? sel;
  }

  _MonthGroup? get _allProgrammesAllMonths {
    if (_monthsAll.isEmpty) return null;
    final split = <String, double>{};
    final sessions = <_Session>[];
    final svc = <String, _ServiceLine>{};
    double rental = 0, manpower = 0, workshopMuster = 0, track = 0;
    for (final g in _monthsAll.values) {
      sessions.addAll(g.sessions);
      rental += g.workshopRental;
      manpower += g.manpowerCost;
      workshopMuster += g.workshopMusterCost;
      track += g.trackAcc;
      g.programmeSplit.forEach((k, v) => split[k] = (split[k] ?? 0) + v);
      for (final l in g.serviceLines) {
        final line = svc.putIfAbsent(l.name, () => _ServiceLine(name: l.name));
        line.quantity += l.quantity;
        line.cost += l.cost;
        line.entries.addAll(l.entries);
      }
    }
    sessions.sort((a, b) => a.date.compareTo(b.date));
    return _MonthGroup(
      monthKey: 'all',
      label: 'All Months',
      sessions: sessions,
      workshopRental: rental,
      trackAccOverride: track,
      manpowerCost: manpower,
      workshopMusterCost: workshopMuster,
      programmeSplit: split,
      serviceLines: svc.values.toList()
        ..sort((a, b) => b.cost.compareTo(a.cost)),
    );
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
                if (activeSessions.isNotEmpty) const SizedBox(height: 16),
                if (activeSessions.isNotEmpty)
                  _buildTrackTableCard(activeSessions),
                const SizedBox(height: 16),
                _buildTrendChartCardOnly(),
                const SizedBox(height: 16),
                if (m != null)
                  _buildInvoiceSummaryCard(_selectedAllProgrammes ?? m),
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
                        if (activeSessions.isNotEmpty)
                          const SizedBox(height: 16),
                        if (activeSessions.isNotEmpty)
                          _buildTrackTableCard(activeSessions),
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
                          _buildInvoiceSummaryCard(_selectedAllProgrammes ?? m),
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

  /// Whether the month table is grouped by day rather than by track.
  ///
  /// Two views of one month because the two questions are different. By track
  /// answers "what does T3 Wet cost us this month"; by day answers "does
  /// 21 September match their sheet", which is how a utilisation sheet is
  /// actually checked — NATRAX write theirs a day at a time.
  bool _tableByDate = false;

  /// One row per day: which tracks ran, and what the day bills.
  ///
  /// The day is the unit NATRAX round on, so a day is also the unit a dispute
  /// lands on. Billable hours here are the sum of each track's own rounding
  /// for that day, with the braking surfaces sharing one floor.
  Widget _buildDateTableCard(List<_Session> sessions) {
    const twoHourTracks = {'T1', 'T2', 'T3W', 'T3D', 'T12'};
    String groupOf(String c) =>
        (c == 'T3W' || c == 'T3D') ? 'T3' : c;
    double ceilHrs(int m) => m <= 0 ? 0 : (m / 60.0).ceilToDouble();

    // Minutes per day per track, then rolled up to the day.
    final perDayTrack = <String, Map<String, int>>{};
    final costPerDay = <String, double>{};
    final runsPerDay = <String, int>{};
    final dateOf = <String, DateTime>{};
    for (final s in sessions) {
      final code =
          (s.trackCode.isNotEmpty ? s.trackCode : s.trackName).toUpperCase();
      if (code == 'MISC' || code.isEmpty) continue;
      final day = DateFormat('yyyy-MM-dd').format(s.date);
      dateOf[day] = DateTime(s.date.year, s.date.month, s.date.day);
      (perDayTrack[day] ??= {})
          .update(code, (v) => v + s.durationMinutes, ifAbsent: () => s.durationMinutes);
      costPerDay[day] = (costPerDay[day] ?? 0) + s.trackCostExcl;
      runsPerDay[day] = (runsPerDay[day] ?? 0) + 1;
    }
    if (perDayTrack.isEmpty) return const SizedBox.shrink();

    final billPerDay = <String, double>{};
    final minsPerDay = <String, int>{};
    perDayTrack.forEach((day, tracks) {
      // Each track rounds up on its own; a shared floor is then topped up
      // once for the group, not once per surface.
      final ceilByGroup = <String, double>{};
      final floorByGroup = <String, double>{};
      var total = 0.0, mins = 0;
      tracks.forEach((code, m) {
        mins += m;
        total += ceilHrs(m);
        final g = groupOf(code);
        ceilByGroup[g] = (ceilByGroup[g] ?? 0) + ceilHrs(m);
        final f = twoHourTracks.contains(code) ? 2.0 : 1.0;
        floorByGroup[g] = (floorByGroup[g] ?? 0) > f ? floorByGroup[g]! : f;
      });
      floorByGroup.forEach((g, floor) {
        final short = floor - (ceilByGroup[g] ?? 0);
        if (short > 0) total += short;
      });
      billPerDay[day] = total;
      minsPerDay[day] = mins;
    });

    final days = perDayTrack.keys.toList()..sort();
    final inr =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    TextStyle head() => GoogleFonts.spaceGrotesk(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF6B7490),
        letterSpacing: 0.8);
    TextStyle cell({bool bold = false, Color? c}) => GoogleFonts.spaceGrotesk(
        fontSize: 11.5,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        color: c ?? Colors.white);
    Widget pad(Widget w, {Alignment a = Alignment.centerLeft}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: Align(alignment: a, child: w));

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.6),
        1: FlexColumnWidth(2.4),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1.4),
        5: FlexColumnWidth(1.9),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: Color(0xFF1E293B), width: 1))),
          children: [
            pad(Text('DATE', style: head())),
            pad(Text('TRACKS', style: head())),
            pad(Text('RUNS', style: head()), a: Alignment.centerRight),
            pad(Text('HOURS', style: head()), a: Alignment.centerRight),
            pad(Text('BILLABLE', style: head()), a: Alignment.centerRight),
            pad(Text('COST', style: head()), a: Alignment.centerRight),
          ],
        ),
        for (final d in days)
          TableRow(children: [
            pad(Text(DateFormat('d MMM').format(dateOf[d]!),
                style: cell(bold: true))),
            pad(Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                for (final c in (perDayTrack[d]!.keys.toList()..sort()))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getTrackColor(c).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _getTrackColor(c).withOpacity(0.35)),
                    ),
                    child: Text(c,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: _getTrackColor(c))),
                  ),
              ],
            )),
            pad(Text('${runsPerDay[d]}',
                    style: cell(c: const Color(0xFF94A3B8))),
                a: Alignment.centerRight),
            pad(Text((minsPerDay[d]! / 60.0).toStringAsFixed(1), style: cell()),
                a: Alignment.centerRight),
            pad(
                Text(billPerDay[d]!.toStringAsFixed(0),
                    style: cell(bold: true, c: const Color(0xFF00F3FF))),
                a: Alignment.centerRight),
            pad(Text(inr.format(costPerDay[d] ?? 0), style: cell()),
                a: Alignment.centerRight),
          ]),
        TableRow(
          decoration: const BoxDecoration(
              border:
                  Border(top: BorderSide(color: Color(0xFF1E293B), width: 1))),
          children: [
            pad(Text('Total', style: cell(bold: true))),
            pad(Text('${days.length} day${days.length == 1 ? '' : 's'}',
                style: cell(c: const Color(0xFF6B7490)))),
            pad(
                Text('${runsPerDay.values.fold(0, (a, b) => a + b)}',
                    style: cell(bold: true, c: const Color(0xFF94A3B8))),
                a: Alignment.centerRight),
            pad(
                Text(
                    (minsPerDay.values.fold(0, (a, b) => a + b) / 60.0)
                        .toStringAsFixed(1),
                    style: cell(bold: true)),
                a: Alignment.centerRight),
            pad(
                Text(
                    billPerDay.values
                        .fold(0.0, (a, b) => a + b)
                        .toStringAsFixed(0),
                    style: cell(bold: true, c: const Color(0xFF00F3FF))),
                a: Alignment.centerRight),
            pad(
                Text(
                    inr.format(costPerDay.values.fold(0.0, (a, b) => a + b)),
                    style: cell(bold: true)),
                a: Alignment.centerRight),
          ],
        ),
      ],
    );
  }

  /// A two-way switch between the by-track and by-day tables.
  Widget _tableModeToggle() {
    Widget tab(String label, bool byDate) {
      final on = _tableByDate == byDate;
      return GestureDetector(
        onTap: () => setState(() => _tableByDate = byDate),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: on
                ? const Color(0xFF00F3FF).withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: on
                    ? const Color(0xFF00F3FF).withOpacity(0.5)
                    : const Color(0xFF1E293B)),
          ),
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color:
                      on ? const Color(0xFF00F3FF) : const Color(0xFF6B7490))),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      tab('BY TRACK', false),
      const SizedBox(width: 6),
      tab('BY DATE', true),
    ]);
  }

  /// The month as a table, per track, in the shape NATRAX bills.
  ///
  /// The doughnut answers "what did we mostly use" and nothing else. Checking
  /// a NATRAX utilisation sheet needs the number they charge on — whole hours
  /// per track per day — against the rupees we hold. Reading that off a
  /// doughnut is impossible, so September was reconciled by exporting a backup
  /// and grouping it by hand, which found 16 hours billed to us that belonged
  /// to another customer's booking.
  ///
  /// Billable hours are not session hours. NATRAX rounds each track up to the
  /// whole hour once a day and applies a floor — two hours on T1, T2 and both
  /// braking surfaces, one elsewhere — so 54 minutes on T1 bills as 2. The
  /// braking surfaces share one floor between them, which is why the shortfall
  /// is worked out per group rather than per track.
  Widget _buildTrackTableCard(List<_Session> sessions) {
    const twoHourTracks = {'T1', 'T2', 'T3W', 'T3D', 'T12'};
    String groupOf(String code) {
      final c = code.toUpperCase();
      return (c == 'T3W' || c == 'T3D') ? 'T3' : c;
    }

    // Minutes per track per day, and per group per day, so the floor can be
    // applied to the braking track once rather than to each surface.
    final perTrackDay = <String, int>{};
    final perGroupDayCeil = <String, double>{};
    final hrs = <String, double>{};
    final cost = <String, double>{};
    final count = <String, int>{};

    for (final s in sessions) {
      final code = (s.trackCode.isNotEmpty ? s.trackCode : s.trackName)
          .toUpperCase();
      if (code == 'MISC' || code.isEmpty) continue;
      final day = DateFormat('yyyy-MM-dd').format(s.date);
      perTrackDay['$day|$code'] = (perTrackDay['$day|$code'] ?? 0) + s.durationMinutes;
      hrs[code] = (hrs[code] ?? 0) + s.durationMinutes / 60.0;
      cost[code] = (cost[code] ?? 0) + s.trackCostExcl;
      count[code] = (count[code] ?? 0) + 1;
    }
    if (hrs.isEmpty) return const SizedBox.shrink();

    double ceilHrs(int m) => m <= 0 ? 0 : (m / 60.0).ceilToDouble();
    for (final e in perTrackDay.entries) {
      final p = e.key.split('|');
      final gk = '${p[0]}|${groupOf(p[1])}';
      perGroupDayCeil[gk] = (perGroupDayCeil[gk] ?? 0) + ceilHrs(e.value);
    }

    final billable = <String, double>{};
    final shortfallDone = <String>{};
    // Largest first inside a day, so a group's shortfall lands on the surface
    // that actually ran rather than on whichever code sorts first.
    final dayKeys = perTrackDay.keys.toList()
      ..sort((a, b) {
        final da = a.split('|')[0], db = b.split('|')[0];
        return da == db
            ? perTrackDay[b]!.compareTo(perTrackDay[a]!)
            : da.compareTo(db);
      });
    for (final key in dayKeys) {
      final p = key.split('|');
      final code = p[1];
      final gk = '${p[0]}|${groupOf(code)}';
      var h = ceilHrs(perTrackDay[key]!);
      if (!shortfallDone.contains(gk)) {
        final floor = twoHourTracks.contains(code) ? 2.0 : 1.0;
        final short = floor - (perGroupDayCeil[gk] ?? 0);
        if (short > 0) {
          h += short;
          shortfallDone.add(gk);
        }
      }
      billable[code] = (billable[code] ?? 0) + h;
    }

    final codes = hrs.keys.toList()
      ..sort((a, b) => (cost[b] ?? 0).compareTo(cost[a] ?? 0));
    final totHrs = hrs.values.fold(0.0, (a, b) => a + b);
    final totBill = billable.values.fold(0.0, (a, b) => a + b);
    final totCost = cost.values.fold(0.0, (a, b) => a + b);
    final inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    TextStyle head() => GoogleFonts.spaceGrotesk(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF6B7490),
        letterSpacing: 0.8);
    TextStyle cell({bool bold = false, Color? c}) => GoogleFonts.spaceGrotesk(
        fontSize: 11.5,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        color: c ?? Colors.white);

    TableRow row(List<Widget> cells, {BoxDecoration? d}) =>
        TableRow(decoration: d, children: cells);
    Widget pad(Widget w, {Alignment a = Alignment.centerLeft}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: Align(alignment: a, child: w));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1520).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00F3FF).withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.table_rows_rounded,
              color: Color(0xFF00F3FF), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_tableByDate ? 'MONTH BY DATE' : 'MONTH BY TRACK',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 1.5)),
          ),
          _tableModeToggle(),
        ]),
        const SizedBox(height: 4),
        Text('Billable hours are whole hours per track per day, '
            'with the day minimum applied — what NATRAX charges on.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9.5, color: const Color(0xFF6B7490), height: 1.4)),
        const SizedBox(height: 14),
        if (_tableByDate)
          _buildDateTableCard(sessions)
        else
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.3),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(2),
          },
          children: [
            row([
              pad(Text('TRACK', style: head())),
              pad(Text('RUNS', style: head()), a: Alignment.centerRight),
              pad(Text('HOURS', style: head()), a: Alignment.centerRight),
              pad(Text('BILLABLE', style: head()), a: Alignment.centerRight),
              pad(Text('COST', style: head()), a: Alignment.centerRight),
            ], d: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Color(0xFF1E293B), width: 1)))),
            for (final c in codes)
              row([
                pad(Row(children: [
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: _getTrackColor(c), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(c, style: cell(bold: true)),
                ])),
                pad(Text('${count[c]}', style: cell(c: const Color(0xFF94A3B8))),
                    a: Alignment.centerRight),
                pad(Text(hrs[c]!.toStringAsFixed(1), style: cell()),
                    a: Alignment.centerRight),
                pad(
                    Text((billable[c] ?? 0).toStringAsFixed(0),
                        style: cell(bold: true, c: const Color(0xFF00F3FF))),
                    a: Alignment.centerRight),
                pad(Text(inr.format(cost[c] ?? 0), style: cell()),
                    a: Alignment.centerRight),
              ]),
            row([
              pad(Text('Total', style: cell(bold: true))),
              pad(
                  Text('${count.values.fold(0, (a, b) => a + b)}',
                      style: cell(bold: true, c: const Color(0xFF94A3B8))),
                  a: Alignment.centerRight),
              pad(Text(totHrs.toStringAsFixed(1), style: cell(bold: true)),
                  a: Alignment.centerRight),
              pad(
                  Text(totBill.toStringAsFixed(0),
                      style: cell(bold: true, c: const Color(0xFF00F3FF))),
                  a: Alignment.centerRight),
              pad(Text(inr.format(totCost), style: cell(bold: true)),
                  a: Alignment.centerRight),
            ], d: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: Color(0xFF1E293B), width: 1)))),
          ],
        ),
      ]),
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
          // The charts are scoped to the vehicle picker while the invoice
          // panel beside them covers the whole account, so a month with no
          // sessions for THIS vehicle draws an empty ring next to a populated
          // invoice. Say which vehicle is being shown rather than leaving a
          // zero to be read as "nothing happened".
          if (totalHrs <= 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB547).withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: const Color(0xFFFFB547).withOpacity(0.25)),
              ),
              child: Text(
                'No track time for $_activeProject this month. The charts follow '
                'the vehicle you picked; the invoice panel covers every '
                'programme on the account.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  height: 1.45,
                  color: const Color(0xFFFFD79A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
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
    final maxVal = chartMonths.fold(0.0, (m, g) => g.subtotalExcl > m ? g.subtotalExcl : m);

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
                        toY: e.value.subtotalExcl,
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
    final invTotal = _invoicedTotal(m);
    final adj = _adjustments[m.monthKey];
    final adjAmount = adj?.amount ?? 0.0;
    // No GST is added here. NATRAX bill Goodyear's SEZ unit under a Letter of
    // Undertaking, "WITHOUT PAYMENT OF IGST": the amount chargeable on the
    // invoice is the ex-GST figure, and the IGST line appears in the tax
    // analysis for information only. Adding 18% read about 18% high against
    // every invoice that actually arrives.
    final total = subtotal + adjAmount;

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
          const SizedBox(height: 4),
          Text(
            'ALL PROGRAMMES ON THE NATRAX ACCOUNT',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: primaryColor.withOpacity(0.8),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 8),
            child: Row(
              children: [
                const Spacer(),
                SizedBox(
                  width: 76,
                  child: Text('OURS',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 8.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF8A93AD))),
                ),
                SizedBox(
                  width: 76,
                  child: Text('NATRAX',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 8.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF8A93AD))),
                ),
                SizedBox(
                  width: 72,
                  child: Text('DIFF',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 8.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF8A93AD))),
                ),
              ],
            ),
          ),
          ..._buildItemisedLines(m),
          const SizedBox(height: 10),
          _invoiceRow('Subtotal (our record)', _inr.format(subtotal)),
          if (invTotal != null) ...[
            const SizedBox(height: 10),
            _invoiceRow('Invoiced by NATRAX', _inr.format(invTotal),
                accent: const Color(0xFF38BDF8)),
            const SizedBox(height: 10),
            _invoiceRow(
              'Difference',
              (subtotal - invTotal).abs() < 0.01
                  ? 'match'
                  : '${subtotal - invTotal > 0 ? '+' : '-'}'
                      '${_inr.format((subtotal - invTotal).abs())}',
              accent: (subtotal - invTotal).abs() < 0.01
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFFF6B6B),
            ),
          ],
          if (adjAmount != 0) ...[
            const SizedBox(height: 10),
            _invoiceRow(
              'Invoice adjustment',
              '${adjAmount > 0 ? '+' : '-'}${_inr.format(adjAmount.abs())}',
              accent: const Color(0xFF38BDF8),
            ),
          ],
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
          const SizedBox(height: 10),
          Text(
            'SEZ supply under LUT - billed without payment of IGST.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B7490),
            ),
          ),
          if (adj != null && adj.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: const Color(0xFF38BDF8).withOpacity(0.2)),
              ),
              child: Text(
                adj.reason,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10.5,
                  height: 1.4,
                  color: const Color(0xFFBAE6FD),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _compareWithInvoice(m),
              icon: const Icon(Icons.description_outlined, size: 15),
              label: const Text('Attach NATRAX invoice'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF38BDF8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editAdjustment(m),
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: Text(
                  adjAmount == 0 ? 'Adjust to invoice' : 'Edit adjustment'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF38BDF8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          const SizedBox(height: 20),
          _buildCostBreakdownBarsOnly(m),
        ],
      ),
    );
  }

  /// Put a month onto the invoice that actually arrived.
  ///
  /// The amount is signed and the reason is required. An unexplained
  /// correction on a billing screen is worse than none at all: months later
  /// nobody can tell a real invoice difference from a typo, and this figure
  /// reaches the manager's report. Saved per month and shared by every
  /// programme, because one NATRAX invoice covers them all.
  Future<void> _editAdjustment(_MonthGroup m) async {
    if (m.monthKey == 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a single month to adjust it.')),
      );
      return;
    }
    final existing = _adjustments[m.monthKey];
    final amountCtl = TextEditingController(
      text: existing == null || existing.amount == 0
          ? ''
          : existing.amount.toStringAsFixed(2),
    );
    final reasonCtl = TextEditingController(text: existing?.reason ?? '');
    final formKey = GlobalKey<FormState>();

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1520),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Adjust ${m.label}',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Computed total ${_inr.format(m.subtotalExcl)}. Enter the '
                'difference to the invoice - negative brings it down.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  height: 1.4,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amountCtl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true, decimal: true),
                style: GoogleFonts.spaceGrotesk(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Adjustment (Rs)',
                  hintText: '-1000',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter an amount';
                  if (double.tryParse(t) == null) return 'Numbers only';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonCtl,
                minLines: 2,
                maxLines: 3,
                style: GoogleFonts.spaceGrotesk(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Why',
                  hintText: 'Round-off on INV/26-27/802',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Say why - this is a billing figure' : null,
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, 'save');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;

    final client = Supabase.instance.client;
    try {
      if (action == 'remove') {
        await client
            .from('month_adjustments')
            .delete()
            .eq('month', m.monthKey);
        if (!mounted) return;
        setState(() => _adjustments.remove(m.monthKey));
      } else {
        final amount = double.parse(amountCtl.text.trim());
        final reason = reasonCtl.text.trim();
        await client.from('month_adjustments').upsert({
          'month': m.monthKey,
          'amount': amount,
          'reason': reason,
        }, onConflict: 'month');
        if (!mounted) return;
        setState(() => _adjustments[m.monthKey] = _MonthAdjustment(
              month: m.monthKey,
              amount: amount,
              reason: reason,
            ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save the adjustment. If this is the first one, the '
            'month_adjustments table may not exist yet. ($e)',
          ),
        ),
      );
    }
  }

  /// What the invoice comes to across the month's lines, with our own figure
  /// standing in for any line not yet checked against it.
  ///
  /// Null when nothing in the month has been reconciled, so the panel stays
  /// quiet rather than claiming an invoice total it does not have.
  double? _invoicedTotal(_MonthGroup m) {
    var any = false;
    double total = 0;
    void add(String key, double ours) {
      final inv = _invoicedFor(m.monthKey, key);
      if (inv != null) any = true;
      total += inv?.invoiced ?? ours;
    }

    m.trackLinesByProgramme.forEach((p, lines) {
      for (final l in lines) {
        add('track:$p:${l.code.isEmpty ? l.name : l.code}', l.cost);
      }
    });
    for (final s in m.serviceLines) {
      add('service:${s.name}', s.cost);
    }
    if (m.workshopMusterCost > 0) add('workshop', m.workshopMusterCost);
    if (m.workshopRental > 0) add('workshop_rental', m.workshopRental);
    if (m.manpowerCost > 0) add('manpower', m.manpowerCost);
    return any ? total : null;
  }

  /// The month written out the way the invoice writes it: each programme with
  /// its own track lines, then the charges that belong to the account rather
  /// than to one programme — workshop, manpower, and every additional service
  /// by name.
  ///
  /// Track lines carry `trackCostExcl` only. The services are listed on their
  /// own below, so folding them into the track figure would count them twice.
  List<Widget> _buildItemisedLines(_MonthGroup m) {
    const manpowerColor = Color(0xFFA855F7);
    const workshopColor = Color(0xFFF59E0B);
    final out = <Widget>[];

    final byProgramme = m.trackLinesByProgramme;
    final programmes = byProgramme.keys.toList()
      ..sort((a, b) {
        final ta = byProgramme[a]!.fold<double>(0, (s, e) => s + e.cost);
        final tb = byProgramme[b]!.fold<double>(0, (s, e) => s + e.cost);
        return tb.compareTo(ta);
      });

    double listed = 0;

    for (final p in programmes) {
      final lines = byProgramme[p]!;
      final total = lines.fold<double>(0, (s, e) => s + e.cost);
      listed += total;
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(_groupHeader(p, _inr.format(total)));
      for (final l in lines) {
        final key = 'track:$p:${l.code.isEmpty ? l.name : l.code}';
        final entries = m.sessions
            .where((s) =>
                (s.projectName ?? 'Mahindra EV PoC') == p &&
                (s.trackCode.isEmpty ? s.trackName : s.trackCode) ==
                    (l.code.isEmpty ? l.name : l.code))
            .map((s) => _LineEntry(
                  date: s.date,
                  detail: '${s.durationMinutes} min',
                  cost: s.trackCostExcl,
                ))
            .toList();
        out.add(_lineItem(
          l.name.isEmpty ? l.code : l.name,
          _hrs(l.minutes),
          l.cost,
          m,
          key,
          entries: entries,
        ));
      }
    }

    final otherLines = <Widget>[];
    for (final s in m.serviceLines) {
      listed += s.cost;
      otherLines.add(_lineItem(
        s.name,
        s.quantity > 0 ? _qty(s.quantity) : '',
        s.cost,
        m,
        'service:${s.name}',
        entries: s.entries,
      ));
    }
    if (m.workshopMusterCost > 0) {
      listed += m.workshopMusterCost;
      otherLines.add(_lineItem(
        'Workshop',
        '${(m.workshopMusterCost / BillingBaseline.workshopDayRate).round()} days',
        m.workshopMusterCost,
        m,
        'workshop',
        accent: workshopColor,
      ));
    }
    if (m.workshopRental > 0) {
      listed += m.workshopRental;
      otherLines.add(_lineItem('Workshop rental', '', m.workshopRental, m,
          'workshop_rental', accent: workshopColor));
    }
    if (m.manpowerCost > 0) {
      listed += m.manpowerCost;
      otherLines.add(_lineItem('Manpower', '', m.manpowerCost, m, 'manpower',
          accent: manpowerColor));
    }

    if (otherLines.isNotEmpty) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 14));
      out.add(_groupHeader('OTHER CHARGES', ''));
      out.addAll(otherLines);
    }

    // A pinned Mahindra EV month replaces that programme's sessions with an
    // invoice-backed figure, so the lines above cannot add up to it. Show the
    // difference rather than letting the subtotal disagree with its own lines.
    final gap = m.subtotalExcl - listed;
    if (gap.abs() >= 1) {
      out.add(const SizedBox(height: 14));
      out.add(_groupHeader('PINNED TO INVOICE', _inr.format(gap)));
      out.add(Padding(
        padding: const EdgeInsets.only(left: 10, bottom: 6),
        child: Text(
          'Figure taken from the invoice, not from sessions',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10.5,
            color: const Color(0xFFDFE2F0).withOpacity(0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
    }

    return out;
  }

  String _hrs(int minutes) {
    if (minutes <= 0) return '';
    final h = minutes / 60.0;
    return '${h.toStringAsFixed(h % 1 == 0 ? 0 : 1)} h';
  }

  String _qty(double q) =>
      q % 1 == 0 ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

  Widget _groupHeader(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: primaryColor,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  /// One line, with our figure and — once it has been checked — what NATRAX
  /// invoiced for it and the difference between the two. Tapping the line sets
  /// the invoiced figure; nothing here ever edits the recorded sessions.
  Widget _lineItem(
    String label,
    String qty,
    double ours,
    _MonthGroup m,
    String lineKey, {
    Color? accent,
    List<_LineEntry> entries = const [],
  }) {
    final inv = _invoicedFor(m.monthKey, lineKey);
    final diff = inv == null ? 0.0 : ours - inv.invoiced;
    final diffColor = diff.abs() < 0.01
        ? const Color(0xFF22C55E)
        : (diff > 0 ? const Color(0xFFFF6B6B) : const Color(0xFFFFB547));

    return InkWell(
      onTap: () => _editInvoicedLine(m, lineKey, label, ours, entries),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, bottom: 6, top: 2),
        child: Row(
          children: [
            if (accent != null) ...[
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10.5,
                  color: const Color(0xFFDFE2F0).withOpacity(0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (qty.isNotEmpty) ...[
              Text(
                qty,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: const Color(0xFF8A93AD),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
            ],
            SizedBox(
              width: 76,
              child: Text(
                _inr.format(ours),
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                inv == null ? '—' : _inr.format(inv.invoiced),
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: inv == null
                      ? const Color(0xFF4B5563)
                      : const Color(0xFFBAE6FD),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                inv == null
                    ? ''
                    : (diff.abs() < 0.01
                        ? 'match'
                        : '${diff > 0 ? '+' : '-'}${_inr.format(diff.abs())}'),
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: diffColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Record what NATRAX invoiced for one line.
  ///
  /// Deliberately NOT a correction to our own entry. Dhrupad's rule is that
  /// both records are kept and the difference is the thing worth looking at —
  /// editing the sessions to match the bill would lose which side was wrong.
  Future<void> _editInvoicedLine(_MonthGroup m, String lineKey, String label,
      double ours, List<_LineEntry> entries) async {
    if (m.monthKey == 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a single month to reconcile it.')),
      );
      return;
    }
    final existing = _invoicedFor(m.monthKey, lineKey);
    final amount = TextEditingController(
        text: existing == null ? '' : existing.invoiced.toStringAsFixed(2));
    final note = TextEditingController(text: existing?.note ?? '');
    final formKey = GlobalKey<FormState>();

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Our record says ${_inr.format(ours)}. Enter what NATRAX '
                'invoiced for this line. Our entry is left alone.',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, height: 1.4, color: const Color(0xFF94A3B8)),
              ),
              // The entries behind the figure. A total nobody can open up is a
              // total nobody can check — this is where "278 units" becomes six
              // dated rows that either add up or do not.
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'MADE UP OF ${entries.length} ENTR${entries.length == 1 ? 'Y' : 'IES'}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF8A93AD),
                  ),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 170),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final e in entries
                          ..sort((a, b) => a.date.compareTo(b.date)))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 62,
                                  child: Text(
                                    DateFormat('d MMM').format(e.date),
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10.5,
                                        color: const Color(0xFF94A3B8)),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    e.detail,
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10.5,
                                        color: const Color(0xFFDFE2F0)),
                                  ),
                                ),
                                Text(
                                  _inr.format(e.cost),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 10.5,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.spaceGrotesk(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Invoiced (Rs)'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter the invoiced amount';
                  if (double.tryParse(t) == null) return 'Numbers only';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                minLines: 2,
                maxLines: 3,
                style: GoogleFonts.spaceGrotesk(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Billed 1 h, we logged 2 h minimum',
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                child: const Text('Clear')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, 'save');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'cancel') return;
    final client = Supabase.instance.client;
    final key = _lineKey(m.monthKey, lineKey);
    try {
      if (action == 'remove') {
        await client
            .from('invoice_lines')
            .delete()
            .eq('month', m.monthKey)
            .eq('line_key', lineKey);
        if (!mounted) return;
        setState(() => _invoiced.remove(key));
      } else {
        final value = double.parse(amount.text.trim());
        final text = note.text.trim();
        await client.from('invoice_lines').upsert({
          'month': m.monthKey,
          'line_key': lineKey,
          'invoiced': value,
          'note': text,
        }, onConflict: 'month,line_key');
        if (!mounted) return;
        setState(() =>
            _invoiced[key] = _InvoicedLine(invoiced: value, note: text));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not save. If this is the first one, the invoice_lines '
            'table may not exist yet. ($e)',
          ),
        ),
      );
    }
  }

  /// Read a NATRAX invoice and set it against the month, line by line.
  ///
  /// The invoice does not say which programme a line belongs to — one 28-hour
  /// wet braking line can cover two vehicles — so a track used by more than
  /// one programme is shown and NOT saved. Apportioning it would invent a
  /// split NATRAX never made. Those lines are entered by hand, which is the
  /// only honest way to do it.
  Future<void> _compareWithInvoice(_MonthGroup m) async {
    if (m.monthKey == 'all') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a single month to compare it.')),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file')));
      return;
    }

    final parsed = NatraxInvoiceParser.parse(file.bytes!);
    if (!mounted) return;
    if (parsed.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(parsed.isUnreadable
            ? 'That PDF has no text layer — it is a scan, so nothing can be read from it.'
            : 'No charged lines could be read from that invoice.'),
      ));
      return;
    }

    // Our side, gathered the way the invoice groups things: by track across
    // every programme, and by service name.
    final byCode = <String, List<MapEntry<String, _TrackLine>>>{};
    m.trackLinesByProgramme.forEach((p, lines) {
      for (final l in lines) {
        final code = (l.code.isEmpty ? l.name : l.code).toUpperCase();
        byCode.putIfAbsent(code, () => []).add(MapEntry(p, l));
      }
    });

    _ServiceLine? serviceMatching(List<String> words) {
      for (final s in m.serviceLines) {
        final n = s.name.toLowerCase();
        if (words.any(n.contains)) return s;
      }
      return null;
    }

    final rows = <_CompareRow>[];
    for (final l in parsed.lines) {
      final key = l.matchKey;
      double ours = 0;
      String? saveKey;
      String note = '';

      if (key == null) {
        note = 'not recognised';
      } else if (key.startsWith('SVC_') || key == 'WORKSHOP') {
        if (key == 'WORKSHOP') {
          ours = m.workshopMusterCost + m.workshopRental;
          saveKey = m.workshopRental > 0 ? 'workshop_rental' : 'workshop';
        } else {
          final svc = serviceMatching(switch (key) {
            'SVC_EV' => ['charger', 'charging', 'ev '],
            'SVC_WEIGH' => ['weigh'],
            'SVC_FOOD' => ['refreshment', 'lunch', 'food'],
            _ => ['water', 'bisleri', 'jar'],
          });
          if (svc == null) {
            note = 'nothing of ours matches';
          } else {
            ours = svc.cost;
            saveKey = 'service:${svc.name}';
          }
        }
      } else {
        final hits = byCode[key] ?? const [];
        ours = hits.fold<double>(0, (s, e) => s + e.value.cost);
        if (hits.isEmpty) {
          note = 'nothing of ours matches';
        } else if (hits.length == 1) {
          final h = hits.first;
          saveKey =
              'track:${h.key}:${h.value.code.isEmpty ? h.value.name : h.value.code}';
        } else {
          note = 'split across ${hits.length} programmes — enter per line';
        }
      }
      rows.add(_CompareRow(
          line: l, ours: ours, saveKey: saveKey, note: note));
    }

    final invTotal = rows.fold<double>(0, (s, r) => s + r.line.amount);
    final oursTotal = rows.fold<double>(0, (s, r) => s + r.ours);
    final savable = rows.where((r) => r.saveKey != null).length;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '${parsed.invoiceNumber ?? 'Invoice'} against ${m.label}',
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in rows) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.line.description,
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10.5,
                                      color: const Color(0xFFDFE2F0))),
                              if (r.note.isNotEmpty)
                                Text(r.note,
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        color: const Color(0xFFFFB547))),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 78,
                          child: Text(_inr.format(r.ours),
                              textAlign: TextAlign.right,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10.5, color: Colors.white)),
                        ),
                        SizedBox(
                          width: 78,
                          child: Text(_inr.format(r.line.amount),
                              textAlign: TextAlign.right,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10.5,
                                  color: const Color(0xFFBAE6FD))),
                        ),
                        SizedBox(
                          width: 72,
                          child: Text(
                            (r.ours - r.line.amount).abs() < 0.01
                                ? 'match'
                                : '${r.ours - r.line.amount > 0 ? '+' : '-'}'
                                    '${_inr.format((r.ours - r.line.amount).abs())}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: (r.ours - r.line.amount).abs() < 0.01
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFFF6B6B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(color: Color(0xFF2A3C6C)),
                Row(children: [
                  Expanded(
                      child: Text('Totals on these lines',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white))),
                  SizedBox(
                      width: 78,
                      child: Text(_inr.format(oursTotal),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white))),
                  SizedBox(
                      width: 78,
                      child: Text(_inr.format(invTotal),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFBAE6FD)))),
                  SizedBox(
                      width: 72,
                      child: Text(
                          '${oursTotal - invTotal > 0 ? '+' : '-'}${_inr.format((oursTotal - invTotal).abs())}',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFF6B6B)))),
                ]),
                const SizedBox(height: 10),
                Text(
                  '$savable of ${rows.length} lines can be filled in '
                  'automatically. The rest are left for you — a track used by '
                  'more than one programme has to be split by hand, because '
                  'the invoice does not say how.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, height: 1.4, color: const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Close')),
          ElevatedButton(
            onPressed:
                savable == 0 ? null : () => Navigator.pop(ctx, true),
            child: Text('Fill in $savable'),
          ),
        ],
      ),
    );

    if (go != true || !mounted) return;

    final client = Supabase.instance.client;
    try {
      final payload = [
        for (final r in rows)
          if (r.saveKey != null)
            {
              'month': m.monthKey,
              'line_key': r.saveKey,
              'invoiced': r.line.amount,
              'note':
                  'From ${parsed.invoiceNumber ?? 'invoice'}: ${r.line.description}',
            }
      ];
      await client
          .from('invoice_lines')
          .upsert(payload, onConflict: 'month,line_key');
      if (!mounted) return;
      setState(() {
        for (final r in rows) {
          if (r.saveKey == null) continue;
          _invoiced[_lineKey(m.monthKey, r.saveKey!)] = _InvoicedLine(
            invoiced: r.line.amount,
            note:
                'From ${parsed.invoiceNumber ?? 'invoice'}: ${r.line.description}',
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Filled in $savable lines from the invoice')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
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
        // Days worked against a PO that has no day rate recorded yet. They
        // price at nothing, so without saying so the composition above reads
        // as though that manpower cost nothing rather than as though nobody
        // has set a rate for it.
        if (_unpricedManDays > 0) ...[
          const SizedBox(height: 10),
          Text(
            '$_unpricedManDays man-day${_unpricedManDays == 1 ? '' : 's'} '
            'not priced — their PO has no day rate recorded yet, so they are '
            'absent from the figures above.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10, height: 1.4, color: const Color(0xFFFFB547)),
          ),
        ],
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
                                  _inr.format(s.subtotalExcl),
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


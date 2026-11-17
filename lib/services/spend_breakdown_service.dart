import 'billing_baseline.dart';
import 'muster_service.dart';
import 'natrax_reconciler.dart' show ServiceCategory;
import 'project_catalog.dart';
import 'session_status.dart';
import 'supabase_service.dart';

/// One programme's spend, by kind, before GST.
class SpendRow {
  final String project;
  double track = 0;

  /// Service lines other than EV charging and workshop — food, water,
  /// weighing pads, conference hall, hire.
  double services = 0;
  double ev = 0;
  double workshop = 0;
  double manpower = 0;
  double deadWeight = 0;
  int sessions = 0;
  int manDays = 0;
  int workshopDays = 0;
  int deadWeightDays = 0;

  /// Mahindra EV PoC: services, EV and workshop are pinned to its invoices
  /// (BillingBaseline) and cannot be split further — EV charging sits inside
  /// the services figure.
  bool pinned = false;

  /// Service lines by name: quantity and rupees, for the detail view.
  final Map<String, ({double quantity, double cost})> serviceLines = {};

  SpendRow(this.project);

  double get total =>
      track + services + ev + workshop + manpower + deadWeight;
}

/// Everything TrackLog has recorded as spend, programme by programme, on
/// one basis: before GST, nothing counted twice.
///
/// Built because the headline on the Projects screen mixed two bases —
/// Mahindra EV before GST, the others grossed up by 18% — and left the
/// muster out altogether. NATRAX bill this SEZ unit without GST (2 Nov
/// 2026), so for them before-GST is what is paid; MOICARS manpower invoices
/// still add 18% IGST, which is said beside the figure rather than mixed in.
class SpendBreakdown {
  final List<SpendRow> rows;

  /// Man-days carried on a PO from before the muster started — worked, but
  /// recorded against no programme.
  final double unassignedManDays;
  final double unassignedManpower;

  /// Known Mahindra EV costs outside the NATRAX invoices (vehicle
  /// validation, instrumentation, Vbox hire). Listed, not in the total.
  final List<UnbilledExtra> outside;

  const SpendBreakdown({
    required this.rows,
    this.unassignedManDays = 0,
    this.unassignedManpower = 0,
    this.outside = const [],
  });

  double get total =>
      rows.fold<double>(0, (s, r) => s + r.total) + unassignedManpower;

  double sum(double Function(SpendRow r) f) =>
      rows.fold<double>(0, (s, r) => s + f(r));

  SpendRow? rowFor(String project) {
    for (final r in rows) {
      if (r.project.toLowerCase() == project.toLowerCase()) return r;
    }
    return null;
  }

  static const _ev = 'Mahindra EV PoC';

  static String _project(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty || t.toLowerCase() == 'general') return _ev;
    return ProjectCatalog.displayName(t);
  }

  /// A service line that is really the workshop / office / porta cabin.
  static bool _isWorkshop(String name) {
    final n = name.toLowerCase();
    return n.contains('workshop') || n.contains('porta') || n.contains('office');
  }

  /// The pure part, so it can be tested without a database.
  ///
  /// [sessions]: id, project_name, track_code, total_cost, started_at,
  /// session_status. [services]: session_id, service_name, quantity,
  /// total_cost. [charges]: the muster's figures per programme.
  /// [positions]: manpower POs, for days worked before the muster began.
  static SpendBreakdown build({
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> services,
    required Map<String, ProjectCharges> charges,
    List<ManpowerPosition> positions = const [],
  }) {
    final rows = <String, SpendRow>{
      for (final p in ProjectCatalog.displayNames) p.toLowerCase(): SpendRow(p),
    };
    SpendRow rowOf(String p) =>
        rows.putIfAbsent(p.toLowerCase(), () => SpendRow(p));

    final covered = BillingBaseline.coveredMonths(_ev);
    final projectOf = <String, String>{};
    final monthOf = <String, String>{};

    for (final s in sessions) {
      final status = ((s['session_status'] as String?) ?? '').toLowerCase();
      if (!kBillableSessionStatuses.contains(status)) continue;
      final id = s['id'] as String;
      final p = _project(s['project_name'] as String?);
      final started = DateTime.tryParse((s['started_at'] as String?) ?? '');
      final month = started == null
          ? ''
          : '${started.year}-${started.month.toString().padLeft(2, '0')}';
      projectOf[id] = p;
      monthOf[id] = month;
      final r = rowOf(p);
      r.track += (s['total_cost'] as num?)?.toDouble() ?? 0;
      final code = ((s['track_code'] as String?) ?? '').trim().toUpperCase();
      if (code != 'MISC') r.sessions++;
    }

    // Workshop logged as a service line, per programme-month, so the muster's
    // workshop days for the same month are not added on top.
    final workshopServiceMonths = <String>{};
    for (final l in services) {
      final sid = l['session_id'] as String?;
      final p = projectOf[sid];
      if (p == null) continue; // a line on a non-billable session
      final name = ((l['service_name'] as String?) ?? 'Other service').trim();
      final cost = (l['total_cost'] as num?)?.toDouble() ?? 0;
      final qty = (l['quantity'] as num?)?.toDouble() ?? 0;
      final r = rowOf(p);
      final month = monthOf[sid] ?? '';
      // Mahindra EV's invoiced months are pinned below as one figure.
      if (p == _ev && covered.contains(month)) continue;
      final prev = r.serviceLines[name];
      r.serviceLines[name] = (
        quantity: (prev?.quantity ?? 0) + qty,
        cost: (prev?.cost ?? 0) + cost,
      );
      if (ServiceCategory.isEv(name)) {
        r.ev += cost;
      } else if (_isWorkshop(name)) {
        r.workshop += cost;
        workshopServiceMonths.add('${p.toLowerCase()}|$month');
      } else {
        r.services += cost;
      }
    }

    // Mahindra EV: services and workshop as invoiced, pinned. Its "Workshop
    // - May 2026" extra is part of the agreed 2,45,000; the other extras sit
    // outside NATRAX's invoices and are listed, not totalled.
    final ev = rowOf(_ev)..pinned = true;
    ev.services += BillingBaseline.accessoriesTotal(_ev);
    ev.workshop += BillingBaseline.workshopTotal(_ev);
    final outside = <UnbilledExtra>[];
    for (final x in BillingBaseline.extrasForProject(_ev)) {
      if (x.label.toLowerCase().startsWith('workshop')) {
        ev.workshop += x.exclGst;
      } else {
        outside.add(x);
      }
    }
    ev.workshopDays =
        (ev.workshop / BillingBaseline.workshopDayRate).round();

    charges.forEach((project, c) {
      final r = rowOf(project);
      r.manpower += c.manpowerCost;
      r.manDays += c.manDays;
      r.deadWeight += c.deadWeightCost;
      r.deadWeightDays += c.deadWeightDays;
      c.workshopByMonth.forEach((month, cost) {
        final skip = workshopServiceMonths.contains('${project.toLowerCase()}|$month') ||
            (project == _ev && covered.contains(month));
        if (skip) return;
        r.workshop += cost;
        r.workshopDays += (cost / kWorkshopRatePerDay).round();
      });
    });

    var openingDays = 0.0, openingMoney = 0.0;
    for (final p in positions) {
      if (p.manDaysOpening <= 0) continue;
      openingDays += p.manDaysOpening;
      openingMoney += p.manDaysOpening * p.ratePerDay;
    }

    return SpendBreakdown(
      rows: rows.values.toList(),
      unassignedManDays: openingDays,
      unassignedManpower: openingMoney,
      outside: outside,
    );
  }
}

class SpendBreakdownService {
  const SpendBreakdownService._();

  static dynamic get _db => SupabaseService.instance.client;

  static Future<SpendBreakdown> load() async {
    final sessions = (await _db
            .from('engineer_sessions')
            .select('id, project_name, track_code, total_cost, started_at, session_status')
            .inFilter('session_status', kBillableSessionStatuses) as List)
        .cast<Map<String, dynamic>>();
    final ids = [for (final s in sessions) s['id'] as String];
    final services = <Map<String, dynamic>>[];
    // In slices: one IN list of every session id grows with the history.
    for (var i = 0; i < ids.length; i += 300) {
      final slice = ids.sublist(i, i + 300 > ids.length ? ids.length : i + 300);
      final rows = await _db
          .from('session_additional_services')
          .select('session_id, service_name, quantity, total_cost')
          .inFilter('session_id', slice);
      services.addAll((rows as List).cast<Map<String, dynamic>>());
    }
    final charges = <String, ProjectCharges>{};
    for (final p in ProjectCatalog.displayNames) {
      try {
        charges[p] = await MusterService.instance.chargesForProject(p);
      } catch (_) {
        // A muster that cannot be read costs the manpower column, not the view.
      }
    }
    List<ManpowerPosition> positions = const [];
    try {
      positions = await MusterService.instance.positions();
    } catch (_) {}
    return SpendBreakdown.build(
      sessions: sessions,
      services: services,
      charges: charges,
      positions: positions,
    );
  }
}

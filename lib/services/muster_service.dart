import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// What a muster row records.
///
/// The two are counted differently and funded differently, which is why they
/// are separate rows rather than two columns on one row:
///
///  - [manpower] is per person per day. Two people for a day is two man-days,
///    so days used is the sum of head counts. Drawn against a MOICARS PO,
///    contracted in days.
///  - [workshop] is per day, flat, whoever is in it. Days used is a count of
///    rows and head count is always zero. Drawn against the NATRAX track PO,
///    a lumpsum billed on actuals, so it accrues rupees rather than drawing
///    down a contracted number of days.
enum MusterKind { manpower, workshop }

extension MusterKindX on MusterKind {
  String get label => this == MusterKind.manpower ? 'Manpower' : 'Workshop';

  /// The `kind` column value. Must match the check constraint on
  /// manpower_muster.kind.
  String get dbValue => name;

  /// PO category a day of this kind draws against.
  String get poCategory =>
      this == MusterKind.manpower ? 'manpower' : 'track_booking';

  static MusterKind parse(String? raw) =>
      (raw ?? '').trim() == 'workshop' ? MusterKind.workshop : MusterKind.manpower;
}

/// Workshop rental at NATRAX, per operational day. Matches the WORKSHOP
/// service line in manual entry and the VBA macro.
const double kWorkshopRatePerDay = 5000.0;

/// One day of the muster: what was consumed, and which PO it draws against.
class MusterDay {
  final String? id;
  final DateTime date;
  final int headCount;
  final String poNumber;
  final String? projectName;
  final String? notes;
  final MusterKind kind;

  const MusterDay({
    this.id,
    required this.date,
    required this.headCount,
    required this.poNumber,
    this.projectName,
    this.notes,
    this.kind = MusterKind.manpower,
  });

  /// One day of drawdown, in the unit this kind is counted in.
  int get daysConsumed =>
      kind == MusterKind.workshop ? 1 : headCount;

  /// 'YYYY-MM-DD' — the form Postgres wants and the key the UI groups on.
  String get dateKey => date.toIso8601String().split('T').first;

  String get monthKey => dateKey.substring(0, 7);

  factory MusterDay.fromJson(Map<String, dynamic> j) => MusterDay(
        id: j['id'] as String?,
        date: DateTime.parse(j['muster_date'] as String),
        headCount: (j['head_count'] as num?)?.toInt() ?? 0,
        poNumber: j['po_number'] as String? ?? '',
        projectName: j['project_name'] as String?,
        notes: j['notes'] as String?,
        kind: MusterKindX.parse(j['kind'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'muster_date': dateKey,
        'po_number': poNumber,
        'project_name': projectName,
        'notes': notes,
        'kind': kind.dbValue,
        // Meaningless for a workshop day, which is flat per day. Forced
        // to zero so it can never leak into the manpower sum.
        'head_count': kind == MusterKind.workshop ? 0 : headCount,
      };
}


/// The workshop position for one PO.
///
/// Deliberately not a [ManpowerPosition]. Manpower POs are contracted in days,
/// so they have a "days left"; the track PO workshop is billed on is a lumpsum
/// on actuals, so there is no contracted day count to draw down. Reporting a
/// days-remaining figure here would be inventing one.
class WorkshopPosition {
  final String poNumber;
  final int daysRecorded;
  final double ratePerDay;

  /// The PO's lumpsum value, for context only. Zero where the value has not
  /// been recorded yet.
  final double poValue;

  /// Closed POs are shown when they carry days, but cannot take new ones.
  final bool isClosed;

  /// Billed against this PO so far, ex-GST, from the invoice register.
  final double invoicedExclGst;

  const WorkshopPosition({
    required this.poNumber,
    required this.daysRecorded,
    required this.ratePerDay,
    required this.poValue,
    this.isClosed = false,
    this.invoicedExclGst = 0,
  });

  /// What is left on the PO: its value less what has been billed against
  /// it. Deliberately measured against INVOICED, not against days recorded -
  /// a day worked draws nothing down until someone bills it, and treating
  /// accrual as drawdown is what once made a PO read overspent with 6.4
  /// lakh still on it. Zero PO value means the figure was never recorded,
  /// so there is no balance to state.
  double? get balanceExclGst =>
      poValue > 0 ? poValue - invoicedExclGst : null;

  double get accruedExclGst => daysRecorded * ratePerDay;
}

/// The manpower position for one PO, in the unit it is actually contracted in.
///
/// Two different counts of "days used" live here on purpose. [manDaysMustered]
/// is what the register says was worked; [manDaysInvoiced] is what MOICARS has
/// billed. They diverge whenever work is done ahead of billing, and collapsing
/// them into one number is what hid 30 unbilled days on 8242356330.
class ManpowerPosition {
  final String poNumber;
  final double daysContracted;
  final double ratePerDay;

  /// When the PO starts. Orders the rollover: when one PO is used up, the next
  /// day books against the next one to come into force, not an arbitrary one.
  final DateTime? validFrom;

  /// Days consumed before the muster existed, carried on the PO because the
  /// dates behind them were never recorded.
  final double manDaysOpening;
  final int manDaysMustered;
  final double manDaysInvoiced;

  const ManpowerPosition({
    required this.poNumber,
    required this.daysContracted,
    required this.ratePerDay,
    required this.manDaysOpening,
    required this.manDaysMustered,
    required this.manDaysInvoiced,
    this.validFrom,
  });

  /// No contracted days left. A further day booked here has no budget behind
  /// it, so the next day belongs on the next PO.
  ///
  /// A PO with no day count recorded yet (daysContracted 0) is not exhausted —
  /// it is unknown, and treating unknown as full would push every day onto a
  /// PO that may not be the right one.
  bool get isExhausted => daysContracted > 0 && daysLeft <= 0;

  /// Close enough that the next booking is worth a warning rather than a
  /// surprise. One day left on a register filled a fortnight at a time is
  /// already too late to notice at the point of entry.
  bool get isNearlyExhausted =>
      daysContracted > 0 && !isExhausted && daysLeft <= 5;

  /// How much of the contracted days are gone, 0..1, for a progress bar.
  double get fractionUsed => daysContracted > 0
      ? (manDaysUsed / daysContracted).clamp(0.0, 1.0)
      : 0.0;

  /// Everything consumed, however it was recorded.
  double get manDaysUsed => manDaysOpening + manDaysMustered;

  double get daysLeft => daysContracted - manDaysUsed;

  /// Worked but not yet billed — the exposure that sits outside PO drawdown.
  double get daysUnbilled {
    final gap = manDaysUsed - manDaysInvoiced;
    return gap > 0 ? gap : 0;
  }

  double get valueUnbilled => daysUnbilled * ratePerDay;
  double get valueMustered => manDaysUsed * ratePerDay;

  bool get isOverrun => daysContracted > 0 && manDaysUsed > daysContracted;

  /// Only meaningful once the PO carries both a value and a day count.
  bool get isComplete => daysContracted > 0 && ratePerDay > 0;
}

/// What one project's muster has accrued.
///
/// A class rather than an inline record because every caller has to name the
/// shape, and a record forces each of them to restate all seven fields — add
/// one and they stop compiling one by one. The figures here are quoted on more
/// than one screen, so the type they travel in should not be the fragile part.
class ProjectCharges {
  /// Man-days priced at their own PO's day rate.
  final double manpowerCost;

  /// Workshop days at the flat daily rental.
  final double workshopCost;

  /// Man-days recorded, priced or not.
  final int manDays;
  final int workshopDays;

  /// Man-days on a PO with no day rate recorded yet. Counted in [manDays] but
  /// contributing nothing to [manpowerCost], because there is no rate to
  /// multiply by — not because the work was free.
  final int manpowerUnpricedDays;

  /// The same money split by 'YYYY-MM', for callers reporting per month.
  final Map<String, double> manpowerByMonth;
  final Map<String, double> workshopByMonth;

  const ProjectCharges({
    this.manpowerCost = 0,
    this.workshopCost = 0,
    this.manDays = 0,
    this.workshopDays = 0,
    this.manpowerUnpricedDays = 0,
    this.manpowerByMonth = const {},
    this.workshopByMonth = const {},
  });

  /// What a project with nothing logged costs. Used where a failed read must
  /// not be mistaken for a project that has spent money.
  static const ProjectCharges none = ProjectCharges();

  double get total => manpowerCost + workshopCost;
}

/// The muster register, and the notifier for it.
///
/// A [ChangeNotifier] because a day recorded here changes figures on screens
/// that are nowhere near the muster — the monthly invoice view prices workshop
/// days off it, and the manager report counts man-days from it. Those used to
/// read the table once when they were opened, so a day marked after that read
/// silently did not exist for them until the screen was rebuilt. Every write
/// below announces itself instead; listeners reload and stay in step.
///
/// Mirrors [ProjectManager]'s shape deliberately: one singleton, listeners
/// attached in initState and dropped in dispose.
class MusterService extends ChangeNotifier {
  MusterService._();
  static MusterService? _instance;
  static MusterService get instance => _instance ??= MusterService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// How many rows one PostgREST round trip asks for. The server caps a
  /// response well below what this register will eventually hold, so the
  /// history is paged rather than requested in one go.
  static const int _pageSize = 1000;

  /// Every day in the register, newest first.
  ///
  /// Pages until the server stops returning a full page, so the count of rows
  /// is bounded by the table and not by a number chosen here. The previous
  /// `limit: 400` silently truncated the history: at roughly a row a day per
  /// PO, plus a workshop row alongside, it was a cut-off the register would
  /// have reached without ever saying so — the oldest months would simply have
  /// stopped appearing.
  Future<List<MusterDay>> list({String? poNumber}) async {
    final out = <MusterDay>[];
    for (var from = 0;; from += _pageSize) {
      var q = _client.from('manpower_muster').select();
      if (poNumber != null && poNumber.isNotEmpty) {
        q = q.eq('po_number', poNumber);
      }
      // `id` is the tiebreaker, and it is not optional. muster_date alone is
      // not unique — a workshop day and a manpower day share a date by
      // design, as do two POs on one date — and Postgres may order tied rows
      // differently between the two queries that fetch consecutive pages.
      // A tie straddling a page boundary would then repeat one row and drop
      // another. Ordering on a unique column makes the sequence total.
      final rows = await q
          .order('muster_date', ascending: false)
          .order('id', ascending: false)
          .range(from, from + _pageSize - 1);
      final batch = (rows as List).cast<Map<String, dynamic>>();
      out.addAll(batch.map(MusterDay.fromJson));
      // A short page is the last page. Equally, an exactly-full final page
      // costs one more empty round trip and then stops — correct, not fast.
      if (batch.length < _pageSize) break;
    }
    return out;
  }

  /// Upsert on (muster_date, po_number, kind), so recording the same day
  /// twice corrects it instead of counting it twice - while still letting a
  /// workshop day and a manpower day share a date.
  Future<void> save(MusterDay day) async {
    await _client.from('manpower_muster').upsert(
          day.toJson(),
          onConflict: 'muster_date,po_number,kind',
        );
    notifyListeners();
  }


  /// Upserts one row per day across an inclusive date range.
  ///
  /// Contract manpower is booked in stretches, not a day at a time, and
  /// marking a fortnight meant fourteen trips through the sheet. The stored
  /// shape does not change: still one row per day, so the drawdown maths, the
  /// per-day edit and the unique constraint all keep working. The range is an
  /// input convenience only.
  ///
  /// Returns how many days were written.
  Future<int> saveRange({
    required DateTime from,
    required DateTime to,
    required int headCount,
    required String poNumber,
    String? projectName,
    String? notes,
    MusterKind kind = MusterKind.manpower,
    /// Saturdays to count, as 'YYYY-MM-DD'. Saturday is worked some weeks
    /// and not others, so it cannot be inferred - the caller names the ones
    /// actually worked. Sunday is never counted here; a one-off Sunday is
    /// recorded by saving that single date on its own.
    Set<String> saturdaysWorked = const {},
  }) async {
    var day = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(day)) return 0;

    final rows = <Map<String, dynamic>>[];
    while (!day.isAfter(end)) {
      // The contract week is Mon-Fri. Dragging a range across a weekend
      // must not book those days and draw them off the PO - the silent
      // over-count this register exists to stop.
      //
      // Sunday is never worked, so a range never books one. Saturday is
      // worked some weeks and not others, so each one in the range has to
      // be named explicitly rather than guessed from a blanket setting.
      //
      // Workshop is the exception, the other way round: the rental is payable
      // for every calendar day of the hire, whether or not anybody is in the
      // workshop that day. So a workshop range books all seven days and skips
      // nothing. Manpower keeps the weekday rule, because a technician is paid
      // for days actually worked.
      final key = day.toIso8601String().split('T').first;
      final skip = kind == MusterKind.workshop
          ? false
          : (day.weekday == DateTime.sunday ||
              (day.weekday == DateTime.saturday &&
                  !saturdaysWorked.contains(key)));
      if (skip) {
        day = DateTime(day.year, day.month, day.day + 1);
        continue;
      }
      rows.add(MusterDay(
        date: day,
        headCount: headCount,
        poNumber: poNumber,
        projectName: projectName,
        notes: notes,
        kind: kind,
      ).toJson());
      // Rebuilt from parts rather than adding a Duration, so the walk cannot
      // drift on a day that is not 24 hours long.
      day = DateTime(day.year, day.month, day.day + 1);
    }

    // A weekend-only range with no Saturday ticked legitimately writes
    // nothing. Sending an empty list to upsert is not an error worth
    // raising at the user.
    if (rows.isEmpty) return 0;

    await _client.from('manpower_muster').upsert(
          rows,
          onConflict: 'muster_date,po_number,kind',
        );
    notifyListeners();
    return rows.length;
  }

  Future<void> delete(String id) async {
    await _client.from('manpower_muster').delete().eq('id', id);
    notifyListeners();
  }

  /// What a project's muster has accrued: manpower priced off each day's own
  /// PO rate, and workshop at the flat daily rental.
  ///
  /// One implementation, called by every screen that shows these figures, so
  /// the Analyser and the History panel cannot quote different numbers for the
  /// same project.
  ///
  /// Rows with an empty or 'General' project_name belong to Mahindra EV PoC —
  /// the convention the session path has always applied. Matching project_name
  /// exactly in SQL instead, as the Analyser used to, made those rows match no
  /// project at all and vanish from every total, so the filtering is done here
  /// in Dart where the convention can be honoured.
  ///
  /// [manpowerUnpricedDays] counts man-days sitting on a PO with no day rate
  /// yet — its value or day count is still zero, so the rate divides to zero
  /// and the days would otherwise contribute nothing with nothing said. They
  /// are real days worked; the caller can show them as unpriced rather than
  /// letting them read as free.
  /// [manpowerByMonth] and [workshopByMonth] carry the same figures split by
  /// 'YYYY-MM', for callers that report per month rather than in total. They
  /// are returned from this one call rather than computed again by the caller:
  /// the Analyser grouped the muster itself and matched project_name exactly
  /// in SQL, so it and the History panel could disagree about one project's
  /// manpower. Same rows, same rules, one place.
  /// Passing null (or an empty name) totals every project instead of one —
  /// what a view showing all programmes at once needs, without it having to
  /// call this once per programme and add the results up itself.
  Future<ProjectCharges> chargesForProject(String? projectName) async {
    final key = (projectName ?? '').toLowerCase().trim();
    final everyProject = key.isEmpty;
    bool belongs(String? raw) {
      if (everyProject) return true;
      final r = (raw ?? '').trim();
      if (r.isEmpty || r.toLowerCase() == 'general') {
        return key == 'mahindra ev poc';
      }
      return r.toLowerCase() == key;
    }

    final rows = await _client
        .from('manpower_muster')
        .select('muster_date, head_count, kind, po_number, project_name');

    final pos = await _client
        .from('po_trackers')
        .select('po_number, total_po_value, manpower_days')
        .eq('category', 'manpower');

    final rate = <String, double>{};
    for (final p in (pos as List)) {
      final n = (p['po_number'] as String? ?? '').trim();
      final v = (p['total_po_value'] as num?)?.toDouble() ?? 0;
      final d = (p['manpower_days'] as num?)?.toDouble() ?? 0;
      rate[n] = d > 0 ? v / d : 0.0;
    }

    double manpowerCost = 0, workshopCost = 0;
    int manDays = 0, workshopDays = 0, unpriced = 0;
    final manByMonth = <String, double>{};
    final shopByMonth = <String, double>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      if (!belongs(r['project_name'] as String?)) continue;
      // 'YYYY-MM-DD' -> 'YYYY-MM'. A row whose date is too short to carry a
      // month is skipped rather than bucketed under a truncated key.
      final dateStr = (r['muster_date'] as String? ?? '');
      final monthKey = dateStr.length >= 7 ? dateStr.substring(0, 7) : null;
      if (MusterKindX.parse(r['kind'] as String?) == MusterKind.workshop) {
        workshopDays++;
        workshopCost += kWorkshopRatePerDay;
        if (monthKey != null) {
          shopByMonth[monthKey] =
              (shopByMonth[monthKey] ?? 0) + kWorkshopRatePerDay;
        }
      } else {
        final heads = (r['head_count'] as num?)?.toInt() ?? 0;
        final po = (r['po_number'] as String? ?? '').trim();
        final perDay = rate[po] ?? 0.0;
        manDays += heads;
        if (perDay <= 0) {
          unpriced += heads;
        } else {
          manpowerCost += heads * perDay;
          if (monthKey != null) {
            manByMonth[monthKey] =
                (manByMonth[monthKey] ?? 0) + (heads * perDay);
          }
        }
      }
    }
    return ProjectCharges(
      manpowerCost: manpowerCost,
      workshopCost: workshopCost,
      manDays: manDays,
      workshopDays: workshopDays,
      manpowerUnpricedDays: unpriced,
      manpowerByMonth: manByMonth,
      workshopByMonth: shopByMonth,
    );
  }

  /// Man-days mustered per PO — manpower rows only.
  ///
  /// Filtered on kind because workshop rows carry head_count 0 and are counted
  /// by row, not by head. Summing across both kinds would report every workshop
  /// day as zero man-days and quietly understate nothing, but the filter makes
  /// the intent explicit rather than relying on that zero.
  Future<Map<String, int>> manDaysByPo() async {
    final rows = await _client
        .from('manpower_muster')
        .select('po_number, head_count')
        .eq('kind', MusterKind.manpower.dbValue);
    final out = <String, int>{};
    for (final r in rows as List) {
      final po = (r['po_number'] as String? ?? '').trim();
      if (po.isEmpty) continue;
      out[po] = (out[po] ?? 0) + ((r['head_count'] as num?)?.toInt() ?? 0);
    }
    return out;
  }

  /// Workshop days per PO — a row count, since the rental is flat per day.
  Future<Map<String, int>> workshopDaysByPo() async {
    final rows = await _client
        .from('manpower_muster')
        .select('po_number')
        .eq('kind', MusterKind.workshop.dbValue);
    final out = <String, int>{};
    for (final r in rows as List) {
      final po = (r['po_number'] as String? ?? '').trim();
      if (po.isEmpty) continue;
      out[po] = (out[po] ?? 0) + 1;
    }
    return out;
  }

  /// The POs a workshop day can be booked against.
  ///
  /// Workshop is billed on the NATRAX track PO, not a manpower one — 8242390552
  /// is described in the source document as "Track & Workshop Booking". Those
  /// POs are lumpsum billed on actuals rather than contracted in days, so a
  /// workshop day accrues rupees against them instead of drawing a day down.
  /// The PO every August-2026-onwards resource books against.
  ///
  /// NATRAX quote the PO on the invoice and use the latest one unless something
  /// else is explicitly agreed, so a day booked to a superseded PO cannot be
  /// invoiced against the PO the invoice will actually name. 8242348442 is the
  /// previous Track & Workshop Booking PO; six September workshop days were
  /// booked to it by mistake and had to be moved.
  static const String kCurrentTrackBookingPo = '8242390552';

  /// The date from which [kCurrentTrackBookingPo] is the only valid
  /// destination. Days before it stay wherever they were booked.
  static final DateTime kCurrentTrackPoFrom = DateTime(2026, 8, 1);

  Future<List<Map<String, dynamic>>> workshopPos() async {
    final rows = await _client
        .from('po_trackers')
        .select('po_number, po_status, total_po_value, valid_from')
        .eq('category', 'track_booking')
        .order('po_status');
    final open = (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => (r['po_status'] as String? ?? '') != 'closed')
        .toList();
    // Superseded track POs are dropped from the picker outright rather than
    // merely deprioritised. Leaving them selectable is how six days ended up
    // on 8242348442, and a mis-booked day is invisible until somebody
    // reconciles an invoice months later.
    open.removeWhere((r) =>
        (r['po_number'] as String? ?? '').trim() != kCurrentTrackBookingPo);
    return open;
  }

  /// Every track PO that workshop can be or has been booked against.
  ///
  /// Unlike [workshopPos] this does not drop closed POs. A closed PO cannot
  /// take new days but the days already on it still have to be reported -
  /// 8242348442 is the historical "Track & Workshop Booking" PO, so that is
  /// precisely where the older workshop days sit.
  Future<List<Map<String, dynamic>>> _allWorkshopPos() async {
    final rows = await _client
        .from('po_trackers')
        .select('po_number, po_status, total_po_value, valid_from')
        .eq('category', 'track_booking')
        .order('po_number');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Workshop position per PO: days recorded and what they accrue.
  Future<List<WorkshopPosition>> workshopPositions({
    Map<String, double> invoicedExclGstByPo = const {},
  }) async {
    final days = await workshopDaysByPo();
    final pos = await _allWorkshopPos();
    final out = pos.map((p) {
      final number = (p['po_number'] as String? ?? '').trim();
      return WorkshopPosition(
        poNumber: number,
        daysRecorded: days[number] ?? 0,
        ratePerDay: kWorkshopRatePerDay,
        poValue: (p['total_po_value'] as num?)?.toDouble() ?? 0,
        isClosed: (p['po_status'] as String? ?? '') == 'closed',
        invoicedExclGst: invoicedExclGstByPo[number] ?? 0,
      );
    }).toList();
    // An open PO with no days yet is still worth showing - it is where the
    // next one goes. A closed PO with no days is finished and empty, so it
    // only earns a card if something was actually booked to it.
    out.removeWhere((w) => w.isClosed && w.daysRecorded == 0);
    out.sort((a, b) => a.poNumber.compareTo(b.poNumber));
    return out;
  }


  /// Builds the position for every manpower PO.
  ///
  /// [invoicedExclGstByPo] comes from the invoices already loaded by the
  /// caller — this service does not re-read them, so the two views cannot
  /// disagree about what has been billed.
  Future<List<ManpowerPosition>> positions({
    Map<String, double> invoicedExclGstByPo = const {},
  }) async {
    final pos = await _client
        .from('po_trackers')
        .select('po_number, total_po_value, manpower_days, '
            'manpower_days_opening, category, valid_from')
        .eq('category', 'manpower');

    final mustered = await manDaysByPo();

    return (pos as List).cast<Map<String, dynamic>>().map((p) {
      final number = (p['po_number'] as String? ?? '').trim();
      final base = (p['total_po_value'] as num?)?.toDouble() ?? 0;
      final days = (p['manpower_days'] as num?)?.toDouble() ?? 0;
      final rate = days > 0 ? base / days : 0.0;
      final invoiced = invoicedExclGstByPo[number] ?? 0;
      return ManpowerPosition(
        poNumber: number,
        daysContracted: days,
        ratePerDay: rate,
        manDaysOpening:
            (p['manpower_days_opening'] as num?)?.toDouble() ?? 0,
        manDaysMustered: mustered[number] ?? 0,
        manDaysInvoiced: rate > 0 ? invoiced / rate : 0,
        validFrom: DateTime.tryParse((p['valid_from'] ?? '').toString()),
      );
    }).toList()
      ..sort((a, b) => a.poNumber.compareTo(b.poNumber));
  }

  /// The manpower POs a muster day can be booked against.
  Future<List<Map<String, dynamic>>> activeManpowerPos() async {
    final rows = await _client
        .from('po_trackers')
        .select('po_number, po_status, total_po_value, manpower_days, valid_from')
        .eq('category', 'manpower')
        .order('po_status');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => (r['po_status'] as String? ?? '') != 'closed')
        .toList();
  }

  /// The manpower PO a new day should book against.
  ///
  /// The PO in force with days still on it, earliest first — so a register
  /// stays on one PO until it is used up and then rolls onto the next, rather
  /// than piling days onto a PO with no budget behind them. 8242356330 reached
  /// exactly its 38 contracted days (28 opening + 10 mustered) on the 14 Sep
  /// 2026 data while the muster was still defaulting to it; every further day
  /// would have been an overrun nothing warned about.
  ///
  /// Returns null when every PO is exhausted or none carries a day count —
  /// the caller must say so rather than silently pick one.
  String? nextManpowerPo(List<ManpowerPosition> positions) {
    final usable = positions.where((p) => !p.isExhausted).toList()
      ..sort((a, b) {
        // A PO with a start date comes before one without, and earlier before
        // later. Ties fall back to the number so the choice is deterministic.
        final av = a.validFrom, bv = b.validFrom;
        if (av != null && bv != null && av != bv) return av.compareTo(bv);
        if (av != null && bv == null) return -1;
        if (av == null && bv != null) return 1;
        return a.poNumber.compareTo(b.poNumber);
      });
    // Prefer one that actually has a contracted day count; a PO whose days are
    // still unknown cannot be shown as having room.
    for (final p in usable) {
      if (p.daysContracted > 0) return p.poNumber;
    }
    return usable.isEmpty ? null : usable.first.poNumber;
  }
}

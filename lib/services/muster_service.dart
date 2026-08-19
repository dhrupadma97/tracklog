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

  const WorkshopPosition({
    required this.poNumber,
    required this.daysRecorded,
    required this.ratePerDay,
    required this.poValue,
  });

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
  });

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

class MusterService {
  MusterService._();
  static MusterService? _instance;
  static MusterService get instance => _instance ??= MusterService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  Future<List<MusterDay>> list({String? poNumber, int limit = 400}) async {
    var q = _client.from('manpower_muster').select();
    if (poNumber != null && poNumber.isNotEmpty) {
      q = q.eq('po_number', poNumber);
    }
    final rows = await q.order('muster_date', ascending: false).limit(limit);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(MusterDay.fromJson)
        .toList();
  }

  /// Upsert on (muster_date, po_number, kind), so recording the same day
  /// twice corrects it instead of counting it twice - while still letting a
  /// workshop day and a manpower day share a date.
  Future<void> save(MusterDay day) async {
    await _client.from('manpower_muster').upsert(
          day.toJson(),
          onConflict: 'muster_date,po_number,kind',
        );
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
  }) async {
    var day = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(day)) return 0;

    final rows = <Map<String, dynamic>>[];
    while (!day.isAfter(end)) {
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

    await _client.from('manpower_muster').upsert(
          rows,
          onConflict: 'muster_date,po_number,kind',
        );
    return rows.length;
  }

  Future<void> delete(String id) async {
    await _client.from('manpower_muster').delete().eq('id', id);
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
  Future<List<Map<String, dynamic>>> workshopPos() async {
    final rows = await _client
        .from('po_trackers')
        .select('po_number, po_status, total_po_value, valid_from')
        .eq('category', 'track_booking')
        .order('po_status');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => (r['po_status'] as String? ?? '') != 'closed')
        .toList();
  }

  /// Workshop position per PO: days recorded and what they accrue.
  Future<List<WorkshopPosition>> workshopPositions() async {
    final days = await workshopDaysByPo();
    final pos = await workshopPos();
    final out = pos.map((p) {
      final number = (p['po_number'] as String? ?? '').trim();
      return WorkshopPosition(
        poNumber: number,
        daysRecorded: days[number] ?? 0,
        ratePerDay: kWorkshopRatePerDay,
        poValue: (p['total_po_value'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
    // A PO that has never had a workshop day recorded is still worth showing:
    // it is where the next one goes.
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
            'manpower_days_opening, category')
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
}

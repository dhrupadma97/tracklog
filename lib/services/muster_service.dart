import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// One day of the manpower muster: how many people were on site, and which
/// manpower PO the day draws against.
class MusterDay {
  final String? id;
  final DateTime date;
  final int headCount;
  final String poNumber;
  final String? projectName;
  final String? notes;

  const MusterDay({
    this.id,
    required this.date,
    required this.headCount,
    required this.poNumber,
    this.projectName,
    this.notes,
  });

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
      );

  Map<String, dynamic> toJson() => {
        'muster_date': dateKey,
        'head_count': headCount,
        'po_number': poNumber,
        'project_name': projectName,
        'notes': notes,
      };
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

  /// Upsert on (muster_date, po_number), so recording the same day twice
  /// corrects it instead of counting it twice.
  Future<void> save(MusterDay day) async {
    await _client.from('manpower_muster').upsert(
          day.toJson(),
          onConflict: 'muster_date,po_number',
        );
  }

  Future<void> delete(String id) async {
    await _client.from('manpower_muster').delete().eq('id', id);
  }

  /// Man-days mustered per PO.
  Future<Map<String, int>> manDaysByPo() async {
    final rows =
        await _client.from('manpower_muster').select('po_number, head_count');
    final out = <String, int>{};
    for (final r in rows as List) {
      final po = (r['po_number'] as String? ?? '').trim();
      if (po.isEmpty) continue;
      out[po] = (out[po] ?? 0) + ((r['head_count'] as num?)?.toInt() ?? 0);
    }
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

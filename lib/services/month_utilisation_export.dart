import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'excel_backup_downloader.dart';
import 'project_catalog.dart';
import 'project_manager.dart';
import 'session_status.dart';
import 'supabase_service.dart';
import 'track_cost_rules.dart';

/// One track, on one day, for one programme — the row NATRAX bills.
///
/// NATRAX charges whole hours per track per day, so this is the unit their
/// utilisation sheet is written in. Comparing session by session against that
/// sheet is impossible: four runs on T8 appear as four lines there and one
/// charge.
class UtilisationRow {
  final DateTime date;
  final String project;
  final String trackCode;
  final String trackName;
  final int sessions;
  final int minutes;
  final double billableHours;
  final double cost;

  const UtilisationRow({
    required this.date,
    required this.project,
    required this.trackCode,
    required this.trackName,
    required this.sessions,
    required this.minutes,
    required this.billableHours,
    required this.cost,
  });
}

/// Downloads one month of track usage as a .xlsx, in the shape NATRAX bills.
///
/// Reconciling the September sheet by hand took a backup, a script and an
/// afternoon, and it turned up 16 hours on the sheet that belonged to another
/// customer's booking. That check has to be something the app can hand over in
/// one click, every month, before the invoice is raised.
///
/// Costs are the ones already stored on the sessions, not recomputed here:
/// the app priced them at entry with the marginal rule, and an export that
/// re-derived them could disagree with every other screen. Only the billable
/// hours are worked out, because NATRAX's sheet quotes hours and the database
/// stores rupees.
class MonthUtilisationExport {
  const MonthUtilisationExport._();

  static const _sheetUtilisation = 'Utilisation';
  static const _sheetSessions = 'Sessions';
  static const _sheetServices = 'Other Services';
  static const _sheetSummary = 'Summary';

  /// Builds the workbook for [month] and hands it to the browser.
  ///
  /// [project] null means every programme. Returns the filename written.
  static Future<String> run({
    required DateTime month,
    String? project,
  }) async {
    final data = await _fetch(month: month, project: project);
    final name = fileName(month, project);
    ExcelBackupDownloader.save(_build(data, month, project), name);
    return name;
  }

  static String fileName(DateTime month, String? project) {
    final scope = project == null
        ? 'All'
        : project.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    return 'TrackLog_Utilisation_${DateFormat('MMM-yyyy').format(month)}'
        '_$scope.xlsx';
  }

  // ── Fetch ────────────────────────────────────────────────────────────────

  static Future<_MonthData> _fetch({
    required DateTime month,
    String? project,
  }) async {
    final client = SupabaseService.instance.client;
    final from = DateTime(month.year, month.month, 1);
    final to = DateTime(month.year, month.month + 1, 1);

    final raw = await client
        .from('engineer_sessions')
        .select('id, started_at, ended_at, track_code, track_name, '
            'project_name, duration_minutes, hourly_rate, total_cost, '
            'session_status, venue, notes')
        .gte('started_at', from.toIso8601String())
        .lt('started_at', to.toIso8601String())
        .order('started_at');

    // Scoped through ProjectManager, never by matching project_name in the
    // query: empty and 'General' both mean Mahindra EV PoC, and an exact match
    // drops every one of those rows from every programme.
    final rows = (raw as List)
        .cast<Map<String, dynamic>>()
        .where((r) => project == null ||
            ProjectManager.sessionBelongsTo(
                r['project_name'] as String?, project))
        .toList();

    final ids = rows.map((r) => r['id'] as String).toList();
    var services = <Map<String, dynamic>>[];
    if (ids.isNotEmpty) {
      final svc = await client
          .from('session_additional_services')
          .select('session_id, service_name, quantity, rate, total_cost, notes')
          .inFilter('session_id', ids);
      services = (svc as List).cast<Map<String, dynamic>>();
    }

    return _MonthData(sessions: rows, services: services);
  }

  // ── Grouping ─────────────────────────────────────────────────────────────

  /// Collapses sessions into one row per track, per day, per programme.
  ///
  /// Only billable statuses count, and MISC containers are dropped: they carry
  /// no track time and exist to hold service lines. Their money still reaches
  /// the export, on the services sheet.
  static List<UtilisationRow> utilisation(List<Map<String, dynamic>> sessions) {
    final buckets = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      final code = (s['track_code'] as String? ?? '').toUpperCase();
      if (code == 'MISC' || code.isEmpty) continue;
      final status = (s['session_status'] as String? ?? '').toLowerCase();
      if (!kBillableSessionStatuses.contains(status)) continue;
      final started = DateTime.tryParse(s['started_at'] as String? ?? '');
      if (started == null) continue;

      final day = DateTime(started.year, started.month, started.day);
      final proj = ProjectCatalog.displayName(s['project_name'] as String?);
      buckets.putIfAbsent('${day.toIso8601String()}|$proj|$code', () => [])
          .add(s);
    }

    // The minimum belongs to the group, not the surface — T3 Wet and T3 Dry
    // share one. So each track rounds up on its own first, and only the
    // shortfall the group has not covered between them is added, to the track
    // carrying the most minutes that day.
    final minutesByGroup = <String, int>{};
    final ceilByGroup = <String, double>{};
    for (final entry in buckets.entries) {
      final parts = entry.key.split('|');
      final code = parts[2];
      final gk = '${parts[0]}|${parts[1]}|${TrackCostRules.groupFor(code).first}';
      final mins = entry.value.fold<int>(
          0, (t, s) => t + ((s['duration_minutes'] as num?)?.toInt() ?? 0));
      minutesByGroup[gk] = (minutesByGroup[gk] ?? 0) + mins;
      ceilByGroup[gk] =
          (ceilByGroup[gk] ?? 0) + TrackCostRules.ceilHours(mins);
    }

    final out = <UtilisationRow>[];
    final shortfallUsed = <String>{};
    final keys = buckets.keys.toList()..sort();
    // Biggest first inside a group, so a shortfall lands on the track that
    // actually ran rather than on whichever string sorts first.
    keys.sort((a, b) {
      final ma = buckets[a]!.fold<int>(
          0, (t, s) => t + ((s['duration_minutes'] as num?)?.toInt() ?? 0));
      final mb = buckets[b]!.fold<int>(
          0, (t, s) => t + ((s['duration_minutes'] as num?)?.toInt() ?? 0));
      return a.split('|')[0] == b.split('|')[0] ? mb.compareTo(ma) : a.compareTo(b);
    });

    for (final key in keys) {
      final group = buckets[key]!;
      final parts = key.split('|');
      final day = DateTime.parse(parts[0]);
      final proj = parts[1];
      final code = parts[2];
      final gk = '${parts[0]}|$proj|${TrackCostRules.groupFor(code).first}';

      final mins = group.fold<int>(
          0, (t, s) => t + ((s['duration_minutes'] as num?)?.toInt() ?? 0));
      var hours = TrackCostRules.ceilHours(mins);

      final minHrs = _minHoursFor(code);
      if (!shortfallUsed.contains(gk)) {
        final shortfall = minHrs - (ceilByGroup[gk] ?? 0);
        if (shortfall > 0) {
          hours += shortfall;
          shortfallUsed.add(gk);
        }
      }

      out.add(UtilisationRow(
        date: day,
        project: proj,
        trackCode: code,
        trackName: (group.first['track_name'] as String? ?? '').trim(),
        sessions: group.length,
        minutes: mins,
        billableHours: hours,
        cost: group.fold<double>(
            0, (t, s) => t + ((s['total_cost'] as num?)?.toDouble() ?? 0)),
      ));
    }

    out.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.trackCode.compareTo(b.trackCode);
    });
    return out;
  }

  /// The day minimum for a track code.
  ///
  /// T1, T2 and both braking surfaces carry two hours from the booking terms;
  /// T12 is the one other exception. Everything else bills from one hour, per
  /// the programme owner. Held here rather than read from `track_rates`
  /// because the rate card's `min_hours_per_day` defaults to 1 and has never
  /// been the source these figures reconcile against.
  static double _minHoursFor(String code) =>
      const {'T1', 'T2', 'T3W', 'T3D', 'T12'}.contains(code.toUpperCase())
          ? 2
          : 1;

  // ── Workbook ─────────────────────────────────────────────────────────────

  static Uint8List _build(_MonthData data, DateTime month, String? project) {
    final book = Excel.createExcel();
    final rows = utilisation(data.sessions);
    final label = DateFormat('MMMM yyyy').format(month);

    // Utilisation: the sheet to hold next to NATRAX's own.
    final u = book[_sheetUtilisation];
    u.appendRow([TextCellValue('Track utilisation — $label')]);
    u.appendRow([TextCellValue(project ?? 'All programmes')]);
    u.appendRow([]);
    u.appendRow(const [
      'Date', 'Programme', 'Track', 'Track Name', 'Sessions',
      'Minutes', 'Billable Hrs', 'Cost (excl GST)',
    ].map(TextCellValue.new).toList());
    for (final r in rows) {
      u.appendRow([
        TextCellValue(DateFormat('dd-MMM-yyyy').format(r.date)),
        TextCellValue(r.project),
        TextCellValue(r.trackCode),
        TextCellValue(r.trackName),
        IntCellValue(r.sessions),
        IntCellValue(r.minutes),
        DoubleCellValue(r.billableHours),
        DoubleCellValue(r.cost),
      ]);
    }
    u.appendRow([]);
    u.appendRow([
      TextCellValue('Total'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      IntCellValue(rows.fold<int>(0, (t, r) => t + r.sessions)),
      IntCellValue(rows.fold<int>(0, (t, r) => t + r.minutes)),
      DoubleCellValue(rows.fold<double>(0, (t, r) => t + r.billableHours)),
      DoubleCellValue(rows.fold<double>(0, (t, r) => t + r.cost)),
    ]);

    // Summary: per track, the same shape as NATRAX's "Track Code & Total Hours".
    final byTrack = <String, ({double hrs, double cost, int mins})>{};
    for (final r in rows) {
      final p = byTrack[r.trackCode] ?? (hrs: 0.0, cost: 0.0, mins: 0);
      byTrack[r.trackCode] = (
        hrs: p.hrs + r.billableHours,
        cost: p.cost + r.cost,
        mins: p.mins + r.minutes,
      );
    }
    final s = book[_sheetSummary];
    s.appendRow([TextCellValue('Track totals — $label')]);
    s.appendRow([TextCellValue(project ?? 'All programmes')]);
    s.appendRow([]);
    s.appendRow(const ['Track', 'Minutes', 'Billable Hrs', 'Cost (excl GST)']
        .map(TextCellValue.new)
        .toList());
    for (final code in byTrack.keys.toList()..sort()) {
      final v = byTrack[code]!;
      s.appendRow([
        TextCellValue(code),
        IntCellValue(v.mins),
        DoubleCellValue(v.hrs),
        DoubleCellValue(v.cost),
      ]);
    }
    s.appendRow([]);
    s.appendRow([
      TextCellValue('Total'),
      IntCellValue(byTrack.values.fold<int>(0, (t, v) => t + v.mins)),
      DoubleCellValue(byTrack.values.fold<double>(0, (t, v) => t + v.hrs)),
      DoubleCellValue(byTrack.values.fold<double>(0, (t, v) => t + v.cost)),
    ]);
    s.appendRow([]);
    s.appendRow([
      TextCellValue('Generated'),
      TextCellValue(DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())),
    ]);
    s.appendRow([
      TextCellValue('Billable hours are whole hours per track per day, '
          'with the day minimum applied once per braking track.'),
    ]);

    // Sessions: the detail behind every line above, so a disputed hour can be
    // traced to the clock times that produced it.
    final d = book[_sheetSessions];
    d.appendRow(const [
      'Date', 'Start', 'End', 'Programme', 'Track', 'Track Name',
      'Duration (min)', 'Cost (excl GST)', 'Status', 'Venue', 'Notes',
    ].map(TextCellValue.new).toList());
    for (final r in data.sessions) {
      final st = DateTime.tryParse(r['started_at'] as String? ?? '');
      final en = DateTime.tryParse(r['ended_at'] as String? ?? '');
      d.appendRow([
        TextCellValue(st == null ? '' : DateFormat('dd-MMM-yyyy').format(st)),
        TextCellValue(st == null ? '' : DateFormat('HH:mm').format(st)),
        TextCellValue(en == null ? '' : DateFormat('HH:mm').format(en)),
        TextCellValue(
            ProjectCatalog.displayName(r['project_name'] as String?)),
        TextCellValue((r['track_code'] as String? ?? '').toString()),
        TextCellValue((r['track_name'] as String? ?? '').toString()),
        IntCellValue((r['duration_minutes'] as num?)?.toInt() ?? 0),
        DoubleCellValue((r['total_cost'] as num?)?.toDouble() ?? 0),
        TextCellValue((r['session_status'] as String? ?? '').toString()),
        TextCellValue((r['venue'] as String? ?? '').toString()),
        TextCellValue((r['notes'] as String? ?? '').toString()),
      ]);
    }

    // Services carry no date of their own — it lives on the parent session.
    final byId = {for (final r in data.sessions) r['id'] as String: r};
    final v = book[_sheetServices];
    v.appendRow(const [
      'Date', 'Programme', 'Service', 'Qty', 'Rate', 'Cost (excl GST)', 'Notes',
    ].map(TextCellValue.new).toList());
    var svcTotal = 0.0;
    for (final r in data.services) {
      final parent = byId[r['session_id'] as String?];
      final st = DateTime.tryParse(parent?['started_at'] as String? ?? '');
      final cost = (r['total_cost'] as num?)?.toDouble() ?? 0;
      svcTotal += cost;
      v.appendRow([
        TextCellValue(st == null ? '' : DateFormat('dd-MMM-yyyy').format(st)),
        TextCellValue(
            ProjectCatalog.displayName(parent?['project_name'] as String?)),
        TextCellValue((r['service_name'] as String? ?? '').toString()),
        DoubleCellValue((r['quantity'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((r['rate'] as num?)?.toDouble() ?? 0),
        DoubleCellValue(cost),
        TextCellValue((r['notes'] as String? ?? '').toString()),
      ]);
    }
    v.appendRow([]);
    v.appendRow([
      TextCellValue('Total'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(svcTotal),
    ]);

    // Excel.createExcel() seeds 'Sheet1'. Dropped only once real sheets exist:
    // deleting the last sheet leaves a workbook Excel refuses to open.
    if (book.sheets.keys.contains('Sheet1') && book.sheets.length > 1) {
      book.delete('Sheet1');
    }

    final bytes = book.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel encoding produced no bytes');
    }
    return Uint8List.fromList(bytes);
  }
}

class _MonthData {
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> services;
  const _MonthData({required this.sessions, required this.services});
}

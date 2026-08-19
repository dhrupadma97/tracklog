import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// One row of any backup sheet, already flattened to primitives.
///
/// The rows are built from Supabase maps by [BackupData.fromRows] rather than
/// inside the writer, so the writer itself takes no network, no Supabase types
/// and no clock — which is what makes it testable.
typedef Row = List<Object?>;

/// Everything the backup workbook contains, already fetched and flattened.
class BackupData {
  final List<Row> sessions;
  final List<Row> services;
  final List<Row> muster;
  final DateTime generatedAt;

  const BackupData({
    required this.sessions,
    required this.services,
    required this.muster,
    required this.generatedAt,
  });

  static const sessionHeaders = <String>[
    'Date', 'Venue', 'Track Code', 'Track Name', 'Project',
    'Start', 'End', 'Duration (min)', 'Hourly Rate', 'Total Cost (excl GST)',
    'Status', 'Notes',
  ];

  // session_additional_services holds no date or project of its own - both
  // belong to the parent session, so they arrive via the join and are read
  // out of the nested map. There is no service_code column either.
  static const serviceHeaders = <String>[
    'Date', 'Project', 'Service Name', 'Qty', 'Rate',
    'Total Cost (excl GST)',
  ];

  static const musterHeaders = <String>[
    'Date', 'Kind', 'Head Count', 'PO Number', 'Project', 'Notes',
  ];

  /// Rounds to paise. Doubles accumulate error across a few thousand rows and
  /// a backup that does not tie out to the app by a stray 0.000001 is worse
  /// than useless — it starts an investigation into nothing.
  static double money(num? v) =>
      ((v ?? 0).toDouble() * 100).roundToDouble() / 100;

  static String _date(Object? raw) {
    if (raw == null) return '';
    final s = raw.toString();
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return DateFormat('dd-MMM-yyyy').format(dt.toLocal());
  }

  static String _time(Object? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  /// Builds the workbook rows from raw Supabase maps.
  ///
  /// Every field is read defensively. A backup that throws because one row has
  /// a null the schema allows is a backup that does not exist when it matters.
  factory BackupData.fromRows({
    required List<Map<String, dynamic>> sessionRows,
    required List<Map<String, dynamic>> serviceRows,
    required List<Map<String, dynamic>> musterRows,
    required DateTime generatedAt,
  }) {
    final sessions = <Row>[];
    for (final r in sessionRows) {
      sessions.add([
        _date(r['started_at']),
        (r['venue'] ?? 'NATRAX').toString(),
        (r['track_code'] ?? '').toString(),
        (r['track_name'] ?? '').toString(),
        (r['project_name'] ?? '').toString(),
        _time(r['started_at']),
        _time(r['ended_at']),
        (r['duration_minutes'] as num?)?.toInt() ?? 0,
        money(r['hourly_rate'] as num?),
        money(r['total_cost'] as num?),
        (r['session_status'] ?? '').toString(),
        (r['notes'] ?? '').toString(),
      ]);
    }

    final services = <Row>[];
    for (final r in serviceRows) {
      // Supabase nests an embedded select under the table name. Fall back
      // to flat keys so a caller that pre-flattened still works.
      final parent = r['engineer_sessions'];
      final p = parent is Map ? parent : const {};
      services.add([
        _date(p['started_at'] ?? r['started_at'] ?? r['created_at']),
        (p['project_name'] ?? r['project_name'] ?? '').toString(),
        (r['service_name'] ?? '').toString(),
        (r['quantity'] as num?)?.toDouble() ?? 0,
        money(r['rate'] as num?),
        money(r['total_cost'] as num?),
      ]);
    }

    final muster = <Row>[];
    for (final r in musterRows) {
      muster.add([
        _date(r['muster_date']),
        (r['kind'] ?? 'manpower').toString(),
        (r['head_count'] as num?)?.toInt() ?? 0,
        (r['po_number'] ?? '').toString(),
        (r['project_name'] ?? '').toString(),
        (r['notes'] ?? '').toString(),
      ]);
    }

    return BackupData(
      sessions: sessions,
      services: services,
      muster: muster,
      generatedAt: generatedAt,
    );
  }
}

/// Writes [BackupData] into a real .xlsx.
///
/// Pure: takes data, returns bytes. No Supabase, no browser, no clock. The
/// download wrapper lives in the UI layer so this can be run under
/// `flutter test` on any platform.
class ExcelBackupService {
  const ExcelBackupService._();

  static const sheetSessions = 'Sessions';
  static const sheetServices = 'Other Services';
  static const sheetMuster = 'Muster';
  static const sheetSummary = 'Summary';

  /// Suggested filename, sortable and unambiguous.
  static String fileName(DateTime at) =>
      'TrackLog_Backup_${DateFormat('yyyy-MM-dd_HHmm').format(at)}.xlsx';

  static Uint8List build(BackupData data) {
    final book = Excel.createExcel();

    _writeSheet(book, sheetSessions, BackupData.sessionHeaders, data.sessions);
    _writeSheet(book, sheetServices, BackupData.serviceHeaders, data.services);
    _writeSheet(book, sheetMuster, BackupData.musterHeaders, data.muster);
    _writeSummary(book, data);

    // Excel.createExcel() seeds a default 'Sheet1'. Removing it after the real
    // sheets exist, never before: deleting the only sheet leaves an invalid
    // workbook that Excel refuses to open.
    if (book.sheets.keys.contains('Sheet1') && book.sheets.length > 1) {
      book.delete('Sheet1');
    }

    final bytes = book.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel encoding produced no bytes');
    }
    return Uint8List.fromList(bytes);
  }

  static void _writeSheet(
      Excel book, String name, List<String> headers, List<Row> rows) {
    final sheet = book[name];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (final r in rows) {
      sheet.appendRow(r.map(_cell).toList());
    }
  }

  /// A totals sheet, so the backup can be checked against the app at a glance
  /// without re-adding thousands of rows by hand.
  static void _writeSummary(Excel book, BackupData data) {
    final sheet = book[sheetSummary];
    double sum(List<Row> rows, int col) => BackupData.money(
        rows.fold<double>(0, (s, r) => s + ((r[col] as num?)?.toDouble() ?? 0)));

    sheet.appendRow([TextCellValue('TrackLog backup')]);
    sheet.appendRow([
      TextCellValue('Generated'),
      TextCellValue(
          DateFormat('dd-MMM-yyyy HH:mm').format(data.generatedAt.toLocal())),
    ]);
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Sheet'), TextCellValue('Rows'),
      TextCellValue('Total (excl GST)')]);
    sheet.appendRow([
      TextCellValue(sheetSessions),
      IntCellValue(data.sessions.length),
      DoubleCellValue(sum(data.sessions, 9)),
    ]);
    sheet.appendRow([
      TextCellValue(sheetServices),
      IntCellValue(data.services.length),
      DoubleCellValue(sum(data.services, 5)),
    ]);
    sheet.appendRow([
      TextCellValue(sheetMuster),
      IntCellValue(data.muster.length),
      TextCellValue('n/a'),
    ]);
  }

  static CellValue _cell(Object? v) {
    if (v == null) return TextCellValue('');
    if (v is int) return IntCellValue(v);
    if (v is double) return DoubleCellValue(v);
    return TextCellValue(v.toString());
  }
}

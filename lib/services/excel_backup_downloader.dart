import 'dart:typed_data';

import 'package:universal_html/html.dart' as html;

import 'excel_backup_service.dart';
import 'supabase_service.dart';

/// Fetches the live data and hands the browser a .xlsx.
///
/// Kept apart from [ExcelBackupService] so the workbook writer stays pure and
/// testable. Everything that touches the network or the DOM is here.
class ExcelBackupDownloader {
  const ExcelBackupDownloader._();

  /// Rows fetched per page. Supabase caps a single response at 1000 rows, so a
  /// plain select silently truncates once the table passes that — a backup that
  /// quietly stops at row 1000 is the worst possible failure, because it looks
  /// like it worked.
  static const int _pageSize = 1000;

  static Future<List<Map<String, dynamic>>> _fetchAll(
    String table, {
    required String columns,
    String? orderBy,
  }) async {
    final client = SupabaseService.instance.client;
    final out = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      var q = client.from(table).select(columns);
      final page = orderBy != null
          ? await q.order(orderBy).range(from, from + _pageSize - 1)
          : await q.range(from, from + _pageSize - 1);
      final rows = (page as List).cast<Map<String, dynamic>>();
      out.addAll(rows);
      if (rows.length < _pageSize) break;
      from += _pageSize;
    }
    return out;
  }

  /// Builds the workbook from live data. Throws on failure so the caller can
  /// surface it — a backup that silently produces an empty file is worse than
  /// one that visibly fails.
  static Future<({Uint8List bytes, String name, BackupData data})>
      generate() async {
    final sessions = await _fetchAll(
      'engineer_sessions',
      columns:
          'started_at, ended_at, venue, track_code, track_name, project_name, '
          'duration_minutes, hourly_rate, total_cost, session_status, notes',
      orderBy: 'started_at',
    );

    // The date and project of a service live on its parent session, so they
    // have to be embedded rather than selected flat.
    final services = await _fetchAll(
      'session_additional_services',
      columns: 'service_name, quantity, rate, total_cost, created_at, '
          'engineer_sessions(started_at, project_name)',
    );

    final muster = await _fetchAll(
      'manpower_muster',
      columns: 'muster_date, kind, head_count, po_number, project_name, notes',
      orderBy: 'muster_date',
    );

    // The billing register. Read through the same RLS as everything else, so
    // a backup contains exactly what the person taking it can see.
    final invoices = await _fetchAll(
      'natrax_invoices',
      columns: 'invoice_date, invoice_number, period_month, project_name, '
          'po_number, amount_excl_gst, gst_amount, total_amount, file_name, '
          'notes',
      orderBy: 'invoice_date',
    );

    final pos = await _fetchAll(
      'po_trackers',
      columns: 'po_number, category, po_status, valid_from, total_po_value, '
          'manpower_days, manpower_days_opening',
      orderBy: 'po_number',
    );

    final at = DateTime.now();
    final data = BackupData.fromRows(
      sessionRows: sessions,
      serviceRows: services,
      musterRows: muster,
      invoiceRows: invoices,
      poRows: pos,
      generatedAt: at,
    );

    return (
      bytes: ExcelBackupService.build(data),
      name: ExcelBackupService.fileName(at),
      data: data,
    );
  }

  /// Hands [bytes] to the browser as a download, then releases the object URL.
  ///
  /// Not revoking leaks the whole workbook in memory for the life of the tab,
  /// which for repeated backups of a large table adds up.
  static void save(Uint8List bytes, String name) {
    final blob = html.Blob(<Object>[bytes],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      html.AnchorElement(href: url)
        ..setAttribute('download', name)
        ..click();
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }

  /// Build the workbook, hand it to the browser, and record the time — the
  /// whole backup behind one call.
  ///
  /// Exists so callers that just want "back it up now" cannot get the three
  /// steps out of order or forget to record the time, which is what the
  /// staleness banner reads. Returns the filename so the caller can say which
  /// file was written.
  ///
  /// Throws on failure, deliberately: a backup that quietly produces nothing
  /// is worse than one that says it failed.
  static Future<String> runAndSave() async {
    final result = await generate();
    save(result.bytes, result.name);
    await BackupRecency.record(DateTime.now());
    return result.name;
  }
}

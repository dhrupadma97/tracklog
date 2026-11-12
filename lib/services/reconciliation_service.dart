import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';

import 'engineer_auth_service.dart';
import 'invoice_service.dart';
import 'muster_service.dart';
import 'natrax_invoice_parser.dart';
import 'natrax_rate_card.dart';
import 'natrax_reconciler.dart';
import 'natrax_utilisation_sheet.dart';
import 'project_catalog.dart';
import 'project_manager.dart';
import 'session_log_service.dart';
import 'session_status.dart';
import 'supabase_service.dart';
import 'track_cost_rules.dart';

/// A note in the month's running record.
class ReconNote {
  final String id;
  final String note;
  final String kind;
  final DateTime createdAt;
  final String? createdBy;
  const ReconNote({
    required this.id,
    required this.note,
    required this.kind,
    required this.createdAt,
    this.createdBy,
  });
}

/// Everything stored for one month's reconciliation.
class ReconMonthState {
  final String month;
  final NatraxUtilisationSheet? sheet;
  final String? sheetFile;
  final DateTime? sheetUploadedAt;
  final String? invoiceId;
  final String? invoiceNumber;
  final ParsedInvoice? invoice;
  final DateTime? settledAt;
  final String? settledBy;
  final Map<String, dynamic>? settledSummary;
  final Map<String, ReconAnswer> answers;
  final List<ReconNote> notes;

  const ReconMonthState({
    required this.month,
    this.sheet,
    this.sheetFile,
    this.sheetUploadedAt,
    this.invoiceId,
    this.invoiceNumber,
    this.invoice,
    this.settledAt,
    this.settledBy,
    this.settledSummary,
    this.answers = const {},
    this.notes = const [],
  });

  bool get settled => settledAt != null;
}

/// Reads and writes the reconciliation, and fetches our own month to set
/// against NATRAX's.
///
/// The judging is all in [NatraxReconciler], which is pure and tested; this
/// is only the plumbing around it.
class ReconciliationService {
  ReconciliationService._();
  static final ReconciliationService instance = ReconciliationService._();

  /// For a test double that overrides the reads, so the Reconcile screen can
  /// be pumped without Supabase. Never used by the app.
  @visibleForTesting
  ReconciliationService.forTesting();

  dynamic get _db => SupabaseService.instance.client;

  String? get _who {
    final u = SupabaseService.instance.client.auth.currentUser;
    return u?.email ?? u?.id;
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  /// Months that have a sheet or an invoice recorded, newest first.
  Future<List<({String month, bool settled, bool hasSheet})>> months() async {
    final rows = await _db
        .from('recon_months')
        .select('month, settled_at, sheet_reference')
        .order('month', ascending: false);
    return [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        (
          month: r['month'] as String,
          settled: r['settled_at'] != null,
          hasSheet: r['sheet_reference'] != null,
        ),
    ];
  }

  Future<ReconMonthState> load(String month) async {
    final row = await _db
        .from('recon_months')
        .select()
        .eq('month', month)
        .maybeSingle();
    final answerRows =
        await _db.from('recon_answers').select().eq('month', month);
    final noteRows = await _db
        .from('recon_notes')
        .select()
        .eq('month', month)
        .order('created_at');

    NatraxUtilisationSheet? sheet;
    ParsedInvoice? invoice;
    if (row != null) {
      final sj = row['sheet_json'];
      if (sj is Map) sheet = NatraxUtilisationSheet.fromJson(sj.cast());
      final ij = row['invoice_json'];
      if (ij is Map) invoice = invoiceFromJson(ij.cast());
    }
    return ReconMonthState(
      month: month,
      sheet: sheet,
      sheetFile: row?['sheet_file'] as String?,
      sheetUploadedAt:
          DateTime.tryParse(row?['sheet_uploaded_at']?.toString() ?? ''),
      invoiceId: row?['invoice_id'] as String?,
      invoiceNumber: row?['invoice_number'] as String?,
      invoice: invoice,
      settledAt: DateTime.tryParse(row?['settled_at']?.toString() ?? ''),
      settledBy: row?['settled_by'] as String?,
      settledSummary: (row?['settled_summary'] as Map?)?.cast(),
      answers: {
        for (final a in (answerRows as List).cast<Map<String, dynamic>>())
          a['item_key'] as String: ReconAnswer(
            itemKey: a['item_key'] as String,
            choice: a['choice'] as String,
            comment: (a['comment'] as String?) ?? '',
            snapshot: (a['snapshot'] as String?) ?? '',
            at: DateTime.tryParse(a['answered_at']?.toString() ?? ''),
            by: a['answered_by'] as String?,
          ),
      },
      notes: [
        for (final n in (noteRows as List).cast<Map<String, dynamic>>())
          ReconNote(
            id: n['id'] as String,
            note: n['note'] as String,
            kind: (n['kind'] as String?) ?? 'note',
            createdAt: DateTime.parse(n['created_at'].toString()),
            createdBy: n['created_by'] as String?,
          ),
      ],
    );
  }

  Future<Map<String, VehicleDecision>> vehicles() async {
    final rows = await _db.from('recon_vehicles').select();
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['vehicle_key'] as String: VehicleDecision(
          vehicleKey: r['vehicle_key'] as String,
          label: (r['label'] as String?) ?? r['vehicle_key'] as String,
          project: r['project_name'] as String?,
          notOurs: (r['not_ours'] as bool?) ?? false,
        ),
    };
  }

  /// Our own record for [monthKey] ('YYYY-MM'): every programme's NATRAX
  /// sessions, their service lines, and the workshop days in the muster.
  ///
  /// Every programme, because one NATRAX sheet covers the whole account. A
  /// session at another venue is left out — it cannot be on NATRAX's sheet.
  Future<OurMonth> ourMonth(String monthKey) async {
    final p = monthKey.split('-');
    final from = DateTime(int.parse(p[0]), int.parse(p[1]));
    final to = DateTime(from.year, from.month + 1);
    final raw = await _db
        .from('engineer_sessions')
        .select('id, started_at, track_code, project_name, duration_minutes, '
            'total_cost, session_status, venue')
        .gte('started_at', from.toIso8601String())
        .lt('started_at', to.toIso8601String());
    final rows = (raw as List).cast<Map<String, dynamic>>();

    final runs = <OurRun>[];
    final ids = <String>[];
    final projectOf = <String, String>{};
    final dateOf = <String, DateTime>{};
    for (final r in rows) {
      final venue = ((r['venue'] as String?) ?? 'NATRAX').toUpperCase();
      if (venue != 'NATRAX') continue;
      final status = ((r['session_status'] as String?) ?? '').toLowerCase();
      if (!kBillableSessionStatuses.contains(status)) continue;
      final started = DateTime.tryParse(r['started_at'] as String? ?? '');
      if (started == null) continue;
      final id = r['id'] as String;
      final project = ProjectCatalog.displayName(r['project_name'] as String?);
      ids.add(id);
      projectOf[id] = project;
      dateOf[id] = DateTime(started.year, started.month, started.day);
      // Stored times are wall clock as entered, so they are read as they
      // stand — converting to local time would shift every run by 5½ hours.
      runs.add(OurRun(
        id: id,
        date: DateTime(started.year, started.month, started.day),
        startMin: started.hour * 60 + started.minute,
        minutes: (r['duration_minutes'] as num?)?.toInt() ?? 0,
        code: ((r['track_code'] as String?) ?? '').trim().toUpperCase(),
        project: project,
        cost: (r['total_cost'] as num?)?.toDouble() ?? 0,
      ));
    }

    final services = <OurService>[];
    if (ids.isNotEmpty) {
      final svc = await _db
          .from('session_additional_services')
          .select('session_id, service_name, quantity, total_cost')
          .inFilter('session_id', ids);
      for (final s in (svc as List).cast<Map<String, dynamic>>()) {
        final sid = s['session_id'] as String;
        services.add(OurService(
          name: (s['service_name'] as String?) ?? '',
          quantity: (s['quantity'] as num?)?.toDouble() ?? 0,
          cost: (s['total_cost'] as num?)?.toDouble() ?? 0,
          project: projectOf[sid] ?? '',
          date: dateOf[sid],
        ));
      }
    }

    final workshop = <DateTime>{};
    try {
      for (final d in await MusterService.instance.list()) {
        if (d.kind != MusterKind.workshop) continue;
        if (d.date.year == from.year && d.date.month == from.month) {
          workshop.add(DateTime(d.date.year, d.date.month, d.date.day));
        }
      }
    } catch (_) {
      // An unreadable muster leaves the bay unknown, which the reconciliation
      // shows as "ours: 0" — visible, not silently right.
    }

    return OurMonth(runs: runs, services: services, workshopDays: workshop);
  }

  // ── Writing ──────────────────────────────────────────────────────────────

  Future<void> saveSheet(NatraxUtilisationSheet sheet, String fileName) async {
    await _db.from('recon_months').upsert({
      'month': sheet.monthKey,
      'sheet_json': sheet.toJson(),
      'sheet_file': fileName,
      'sheet_reference': sheet.reference,
      'sheet_uploaded_at': DateTime.now().toUtc().toIso8601String(),
      'sheet_uploaded_by': _who,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'month');
    await addNote(
      sheet.monthKey,
      'Utilisation sheet ${sheet.reference.isEmpty ? '' : '${sheet.reference} '}'
      'uploaded ($fileName): ${sheet.blocks.length} track lines, '
      '${sheet.runCount} runs, ${_h(sheet.chargedHours)} h charged.',
      kind: 'sheet',
    );
  }

  Future<void> answer(String month, ReconItem item, String choice,
      String comment) async {
    await _db.from('recon_answers').upsert({
      'month': month,
      'item_key': item.key,
      'choice': choice,
      'comment': comment.trim().isEmpty ? null : comment.trim(),
      'snapshot': item.snapshot,
      'answered_at': DateTime.now().toUtc().toIso8601String(),
      'answered_by': _who,
    }, onConflict: 'month,item_key');
  }

  /// Settles every in-our-favour question at its suggestion, with its own
  /// note. Lines where NATRAX bill MORE are never touched by this.
  Future<int> acceptInFavour(String month, Iterable<ReconItem> items) async {
    final rows = [
      for (final i in items)
        if (i.isOpen && i.bulkOk && i.suggested != null)
          {
            'month': month,
            'item_key': i.key,
            'choice': i.suggested,
            'comment': i.autoComment,
            'snapshot': i.snapshot,
            'answered_at': DateTime.now().toUtc().toIso8601String(),
            'answered_by': _who,
          },
    ];
    if (rows.isEmpty) return 0;
    await _db.from('recon_answers').upsert(rows, onConflict: 'month,item_key');
    return rows.length;
  }

  Future<void> clearAnswer(String month, String itemKey) async {
    await _db
        .from('recon_answers')
        .delete()
        .eq('month', month)
        .eq('item_key', itemKey);
  }

  Future<void> setVehicle(String key, String label,
      {String? project, bool notOurs = false}) async {
    await _db.from('recon_vehicles').upsert({
      'vehicle_key': key,
      'label': label,
      'project_name': notOurs ? null : project,
      'not_ours': notOurs,
      'decided_at': DateTime.now().toUtc().toIso8601String(),
      'decided_by': _who,
    }, onConflict: 'vehicle_key');
  }

  Future<void> addNote(String month, String note, {String kind = 'note'}) async {
    if (note.trim().isEmpty) return;
    await _db.from('recon_notes').insert({
      'month': month,
      'note': note.trim(),
      'kind': kind,
      'created_by': _who,
    });
  }

  // ── The invoice ──────────────────────────────────────────────────────────

  /// NATRAX invoices recorded for [month] — the ones the PO Tracker already
  /// holds, so an invoice is uploaded once and serves both.
  Future<List<NatraxInvoice>> invoicesFor(String month) async {
    final all = await InvoiceService.instance.list();
    return all
        .where((i) =>
            i.periodMonth == month &&
            !i.invoiceNumber.toUpperCase().startsWith('MOI'))
        .toList();
  }

  /// Reads a recorded invoice's own PDF, so the tally uses its lines.
  Future<ParsedInvoice?> readInvoice(NatraxInvoice inv) async {
    if (inv.storagePath == null) return null;
    final Uint8List? bytes = await InvoiceService.instance.download(inv);
    if (bytes == null) return null;
    return NatraxInvoiceParser.parse(bytes);
  }

  Future<void> setInvoice(
      String month, NatraxInvoice inv, ParsedInvoice parsed) async {
    await _db.from('recon_months').upsert({
      'month': month,
      'invoice_id': inv.id,
      'invoice_number': inv.invoiceNumber,
      'invoice_json': invoiceToJson(parsed),
      'invoice_tallied_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'month');
    await addNote(
      month,
      'Invoice ${inv.invoiceNumber} set against the month: '
      '${parsed.lines.length} lines, taxable ₹${_money(parsed.amountExclGst ?? inv.amountExclGst)}, '
      'GST ₹${_money(parsed.gstAmount ?? inv.gstAmount)}.',
      kind: 'invoice',
    );
  }

  // ── Settling ─────────────────────────────────────────────────────────────

  Future<void> settle(String month, Map<String, dynamic> summary) async {
    await _db.from('recon_months').upsert({
      'month': month,
      'settled_at': DateTime.now().toUtc().toIso8601String(),
      'settled_by': _who,
      'settled_summary': summary,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'month');
    await addNote(
      month,
      'Settled: agreed ₹${_money(summary['agreed'] as num?)}, disputed '
      '₹${_money(summary['disputed'] as num?)}'
      '${summary['invoice'] == null ? '' : ', invoice ${summary['invoice']}'}.',
      kind: 'settled',
    );
  }

  Future<void> reopen(String month, String reason) async {
    await _db.from('recon_months').update({
      'settled_at': null,
      'settled_by': null,
      'settled_summary': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('month', month);
    await addNote(month, 'Reopened: $reason', kind: 'reopened');
  }

  // ── Fixing our own record ────────────────────────────────────────────────

  /// NATRAX's runs on [item] that our record does not have: every run for a
  /// line only they have; for a line where they have more, only the runs
  /// that overlap none of ours.
  static List<NatraxRun> missingRuns(ReconItem item) {
    if (item.kind != ReconKind.track) return const [];
    return [
      for (final t in item.theirRuns)
        if (!item.ourRuns.any((o) =>
            o.startMin < t.inMin + t.minutes &&
            t.inMin < o.startMin + o.minutes))
          t,
    ];
  }

  /// Adds [runs] of [item] to TrackLog, each priced exactly as Manual Entry
  /// would price it if typed in by hand: TrackCostRules.marginalCost against
  /// what the day already carries for that programme, track and venue, with
  /// the braking surfaces sharing their floor.
  ///
  /// Returns what was added and what it cost, so the caller can say so.
  Future<({int count, double cost})> addRuns(
      ReconItem item, List<NatraxRun> runs, String sheetRef) async {
    final code = item.code;
    final project = item.project;
    final date = item.date;
    if (code == null || project == null || date == null || runs.isEmpty) {
      return (count: 0, cost: 0.0);
    }
    if (NatraxRateCard.isExclusive(code) || !NatraxRateCard.knows(code)) {
      throw StateError('$code cannot be added automatically — enter it in '
          'Manual Entry.');
    }
    final user = EngineerAuthService.instance.currentUser;
    if (user == null) throw StateError('Not signed in');

    final rate = NatraxRateCard.rateFor(code);
    final minHrs = NatraxRateCard.minHoursFor(code);
    final group = TrackCostRules.groupFor(code);

    // The day as it stands, read the way Manual Entry reads it.
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final rows = await _db
        .from('engineer_sessions')
        .select('track_code, duration_minutes, total_cost, project_name, venue')
        .inFilter('track_code', group)
        .gte('started_at', dayStart.toIso8601String())
        .lt('started_at', dayEnd.toIso8601String());
    var sameMins = 0;
    var sameCost = 0.0;
    final siblingMins = <String, int>{};
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      if (!ProjectManager.sessionBelongsTo(r['project_name'] as String?, project)) {
        continue;
      }
      final venue = ((r['venue'] as String?) ?? 'NATRAX').toUpperCase();
      if (venue != 'NATRAX') continue;
      final c = ((r['track_code'] as String?) ?? '').trim();
      final m = (r['duration_minutes'] as num?)?.toInt() ?? 0;
      if (c == code) {
        sameMins += m;
        sameCost += (r['total_cost'] as num?)?.toDouble() ?? 0;
      } else {
        siblingMins[c] = (siblingMins[c] ?? 0) + m;
      }
    }
    final siblingCeil = siblingMins.values
        .fold<double>(0, (s, m) => s + TrackCostRules.ceilHours(m));

    var added = 0;
    var total = 0.0;
    final sorted = List<NatraxRun>.from(runs)
      ..sort((a, b) => a.inMin.compareTo(b.inMin));
    for (final run in sorted) {
      final cost = TrackCostRules.marginalCost(
        entryMinutes: run.minutes,
        sameDayMinutes: sameMins,
        sameDayCost: sameCost,
        rate: rate,
        minHours: minHrs,
        siblingCeilHours: siblingCeil,
      );
      final started = DateTime(date.year, date.month, date.day,
          run.inMin ~/ 60, run.inMin % 60);
      await _db.from('engineer_sessions').insert({
        'engineer_id': user.id,
        'track_code': code,
        'track_name': NatraxRateCard.nameFor(code),
        'venue': 'NATRAX',
        'vehicle_category': 'below_3_5t',
        'booking_type': 'standard',
        'session_status': 'completed',
        'started_at': started.toIso8601String(),
        'ended_at': started.add(Duration(minutes: run.minutes)).toIso8601String(),
        'duration_minutes': run.minutes,
        'hourly_rate': rate,
        'total_cost': cost,
        'project_name': project,
        // "Manual entry" first, so it lists — and can be deleted — under
        // Manual Entry's recent entries like anything typed in by hand.
        'notes': 'Manual entry — added from NATRAX utilisation'
            '${sheetRef.isEmpty ? '' : ' $sheetRef'} (${run.label})',
      });
      sameMins += run.minutes;
      sameCost += cost;
      total += cost;
      added++;
    }
    SessionLogService.instance.changed();
    return (count: added, cost: total);
  }

  // ── Invoice storage ──────────────────────────────────────────────────────

  static Map<String, dynamic> invoiceToJson(ParsedInvoice p) => {
        'number': p.invoiceNumber,
        'date': p.invoiceDate?.toIso8601String(),
        'period': p.periodMonth,
        'po': p.poNumber,
        'excl': p.amountExclGst,
        'gst': p.gstAmount,
        'total': p.totalAmount,
        'lines': [
          for (final l in p.lines)
            {
              'd': l.description,
              'q': l.quantity,
              'u': l.unit,
              'a': l.amount,
              'x': l.amountDerived,
            },
        ],
      };

  static ParsedInvoice invoiceFromJson(Map<String, dynamic> j) => ParsedInvoice(
        invoiceNumber: j['number'] as String?,
        invoiceDate: DateTime.tryParse(j['date']?.toString() ?? ''),
        periodMonth: j['period'] as String?,
        poNumber: j['po'] as String?,
        amountExclGst: (j['excl'] as num?)?.toDouble(),
        gstAmount: (j['gst'] as num?)?.toDouble(),
        totalAmount: (j['total'] as num?)?.toDouble(),
        lines: [
          for (final l in ((j['lines'] as List?) ?? const []))
            ParsedInvoiceLine(
              description: (l as Map)['d'] as String? ?? '',
              quantity: (l['q'] as num?)?.toDouble(),
              unit: l['u'] as String? ?? '',
              amount: (l['a'] as num?)?.toDouble() ?? 0,
              amountDerived: l['x'] as bool? ?? false,
            ),
        ],
      );

  static String _h(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  static String _money(num? v) => v == null
      ? '—'
      : NumberFormat.decimalPattern('en_IN').format(v.round());
}

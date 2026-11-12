import 'natrax_rate_card.dart';
import 'natrax_reconciler.dart' show ServiceCategory;
import 'project_manager.dart';
import 'session_log_service.dart';
import 'session_status.dart';
import 'supabase_service.dart';
import 'track_cost_rules.dart';

/// One track run on one day, as the day view shows it and edits it.
///
/// [start] is wall-clock time. Manual Entry writes `started_at` as a local
/// time with no offset, Postgres reads that as UTC, and every screen reads
/// the UTC fields straight back as the clock time — so no `toLocal()` here,
/// or a 08:16 run would show as 13:46.
class DayEntry {
  final String id;
  final String code;
  final String name;
  final DateTime start;
  final int minutes;
  final double cost;
  final String project;
  final String notes;
  final String venue;

  const DayEntry({
    required this.id,
    required this.code,
    required this.name,
    required this.start,
    required this.minutes,
    required this.cost,
    required this.project,
    this.notes = '',
    this.venue = 'NATRAX',
  });

  int get startMin => start.hour * 60 + start.minute;
  int get endMin => (startMin + minutes) % TrackCostRules.minutesInDay;
  String get comment => DayEntriesService.commentOf(notes);

  static String clock(int minuteOfDay) {
    final m = minuteOfDay % TrackCostRules.minutesInDay;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  String get timeLabel => '${clock(startMin)}–${clock(endMin)}';

  factory DayEntry.fromRow(Map<String, dynamic> r) {
    final raw = ((r['project_name'] as String?) ?? '').trim();
    return DayEntry(
      id: r['id'] as String,
      code: ((r['track_code'] as String?) ?? '').trim().toUpperCase(),
      name: (r['track_name'] as String?) ?? '',
      start: DateTime.tryParse((r['started_at'] as String?) ?? '') ??
          DateTime(2000),
      minutes: (r['duration_minutes'] as num?)?.toInt() ?? 0,
      cost: (r['total_cost'] as num?)?.toDouble() ?? 0,
      project: (raw.isEmpty || raw.toLowerCase() == 'general')
          ? 'Mahindra EV PoC'
          : raw,
      notes: ((r['notes'] as String?) ?? '').trim(),
      venue: ((r['venue'] as String?) ?? 'NATRAX').toUpperCase(),
    );
  }
}

/// Reads one day's track runs, edits them, and prices the day again.
///
/// An edit changes more than its own row. NATRAX bill a programme's day per
/// track — whole hours, then the day minimum, with T3 Wet and Dry sharing
/// one — so moving one run from T3 Wet to T3 Dry, or shortening it, changes
/// what the whole day costs. After every change the programme's day is
/// priced again from scratch and the money spread over its runs.
class DayEntriesService {
  const DayEntriesService._();

  static const _columns = 'id, track_code, track_name, started_at, '
      'duration_minutes, total_cost, project_name, notes, venue, session_status';

  /// Manual Entry finds its own rows by this prefix — its Recent Entries list
  /// filters on `notes ILIKE 'Manual entry%'` — so an edited comment must
  /// keep it, or the entry would vanish from the list it can be deleted from.
  static const manualPrefix = 'Manual entry';

  /// The part of `notes` a person wrote, without Manual Entry's prefix.
  static String commentOf(String? notes) {
    final n = (notes ?? '').trim();
    if (!n.startsWith(manualPrefix)) return n;
    var rest = n.substring(manualPrefix.length).trim();
    if (rest.startsWith('—') || rest.startsWith('-')) {
      rest = rest.substring(1).trim();
    }
    return rest;
  }

  /// [comment] written back, keeping the prefix if the row had it.
  static String notesWith(String? oldNotes, String comment) {
    final c = comment.trim();
    if ((oldNotes ?? '').trim().startsWith(manualPrefix)) {
      return c.isEmpty ? manualPrefix : '$manualPrefix — $c';
    }
    return c;
  }

  /// What each run of one programme's day costs, by id.
  ///
  /// Standard codes go through [NatraxRateCard.billableForDay] — the same
  /// rounding and shared floor the invoice uses — and exclusive codes are
  /// whole blocks. Each code's money is spread over its runs by minutes,
  /// in rupees, with the rounding left on the longest run so the runs add up
  /// to the day exactly. Codes the rate card does not know are left out, so
  /// the caller keeps whatever cost they already carry.
  static Map<String, double> priceDay(List<DayEntry> runs) {
    final byCode = <String, List<DayEntry>>{};
    for (final r in runs) {
      if (r.minutes <= 0 || !NatraxRateCard.knows(r.code)) continue;
      byCode.putIfAbsent(r.code, () => []).add(r);
    }
    final standardMinutes = <String, int>{
      for (final e in byCode.entries)
        if (!NatraxRateCard.isExclusive(e.key))
          e.key: e.value.fold<int>(0, (s, r) => s + r.minutes),
    };
    final hours = NatraxRateCard.billableForDay(standardMinutes);

    final out = <String, double>{};
    byCode.forEach((code, list) {
      final mins = list.fold<int>(0, (s, r) => s + r.minutes);
      final money = NatraxRateCard.isExclusive(code)
          ? NatraxRateCard.exclusiveCost(code, mins / 60.0)
          : (hours[code] ?? 0) * NatraxRateCard.rateFor(code);
      final longest =
          list.reduce((a, b) => b.minutes > a.minutes ? b : a);
      var given = 0.0;
      for (final r in list) {
        if (identical(r, longest)) continue;
        final share = (money * r.minutes / mins).roundToDouble();
        out[r.id] = share;
        given += share;
      }
      out[longest.id] = money - given;
    });
    return out;
  }

  static dynamic get _db => SupabaseService.instance.client;

  static ({String from, String to}) _range(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return (
      from: d.toIso8601String(),
      to: d.add(const Duration(days: 1)).toIso8601String(),
    );
  }

  /// The day's track runs for [projects], earliest first. Other Services
  /// containers (MISC) are not track runs and are left out.
  static Future<List<DayEntry>> load(DateTime day, Set<String> projects) async {
    final r = _range(day);
    final rows = await _db
        .from('engineer_sessions')
        .select(_columns)
        .gte('started_at', r.from)
        .lt('started_at', r.to)
        .neq('track_code', 'MISC')
        .inFilter('session_status', kBillableSessionStatuses)
        .order('started_at');
    return [
      for (final m in (rows as List).cast<Map<String, dynamic>>())
        if (projects.isEmpty ||
            projects.any((p) => ProjectManager.sessionBelongsTo(
                m['project_name'] as String?, p)))
          DayEntry.fromRow(m),
    ];
  }

  /// The day's EV charging, from the service lines of every session that
  /// day — usually an Other Services container, not a track run.
  static Future<List<({String project, String name, double units, double cost})>>
      loadEv(DateTime day, Set<String> projects) async {
    final r = _range(day);
    final sessions = await _db
        .from('engineer_sessions')
        .select('id, project_name')
        .gte('started_at', r.from)
        .lt('started_at', r.to)
        .inFilter('session_status', kBillableSessionStatuses);
    final projectOf = <String, String>{};
    for (final m in (sessions as List).cast<Map<String, dynamic>>()) {
      final p = m['project_name'] as String?;
      if (projects.isNotEmpty &&
          !projects.any((x) => ProjectManager.sessionBelongsTo(p, x))) {
        continue;
      }
      final raw = (p ?? '').trim();
      projectOf[m['id'] as String] =
          (raw.isEmpty || raw.toLowerCase() == 'general') ? 'Mahindra EV PoC' : raw;
    }
    if (projectOf.isEmpty) return const [];
    final lines = await _db
        .from('session_additional_services')
        .select('session_id, service_name, quantity, total_cost')
        .inFilter('session_id', projectOf.keys.toList());
    return [
      for (final l in (lines as List).cast<Map<String, dynamic>>())
        if (ServiceCategory.isEv((l['service_name'] as String?) ?? ''))
          (
            project: projectOf[l['session_id']] ?? '',
            name: ((l['service_name'] as String?) ?? 'EV charging').trim(),
            units: (l['quantity'] as num?)?.toDouble() ?? 0,
            cost: (l['total_cost'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  /// Prices [project]'s NATRAX day again and writes every cost that moved.
  /// Returns the day's track cost before and after.
  static Future<({double before, double after})> reprice(
      DateTime day, String project) async {
    final runs = (await load(day, {project}))
        .where((e) => e.venue == 'NATRAX')
        .toList();
    final priced = priceDay(runs);
    var before = 0.0, after = 0.0;
    for (final e in runs) {
      before += e.cost;
      final c = priced[e.id] ?? e.cost;
      after += c;
      if ((c - e.cost).abs() >= 0.01) {
        await _db
            .from('engineer_sessions')
            .update({'total_cost': c}).eq('id', e.id);
      }
    }
    return (before: before, after: after);
  }

  /// Changes one run, then prices its day again — for the programme it left
  /// as well as the one it joined, if that changed.
  static Future<({double before, double after})> update(
    DayEntry e, {
    required String code,
    required int startMin,
    required int minutes,
    required String project,
    required String comment,
  }) async {
    if (minutes <= 0) throw ArgumentError('The run must last at least a minute.');
    final d = e.start;
    final started = DateTime(d.year, d.month, d.day, startMin ~/ 60, startMin % 60);
    final rate = NatraxRateCard.rateFor(code);
    await _db.from('engineer_sessions').update({
      'track_code': code,
      'track_name': NatraxRateCard.nameFor(code),
      'started_at': started.toIso8601String(),
      'ended_at': started.add(Duration(minutes: minutes)).toIso8601String(),
      'duration_minutes': minutes,
      'project_name': project,
      'notes': notesWith(e.notes, comment),
      if (rate > 0) 'hourly_rate': rate,
    }).eq('id', e.id);

    // The edited row still carries its old cost when these read the day, so
    // "before" is the day as it was billed and "after" as it now prices —
    // across both programmes when the run moved between them.
    var before = 0.0, after = 0.0;
    for (final p in {e.project, project}) {
      final r = await reprice(d, p);
      before += r.before;
      after += r.after;
    }
    SessionLogService.instance.changed();
    return (before: before, after: after);
  }

  /// Only the comment — no repricing, nothing else touched.
  static Future<void> setComment(DayEntry e, String comment) async {
    await _db
        .from('engineer_sessions')
        .update({'notes': notesWith(e.notes, comment)}).eq('id', e.id);
    SessionLogService.instance.changed();
  }

  /// Deletes one run and prices what is left of its programme's day.
  static Future<({double before, double after})> delete(DayEntry e) async {
    await _db.from('engineer_sessions').delete().eq('id', e.id);
    final r = await reprice(e.start, e.project);
    SessionLogService.instance.changed();
    return (before: r.before + e.cost, after: r.after);
  }
}

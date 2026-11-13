import 'package:intl/intl.dart';

import 'natrax_invoice_parser.dart';
import 'natrax_rate_card.dart';
import 'natrax_utilisation_sheet.dart';
import 'project_catalog.dart';
import 'track_cost_rules.dart';

// ── Inputs ─────────────────────────────────────────────────────────────────

/// One of our sessions, reduced to what a reconciliation needs.
class OurRun {
  final String id;
  final DateTime date;

  /// Minutes after midnight, wall clock, as entered.
  final int startMin;
  final int minutes;
  final String code;

  /// Programme display name, e.g. "Mahindra ICE PoC".
  final String project;
  final double cost;

  const OurRun({
    required this.id,
    required this.date,
    required this.startMin,
    required this.minutes,
    required this.code,
    required this.project,
    required this.cost,
  });

  int get endMin => (startMin + minutes) % TrackCostRules.minutesInDay;
  String get label =>
      '${NatraxRun.clock(startMin)}–${NatraxRun.clock(endMin)}';
}

/// One of our service lines (session_additional_services) in the month.
class OurService {
  final DateTime? date;
  final String project;
  final String name;
  final double quantity;
  final double cost;
  const OurService({
    required this.name,
    required this.quantity,
    required this.cost,
    this.project = '',
    this.date,
  });
}

/// Everything we hold for the month.
class OurMonth {
  final List<OurRun> runs;
  final List<OurService> services;

  /// Workshop days in the muster for the month — the "which days" record of
  /// the bay, which NATRAX bill as office / porta-cabin / workshop days.
  final Set<DateTime> workshopDays;
  const OurMonth({
    this.runs = const [],
    this.services = const [],
    this.workshopDays = const {},
  });
}

/// Who a vehicle on NATRAX's sheet belongs to. Decided once, remembered.
class VehicleDecision {
  final String vehicleKey;

  /// Programme display name; null when [notOurs].
  final String? project;
  final bool notOurs;
  final String label;
  const VehicleDecision({
    required this.vehicleKey,
    required this.label,
    this.project,
    this.notOurs = false,
  });
}

/// A recorded answer to one question.
class ReconAnswer {
  final String itemKey;
  final String choice;
  final String comment;

  /// The figures the question showed when it was answered. If they have
  /// moved since — a missing run was added, a sheet replaced — the answer
  /// may no longer fit, and is shown as needing another look.
  final String snapshot;
  final DateTime? at;
  final String? by;
  const ReconAnswer({
    required this.itemKey,
    required this.choice,
    this.comment = '',
    this.snapshot = '',
    this.at,
    this.by,
  });
}

// ── Questions ──────────────────────────────────────────────────────────────

enum ReconKind { vehicle, track, rule, exclusive, service, ev, notOurs, invoice }

/// Which way a line leans. Drives the colour, the suggestion, and whether it
/// can be settled in bulk.
enum ReconStance {
  matched,

  /// NATRAX bill less than our record — settled at their figure with a note,
  /// never disputed.
  inFavour,

  /// NATRAX bill more than our record.
  theirsMore,

  /// On NATRAX's sheet, not in ours.
  theirsOnly,

  /// In ours, not on NATRAX's sheet.
  oursOnly,

  /// NATRAX charged more hours than their own gate log supports.
  overcharge,

  /// NATRAX charged fewer hours than their own gate log supports. Noted, not
  /// chased.
  undercharge,

  /// Something this tool cannot price or place — a vehicle not yet assigned,
  /// a service with no rate on the card.
  unknown,

  /// Billed against a vehicle that is not ours.
  notOurs,
}

class ReconOption {
  final String id;
  final String label;
  final String detail;

  /// The quantity (hours, units, days) this choice settles the line at.
  final double? agreed;

  /// Money settled at, where it is not quantity × rate (exclusive blocks).
  final double? agreedMoney;
  final bool dispute;

  /// What has to be done in TrackLog afterwards, if anything.
  final String? todo;
  const ReconOption({
    required this.id,
    required this.label,
    this.detail = '',
    this.agreed,
    this.agreedMoney,
    this.dispute = false,
    this.todo,
  });
}

class ReconItem {
  final String key;
  final ReconKind kind;
  final ReconStance stance;
  final String title;
  final String subtitle;
  final DateTime? date;
  final String? project;
  final String? code;

  /// "h", "units", "days", "Nos".
  final String unit;
  final double? ours;
  final double? theirs;

  /// What NATRAX's own gate log supports, by the rounding and floor rules.
  final double? rule;
  final int? oursMinutes;
  final int? theirsMinutes;
  final List<OurRun> ourRuns;
  final List<NatraxRun> theirRuns;

  /// Per hour or per unit; for an exclusive booking, the block price.
  final double rate;
  final List<String> hints;
  final List<ReconOption> options;
  final String? suggested;
  final String autoComment;

  /// False for lines that are information only — a match, an undercharge.
  final bool needsAnswer;

  /// May be settled by "accept all in our favour".
  final bool bulkOk;
  final String snapshot;
  final ReconAnswer? answer;

  /// Answered, but against figures that have since changed.
  final bool stale;

  /// NATRAX's figure in money, and ours.
  final double theirsMoney;
  final double oursMoney;

  const ReconItem({
    required this.key,
    required this.kind,
    required this.stance,
    required this.title,
    this.subtitle = '',
    this.date,
    this.project,
    this.code,
    this.unit = 'h',
    this.ours,
    this.theirs,
    this.rule,
    this.oursMinutes,
    this.theirsMinutes,
    this.ourRuns = const [],
    this.theirRuns = const [],
    this.rate = 0,
    this.hints = const [],
    this.options = const [],
    this.suggested,
    this.autoComment = '',
    this.needsAnswer = true,
    this.bulkOk = false,
    this.snapshot = '',
    this.answer,
    this.stale = false,
    this.theirsMoney = 0,
    this.oursMoney = 0,
  });

  bool get isOpen => needsAnswer && (answer == null || stale);

  ReconOption? get chosen {
    final a = answer;
    if (a == null) return null;
    for (final o in options) {
      if (o.id == a.choice) return o;
    }
    return null;
  }

  /// The quantity this line is settled at — NATRAX's figure until answered.
  double? get agreed {
    final c = stale ? null : chosen;
    if (c != null) return c.agreed;
    return theirs;
  }

  /// Money settled at. NATRAX's figure until answered.
  double get agreedMoney {
    final c = stale ? null : chosen;
    if (c?.agreedMoney != null) return c!.agreedMoney!;
    if (c?.agreed != null) return c!.agreed! * rate;
    return theirsMoney;
  }

  ReconItem withAnswer(ReconAnswer? a) => ReconItem(
        key: key,
        kind: kind,
        stance: stance,
        title: title,
        subtitle: subtitle,
        date: date,
        project: project,
        code: code,
        unit: unit,
        ours: ours,
        theirs: theirs,
        rule: rule,
        oursMinutes: oursMinutes,
        theirsMinutes: theirsMinutes,
        ourRuns: ourRuns,
        theirRuns: theirRuns,
        rate: rate,
        hints: hints,
        options: options,
        suggested: suggested,
        autoComment: autoComment,
        needsAnswer: needsAnswer,
        bulkOk: bulkOk,
        snapshot: snapshot,
        answer: a,
        stale: a != null && a.snapshot.isNotEmpty && a.snapshot != snapshot,
        theirsMoney: theirsMoney,
        oursMoney: oursMoney,
      );
}

/// One track code's month, side by side.
class ReconTrackLine {
  final String code;
  final String name;
  final double rate;
  final double natrax;
  final double ours;
  final double agreed;
  final double natraxMoney;
  final double oursMoney;
  final double agreedMoney;
  const ReconTrackLine({
    required this.code,
    required this.name,
    required this.rate,
    required this.natrax,
    required this.ours,
    required this.agreed,
    required this.natraxMoney,
    required this.oursMoney,
    required this.agreedMoney,
  });
  double get disputedMoney => natraxMoney - agreedMoney;
}

class ReconOutcome {
  final NatraxUtilisationSheet sheet;
  final List<ReconItem> items;
  final List<ReconTrackLine> trackLines;
  const ReconOutcome({
    required this.sheet,
    required this.items,
    required this.trackLines,
  });

  Iterable<ReconItem> get _q => items.where((i) => i.needsAnswer);
  int get open => _q.where((i) => i.isOpen).length;
  int get answered => _q.where((i) => !i.isOpen).length;
  int get inFavourOpen => _q.where((i) => i.isOpen && i.bulkOk).length;
  int get matched =>
      items.where((i) => i.stance == ReconStance.matched).length;
  int get unknownVehicles => items
      .where((i) => i.kind == ReconKind.vehicle && i.isOpen)
      .length;

  /// Every question answered on current figures.
  bool get cleared => open == 0;

  /// What NATRAX's sheet comes to, for vehicles that are ours and the
  /// account-wide services.
  double get natraxMoney =>
      items.where((i) => i.kind != ReconKind.vehicle && i.kind != ReconKind.rule && i.kind != ReconKind.notOurs)
          .fold(0.0, (s, i) => s + i.theirsMoney);
  double get oursMoney =>
      items.where((i) => i.kind != ReconKind.vehicle && i.kind != ReconKind.rule && i.kind != ReconKind.notOurs)
          .fold(0.0, (s, i) => s + i.oursMoney);

  /// What we expect to pay.
  double get agreedMoney {
    var total = 0.0;
    for (final i in items) {
      if (i.kind == ReconKind.vehicle ||
          i.kind == ReconKind.notOurs ||
          i.kind == ReconKind.rule) {
        continue;
      }
      total += i.agreedMoney;
    }
    // A rule question settled as a dispute takes the excess hours off the
    // line it belongs to.
    for (final r in items.where((i) => i.kind == ReconKind.rule)) {
      final c = r.stale ? null : r.chosen;
      if (c != null && c.dispute) total -= r.theirsMoney - r.agreedMoney;
    }
    return total;
  }

  /// Billed against vehicles that are not ours.
  double get notOursMoney => items
      .where((i) => i.kind == ReconKind.notOurs)
      .fold(0.0, (s, i) => s + i.theirsMoney);

  /// Everything raised with NATRAX: not-ours vehicles plus lines disputed.
  double get disputedMoney => natraxMoney + notOursMoney - agreedMoney;

  /// Fix-ups for our own record that the answers imply.
  List<String> get todos => [
        for (final i in items)
          if (!i.stale && i.chosen?.todo != null) i.chosen!.todo!,
      ];

  List<ReconItem> get disputes => [
        for (final i in items)
          if (i.kind == ReconKind.notOurs ||
              (!i.stale && (i.chosen?.dispute ?? false)))
            i,
      ];
}

// ── The engine ─────────────────────────────────────────────────────────────

/// Sets NATRAX's utilisation sheet against our own record and decides what
/// to ask.
///
/// The unit is one programme's track on one day — what NATRAX round and
/// floor, and therefore what a dispute is about. Both sides are worked out by
/// the same rule (NatraxRateCard.billableForDay), so a difference is a
/// difference in the record, never in the arithmetic.
///
/// The standing rules it applies, from the programme owner:
///
///   * NATRAX billing LESS than our record is settled at their figure with a
///     note — "if it's coming less compared to us we are okay, we can adjust
///     with the comments" (12 Nov 2026). Such lines can be settled in bulk.
///   * Only a line where NATRAX bill MORE needs a real decision: is our record
///     short, or is it an overcharge?
///   * An undercharge against NATRAX's own gate log is noted and not chased.
class NatraxReconciler {
  const NatraxReconciler._();

  static final _d = DateFormat('d MMM');
  static String _h(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  static String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Rupees as the user reads them: ₹1,80,000, or ₹67.80 when there are paise.
  static String _rs(double v) => NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: (v - v.roundToDouble()).abs() < 0.005 ? 0 : 2)
      .format(v);
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _groupOf(String code) =>
      (List<String>.from(TrackCostRules.groupFor(code))..sort()).join('+');

  /// Programmes as offered for a vehicle: active ones first, the rest after.
  static List<String> programmes() {
    final all = List<Programme>.from(ProjectCatalog.all)
      ..sort((a, b) => a.status.index.compareTo(b.status.index));
    return [for (final p in all) p.displayName];
  }

  /// Best guess at whose a vehicle is, from the catalogue's own vehicle
  /// names. Null when nothing fits — a guess with nothing behind it would be
  /// worse than an honest blank.
  static String? suggestProgramme(String vehicleLabel, {bool evOnly = false}) {
    final key = NatraxUtilisationSheet.vehicleKey(vehicleLabel);
    if (key.length >= 4) {
      for (final p in ProjectCatalog.all) {
        final v = NatraxUtilisationSheet.vehicleKey(p.vehicle);
        final n = NatraxUtilisationSheet.vehicleKey(p.displayName);
        if (v.contains(key) || key.contains(v) || n.contains(key)) {
          return p.displayName;
        }
      }
    }
    if (evOnly) {
      // A plate that only ever appears on the EV charger is an EV. If exactly
      // one battery-electric programme is running, that is the likely owner.
      final bev = ProjectCatalog.all
          .where((p) =>
              p.powertrain == Powertrain.bev &&
              p.status == ProgrammeStatus.active)
          .toList();
      if (bev.length == 1) return bev.single.displayName;
    }
    return null;
  }

  static ReconOutcome run({
    required NatraxUtilisationSheet sheet,
    required OurMonth ours,
    required Map<String, VehicleDecision> vehicles,
    Map<String, ReconAnswer> answers = const {},
  }) {
    final items = <ReconItem>[];
    ReconItem keep(ReconItem i) {
      // A vehicle's answer is its decision, set when the item is built; the
      // answers table never holds one, so it must not overwrite it.
      final a = i.kind == ReconKind.vehicle ? i.answer : answers[i.key];
      final done = i.withAnswer(a);
      items.add(done);
      return done;
    }

    // ── 1. Whose is each vehicle? ─────────────────────────────────────────
    final bookingVehicle = <String, String>{};
    final vehicleLabel = <String, String>{};
    final vehicleDates = <String, Set<DateTime>>{};
    final vehicleBookings = <String, Set<String>>{};
    final vehicleRfids = <String, Set<String>>{};
    final evOnly = <String, bool>{};
    for (final b in sheet.blocks) {
      final k = b.vehicleKey;
      vehicleLabel.putIfAbsent(k, () => b.vehicle);
      (vehicleDates[k] ??= {}).add(b.date);
      (vehicleBookings[k] ??= {}).add(b.booking);
      if (b.rfid.isNotEmpty) (vehicleRfids[k] ??= {}).add(b.rfid);
      final bk = NatraxUtilisationSheet.bookingKey(b.booking);
      if (bk.isNotEmpty) bookingVehicle.putIfAbsent(bk, () => k);
      evOnly[k] = false;
    }
    String? serviceVehicle(NatraxServiceLine s) {
      final bk = NatraxUtilisationSheet.bookingKey(s.booking);
      if (bk.isNotEmpty && bookingVehicle.containsKey(bk)) {
        return bookingVehicle[bk];
      }
      if (s.vehicle.isEmpty) return null;
      final k = NatraxUtilisationSheet.vehicleKey(s.vehicle);
      vehicleLabel.putIfAbsent(k, () => s.vehicle);
      evOnly.putIfAbsent(k, () => false);
      if (s.date != null) (vehicleDates[k] ??= {}).add(s.date!);
      return k;
    }

    for (final e in sheet.ev) {
      final k = NatraxUtilisationSheet.vehicleKey(e.vehicle);
      if (k.isEmpty) continue;
      vehicleLabel.putIfAbsent(k, () => e.vehicle);
      evOnly.putIfAbsent(k, () => true);
      if (e.date != null) (vehicleDates[k] ??= {}).add(e.date!);
    }
    for (final s in sheet.services) {
      serviceVehicle(s);
    }

    final programmeOptions = programmes();
    for (final k in vehicleLabel.keys) {
      final label = vehicleLabel[k]!;
      final decision = vehicles[k];
      final dates = (vehicleDates[k] ?? <DateTime>{}).toList()..sort();
      final suggestion = suggestProgramme(label, evOnly: evOnly[k] ?? false);
      final hours = sheet.blocks
          .where((b) => b.vehicleKey == k)
          .fold<double>(0, (s, b) => s + (b.charged ?? 0));
      final bookings = (vehicleBookings[k] ?? {}).where((b) => b.isNotEmpty);
      final rfids = vehicleRfids[k] ?? {};
      keep(ReconItem(
        key: 'veh|$k',
        kind: ReconKind.vehicle,
        stance: decision == null
            ? ReconStance.unknown
            : (decision.notOurs ? ReconStance.notOurs : ReconStance.matched),
        title: label,
        subtitle: [
          if (hours > 0) '${_h(hours)} h charged',
          if (evOnly[k] ?? false) 'EV charging only',
          if (bookings.isNotEmpty) bookings.join(', '),
          if (rfids.isNotEmpty) 'RFID ${rfids.join(', ')}',
          if (dates.isNotEmpty)
            dates.length == 1
                ? _d.format(dates.first)
                : '${_d.format(dates.first)} – ${_d.format(dates.last)}',
        ].join('  ·  '),
        options: [
          for (final p in programmeOptions)
            ReconOption(id: 'prog:$p', label: p),
          const ReconOption(
              id: 'not_ours',
              label: 'Not ours',
              detail: 'Everything on this vehicle is disputed',
              dispute: true),
        ],
        suggested: decision != null
            ? (decision.notOurs ? 'not_ours' : 'prog:${decision.project}')
            : (suggestion == null ? null : 'prog:$suggestion'),
        needsAnswer: true,
        // Vehicle answers live in their own table, so the decision itself is
        // the answer here.
        answer: decision == null
            ? null
            : ReconAnswer(
                itemKey: 'veh|$k',
                choice: decision.notOurs
                    ? 'not_ours'
                    : 'prog:${decision.project}'),
      ));
    }

    String? projectOf(String vehicleKey) {
      final d = vehicles[vehicleKey];
      if (d == null || d.notOurs) return null;
      return d.project;
    }

    bool notOurs(String vehicleKey) => vehicles[vehicleKey]?.notOurs ?? false;

    // ── 2. NATRAX's track time, for vehicles that are ours ────────────────
    final theirs = <String, _Side>{}; // date|project|code
    final theirExclusive = <String, List<NatraxBlock>>{}; // date|project
    final notOursBlocks = <String, List<NatraxBlock>>{};
    final theirMinutesByDay = <String, Map<String, int>>{}; // date|project
    final theirChargedNull = <String>{};

    for (final b in sheet.blocks) {
      final k = b.vehicleKey;
      if (notOurs(k)) {
        (notOursBlocks[k] ??= []).add(b);
        continue;
      }
      final p = projectOf(k);
      if (p == null) continue; // waiting on the vehicle question
      final dayKey = '${_ymd(b.date)}|$p';
      if (b.exclusive) {
        (theirExclusive[dayKey] ??= []).add(b);
        continue;
      }
      final code = b.code.isEmpty ? '?' : b.code;
      final key = '$dayKey|$code';
      final side = theirs[key] ??= _Side(b.date, p, code);
      side.hours += b.charged ?? 0;
      if (b.charged == null) theirChargedNull.add(key);
      side.minutes += b.minutes;
      side.theirRuns.addAll(b.runs);
      if (code != '?') {
        final m = theirMinutesByDay[dayKey] ??= {};
        m[code] = (m[code] ?? 0) + b.minutes;
      }
    }

    // ── 3. Ours ───────────────────────────────────────────────────────────
    final mine = <String, _Side>{};
    final myExclusive = <String, List<OurRun>>{};
    final myMinutesByDay = <String, Map<String, int>>{};
    final myRunsByDay = <String, List<OurRun>>{};
    for (final r in ours.runs) {
      final code = r.code.toUpperCase();
      if (code.isEmpty || code == 'MISC') continue;
      final dayKey = '${_ymd(r.date)}|${r.project}';
      (myRunsByDay[dayKey] ??= []).add(r);
      if (NatraxRateCard.isExclusive(code)) {
        (myExclusive[dayKey] ??= []).add(r);
        continue;
      }
      final key = '$dayKey|$code';
      final side = mine[key] ??= _Side(_day(r.date), r.project, code);
      side.minutes += r.minutes;
      side.cost += r.cost;
      side.ourRuns.add(r);
      final m = myMinutesByDay[dayKey] ??= {};
      m[code] = (m[code] ?? 0) + r.minutes;
    }
    // Billable hours by the same rule NATRAX bill on.
    myMinutesByDay.forEach((dayKey, byCode) {
      NatraxRateCard.billableForDay(byCode).forEach((code, h) {
        mine['$dayKey|$code']?.hours = h;
      });
    });
    final ruleByKey = <String, double>{};
    theirMinutesByDay.forEach((dayKey, byCode) {
      NatraxRateCard.billableForDay(byCode).forEach((code, h) {
        ruleByKey['$dayKey|$code'] = h;
      });
    });

    // Runs on the other side, same day and programme, that overlap a run on
    // a DIFFERENT track: most often the same running logged under another
    // code by one side or the other.
    List<String> overlapHints(
        String dayKey, String code, List<OurRun> mineRuns, List<NatraxRun> theirRunsHere) {
      final out = <String>[];
      final dayParts = dayKey.split('|');
      bool overlaps(int a1, int a2, int b1, int b2) =>
          a1 < b2 && b1 < a2;
      // Our runs on this code vs NATRAX runs on other codes.
      for (final r in mineRuns) {
        for (final other in theirs.values) {
          if (_ymd(other.date) != dayParts[0] || other.project != dayParts[1]) continue;
          if (other.code == code) continue;
          for (final t in other.theirRuns) {
            if (overlaps(r.startMin, r.startMin + r.minutes, t.inMin,
                t.inMin + t.minutes)) {
              out.add('Our ${r.label} run on $code overlaps NATRAX\'s '
                  '${t.label} on ${other.code} — possibly the same running, '
                  'logged on different tracks.');
            }
          }
        }
      }
      // NATRAX runs on this code vs our runs on other codes.
      for (final t in theirRunsHere) {
        for (final r in myRunsByDay[dayKey] ?? const <OurRun>[]) {
          if (r.code.toUpperCase() == code) continue;
          if (overlaps(r.startMin, r.startMin + r.minutes, t.inMin,
              t.inMin + t.minutes)) {
            out.add('NATRAX\'s ${t.label} on $code overlaps our '
                '${r.label} on ${r.code} — possibly the same running, logged '
                'on different tracks.');
          }
        }
      }
      return out.toSet().toList();
    }

    // ── 4. Track questions ────────────────────────────────────────────────
    final keys = {...theirs.keys, ...mine.keys}.toList()..sort();
    for (final key in keys) {
      final t = theirs[key];
      final o = mine[key];
      final parts = key.split('|');
      final date = DateTime.parse(parts[0]);
      final project = parts[1];
      final code = parts[2];
      final dayKey = '${parts[0]}|$project';
      final rate = NatraxRateCard.rateFor(code);
      final name = code == '?' ? 'Unrecognised track' : NatraxRateCard.nameFor(code);
      final th = t?.hours ?? 0;
      final oh = o?.hours ?? 0;
      final tm = t?.minutes ?? 0;
      final om = o?.minutes ?? 0;
      final rule = ruleByKey[key];
      final title = '${_d.format(date)} · $code ${code == '?' ? '' : '· $name'}';
      final agrees = t != null && o != null && th == oh;
      final hints = <String>[
        if (code == '?')
          'NATRAX\'s track label was not recognised, so it cannot be priced '
              'or matched. Check the sheet.',
        if (rate == 0 && code != '?')
          '$code is not on the rate card, so it is priced at nil here.',
        // Only worth saying where the line is in question; on a line that
        // agrees it is noise.
        if (!agrees)
          ...overlapHints(dayKey, code, o?.ourRuns ?? const [],
              t?.theirRuns ?? const []),
        if (t != null && o != null && (tm - om).abs() >= 30)
          'Minutes differ: NATRAX\'s gate log has $tm, our record $om.',
      ];
      final snapshot = 't=${_h(th)}|o=${_h(oh)}|tm=$tm|om=$om';
      final theirsMoney = th * rate;
      final oursMoney = o?.cost ?? 0;
      final base = (
        date: date,
        project: project,
        code: code,
        title: title,
        rate: rate,
      );

      ReconItem make({
        required ReconStance stance,
        required List<ReconOption> options,
        String? suggested,
        String auto = '',
        bool needs = true,
        bool bulk = false,
      }) =>
          ReconItem(
            key: 'trk|$key',
            kind: ReconKind.track,
            stance: stance,
            title: base.title,
            subtitle: project,
            date: base.date,
            project: base.project,
            code: base.code,
            ours: o == null ? 0 : oh,
            theirs: t == null ? 0 : th,
            rule: rule,
            oursMinutes: om,
            theirsMinutes: tm,
            ourRuns: o?.ourRuns ?? const [],
            theirRuns: t?.theirRuns ?? const [],
            rate: base.rate,
            hints: hints,
            options: options,
            suggested: suggested,
            autoComment: auto,
            needsAnswer: needs,
            bulkOk: bulk,
            snapshot: snapshot,
            theirsMoney: theirsMoney,
            oursMoney: oursMoney,
          );

      if (t != null && o != null && th == oh) {
        keep(make(stance: ReconStance.matched, options: const [], needs: false));
        continue;
      }
      if (t != null && o == null) {
        keep(make(
          stance: ReconStance.theirsOnly,
          options: [
            ReconOption(
              id: 'add',
              label: 'We ran it — accept ${_h(th)} h',
              detail: 'It is missing from TrackLog; add the runs.',
              agreed: th,
              todo: 'Add ${_d.format(date)} $code for $project '
                  '(${t.theirRuns.map((r) => r.label).join(', ')}) — '
                  'on NATRAX\'s sheet, not in TrackLog.',
            ),
            ReconOption(
              id: 'dispute',
              label: 'Not run by us — dispute',
              detail: 'Ask NATRAX to take ${_h(th)} h off.',
              agreed: 0,
              dispute: true,
            ),
          ],
          suggested: 'add',
          auto: 'On NATRAX\'s sheet — ${t.theirRuns.length} run'
              '${t.theirRuns.length == 1 ? '' : 's'}, $tm min, ${_h(th)} h — '
              'but not in TrackLog.',
        ));
        continue;
      }
      if (t == null && o != null) {
        keep(make(
          stance: ReconStance.oursOnly,
          options: [
            ReconOption(
              id: 'accept',
              label: 'Accept — NATRAX did not bill it',
              detail: 'Settled at nil; our record shows ${_h(oh)} h.',
              agreed: 0,
            ),
            ReconOption(
              id: 'later',
              label: 'Expect it on a later sheet',
              detail: 'Settled at nil for now; watch next month.',
              agreed: 0,
              todo: 'Watch for ${_d.format(date)} $code ($project, '
                  '${_h(oh)} h) on a later NATRAX sheet.',
            ),
          ],
          suggested: 'accept',
          bulk: true,
          auto: 'Not on NATRAX\'s sheet; our record has ${_h(oh)} h '
              '($om min). Settled at nil.',
        ));
        continue;
      }
      // Both have it, at different hours.
      if (th < oh) {
        keep(make(
          stance: ReconStance.inFavour,
          options: [
            ReconOption(
              id: 'accept',
              label: 'NATRAX are right — settle at ${_h(th)} h',
              detail: 'Their gate log stands; correct our record.',
              agreed: th,
              todo: 'Correct ${_d.format(date)} $code for $project: we have '
                  '${_h(oh)} h ($om min), NATRAX ${_h(th)} h ($tm min).',
            ),
            ReconOption(
              id: 'noted',
              label: 'Ours is right — they billed less',
              detail: 'Settle at their ${_h(th)} h and keep our record.',
              agreed: th,
            ),
          ],
          suggested: 'accept',
          bulk: true,
          auto: 'NATRAX charged ${_h(th)} h against our ${_h(oh)} h '
              '(their gate log $tm min, ours $om min). Settled at their '
              'figure.',
        ));
      } else {
        // NATRAX more. Their gate log showing more time than ours points to
        // runs we did not log; showing less while charging more points to an
        // error on their side.
        final likelyShort = tm > om;
        keep(make(
          stance: ReconStance.theirsMore,
          options: [
            ReconOption(
              id: 'accept',
              label: 'Accept ${_h(th)} h — our record is short',
              detail: 'Add what TrackLog is missing.',
              agreed: th,
              todo: 'Add the missing ${_d.format(date)} $code runs for '
                  '$project: NATRAX ${_h(th)} h ($tm min), ours ${_h(oh)} h '
                  '($om min).',
            ),
            ReconOption(
              id: 'dispute',
              label: 'Dispute — we make it ${_h(oh)} h',
              detail: 'Ask NATRAX to take ${_h(th - oh)} h off.',
              agreed: oh,
              dispute: true,
            ),
          ],
          suggested: likelyShort ? 'accept' : 'dispute',
          auto: likelyShort
              ? 'NATRAX\'s gate log has $tm min against our $om; accepted '
                  '${_h(th)} h.'
              : 'NATRAX charged ${_h(th)} h on $tm min of gate time; we make '
                  'it ${_h(oh)} h on $om min.',
        ));
      }
    }

    // ── 5. NATRAX against their own gate log ──────────────────────────────
    // Per shared-floor group, so a correct wet/dry split NATRAX happen to
    // book the other way round is not flagged.
    final groupCharged = <String, double>{};
    final groupRule = <String, double>{};
    final groupInfo = <String, ({DateTime date, String project, String group})>{};
    for (final entry in theirs.entries) {
      final side = entry.value;
      if (side.code == '?') continue;
      if (theirChargedNull.contains(entry.key)) continue;
      final g = _groupOf(side.code);
      final gk = '${_ymd(side.date)}|${side.project}|$g';
      groupCharged[gk] = (groupCharged[gk] ?? 0) + side.hours;
      groupRule[gk] = (groupRule[gk] ?? 0) + (ruleByKey[entry.key] ?? 0);
      groupInfo[gk] = (date: side.date, project: side.project, group: g);
    }
    for (final gk in groupCharged.keys) {
      final charged = groupCharged[gk]!;
      final rule = groupRule[gk]!;
      if (charged == rule) continue;
      final info = groupInfo[gk]!;
      final codes = info.group.split('+');
      final rate = codes.map(NatraxRateCard.rateFor).reduce((a, b) => a > b ? a : b);
      final mins = theirMinutesByDay['${_ymd(info.date)}|${info.project}'] ?? {};
      final minuteText = codes
          .where((c) => mins.containsKey(c))
          .map((c) => '$c ${mins[c]} min')
          .join(' + ');
      final label = codes.length > 1 ? 'T3 (wet + dry)' : info.group;
      if (charged > rule) {
        keep(ReconItem(
          key: 'rule|$gk',
          kind: ReconKind.rule,
          stance: ReconStance.overcharge,
          title: '${_d.format(info.date)} · $label · charged above the gate log',
          subtitle: info.project,
          date: info.date,
          project: info.project,
          code: info.group,
          theirs: charged,
          rule: rule,
          rate: rate,
          hints: [
            'NATRAX\'s own in/out times ($minuteText) round to ${_h(rule)} h '
                'with the day minimum. They charged ${_h(charged)} h.',
          ],
          options: [
            ReconOption(
              id: 'dispute',
              label: 'Dispute the extra ${_h(charged - rule)} h',
              detail: 'Ask NATRAX to bill ${_h(rule)} h.',
              agreed: rule,
              dispute: true,
            ),
            ReconOption(
              id: 'accept',
              label: 'Accept ${_h(charged)} h',
              detail: 'There is a reason the gate log does not show.',
              agreed: charged,
            ),
          ],
          suggested: 'dispute',
          autoComment: 'NATRAX\'s gate log ($minuteText) supports '
              '${_h(rule)} h; ${_h(charged)} h charged.',
          snapshot: 'c=${_h(charged)}|r=${_h(rule)}',
          theirsMoney: charged * rate,
        ));
      } else {
        keep(ReconItem(
          key: 'rule|$gk',
          kind: ReconKind.rule,
          stance: ReconStance.undercharge,
          title: '${_d.format(info.date)} · $label · charged below the gate log',
          subtitle: info.project,
          date: info.date,
          project: info.project,
          code: info.group,
          theirs: charged,
          rule: rule,
          rate: rate,
          hints: [
            'Their in/out times ($minuteText) round to ${_h(rule)} h; they '
                'charged ${_h(charged)} h. In your favour — not chased.',
          ],
          needsAnswer: false,
          snapshot: 'c=${_h(charged)}|r=${_h(rule)}',
          theirsMoney: charged * rate,
        ));
      }
    }
    for (final key in theirChargedNull) {
      final side = theirs[key]!;
      final rule = ruleByKey[key] ?? 0;
      keep(ReconItem(
        key: 'rule|$key|blank',
        kind: ReconKind.rule,
        stance: ReconStance.unknown,
        title: '${_d.format(side.date)} · ${side.code} · no hours charged',
        subtitle: side.project,
        date: side.date,
        project: side.project,
        code: side.code,
        rule: rule,
        rate: NatraxRateCard.rateFor(side.code),
        hints: [
          'The sheet leaves "Charged HRS" blank for this block. Their gate log '
              'rounds to ${_h(rule)} h.',
        ],
        options: [
          ReconOption(
              id: 'rule',
              label: 'Expect ${_h(rule)} h',
              detail: 'What their own in/out times support.',
              agreed: rule),
          const ReconOption(
              id: 'nil',
              label: 'Expect nil',
              detail: 'NATRAX are not billing it.',
              agreed: 0),
        ],
        suggested: 'rule',
        snapshot: 'r=${_h(rule)}',
      ));
    }

    // ── 6. Exclusive bookings ─────────────────────────────────────────────
    final exDays = {...theirExclusive.keys, ...myExclusive.keys}.toList()..sort();
    for (final dayKey in exDays) {
      final tb = theirExclusive[dayKey] ?? const <NatraxBlock>[];
      final ob = myExclusive[dayKey] ?? const <OurRun>[];
      final parts = dayKey.split('|');
      final date = DateTime.parse(parts[0]);
      final th = tb.fold<double>(0, (s, b) => s + (b.charged ?? 0));
      final tm = tb.fold<int>(0, (s, b) => s + b.minutes);
      final om = ob.fold<int>(0, (s, r) => s + r.minutes);
      final oh = TrackCostRules.ceilHours(om);
      final tCode = tb.isEmpty ? '' : tb.first.code;
      final oCode = ob.isEmpty ? '' : ob.first.code.toUpperCase();
      final tMoney = tb.isEmpty ? 0.0 : NatraxRateCard.exclusiveCost(tCode, th);
      final oMoney = ob.fold<double>(0, (s, r) => s + r.cost);
      final hints = <String>[
        if (tCode.isNotEmpty && oCode.isNotEmpty && tCode != oCode)
          'NATRAX booked ${NatraxRateCard.nameFor(tCode)}; we logged '
              '${NatraxRateCard.nameFor(oCode)}. Different tracks, different '
              'block prices.',
        for (final b in tb)
          if (b.rawTrack.toUpperCase().contains('AFTER'))
            'NATRAX label it "${b.rawTrack}" — the invoice will show how they '
                'price time after the first block.',
        'Exclusive time is sold in ${_h(NatraxRateCard.blockHoursFor(tCode.isEmpty ? oCode : tCode))}-hour '
            'blocks, so the money is estimated by block, not by the hour.',
      ];
      final same = tb.isNotEmpty && ob.isNotEmpty && tCode == oCode && th == oh;
      // Their sheet names one exclusive track, our record another. 15 Oct
      // 2026: the sheet says "(After 2 Hrs)(T1-003)" — High Speed, ₹1,80,000
      // a block — where the car was on the braking track, ₹1,50,000. Their
      // hours can be right while their track is wrong, so the fair figure is
      // their hours at OUR track's block price. When that is below theirs,
      // the line is NATRAX billing more and must not be swept up by "accept
      // all in our favour", however much higher our own 4 h might be.
      final wrongTrack = tCode.isNotEmpty &&
          oCode.isNotEmpty &&
          tCode != oCode &&
          NatraxRateCard.isExclusive(oCode);
      final fairMoney =
          wrongTrack ? NatraxRateCard.exclusiveCost(oCode, th) : tMoney;
      final overByTrack = wrongTrack && fairMoney < tMoney;
      final favour = !overByTrack && tMoney <= oMoney;
      keep(ReconItem(
        key: 'exc|$dayKey',
        kind: ReconKind.exclusive,
        stance: same
            ? ReconStance.matched
            : (tb.isEmpty
                ? ReconStance.oursOnly
                : (ob.isEmpty
                    ? ReconStance.theirsOnly
                    : (favour ? ReconStance.inFavour : ReconStance.theirsMore))),
        title: '${_d.format(date)} · exclusive booking',
        subtitle: parts[1],
        date: date,
        project: parts[1],
        code: tCode.isEmpty ? oCode : tCode,
        ours: oh,
        theirs: th,
        oursMinutes: om,
        theirsMinutes: tm,
        ourRuns: ob,
        theirRuns: [for (final b in tb) ...b.runs],
        rate: NatraxRateCard.rateFor(tCode.isEmpty ? oCode : tCode),
        hints: hints,
        options: same
            ? const []
            : [
                ReconOption(
                  id: 'accept',
                  label: tb.isEmpty
                      ? 'Accept — NATRAX did not bill it'
                      : 'Accept NATRAX\'s ${_h(th)} h exclusive',
                  agreed: th,
                  agreedMoney: tMoney,
                  todo: (tCode != oCode && ob.isNotEmpty && tb.isNotEmpty)
                      ? 'Check ${_d.format(date)} exclusive: we logged $oCode, '
                          'NATRAX booked $tCode.'
                      : null,
                ),
                if (wrongTrack)
                  ReconOption(
                    id: 'their_hours_our_track',
                    label: 'Their ${_h(th)} h, priced as $oCode — '
                        '${_rs(fairMoney)}',
                    detail: 'Their hours, but the sheet names the wrong track: '
                        'it was ${NatraxRateCard.nameFor(oCode)}.',
                    agreed: th,
                    agreedMoney: fairMoney,
                    dispute: fairMoney < tMoney,
                  ),
                ReconOption(
                  id: 'dispute',
                  label: ob.isEmpty
                      ? 'Dispute — we had no exclusive run that day'
                      : 'Dispute — we make it ${_h(oh)} h'
                          '${oCode.isEmpty ? '' : ' on $oCode'}',
                  agreed: oh,
                  agreedMoney: oMoney,
                  dispute: true,
                ),
              ],
        suggested: same
            ? null
            : (wrongTrack ? 'their_hours_our_track' : (favour ? 'accept' : null)),
        autoComment: wrongTrack
            ? 'NATRAX\'s sheet names ${NatraxRateCard.nameFor(tCode)} '
                '(${_rs(tMoney)}); the car was on ${NatraxRateCard.nameFor(oCode)}. '
                'Their ${_h(th)} h priced as $oCode: ${_rs(fairMoney)}.'
            : favour
                ? 'Exclusive: NATRAX ${_h(th)} h${tCode.isEmpty ? '' : ' on $tCode'}, '
                    'ours ${_h(oh)} h${oCode.isEmpty ? '' : ' on $oCode'}. Settled at their figure.'
                : '',
        needsAnswer: !same,
        bulkOk: !same && favour && !wrongTrack,
        snapshot: 't=${_h(th)}$tCode|o=${_h(oh)}$oCode',
        theirsMoney: tMoney,
        oursMoney: oMoney,
      ));
    }

    // ── 7. Services and EV ────────────────────────────────────────────────
    final theirSvc = <String, double>{};
    final theirSvcNames = <String, Set<String>>{};
    final notOursSvc = <String, List<NatraxServiceLine>>{};
    for (final s in sheet.services) {
      final vk = serviceVehicle(s);
      if (vk != null && notOurs(vk)) {
        (notOursSvc[vk] ??= []).add(s);
        continue;
      }
      if (vk != null && projectOf(vk) == null) continue; // vehicle unanswered
      final cat = ServiceCategory.of(s.name);
      final k = cat?.id ?? 'OTHER:${s.name}';
      theirSvc[k] = (theirSvc[k] ?? 0) + s.quantity;
      (theirSvcNames[k] ??= {}).add(s.name);
    }
    final mySvc = <String, double>{};
    final mySvcCost = <String, double>{};
    var myEvUnits = 0.0, myEvCost = 0.0;
    for (final s in ours.services) {
      if (ServiceCategory.isEv(s.name)) {
        myEvUnits += s.quantity;
        myEvCost += s.cost;
        continue;
      }
      final cat = ServiceCategory.of(s.name);
      // The bay is counted from the muster, not from service lines, which
      // record rupees on an invoice rather than which days.
      if (cat == null || cat.id == 'ACCOM') continue;
      mySvc[cat.id] = (mySvc[cat.id] ?? 0) + s.quantity;
      mySvcCost[cat.id] = (mySvcCost[cat.id] ?? 0) + s.cost;
    }
    final accomDays = ours.workshopDays
        .where((d) => d.year == sheet.month.year && d.month == sheet.month.month)
        .toList()
      ..sort();
    if (accomDays.isNotEmpty || theirSvc.containsKey('ACCOM')) {
      mySvc['ACCOM'] = accomDays.length.toDouble();
      mySvcCost['ACCOM'] = accomDays.length * ServiceCategory.byId('ACCOM')!.rate;
    }

    final monthEnd = DateTime(sheet.month.year, sheet.month.month + 1, 0);
    final registerStopsEarly =
        accomDays.isNotEmpty && accomDays.last.isBefore(monthEnd);
    final svcKeys = {...theirSvc.keys, ...mySvc.keys}.toList()..sort();
    for (final k in svcKeys) {
      final cat = ServiceCategory.byId(k);
      final tq = theirSvc[k] ?? 0;
      final oq = mySvc[k] ?? 0;
      final rate = cat?.rate ?? 0;
      final name = cat?.name ?? k.substring('OTHER:'.length);
      final unit = cat?.unit ?? 'Nos';
      final hints = <String>[
        if (cat == null)
          '"$name" is not on the agreed service list, so there is no rate to '
              'check it against. Put the rate in the comment, or ask NATRAX.',
        if (k == 'ACCOM' && accomDays.isNotEmpty &&
            accomDays.last.day < DateTime(sheet.month.year, sheet.month.month + 1, 0).day)
          'Our workshop register stops on ${_d.format(accomDays.last)}.',
        if (k == 'ACCOM' && (theirSvcNames[k]?.isNotEmpty ?? false))
          'NATRAX: ${theirSvcNames[k]!.join(', ')}.',
      ];
      final snapshot = 't=${_h(tq)}|o=${_h(oq)}';
      final tMoney = tq * rate;
      final oMoney = mySvcCost[k] ?? oq * rate;
      if (cat == null) {
        keep(ReconItem(
          key: 'svc|$k',
          kind: ReconKind.service,
          stance: ReconStance.unknown,
          title: name,
          subtitle: 'Not on the service list',
          unit: unit,
          ours: oq,
          theirs: tq,
          hints: hints,
          options: [
            ReconOption(
                id: 'accept',
                label: 'Accept ${_h(tq)} $unit',
                detail: 'Note the agreed rate in the comment.',
                agreed: tq),
            const ReconOption(
                id: 'query',
                label: 'Ask NATRAX for the rate',
                dispute: true,
                agreed: 0),
          ],
          snapshot: snapshot,
        ));
        continue;
      }
      if (tq == oq) {
        keep(ReconItem(
          key: 'svc|$k',
          kind: ReconKind.service,
          stance: ReconStance.matched,
          title: name,
          unit: unit,
          ours: oq,
          theirs: tq,
          rate: rate,
          hints: hints,
          needsAnswer: false,
          snapshot: snapshot,
          theirsMoney: tMoney,
          oursMoney: oMoney,
        ));
        continue;
      }
      final favour = tq < oq;
      keep(ReconItem(
        key: 'svc|$k',
        kind: ReconKind.service,
        stance: favour
            ? ReconStance.inFavour
            : (oq == 0 ? ReconStance.theirsOnly : ReconStance.theirsMore),
        title: name,
        unit: unit,
        ours: oq,
        theirs: tq,
        rate: rate,
        hints: hints,
        options: favour
            ? [
                ReconOption(
                    id: 'accept',
                    label: 'Settle at NATRAX\'s ${_h(tq)} $unit',
                    agreed: tq,
                    todo: 'Correct $name: we have ${_h(oq)}, NATRAX ${_h(tq)}.'),
                ReconOption(
                    id: 'noted',
                    label: 'Ours is right — they billed less',
                    agreed: tq),
              ]
            : [
                ReconOption(
                    id: 'accept',
                    label: 'Accept ${_h(tq)} $unit — our record is short',
                    agreed: tq,
                    todo: k == 'ACCOM'
                        ? 'Add the missing workshop days to the muster '
                            '(NATRAX ${_h(tq)}, ours ${_h(oq)}).'
                        : 'Add the missing $name to TrackLog '
                            '(NATRAX ${_h(tq)}, ours ${_h(oq)}).'),
                ReconOption(
                    id: 'dispute',
                    label: 'Dispute — we make it ${_h(oq)} $unit',
                    agreed: oq,
                    dispute: true),
              ],
        // NATRAX more: a consumable we never logged (water, coupons) or a bay
        // register that stopped early is far likelier than an overcharge, so
        // those lean towards accepting. Anything else is left to the person.
        suggested: favour || oq == 0 || (k == 'ACCOM' && registerStopsEarly)
            ? 'accept'
            : null,
        autoComment: favour
            ? 'NATRAX ${_h(tq)} $unit against our ${_h(oq)}. Settled at their figure.'
            : (oq == 0
                ? 'Not in TrackLog; NATRAX ${_h(tq)} $unit. Accepted.'
                : (k == 'ACCOM' && registerStopsEarly
                    ? 'Our workshop register stops on '
                        '${_d.format(accomDays.last)}; NATRAX bill ${_h(tq)} days.'
                    : '')),
        bulkOk: favour,
        snapshot: snapshot,
        theirsMoney: tMoney,
        oursMoney: oMoney,
      ));
    }

    // EV charging: units, for vehicles that are ours.
    var theirEv = 0.0;
    final evDates = <DateTime>{};
    var evWaiting = false;
    for (final e in sheet.ev) {
      final k = NatraxUtilisationSheet.vehicleKey(e.vehicle);
      if (notOurs(k)) continue;
      if (projectOf(k) == null) {
        evWaiting = true;
        continue;
      }
      theirEv += e.units;
      if (e.date != null) evDates.add(e.date!);
    }
    if (theirEv > 0 || myEvUnits > 0) {
      final tq = double.parse(theirEv.toStringAsFixed(2));
      final oq = double.parse(myEvUnits.toStringAsFixed(2));
      final rate = ServiceCategory.evRate;
      final favour = tq <= oq;
      final same = (tq - oq).abs() < 0.5;
      keep(ReconItem(
        key: 'ev|units',
        kind: ReconKind.ev,
        stance: same
            ? ReconStance.matched
            : (favour ? ReconStance.inFavour : ReconStance.theirsMore),
        title: 'EV charging',
        unit: 'units',
        ours: oq,
        theirs: tq,
        rate: rate,
        hints: [
          if (evWaiting) 'Some EV charging is waiting on a vehicle question.',
          'NATRAX bill whole units on the invoice; the sheet carries decimals.',
        ],
        options: same
            ? const []
            : (favour
                ? [
                    ReconOption(
                        id: 'accept',
                        label: 'Settle at NATRAX\'s ${_h(tq)} units',
                        agreed: tq,
                        todo: 'Correct EV charging: ours ${_h(oq)} units, '
                            'NATRAX ${_h(tq)}.'),
                    ReconOption(
                        id: 'noted',
                        label: 'Ours is right — they billed less',
                        agreed: tq),
                  ]
                : [
                    ReconOption(
                        id: 'accept',
                        label: 'Accept ${_h(tq)} units — our record is short',
                        agreed: tq,
                        todo: 'Add the missing EV charging '
                            '(NATRAX ${_h(tq)} units, ours ${_h(oq)}).'),
                    ReconOption(
                        id: 'dispute',
                        label: 'Query the extra ${_h(tq - oq)} units',
                        agreed: oq,
                        dispute: true),
                  ]),
        suggested: same ? null : (favour ? 'accept' : null),
        autoComment:
            favour ? 'NATRAX ${_h(tq)} units against our ${_h(oq)}.' : '',
        needsAnswer: !same,
        bulkOk: !same && favour,
        snapshot: 't=${_h(tq)}|o=${_h(oq)}',
        theirsMoney: tq * rate,
        oursMoney: myEvCost,
      ));
    }

    // ── 8. Vehicles that are not ours ─────────────────────────────────────
    for (final k in {...notOursBlocks.keys, ...notOursSvc.keys}) {
      final blocks = notOursBlocks[k] ?? const <NatraxBlock>[];
      final svc = notOursSvc[k] ?? const <NatraxServiceLine>[];
      var money = 0.0;
      var hours = 0.0;
      for (final b in blocks) {
        final h = b.charged ?? 0;
        hours += h;
        money += b.exclusive
            ? NatraxRateCard.exclusiveCost(b.code, h)
            : h * NatraxRateCard.rateFor(b.code);
      }
      for (final s in svc) {
        money += s.quantity * (ServiceCategory.of(s.name)?.rate ?? 0);
      }
      final bookings = blocks.map((b) => b.booking).toSet().join(', ');
      keep(ReconItem(
        key: 'nto|$k',
        kind: ReconKind.notOurs,
        stance: ReconStance.notOurs,
        title: '${vehicleLabel[k] ?? k} — not ours',
        subtitle: bookings,
        theirs: hours,
        hints: [
          for (final b in blocks)
            '${_d.format(b.date)} ${b.code}: ${_h(b.charged ?? 0)} h '
                '(${b.runs.length} runs, ${b.minutes} min)',
          for (final s in svc)
            '${s.date == null ? '' : '${_d.format(s.date!)} '}${s.name}: '
                '${_h(s.quantity)}',
        ],
        needsAnswer: false,
        theirsMoney: money,
      ));
    }

    // ── Summary by track ──────────────────────────────────────────────────
    final lines = <String, _Line>{};
    for (final i in items) {
      if (i.kind != ReconKind.track && i.kind != ReconKind.exclusive) continue;
      final code = i.code ?? '?';
      final l = lines[code] ??= _Line(code);
      l.natrax += i.theirs ?? 0;
      l.ours += i.ours ?? 0;
      l.agreed += i.agreed ?? 0;
      l.natraxMoney += i.theirsMoney;
      l.oursMoney += i.oursMoney;
      l.agreedMoney += i.agreedMoney;
    }
    for (final r in items.where((i) => i.kind == ReconKind.rule)) {
      final c = r.stale ? null : r.chosen;
      if (c == null || !c.dispute) continue;
      final excess = (r.theirs ?? 0) - (c.agreed ?? 0);
      final code = (r.code ?? '').split('+').first;
      final l = lines[code];
      if (l == null) continue;
      l.agreed -= excess;
      l.agreedMoney -= excess * r.rate;
    }
    final trackLines = [
      for (final l in lines.values)
        ReconTrackLine(
          code: l.code,
          name: l.code == '?' ? 'Unrecognised' : NatraxRateCard.nameFor(l.code),
          rate: NatraxRateCard.rateFor(l.code),
          natrax: l.natrax,
          ours: l.ours,
          agreed: l.agreed,
          natraxMoney: l.natraxMoney,
          oursMoney: l.oursMoney,
          agreedMoney: l.agreedMoney,
        ),
    ]..sort((a, b) => b.natraxMoney.compareTo(a.natraxMoney));

    // Questions first, information after; within each, by date.
    items.sort((a, b) {
      int rank(ReconItem i) => i.kind == ReconKind.vehicle ? 0 : (i.needsAnswer ? 1 : 2);
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final da = a.date ?? DateTime(2100), db = b.date ?? DateTime(2100);
      final d = da.compareTo(db);
      return d != 0 ? d : a.key.compareTo(b.key);
    });

    return ReconOutcome(sheet: sheet, items: items, trackLines: trackLines);
  }

  // ── The invoice ───────────────────────────────────────────────────────────

  /// Sets the final invoice against what the sheet was cleared at.
  ///
  /// One question per kind of line — T3 Wet, EV charging, water — because
  /// the invoice carries no dates. Any difference needs an answer, and the
  /// comment is what records it against the month.
  static List<ReconItem> tally({
    required ReconOutcome outcome,
    required ParsedInvoice invoice,
    Map<String, ReconAnswer> answers = const {},
  }) {
    final agreedQty = <String, double>{};
    final agreedMoney = <String, double>{};
    final names = <String, String>{};
    for (final i in outcome.items) {
      String? k;
      if (i.kind == ReconKind.track || i.kind == ReconKind.exclusive) {
        k = i.code;
        if (k != null) names[k] = NatraxRateCard.nameFor(k);
      } else if (i.kind == ReconKind.service) {
        k = i.key.substring('svc|'.length);
        names[k] = i.title;
      } else if (i.kind == ReconKind.ev) {
        k = 'EV';
        names[k] = 'EV charging';
      }
      if (k == null) continue;
      agreedQty[k] = (agreedQty[k] ?? 0) + (i.agreed ?? 0);
      agreedMoney[k] = (agreedMoney[k] ?? 0) + i.agreedMoney;
    }
    // Disputed rule excess comes off the line.
    for (final r in outcome.items.where((i) => i.kind == ReconKind.rule)) {
      final c = r.stale ? null : r.chosen;
      if (c == null || !c.dispute) continue;
      final code = (r.code ?? '').split('+').first;
      final excess = (r.theirs ?? 0) - (c.agreed ?? 0);
      agreedQty[code] = (agreedQty[code] ?? 0) - excess;
      agreedMoney[code] = (agreedMoney[code] ?? 0) - excess * r.rate;
    }

    final invQty = <String, double>{};
    final invMoney = <String, double>{};
    final invDerived = <String>{};
    for (final l in invoice.lines) {
      final k = invoiceLineKey(l);
      names.putIfAbsent(k, () => l.description);
      invQty[k] = (invQty[k] ?? 0) + (l.quantity ?? 0);
      invMoney[k] = (invMoney[k] ?? 0) + l.amount;
      if (l.amountDerived) invDerived.add(k);
    }

    final out = <ReconItem>[];
    final keys = {...agreedMoney.keys, ...invMoney.keys}.toList()..sort();
    for (final k in keys) {
      final aq = agreedQty[k] ?? 0, am = agreedMoney[k] ?? 0;
      final iq = invQty[k] ?? 0, im = invMoney[k] ?? 0;
      if (am == 0 && im == 0 && aq == 0 && iq == 0) continue;
      final name = names[k] ?? k;
      final unit = k.startsWith('T') ? 'h' : (k == 'EV' ? 'units' : '');
      final rateOnCard = k.startsWith('T')
          ? NatraxRateCard.rateFor(k)
          : (k == 'EV'
              ? ServiceCategory.evRate
              : (ServiceCategory.byId(k)?.rate ?? 0));
      final hints = <String>[
        if (invDerived.contains(k))
          'The invoice\'s amount for this line was not in its text; it is '
              'worked out here as quantity × rate.',
        if (iq > 0 && rateOnCard > 0 && !NatraxRateCard.isExclusive(k) &&
            (im / iq - rateOnCard).abs() > 0.5)
          'Invoiced at ${_rs(im / iq)} a unit; the rate card says '
              '${_rs(rateOnCard)}.',
        if (k.startsWith('OTHER:') || ServiceCategory.byId(k) == null && !k.startsWith('T') && k != 'EV')
          'Not a line the cleared sheet has a figure for.',
      ];
      final same = (am - im).abs() <= 1.0 && (aq - iq).abs() < 0.5;
      final favour = im < am;
      final snapshot = 'a=${am.toStringAsFixed(2)}|i=${im.toStringAsFixed(2)}';
      final item = ReconItem(
        key: 'inv|$k',
        kind: ReconKind.invoice,
        stance: same
            ? ReconStance.matched
            : (favour ? ReconStance.inFavour : ReconStance.theirsMore),
        title: name,
        unit: unit,
        ours: aq,
        theirs: iq,
        rate: rateOnCard,
        hints: hints,
        options: same
            ? const []
            : [
                ReconOption(
                    id: 'accept',
                    label: favour
                        ? 'Accept — invoiced less than agreed'
                        : 'Accept the invoice figure',
                    agreed: iq,
                    agreedMoney: im),
                ReconOption(
                    id: 'dispute',
                    label: 'Dispute — expected ${_rs(am)}',
                    agreed: aq,
                    agreedMoney: am,
                    dispute: true),
              ],
        suggested: same ? null : (favour ? 'accept' : null),
        autoComment: favour
            ? 'Invoiced ${_rs(im)} against ${_rs(am)} agreed. Settled at the invoice figure.'
            : '',
        needsAnswer: !same,
        bulkOk: !same && favour,
        snapshot: snapshot,
        theirsMoney: im,
        oursMoney: am,
      );
      out.add(item.withAnswer(answers[item.key]));
    }
    return out;
  }

  /// The line key an invoice line tallies under: a track code (with X for an
  /// exclusive booking), a service category, EV, or OTHER:<description>.
  static String invoiceLineKey(ParsedInvoiceLine l) {
    final d = l.description.toLowerCase();
    final svc = ServiceCategory.of(l.description);
    if (ServiceCategory.isEv(l.description)) return 'EV';
    final base = l.matchKey;
    if (base != null && base.startsWith('T')) {
      if (d.contains('exclusive')) {
        final n = RegExp(r'T(\d+)').firstMatch(base)?.group(1);
        if (n != null) return 'T${n}X';
      }
      return base;
    }
    if (svc != null) return svc.id;
    return 'OTHER:${l.description}';
  }
}

/// A service NATRAX bill, with the rate it is checked against.
class ServiceCategory {
  final String id;
  final String name;
  final double rate;
  final String unit;
  final List<String> words;
  const ServiceCategory(this.id, this.name, this.rate, this.unit, this.words);

  /// S10, per kWh.
  static const double evRate = 25.0;

  /// From the S01–S16 card in Manual Entry. "Accommodation" is the bay: the
  /// workshop, the porta-cabin, the office — ₹5,000 a day, confirmed for
  /// "Right office B-1" and "Porta Cabin-02" on 12 Nov 2026.
  static const all = [
    ServiceCategory('PAD', 'Weighing pads', 600, 'Nos', ['pad']),
    ServiceCategory('BRIDGE', 'Weigh bridge', 1100, 'Nos', ['bridge']),
    ServiceCategory('CONF', 'Conference hall', 11000, 'days', ['conference']),
    ServiceCategory('FOOD', 'Refreshment / food coupons', 125, 'Nos',
        ['food', 'coupon', 'coupan', 'refresh', 'lunch']),
    ServiceCategory('WATER', 'Bisleri water 20L', 67.80, 'Nos',
        ['bisleri', 'risleri', 'water']),
    ServiceCategory('ACCOM', 'Workshop / office / cabin', 5000, 'days',
        ['office', 'porta', 'cabin', 'workshop', 'work shop']),
    ServiceCategory('SAND', 'Sand bags', 150, 'Nos', ['sand']),
    ServiceCategory('LABOUR', 'Unskilled labour', 1100, 'days',
        ['labour', 'labor']),
    ServiceCategory('JCB', 'JCB hire', 1200, 'h', ['jcb']),
    ServiceCategory('ELEC', 'Electricity', 15, 'units', ['electricity']),
    ServiceCategory('VBOXBAT', 'VBOX battery hire', 1000, 'days', ['battery']),
    ServiceCategory('VBOX', 'VBOX 3i hire', 27000, 'days', ['vbox']),
  ];

  static ServiceCategory? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  static bool isEv(String name) {
    final n = name.toLowerCase();
    return n.contains('charger') || n.contains('charging');
  }

  static ServiceCategory? of(String name) {
    final n = name.toLowerCase();
    if (isEv(n)) return null;
    for (final c in all) {
      if (c.words.any(n.contains)) return c;
    }
    return null;
  }
}

class _Side {
  final DateTime date;
  final String project;
  final String code;
  double hours = 0;
  int minutes = 0;
  double cost = 0;
  final List<OurRun> ourRuns = [];
  final List<NatraxRun> theirRuns = [];
  _Side(this.date, this.project, this.code);
}

class _Line {
  final String code;
  double natrax = 0, ours = 0, agreed = 0;
  double natraxMoney = 0, oursMoney = 0, agreedMoney = 0;
  _Line(this.code);
}

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'track_cost_rules.dart';

/// One run through the gate: in and out, as minutes after midnight.
class NatraxRun {
  final int inMin;
  final int outMin;
  const NatraxRun(this.inMin, this.outMin);

  /// Wraps past midnight, the same way Manual Entry does.
  int get minutes => TrackCostRules.minutesBetween(inMin, outMin);

  static String clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String get label => '${clock(inMin)}–${clock(outMin)}';

  Map<String, dynamic> toJson() => {'in': inMin, 'out': outMin};
  factory NatraxRun.fromJson(Map<String, dynamic> j) =>
      NatraxRun((j['in'] as num).toInt(), (j['out'] as num).toInt());
}

/// One track, on one day, for one vehicle: the unit NATRAX charge.
///
/// On the sheet it is a block of rows. The first row carries the date,
/// booking, vehicle, track and the hours charged; the rows under it carry
/// only further in/out times and inherit everything else.
class NatraxBlock {
  final DateTime date;
  final String booking;
  final String rfid;
  final String vehicle;
  final double? weightKg;

  /// As printed, e.g. "(GVW<3.5T)(T3wet-002)".
  final String rawTrack;

  /// Normalised to the codes TrackLog uses — T3W, T3D, T1, T16 — with an X
  /// suffix for exclusive bookings (T1X). Empty when the label is not one
  /// this reader recognises; the reconciliation then asks about it.
  final String code;
  final bool exclusive;

  /// Above 3.5 tonnes GVW, which NATRAX price on a different card.
  final bool heavy;
  final List<NatraxRun> runs;

  /// NATRAX's own decision for the block. Null when the sheet left it blank.
  final double? charged;

  const NatraxBlock({
    required this.date,
    required this.booking,
    required this.rfid,
    required this.vehicle,
    required this.rawTrack,
    required this.code,
    required this.exclusive,
    required this.heavy,
    required this.runs,
    this.weightKg,
    this.charged,
  });

  int get minutes => runs.fold(0, (s, r) => s + r.minutes);
  String get vehicleKey => NatraxUtilisationSheet.vehicleKey(vehicle);

  Map<String, dynamic> toJson() => {
        'date': _ymd(date),
        'booking': booking,
        'rfid': rfid,
        'vehicle': vehicle,
        'weight': weightKg,
        'raw': rawTrack,
        'code': code,
        'exclusive': exclusive,
        'heavy': heavy,
        'runs': runs.map((r) => r.toJson()).toList(),
        'charged': charged,
      };

  factory NatraxBlock.fromJson(Map<String, dynamic> j) => NatraxBlock(
        date: DateTime.parse(j['date'] as String),
        booking: j['booking'] as String? ?? '',
        rfid: j['rfid'] as String? ?? '',
        vehicle: j['vehicle'] as String? ?? '',
        weightKg: (j['weight'] as num?)?.toDouble(),
        rawTrack: j['raw'] as String? ?? '',
        code: j['code'] as String? ?? '',
        exclusive: j['exclusive'] as bool? ?? false,
        heavy: j['heavy'] as bool? ?? false,
        runs: ((j['runs'] as List?) ?? const [])
            .map((r) => NatraxRun.fromJson((r as Map).cast<String, dynamic>()))
            .toList(),
        charged: (j['charged'] as num?)?.toDouble(),
      );
}

/// A line from "The other service you utilized at NATRAX".
class NatraxServiceLine {
  final DateTime? date;

  /// For a stretch — "Right office B-1", 14 to 31 October — the two ends.
  final DateTime? from;
  final DateTime? to;
  final String booking;
  final String vehicle;
  final String name;
  final double quantity;

  const NatraxServiceLine({
    required this.name,
    required this.quantity,
    this.date,
    this.from,
    this.to,
    this.booking = '',
    this.vehicle = '',
  });

  Map<String, dynamic> toJson() => {
        'date': date == null ? null : _ymd(date!),
        'from': from == null ? null : _ymd(from!),
        'to': to == null ? null : _ymd(to!),
        'booking': booking,
        'vehicle': vehicle,
        'name': name,
        'qty': quantity,
      };

  factory NatraxServiceLine.fromJson(Map<String, dynamic> j) =>
      NatraxServiceLine(
        date: _parseYmd(j['date']),
        from: _parseYmd(j['from']),
        to: _parseYmd(j['to']),
        booking: j['booking'] as String? ?? '',
        vehicle: j['vehicle'] as String? ?? '',
        name: j['name'] as String? ?? '',
        quantity: (j['qty'] as num?)?.toDouble() ?? 0,
      );
}

/// A charge from "EV Charging Details".
class NatraxEvLine {
  final DateTime? date;
  final String vehicle;
  final int? inMin;
  final int? outMin;
  final double units;

  const NatraxEvLine({
    required this.vehicle,
    required this.units,
    this.date,
    this.inMin,
    this.outMin,
  });

  Map<String, dynamic> toJson() => {
        'date': date == null ? null : _ymd(date!),
        'vehicle': vehicle,
        'in': inMin,
        'out': outMin,
        'units': units,
      };

  factory NatraxEvLine.fromJson(Map<String, dynamic> j) => NatraxEvLine(
        date: _parseYmd(j['date']),
        vehicle: j['vehicle'] as String? ?? '',
        inMin: (j['in'] as num?)?.toInt(),
        outMin: (j['out'] as num?)?.toInt(),
        units: (j['units'] as num?)?.toDouble() ?? 0,
      );
}

/// NATRAX's monthly Service Utilization Sheet, read.
///
/// What is kept is what NATRAX typed: dates, bookings, vehicles, tracks, the
/// gate in/out times, the hours they charged, and the quantities of services.
/// What is NOT kept is anything the sheet works out — "Time on Track", "Total
/// Use Time" and the "Track Code & Total Hours" summary are all formulas, and
/// the spreadsheet reader used on the web returns a formula's text, not its
/// value. They are worked out again here from the in/out times instead, which
/// is the stronger check anyway: it is what the charged hours have to agree
/// with.
class NatraxUtilisationSheet {
  /// First day of the month the sheet covers.
  final DateTime month;

  /// NATRAX's reference, e.g. "NAT/USAGE/26-27/0D-01705".
  final String reference;
  final DateTime? issuedOn;

  /// "Company Name (GST)" as printed — a sheet addressed to somebody else is
  /// worth knowing about before anything is matched against it.
  final String company;
  final List<NatraxBlock> blocks;
  final List<NatraxServiceLine> services;
  final List<NatraxEvLine> ev;

  /// Things noticed while reading that a person should see: a date in the
  /// wrong year, a block with no hours charged, a track label not recognised.
  final List<String> warnings;

  const NatraxUtilisationSheet({
    required this.month,
    required this.reference,
    required this.company,
    required this.blocks,
    required this.services,
    required this.ev,
    required this.warnings,
    this.issuedOn,
  });

  double get chargedHours => blocks.fold(0.0, (s, b) => s + (b.charged ?? 0));
  int get runCount => blocks.fold(0, (s, b) => s + b.runs.length);
  String get monthKey => DateFormat('yyyy-MM').format(month);

  // ── Normalising ──────────────────────────────────────────────────────────

  /// A vehicle as a key: upper case, letters and digits only, and the letter
  /// O read as the digit 0. NATRAX write the same car as "XUV-7X0" on the
  /// track rows and "XUV 7X0" on the services, and the same EV as "EPO-9349"
  /// and "EP09349"; both pairs must land on one key or the reconciliation
  /// asks the same question twice.
  static String vehicleKey(String raw) => raw
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .replaceAll('O', '0');

  /// The digits that identify a booking: "BUK/26-27/01283" and the services
  /// table's bare "1283" are the same booking.
  static String bookingKey(String raw) {
    final digits = RegExp(r'(\d+)\s*$').firstMatch(raw.trim())?.group(1);
    if (digits == null) return '';
    return int.tryParse(digits)?.toString() ?? '';
  }

  /// "(GVW<3.5T)(T3wet-002)" → T3W. "(After 2 Hrs)(T1-003)" on an
  /// "Exclusive" booking → T1X.
  static ({String code, bool exclusive, bool heavy}) trackCode(String raw,
      {String booking = ''}) {
    final s = raw.toUpperCase();
    final heavy = RegExp(r'>\s*3\.5').hasMatch(s);
    final exclusive = booking.toUpperCase().contains('EXCLUSIVE') ||
        s.contains('EXCLUSIVE') ||
        s.contains('AFTER 2');
    final matches = RegExp(r'T\s*(\d{1,2})\s*(WET|DRY)?').allMatches(s).toList();
    if (matches.isEmpty) return (code: '', exclusive: exclusive, heavy: heavy);
    final m = matches.last;
    final n = m.group(1)!;
    if (exclusive) return (code: 'T${n}X', exclusive: true, heavy: heavy);
    final surface = switch (m.group(2)) { 'WET' => 'W', 'DRY' => 'D', _ => '' };
    // T3 with no surface stated is ambiguous between two rates; say so.
    if (n == '3' && surface.isEmpty) {
      return (code: '', exclusive: false, heavy: heavy);
    }
    return (code: 'T$n$surface', exclusive: false, heavy: heavy);
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  /// From the .xlsx NATRAX send. Throws on a file that is not a workbook.
  static NatraxUtilisationSheet fromXlsx(Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) {
      throw const FormatException('The workbook has no sheets.');
    }
    // The utilisation is on the first sheet; NATRAX name it after the
    // customer ("Good year"), so the name cannot be relied on.
    final table = book.tables.values.first;
    final grid = <List<Object?>>[
      for (final row in table.rows) [for (final c in row) _cell(c?.value)],
    ];
    return fromGrid(grid);
  }

  /// Excel's cell types down to what the reader needs: text, a number, a
  /// date, or a clock time written "HH:mm". Formulas come back as null —
  /// their values are not available here, and are recomputed instead.
  static Object? _cell(CellValue? v) {
    if (v == null) return null;
    return switch (v) {
      TextCellValue() => v.toString().trim(),
      IntCellValue() => v.value,
      DoubleCellValue() => v.value,
      DateCellValue() => DateTime(v.year, v.month, v.day),
      DateTimeCellValue() => (v.year <= 1900)
          ? NatraxRun.clock(v.hour * 60 + v.minute)
          : DateTime(v.year, v.month, v.day, v.hour, v.minute),
      TimeCellValue() => NatraxRun.clock(v.hour * 60 + v.minute),
      BoolCellValue() => v.value.toString(),
      FormulaCellValue() => null,
    };
  }

  static String _text(Object? v) {
    if (v == null) return '';
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().trim();
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim());
    return null;
  }

  /// Minutes after midnight from "10:31", a time cell, or a day fraction.
  static int? _clock(Object? v) {
    if (v == null) return null;
    if (v is double && v >= 0 && v < 1) return (v * 1440).round();
    if (v is DateTime) return v.hour * 60 + v.minute;
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(_text(v));
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  static DateTime? _date(Object? v) {
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is num && v > 20000 && v < 80000) {
      // An Excel serial that came through as a plain number.
      return DateTime(1899, 12, 30).add(Duration(days: v.toInt()));
    }
    final s = _text(v);
    if (s.isEmpty) return null;
    for (final f in const ['d-MMM-yy', 'd-MMM-yyyy', 'dd-MM-yyyy', 'd/M/yyyy']) {
      try {
        return DateFormat(f).parseStrict(s);
      } catch (_) {}
    }
    return null;
  }

  static bool _starts(Object? cell, String prefix) =>
      _text(cell).toLowerCase().startsWith(prefix);

  /// Where a header sits in its row, by how its text begins. Headers are
  /// found rather than assumed, so a column NATRAX add or move one month
  /// does not shift every figure along by one.
  static int _col(List<Object?> header, bool Function(String t) test) {
    for (var i = 0; i < header.length; i++) {
      if (test(_text(header[i]).toLowerCase())) return i;
    }
    return -1;
  }

  static Object? _at(List<Object?> row, int i) =>
      (i >= 0 && i < row.length) ? row[i] : null;

  static NatraxUtilisationSheet fromGrid(List<List<Object?>> grid) {
    final warnings = <String>[];

    // Header fields.
    var reference = '';
    DateTime? issuedOn;
    var company = '';
    DateTime? headerMonth;
    for (var r = 0; r < grid.length && r < 14; r++) {
      final row = grid[r];
      for (var c = 0; c < row.length; c++) {
        final t = _text(row[c]);
        if (reference.isEmpty && t.toUpperCase().contains('NAT/USAGE')) {
          reference = t;
        }
        if (t.toLowerCase().startsWith('service utilization sheet')) {
          for (var k = c + 1; k < row.length; k++) {
            final d = _date(row[k]);
            if (d != null) {
              headerMonth = DateTime(d.year, d.month);
              break;
            }
          }
        }
        if (t.toLowerCase().startsWith('date /') && issuedOn == null) {
          for (var k = c + 1; k < row.length; k++) {
            final d = _date(row[k]);
            if (d != null) {
              issuedOn = d;
              break;
            }
          }
        }
        if (t.toLowerCase().startsWith('company name (gst)')) {
          for (var k = c + 1; k < row.length; k++) {
            if (_text(row[k]).isNotEmpty) {
              company = _text(row[k]);
              break;
            }
          }
        }
      }
    }

    // ── Track usage ──────────────────────────────────────────────────────
    final blocks = <_BlockBuilder>[];
    var r = 0;
    var trackHeader = -1;
    for (; r < grid.length; r++) {
      final row = grid[r];
      final hasIn = row.any((c) => _starts(c, 'in time'));
      final hasCharged =
          row.any((c) => _text(c).toLowerCase().contains('charged'));
      if (hasIn && hasCharged) {
        trackHeader = r;
        break;
      }
    }
    if (trackHeader >= 0) {
      final h = grid[trackHeader];
      final cDate = _col(h, (t) => t.startsWith('date'));
      final cBooking = _col(h, (t) => t.startsWith('booking'));
      final cRfid = _col(h, (t) => t.startsWith('rfid'));
      final cVehicle = _col(h, (t) => t.startsWith('vehicle no'));
      final cWeight = _col(h, (t) => t.startsWith('vehicle weight'));
      final cTrack = _col(h, (t) => t.startsWith('track') && !t.contains('time'));
      final cIn = _col(h, (t) => t.startsWith('in time'));
      final cOut = _col(h, (t) => t.startsWith('out time'));
      final cCharged = _col(h, (t) => t.contains('charged'));

      DateTime? date;
      var booking = '', rfid = '', vehicle = '', track = '';
      double? weight;

      for (r = trackHeader + 1; r < grid.length; r++) {
        final row = grid[r];
        final first = _text(_at(row, 0)).toLowerCase();
        if (first.startsWith('track code') || first.startsWith('the other service')) {
          break;
        }
        final inMin = _clock(_at(row, cIn));
        final outMin = _clock(_at(row, cOut));
        if (inMin == null || outMin == null) continue;

        final d = _date(_at(row, cDate));
        final b = _text(_at(row, cBooking));
        final f = _text(_at(row, cRfid));
        final v = _text(_at(row, cVehicle));
        final w = _num(_at(row, cWeight));
        final t = _text(_at(row, cTrack));
        final charged = _num(_at(row, cCharged));

        final newBlock = t.isNotEmpty ||
            charged != null ||
            blocks.isEmpty ||
            (d != null && d != date) ||
            (b.isNotEmpty && b != booking);
        if (d != null) date = d;
        if (b.isNotEmpty) booking = b;
        if (f.isNotEmpty) rfid = f;
        if (v.isNotEmpty) vehicle = v;
        if (w != null) weight = w;
        if (t.isNotEmpty) track = t;

        if (date == null) {
          warnings.add('Row ${r + 1}: a run with no date was skipped.');
          continue;
        }
        if (newBlock) {
          blocks.add(_BlockBuilder(
            date: date,
            booking: booking,
            rfid: rfid,
            vehicle: vehicle,
            weight: weight,
            rawTrack: track,
            charged: charged,
          ));
        }
        blocks.last.runs.add(NatraxRun(inMin, outMin));
      }
    }

    // ── Other services ───────────────────────────────────────────────────
    final services = <NatraxServiceLine>[];
    var svcHeader = -1;
    for (var k = (trackHeader < 0 ? 0 : trackHeader); k < grid.length; k++) {
      final row = grid[k];
      if (row.any((c) => _text(c).toLowerCase() == 'qty') &&
          row.any((c) => _starts(c, 'to provide service') || _starts(c, 'remarks'))) {
        svcHeader = k;
        break;
      }
    }
    var evHeader = -1;
    if (svcHeader >= 0) {
      final h = grid[svcHeader];
      final cDate = _col(h, (t) => t.startsWith('date'));
      final cBooking = _col(h, (t) => t.startsWith('booking'));
      final cVehicle = _col(h, (t) => t.startsWith('vehicle'));
      final cIn = _col(h, (t) => t == 'in');
      final cOut = _col(h, (t) => t == 'out');
      final cQty = _col(h, (t) => t == 'qty');
      final cDays = _col(h, (t) => t == 'days');
      final cTotal = _col(h, (t) => t == 'total');
      final cName = _col(h, (t) => t.startsWith('to provide service'));
      final cRemarks = _col(h, (t) => t.startsWith('remarks'));

      for (var k = svcHeader + 1; k < grid.length; k++) {
        final row = grid[k];
        if (row.any((c) => _starts(c, 'ev charging'))) {
          evHeader = k;
          break;
        }
        var name = _text(_at(row, cName));
        if (name.isEmpty || name == '-') name = _text(_at(row, cRemarks));
        if (name.isEmpty || name == '-') continue;

        double? positive(Object? v) {
          final n = _num(v);
          return (n != null && n > 0) ? n : null;
        }

        // A quantity, a day count, or failing both the Total column. Office
        // and porta-cabin lines leave Qty blank and give days instead.
        final qty = positive(_at(row, cQty)) ??
            positive(_at(row, cDays)) ??
            positive(_at(row, cTotal)) ??
            0;
        final inCell = _at(row, cIn), outCell = _at(row, cOut);
        final booking = _text(_at(row, cBooking));
        final vehicle = _text(_at(row, cVehicle));
        services.add(NatraxServiceLine(
          name: name,
          quantity: qty,
          date: _date(_at(row, cDate)),
          from: inCell is DateTime ? _date(inCell) : null,
          to: outCell is DateTime ? _date(outCell) : null,
          booking: booking == '-' ? '' : booking,
          vehicle: vehicle == '-' ? '' : vehicle,
        ));
      }
    }

    // ── EV charging ──────────────────────────────────────────────────────
    final ev = <NatraxEvLine>[];
    if (evHeader < 0) {
      for (var k = 0; k < grid.length; k++) {
        if (grid[k].any((c) => _starts(c, 'ev charging'))) {
          evHeader = k;
          break;
        }
      }
    }
    if (evHeader >= 0) {
      var h = evHeader;
      // The title row and the column row are separate; find the columns.
      for (var k = evHeader; k < grid.length && k < evHeader + 3; k++) {
        if (grid[k].any((c) => _starts(c, 'vehicle number'))) {
          h = k;
          break;
        }
      }
      final cols = grid[h];
      final cDate = _col(cols, (t) => t.startsWith('date'));
      final cVehicle = _col(cols, (t) => t.startsWith('vehicle'));
      final cIn = _col(cols, (t) => t.startsWith('in time'));
      final cOut = _col(cols, (t) => t.startsWith('out time'));
      // "unit" — not "Total unit", which on the first row is the column sum.
      final cUnit = _col(cols, (t) => t == 'unit' || t == 'units');

      DateTime? date;
      var vehicle = '';
      for (var k = h + 1; k < grid.length; k++) {
        final row = grid[k];
        final units = _num(_at(row, cUnit));
        if (units == null) continue;
        final d = _date(_at(row, cDate));
        final v = _text(_at(row, cVehicle));
        if (d != null) date = d;
        if (v.isNotEmpty) vehicle = v;
        ev.add(NatraxEvLine(
          date: date,
          vehicle: vehicle,
          inMin: _clock(_at(row, cIn)),
          outMin: _clock(_at(row, cOut)),
          units: units,
        ));
      }
    }

    // ── The month, and dates that disagree with it ───────────────────────
    final votes = <String, int>{};
    for (final b in blocks) {
      final k = '${b.date.year}-${b.date.month}';
      votes[k] = (votes[k] ?? 0) + 1;
    }
    DateTime month;
    if (votes.isNotEmpty) {
      final top = votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      final p = top.split('-');
      month = DateTime(int.parse(p[0]), int.parse(p[1]));
    } else if (headerMonth != null) {
      month = headerMonth;
    } else {
      throw const FormatException(
          'No track runs were found, so the month the sheet covers is unknown.');
    }

    // A date in the right month but the wrong year is a typing slip — the
    // October sheet has an EV charge on "22-Oct-02". Put it in the sheet's
    // year and say so, rather than drop a real charge into 2002.
    DateTime fix(DateTime d, String what) {
      if (d.month == month.month && d.year != month.year) {
        final fixed = DateTime(month.year, d.month, d.day);
        warnings.add('$what dated ${DateFormat('d MMM yyyy').format(d)} read '
            'as ${DateFormat('d MMM yyyy').format(fixed)}.');
        return fixed;
      }
      if (d.year != month.year || d.month != month.month) {
        warnings.add('$what is dated ${DateFormat('d MMM yyyy').format(d)}, '
            'outside ${DateFormat('MMMM yyyy').format(month)}.');
      }
      return d;
    }

    final finalBlocks = <NatraxBlock>[];
    for (final b in blocks) {
      final t = trackCode(b.rawTrack, booking: b.booking);
      final date = fix(b.date, 'A run on ${b.vehicle}');
      if (t.code.isEmpty) {
        warnings.add('${DateFormat('d MMM').format(date)}: track '
            '"${b.rawTrack}" was not recognised.');
      }
      if (b.charged == null) {
        warnings.add('${DateFormat('d MMM').format(date)} ${t.code.isEmpty ? b.rawTrack : t.code}: '
            'no hours charged on the sheet.');
      }
      if (t.heavy) {
        warnings.add('${DateFormat('d MMM').format(date)} ${t.code}: above '
            '3.5 t, which NATRAX price on a different card.');
      }
      finalBlocks.add(NatraxBlock(
        date: date,
        booking: b.booking,
        rfid: b.rfid,
        vehicle: b.vehicle,
        weightKg: b.weight,
        rawTrack: b.rawTrack,
        code: t.code,
        exclusive: t.exclusive,
        heavy: t.heavy,
        runs: b.runs,
        charged: b.charged,
      ));
    }
    final finalEv = [
      for (final e in ev)
        NatraxEvLine(
          date: e.date == null ? null : fix(e.date!, 'EV charging on ${e.vehicle}'),
          vehicle: e.vehicle,
          inMin: e.inMin,
          outMin: e.outMin,
          units: e.units,
        ),
    ];

    return NatraxUtilisationSheet(
      month: month,
      reference: reference,
      issuedOn: issuedOn,
      company: company,
      blocks: finalBlocks,
      services: services,
      ev: finalEv,
      warnings: warnings,
    );
  }

  // ── Storage ──────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'month': monthKey,
        'reference': reference,
        'issued': issuedOn == null ? null : _ymd(issuedOn!),
        'company': company,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'services': services.map((s) => s.toJson()).toList(),
        'ev': ev.map((e) => e.toJson()).toList(),
        'warnings': warnings,
      };

  factory NatraxUtilisationSheet.fromJson(Map<String, dynamic> j) {
    final m = (j['month'] as String).split('-');
    List<Map<String, dynamic>> list(String k) => ((j[k] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    return NatraxUtilisationSheet(
      month: DateTime(int.parse(m[0]), int.parse(m[1])),
      reference: j['reference'] as String? ?? '',
      issuedOn: _parseYmd(j['issued']),
      company: j['company'] as String? ?? '',
      blocks: list('blocks').map(NatraxBlock.fromJson).toList(),
      services: list('services').map(NatraxServiceLine.fromJson).toList(),
      ev: list('ev').map(NatraxEvLine.fromJson).toList(),
      warnings: ((j['warnings'] as List?) ?? const []).cast<String>(),
    );
  }
}

class _BlockBuilder {
  final DateTime date;
  final String booking;
  final String rfid;
  final String vehicle;
  final double? weight;
  final String rawTrack;
  final double? charged;
  final List<NatraxRun> runs = [];
  _BlockBuilder({
    required this.date,
    required this.booking,
    required this.rfid,
    required this.vehicle,
    required this.weight,
    required this.rawTrack,
    required this.charged,
  });
}

String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime? _parseYmd(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

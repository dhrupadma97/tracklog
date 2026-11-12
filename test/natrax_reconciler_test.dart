import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/natrax_invoice_parser.dart';
import 'package:tracklog/services/natrax_reconciler.dart';
import 'package:tracklog/services/natrax_utilisation_sheet.dart';

/// A NATRAX utilisation sheet as the spreadsheet reader hands it over: the
/// header rows, the track table with blocks of continuation rows, the
/// services table and the EV table — the layout of the real Sep-26 and
/// Oct-26 sheets, with only the rows each test needs.
List<List<Object?>> _grid({
  required List<List<Object?>> track,
  List<List<Object?>> services = const [],
  List<List<Object?>> ev = const [],
}) =>
    [
      ['National Automotive Test Tracks (NATRAX)', null, null, null, null, null,
          null, null, null, null, 'NAT/USAGE/26-27/0D-01705'],
      [null, null, 'Service Utilization Sheet / सेवा उपयोग विवरण पत्रक', null,
          null, null, null, null, DateTime(2026, 10, 26), null, 'Date /दिनांक',
          DateTime(2026, 11, 12)],
      ['Company Name (GST) / कंपनी का नाम', null, null,
          'Goodyear South Asia Tyres Private Limited'],
      ['S/n', 'Date / दिनांक', 'Booking No./बुकिंग संख्या', 'RFID No.',
          'Vehicle No./ वाहन संख्या', 'Vehicle Weight / वाहन का वजन',
          'Tracks/ ट्रैक', 'In Time/ प्रवेश समय', 'Out Time/ निकास समय',
          'Time on Track/ ट्रैक पर समय', 'Total Use Time/ कुल उपयोग समय',
          'Charged HRS/ चार्ज किए गए घंटे'],
      ...track,
      ['Track Code & Total Hours'],
      ['The other service you utilized at NATRAX'],
      ['Date', 'Booking No.', 'Vehicle No.', 'In', 'Out', 'Weight', 'Qty',
          'Days', 'Total', 'Block Calculation', 'To Provide Service', 'Remarks'],
      ...services,
      ['EV Charging Datails '],
      ['Date', 'Vehicle Number', 'In time', 'Out time', 'Total time', 'unit ',
          'Total unit'],
      ...ev,
    ];

/// One block's first row: date, booking, RFID, vehicle, weight, track, in,
/// out, the two formula columns (null — the reader never sees their value),
/// and charged hours.
List<Object?> _row(int sn, DateTime? date, String booking, String vehicle,
        String track, String inT, String outT, int? charged) =>
    [sn, date, booking, booking.isEmpty ? null : 38063, vehicle, 2000, track,
        inT, outT, null, null, charged];

/// A continuation row: only further in/out times.
List<Object?> _more(int sn, String inT, String outT) =>
    [sn, null, null, null, null, null, null, inT, outT, null];

OurRun _ours(int day, String start, int minutes, String code,
    {String project = 'Mahindra ICE PoC', double cost = 0}) {
  final p = start.split(':');
  return OurRun(
    id: '$day-$start-$code',
    date: DateTime(2026, 10, day),
    startMin: int.parse(p[0]) * 60 + int.parse(p[1]),
    minutes: minutes,
    code: code,
    project: project,
    cost: cost,
  );
}

const _ice = {
  'XUV7X0': VehicleDecision(
      vehicleKey: 'XUV7X0', label: 'XUV-7X0', project: 'Mahindra ICE PoC'),
};

ReconItem _item(ReconOutcome o, String key) =>
    o.items.firstWhere((i) => i.key == key);

void main() {
  group('reading the sheet', () {
    final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
      _row(1, DateTime(2026, 10, 7), 'BUK/26-27/01525', 'XUV-7X0',
          '(GVW<3.5T)(T16-002)', '12:13', '14:51', 4),
      _more(2, '15:38', '16:00'),
      _more(3, '16:49', '17:34'),
      _row(4, null, '', '', '(GVW<3.5T)(T3Dry-002)', '08:16', '09:32', 2),
      _row(5, DateTime(2026, 10, 15), 'Exclusive', 'XUV-7X0',
          '(After 2 Hrs)(T1-003)', '08:25', '08:51', 2),
    ], ev: [
      [DateTime(2002, 10, 22), 'EP09349', '10:12', '11:19', null, 46, null],
    ]));

    test('blocks carry their date and vehicle down the continuation rows', () {
      expect(sheet.blocks, hasLength(3));
      final t16 = sheet.blocks[0];
      expect(t16.code, 'T16');
      expect(t16.runs, hasLength(3));
      // 158 + 22 + 45, worked out from the in/out times — "Total Use Time"
      // is a formula whose value the reader never sees.
      expect(t16.minutes, 225);
      expect(t16.charged, 4);
      // A new track under the same date starts a new block, same day.
      expect(sheet.blocks[1].code, 'T3D');
      expect(sheet.blocks[1].date, DateTime(2026, 10, 7));
    });

    test('an exclusive booking reads as an X code', () {
      expect(sheet.blocks[2].code, 'T1X');
      expect(sheet.blocks[2].exclusive, isTrue);
    });

    test('the month, the reference and a mistyped year', () {
      expect(sheet.monthKey, '2026-10');
      expect(sheet.reference, 'NAT/USAGE/26-27/0D-01705');
      expect(sheet.issuedOn, DateTime(2026, 11, 12));
      // "22-Oct-02" on the real October sheet: kept, in the right year.
      expect(sheet.ev.single.date, DateTime(2026, 10, 22));
      expect(sheet.warnings.join(), contains('22 Oct 2002'));
    });

    test('vehicle keys survive NATRAX writing a car two ways', () {
      expect(NatraxUtilisationSheet.vehicleKey('XUV-7X0'),
          NatraxUtilisationSheet.vehicleKey('XUV 7X0'));
      expect(NatraxUtilisationSheet.vehicleKey('EPO-9349'),
          NatraxUtilisationSheet.vehicleKey('EP09349'));
      expect(NatraxUtilisationSheet.bookingKey('BUK/26-27/01283'), '1283');
      expect(NatraxUtilisationSheet.bookingKey('1283'), '1283');
    });

    test('it survives a round trip through storage', () {
      final back = NatraxUtilisationSheet.fromJson(sheet.toJson());
      expect(back.blocks.length, sheet.blocks.length);
      expect(back.blocks.first.minutes, 225);
      expect(back.chargedHours, sheet.chargedHours);
    });
  });

  group('track lines', () {
    NatraxUtilisationSheet one(String track, List<(String, String)> runs,
        int charged,
        {int day = 9}) {
      final rows = <List<Object?>>[
        _row(1, DateTime(2026, 10, day), 'BUK/26-27/01525', 'XUV-7X0', track,
            runs.first.$1, runs.first.$2, charged),
        for (var i = 1; i < runs.length; i++) _more(i + 1, runs[i].$1, runs[i].$2),
      ];
      return NatraxUtilisationSheet.fromGrid(_grid(track: rows));
    }

    test('NATRAX billing less is settled at their figure, in bulk', () {
      // 9 Oct: their gate 166 min, 3 h; ours 325 min, 6 h.
      final o = NatraxReconciler.run(
        sheet: one('(GVW<3.5T)(T16-002)',
            [('11:03', '11:29'), ('13:10', '15:30')], 3),
        ours: OurMonth(runs: [
          _ours(9, '11:00', 125, 'T16', cost: 27000),
          _ours(9, '13:00', 200, 'T16', cost: 27000),
        ]),
        vehicles: _ice,
      );
      final it = _item(o, 'trk|2026-10-09|Mahindra ICE PoC|T16');
      expect(it.stance, ReconStance.inFavour);
      expect(it.bulkOk, isTrue);
      expect(it.suggested, 'accept');
      expect(it.theirs, 3);
      expect(it.ours, 6);
      expect(it.autoComment, contains('Settled at their figure'));
      // Until answered it already stands at NATRAX's figure.
      expect(it.agreed, 3);
    });

    test('NATRAX more with more gate time leans towards our record being short', () {
      final o = NatraxReconciler.run(
        sheet: one('(GVW<3.5T)(T3Dry-002)',
            [('09:45', '11:00'), ('13:11', '15:04')], 3, day: 13),
        ours: OurMonth(runs: [_ours(13, '09:45', 73, 'T3D', cost: 38000)]),
        vehicles: _ice,
      );
      final it = _item(o, 'trk|2026-10-13|Mahindra ICE PoC|T3D');
      expect(it.stance, ReconStance.theirsMore);
      expect(it.bulkOk, isFalse);
      expect(it.suggested, 'accept');
      expect(it.options.map((x) => x.id), ['accept', 'dispute']);
    });

    test('a line only NATRAX have is offered as missing from TrackLog', () {
      final o = NatraxReconciler.run(
        sheet: one('(GVW<3.5T)(T3Dry-002)', [('15:12', '16:02')], 2, day: 5),
        ours: const OurMonth(),
        vehicles: _ice,
      );
      final it = _item(o, 'trk|2026-10-05|Mahindra ICE PoC|T3D');
      expect(it.stance, ReconStance.theirsOnly);
      expect(it.suggested, 'add');
      expect(it.options.first.todo, contains('15:12–16:02'));
    });

    test('a line only we have is settled at nil, in bulk', () {
      final o = NatraxReconciler.run(
        sheet: one('(GVW<3.5T)(T16-002)', [('11:00', '11:30')], 1),
        ours: OurMonth(runs: [
          _ours(9, '11:00', 30, 'T16', cost: 9000),
          _ours(9, '14:00', 90, 'T3W', cost: 42000),
        ]),
        vehicles: _ice,
      );
      final it = _item(o, 'trk|2026-10-09|Mahindra ICE PoC|T3W');
      expect(it.stance, ReconStance.oursOnly);
      expect(it.bulkOk, isTrue);
      expect(it.agreed, 0);
    });

    test('lines that agree ask nothing', () {
      final o = NatraxReconciler.run(
        sheet: one('(GVW<3.5T)(T3wet-002)', [('10:31', '11:18')], 2, day: 1),
        ours: OurMonth(runs: [_ours(1, '10:31', 47, 'T3W', cost: 42000)]),
        vehicles: _ice,
      );
      expect(_item(o, 'trk|2026-10-01|Mahindra ICE PoC|T3W').stance,
          ReconStance.matched);
      expect(o.open, 0);
      expect(o.cleared, isTrue);
    });
  });

  group('NATRAX against their own gate log', () {
    test('53 minutes on a one-hour track charged as 2 hours is an overcharge', () {
      // 18 Sep, T8: four runs, 53 minutes, charged 2 — two days later the
      // same sheet charged 46 minutes as 1.
      final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
        _row(1, DateTime(2026, 10, 18), 'BUK/26-27/01525', 'XUV-7X0',
            '(GVW<3.5T)(T8-002)', '10:36', '10:51', 2),
        _more(2, '11:48', '12:00'),
        _more(3, '12:39', '12:52'),
        _more(4, '14:21', '14:34'),
      ]));
      final o = NatraxReconciler.run(
          sheet: sheet, ours: const OurMonth(), vehicles: _ice);
      final rule = o.items.firstWhere((i) => i.kind == ReconKind.rule);
      expect(rule.stance, ReconStance.overcharge);
      expect(rule.rule, 1);
      expect(rule.theirs, 2);
      expect(rule.suggested, 'dispute');
    });

    test('charging below the gate log is noted and not chased', () {
      // 28 Oct, T1: 121 minutes rounds to 3 hours; NATRAX charged 2.
      final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
        _row(1, DateTime(2026, 10, 28), 'BUK/26-27/01525', 'XUV-7X0',
            '(GVW<3.5T)(T1-002)', '11:29', '13:30', 2),
      ]));
      final o = NatraxReconciler.run(
          sheet: sheet, ours: const OurMonth(), vehicles: _ice);
      final rule = o.items.firstWhere((i) => i.kind == ReconKind.rule);
      expect(rule.stance, ReconStance.undercharge);
      expect(rule.needsAnswer, isFalse);
    });

    test('wet and dry are judged as one track, not two', () {
      // Wet 100 min + dry 50 min on one day: each rounds on its own to
      // 2 + 1, and the pair already covers the two-hour floor. NATRAX
      // charging 2 + 1 is right, and must raise nothing.
      final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
        _row(1, DateTime(2026, 10, 21), 'BUK/26-27/01525', 'XUV-7X0',
            '(GVW<3.5T)(T3wet-002)', '09:00', '10:40', 2),
        _row(2, null, '', '', '(GVW<3.5T)(T3Dry-002)', '11:00', '11:50', 1),
      ]));
      final o = NatraxReconciler.run(
          sheet: sheet, ours: const OurMonth(), vehicles: _ice);
      expect(o.items.where((i) => i.kind == ReconKind.rule), isEmpty);
    });
  });

  group('vehicles', () {
    final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
      _row(1, DateTime(2026, 10, 18), 'BUK/26-27/01283', 'Ertiga',
          '(GVW<3.5T)(T8-002)', '10:36', '10:51', 2),
      _row(2, DateTime(2026, 10, 20), 'BUK/26-27/01525', 'XUV-7X0',
          '(GVW<3.5T)(T16-002)', '09:00', '09:40', 1),
    ], services: [
      [DateTime(2026, 10, 17), 1283, 'MP09 AR 1597', '16:50', '16:56', 1450, 1,
          '-', 1, '-', 'Bridge weight'],
    ]));

    test('an unknown vehicle is asked about, and its runs wait for it', () {
      final o = NatraxReconciler.run(
          sheet: sheet, ours: const OurMonth(), vehicles: _ice);
      final v = _item(o, 'veh|ERTIGA');
      expect(v.isOpen, isTrue);
      expect(o.items.any((i) => i.key.contains('|T8')), isFalse);
      expect(o.cleared, isFalse);
    });

    test('a vehicle marked not ours is disputed whole, services included', () {
      final o = NatraxReconciler.run(
        sheet: sheet,
        ours: const OurMonth(),
        vehicles: {
          ..._ice,
          'ERTIGA': const VehicleDecision(
              vehicleKey: 'ERTIGA', label: 'Ertiga', notOurs: true),
        },
      );
      final n = _item(o, 'nto|ERTIGA');
      // 2 h of T8 at 10,500, plus the weigh-bridge found through booking
      // 1283 — the plate on the services row is not the same text as the
      // vehicle on the track row, but the booking is.
      expect(n.theirsMoney, 2 * 10500 + 1100);
      expect(o.notOursMoney, 22100);
      expect(o.items.any((i) => i.key == 'svc|BRIDGE'), isFalse);
    });

    test('the catalogue suggests the programme for a known car', () {
      expect(NatraxReconciler.suggestProgramme('XUV-7X0'), 'Mahindra ICE PoC');
      expect(NatraxReconciler.suggestProgramme('Tata Harrier'),
          'Tata Harrier EV PoC');
      expect(NatraxReconciler.suggestProgramme('Ertiga'), isNull);
    });
  });

  group('services', () {
    test('a bay register that stops early leans towards our record being short', () {
      final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
        _row(1, DateTime(2026, 10, 1), 'BUK/26-27/01181', 'XUV-7X0',
            '(GVW<3.5T)(T3wet-002)', '10:31', '11:18', 2),
      ], services: [
        ['-', '-', '-', DateTime(2026, 10, 14), DateTime(2026, 10, 31), '-', '-',
            18, 18, '-', 'Right office B-1'],
        ['-', '-', '-', DateTime(2026, 10, 1), DateTime(2026, 10, 13), '-', '-',
            13, 13, '-', 'Porta Cabin-02'],
      ]));
      final o = NatraxReconciler.run(
        sheet: sheet,
        ours: OurMonth(workshopDays: {
          for (var d = 1; d <= 19; d++) DateTime(2026, 10, d),
        }),
        vehicles: _ice,
      );
      final bay = _item(o, 'svc|ACCOM');
      expect(bay.theirs, 31);
      expect(bay.ours, 19);
      expect(bay.suggested, 'accept');
      expect(bay.hints.join(), contains('stops on 19 Oct'));
      expect(bay.theirsMoney, 31 * 5000);
    });
  });

  group('answers', () {
    final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
      _row(1, DateTime(2026, 10, 9), 'BUK/26-27/01525', 'XUV-7X0',
          '(GVW<3.5T)(T16-002)', '11:03', '11:29', 1),
    ]));
    final ours = OurMonth(runs: [_ours(9, '11:00', 90, 'T16', cost: 18000)]);
    const key = 'trk|2026-10-09|Mahindra ICE PoC|T16';

    test('an answer settles the line at its choice', () {
      final first = NatraxReconciler.run(
          sheet: sheet, ours: ours, vehicles: _ice);
      final snap = _item(first, key).snapshot;
      final o = NatraxReconciler.run(sheet: sheet, ours: ours, vehicles: _ice,
          answers: {
            key: ReconAnswer(itemKey: key, choice: 'accept', snapshot: snap),
          });
      expect(_item(o, key).isOpen, isFalse);
      expect(o.cleared, isTrue);
      expect(o.todos.single, contains('Correct 9 Oct T16'));
    });

    test('an answer given on figures that have since moved is asked again', () {
      final o = NatraxReconciler.run(sheet: sheet, ours: ours, vehicles: _ice,
          answers: {
            key: const ReconAnswer(
                itemKey: key, choice: 'accept', snapshot: 't=1|o=5|tm=26|om=300'),
          });
      final it = _item(o, key);
      expect(it.stale, isTrue);
      expect(it.isOpen, isTrue);
    });
  });

  group('the invoice', () {
    final sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
      _row(1, DateTime(2026, 10, 1), 'BUK/26-27/01181', 'XUV-7X0',
          '(GVW<3.5T)(T3wet-002)', '10:31', '11:18', 2),
      _row(2, DateTime(2026, 10, 5), 'BUK/26-27/01181', 'XUV-7X0',
          '(GVW<3.5T)(T1-002)', '12:31', '12:59', 2),
    ]));
    final cleared = NatraxReconciler.run(
      sheet: sheet,
      ours: OurMonth(runs: [
        _ours(1, '10:31', 47, 'T3W', cost: 42000),
        _ours(5, '12:31', 28, 'T1', cost: 50000),
      ]),
      vehicles: _ice,
    );

    test('lines that agree with the cleared sheet ask nothing', () {
      final items = NatraxReconciler.tally(
        outcome: cleared,
        invoice: const ParsedInvoice(lines: [
          ParsedInvoiceLine(
              description: 'Braking Track Testing (GVW < 3.5T) - WET',
              quantity: 2, unit: 'Hrs', amount: 42000),
          ParsedInvoiceLine(
              description: 'High Speed Track Testing ( GVW< 3.5T)',
              quantity: 2, unit: 'Hrs', amount: 50000),
        ]),
      );
      expect(items.every((i) => i.stance == ReconStance.matched), isTrue);
    });

    test('an invoice line above the cleared figure must be answered', () {
      final items = NatraxReconciler.tally(
        outcome: cleared,
        invoice: const ParsedInvoice(lines: [
          ParsedInvoiceLine(
              description: 'Braking Track Testing (GVW < 3.5T) - WET',
              quantity: 3, unit: 'Hrs', amount: 63000),
        ]),
      );
      final wet = items.firstWhere((i) => i.key == 'inv|T3W');
      expect(wet.stance, ReconStance.theirsMore);
      expect(wet.needsAnswer, isTrue);
      expect(wet.bulkOk, isFalse);
      // T1 was cleared but never invoiced: in our favour.
      final t1 = items.firstWhere((i) => i.key == 'inv|T1');
      expect(t1.stance, ReconStance.inFavour);
      expect(t1.bulkOk, isTrue);
    });

    test('an exclusive line on the invoice tallies against the X code', () {
      expect(
          NatraxReconciler.invoiceLineKey(const ParsedInvoiceLine(
              description: 'High Speed Track Testing (Exclusive)',
              amount: 180000)),
          'T1X');
      expect(
          NatraxReconciler.invoiceLineKey(const ParsedInvoiceLine(
              description: 'Other Support Services (Bisleri Water 20L)',
              amount: 474.6)),
          'WATER');
    });
  });
}

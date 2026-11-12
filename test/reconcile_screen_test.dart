import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tracklog/presentation/reconcile_screen/reconcile_screen.dart';
import 'package:tracklog/services/invoice_service.dart';
import 'package:tracklog/services/natrax_invoice_parser.dart';
import 'package:tracklog/services/natrax_reconciler.dart';
import 'package:tracklog/services/natrax_utilisation_sheet.dart';
import 'package:tracklog/services/reconciliation_service.dart';

/// The Reconcile screen, pumped on a fake month at desktop and phone width.
///
/// The judging is tested in natrax_reconciler_test.dart. This is about the
/// screen: that every card lays out without overflowing at either width, and
/// that the one-click "accept all in our favour" really settles those lines.

List<List<Object?>> _grid({
  required List<List<Object?>> track,
  List<List<Object?>> services = const [],
  List<List<Object?>> ev = const [],
}) =>
    [
      ['National Automotive Test Tracks (NATRAX)', null, null, null, null, null,
          null, null, null, null, 'NAT/USAGE/26-27/0D-01705'],
      [null, null, 'Service Utilization Sheet', null, null, null, null, null,
          DateTime(2026, 10, 26), null, 'Date', DateTime(2026, 11, 12)],
      ['Company Name (GST)', null, null, 'Goodyear South Asia Tyres Private Limited'],
      ['S/n', 'Date', 'Booking No.', 'RFID No.', 'Vehicle No.', 'Vehicle Weight',
          'Tracks', 'In Time', 'Out Time', 'Time on Track', 'Total Use Time',
          'Charged HRS'],
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

List<Object?> _row(int sn, DateTime? date, String booking, String vehicle,
        String track, String inT, String outT, int? charged) =>
    [sn, date, booking, booking.isEmpty ? null : 38063, vehicle, 2000, track,
        inT, outT, null, null, charged];

List<Object?> _more(int sn, String inT, String outT) =>
    [sn, null, null, null, null, null, null, inT, outT, null];

OurRun _ours(int day, String start, int minutes, String code, double cost) {
  final p = start.split(':');
  return OurRun(
    id: '$day-$start-$code',
    date: DateTime(2026, 10, day),
    startMin: int.parse(p[0]) * 60 + int.parse(p[1]),
    minutes: minutes,
    code: code,
    project: 'Mahindra ICE PoC',
    cost: cost,
  );
}

final _sheet = NatraxUtilisationSheet.fromGrid(_grid(track: [
  _row(1, DateTime(2026, 10, 7), 'BUK/26-27/01525', 'XUV-7X0',
      '(GVW<3.5T)(T16-002)', '12:13', '14:51', 4),
  _more(2, '15:38', '16:00'),
  _more(3, '16:49', '17:34'),
  _row(4, null, '', '', '(GVW<3.5T)(T3Dry-002)', '08:16', '09:32', 2),
  // NATRAX 3 h against our 6 h — in our favour.
  _row(5, DateTime(2026, 10, 9), 'BUK/26-27/01530', 'XUV-7X0',
      '(GVW<3.5T)(T16-002)', '11:03', '11:29', 3),
  _more(6, '13:10', '15:30'),
  // NATRAX 3 h against our one 73-minute run — needs a decision.
  _row(7, DateTime(2026, 10, 13), 'BUK/26-27/01540', 'XUV-7X0',
      '(GVW<3.5T)(T3Dry-002)', '09:45', '11:00', 3),
  _more(8, '13:11', '15:04'),
  _row(9, DateTime(2026, 10, 15), 'Exclusive', 'XUV-7X0',
      '(After 2 Hrs)(T1-003)', '08:25', '08:51', 2),
  // Somebody else's car, not yet placed.
  _row(10, DateTime(2026, 10, 17), 'BUK/26-27/01283', 'Ertiga',
      '(GVW<3.5T)(T3Wet-001)', '10:00', '12:00', 2),
], services: [
  [DateTime(2026, 10, 17), 1283, 'MP09 AR 1597', '16:50', '16:56', 1450, 1, '-',
      1, '-', 'Bridge weight'],
  ['-', '-', '-', DateTime(2026, 10, 14), DateTime(2026, 10, 31), '-', '-', 18,
      18, '-', 'Right office B-1'],
  ['-', '-', '-', DateTime(2026, 10, 1), DateTime(2026, 10, 13), '-', '-', 13,
      13, '-', 'Porta Cabin-02'],
], ev: [
  [DateTime(2026, 10, 22), 'EP09349', '10:12', '11:19', null, 46, null],
]));

final _ourMonth = OurMonth(
  runs: [
    _ours(7, '12:13', 158, 'T16', 36000),
    _ours(7, '15:38', 22, 'T16', 0),
    _ours(7, '16:49', 45, 'T16', 0),
    _ours(7, '08:16', 76, 'T3D', 38000),
    _ours(9, '11:00', 125, 'T16', 27000),
    _ours(9, '13:00', 200, 'T16', 27000),
    _ours(13, '09:45', 73, 'T3D', 38000),
  ],
  services: const [
    OurService(
        name: 'EV Charging', quantity: 40, cost: 1000, project: 'Tata Harrier EV PoC'),
  ],
  workshopDays: {for (var d = 1; d <= 19; d++) DateTime(2026, 10, d)},
);

class _FakeService extends ReconciliationService {
  _FakeService(this.state) : super.forTesting();

  ReconMonthState state;
  bool failLoad = false;
  final bulkAccepted = <String>[];

  @override
  Future<List<({String month, bool settled, bool hasSheet})>> months() async =>
      [(month: state.month, settled: state.settled, hasSheet: state.sheet != null)];

  @override
  Future<ReconMonthState> load(String month) async {
    if (failLoad) {
      throw Exception('relation "public.recon_months" does not exist');
    }
    return state;
  }

  @override
  Future<Map<String, VehicleDecision>> vehicles() async => const {
        'XUV7X0': VehicleDecision(
            vehicleKey: 'XUV7X0', label: 'XUV-7X0', project: 'Mahindra ICE PoC'),
      };

  @override
  Future<OurMonth> ourMonth(String monthKey) async => _ourMonth;

  @override
  Future<List<NatraxInvoice>> invoicesFor(String month) async => const [];

  @override
  Future<int> acceptInFavour(String month, Iterable<ReconItem> items) async {
    final answers = {...state.answers};
    var n = 0;
    for (final i in items) {
      if (i.isOpen && i.bulkOk && i.suggested != null) {
        answers[i.key] = ReconAnswer(
            itemKey: i.key,
            choice: i.suggested!,
            comment: i.autoComment,
            snapshot: i.snapshot);
        bulkAccepted.add(i.key);
        n++;
      }
    }
    state = ReconMonthState(
      month: state.month,
      sheet: state.sheet,
      invoice: state.invoice,
      invoiceNumber: state.invoiceNumber,
      answers: answers,
      notes: state.notes,
    );
    return n;
  }
}

ReconMonthState _october({ParsedInvoice? invoice, DateTime? settledAt}) =>
    ReconMonthState(
      month: '2026-10',
      sheet: _sheet,
      sheetFile: 'Goodyear Oct-26.xlsx',
      invoice: invoice,
      invoiceNumber: invoice?.invoiceNumber,
      settledAt: settledAt,
      settledSummary: settledAt == null ? null : const {'agreed': 100000, 'disputed': 0},
      notes: [
        ReconNote(
          id: 'n1',
          note: 'Sheet NAT/USAGE/26-27/0D-01705 uploaded — 10 track lines.',
          kind: 'sheet',
          createdAt: DateTime(2026, 11, 12, 10),
          createdBy: 'engineer@example.com',
        ),
      ],
    );

const _invoice = ParsedInvoice(
  invoiceNumber: 'INV/26-27/999',
  periodMonth: '2026-10',
  amountExclGst: 120000,
  gstAmount: 0,
  totalAmount: 120000,
  lines: [
    ParsedInvoiceLine(
        description: 'General Road Track Testing (GVW< 3.5T)',
        quantity: 7, unit: 'Hrs', amount: 63000),
    ParsedInvoiceLine(
        description: 'Braking Track Testing (GVW < 3.5T) - DRY',
        quantity: 5, unit: 'Hrs', amount: 95000),
  ],
);

Future<void> _pump(WidgetTester tester, _FakeService svc, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ReconcileScreen(service: svc, initialMonth: '2026-10'),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls every column of cards to its end, so each card is built and laid
/// out at least once; an overflow anywhere fails the test. Then back to the
/// top — the lists build lazily, so a card scrolled past no longer exists.
Future<void> _scrollAll(WidgetTester tester) async {
  final n = find.byType(ListView).evaluate().length;
  for (final dy in [-600.0, 600.0]) {
    for (var k = 0; k < n; k++) {
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView).at(k), Offset(0, dy),
            warnIfMissed: false);
        await tester.pump();
      }
    }
  }
  await tester.pumpAndSettle();
}

/// Scrolls the main column down until [finder] has been built.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -300),
        warnIfMissed: false);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const desktop = Size(1440, 1000);
  const phone = Size(390, 844);

  testWidgets('a month with a sheet lays out on desktop', (tester) async {
    await _pump(tester, _FakeService(_october()), desktop);
    expect(find.text('NATRAX RECONCILIATION'), findsOneWidget);
    expect(find.text('STEP 2 · WHOSE VEHICLES'), findsOneWidget);
    expect(find.text('Ertiga'), findsWidgets);
    expect(find.text('STEP 3 · WHAT DOES NOT AGREE'), findsOneWidget);
    expect(find.text('THE MONTH IN MONEY'), findsOneWidget);
    await _scrollAll(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('and on a phone', (tester) async {
    await _pump(tester, _FakeService(_october()), phone);
    await _scrollAll(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every filter view lays out on a phone', (tester) async {
    await _pump(tester, _FakeService(_october()), phone);
    for (final label in ['In your favour', 'Settled', 'Agrees / for info', 'All']) {
      // The chip reads "Settled  3"; the two spaces and the count keep it
      // apart from the stage strip's "5. Settled".
      final chip = find.textContaining(RegExp('${RegExp.escape(label)}  \\d'));
      await _scrollTo(tester, chip);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await _scrollAll(tester);
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  testWidgets('"Accept all" settles only the in-our-favour lines', (tester) async {
    final svc = _FakeService(_october());
    await _pump(tester, svc, desktop);
    final button = find.textContaining('Accept all');
    await _scrollTo(tester, button);
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(svc.bulkAccepted, contains('trk|2026-10-09|Mahindra ICE PoC|T16'));
    // NATRAX billing more is never swept up by the bulk accept.
    expect(svc.bulkAccepted, isNot(contains('trk|2026-10-13|Mahindra ICE PoC|T3D')));
    expect(find.textContaining('Accept all'), findsNothing);
  });

  testWidgets('an invoice tallied against the month lays out', (tester) async {
    await _pump(tester, _FakeService(_october(invoice: _invoice)), phone);
    await _scrollAll(tester);
    expect(tester.takeException(), isNull);
    await _scrollTo(tester, find.text('STEP 4 · THE FINAL INVOICE'));
    expect(find.text('STEP 4 · THE FINAL INVOICE'), findsOneWidget);
    expect(find.textContaining('INV/26-27/999'), findsWidgets);
  });

  testWidgets('a settled month shows as settled and locked', (tester) async {
    await _pump(tester,
        _FakeService(_october(invoice: _invoice, settledAt: DateTime(2026, 11, 20))),
        desktop);
    await _scrollAll(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Accept all'), findsNothing);
    await _scrollTo(tester, find.text('STEP 5 · SETTLED'));
    expect(find.text('STEP 5 · SETTLED'), findsOneWidget);
    expect(find.textContaining('Reopen'), findsOneWidget);
  });

  testWidgets('a month with no sheet asks for one', (tester) async {
    final svc = _FakeService(const ReconMonthState(month: '2026-10'));
    await _pump(tester, svc, phone);
    expect(find.text('Choose the .xlsx file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing tables say which SQL to paste', (tester) async {
    final svc = _FakeService(_october())..failLoad = true;
    await _pump(tester, svc, desktop);
    expect(find.textContaining('20261112120000_natrax_reconciliation.sql'),
        findsOneWidget);
  });
}

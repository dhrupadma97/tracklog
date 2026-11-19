import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/recon_pdf_report.dart';

/// The month's PDF builds, whatever the comments contain.
void main() {
  ReconReportData data({bool invoice = true}) => ReconReportData(
        monthLabel: 'October 2026',
        sheetRef: 'NAT/USAGE/26-27/0D-01705',
        invoiceNumber: invoice ? 'INV/26-27/899' : null,
        sheet: 908050,
        ours: 1147325,
        invoiceExcl: invoice ? 1186050 : null,
        invoiceGst: invoice ? 0 : null,
        invoiceTotal: invoice ? 1186050 : null,
        toRaise: 60000,
        toPay: invoice ? 1126050 : null,
        stillOpen: const ['Everything is answered — settle the month'],
        lines: [
          const ReconReportLine(
              name: 'T1X  High Speed Track (Exclusive)',
              sheet: 180000,
              ours: 300000,
              invoice: 360000,
              toPay: 300000,
              why: 'Disputed: invoice ₹60,000 above what you agreed',
              tone: 1),
          for (var i = 0; i < 30; i++)
            ReconReportLine(name: 'Line $i', sheet: 1000.0 * i, ours: 900.0 * i, invoice: 1000.0 * i, toPay: 1000.0 * i),
        ],
        raise: const [
          ReconReportRaise('High Speed Track (Exclusive)', 360000, 300000,
              'Raised already — it should be ₹3,00,000 → braking track'),
        ],
        remarks: const [
          ReconReportRemark('Workshop / office / cabin', 'Invoice', 'Accept the invoice figure',
              'B1 workshop billed separately “30 days”…', 'dhrupad\n19 Nov 2026, 11:29'),
        ],
        todos: const ['Correct 7 Oct T16 for Mahindra ICE PoC: we have 7 h, NATRAX 4 h.'],
        history: [
          for (var i = 0; i < 40; i++)
            ReconReportEvent('19 Nov 2026, 11:${i.toString().padLeft(2, '0')}', 'answered',
                'Line $i', 'Accept\n"comment ₹ $i"', 'dhrupad'),
        ],
        exportedBy: 'engineer@example.com',
        exportedAt: DateTime(2026, 11, 19, 14, 5),
      );

  test('builds a multi-page PDF with an invoice', () async {
    final bytes = await ReconPdfReport.build(data());
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('and without one', () async {
    final bytes = await ReconPdfReport.build(data(invoice: false));
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('text Helvetica cannot draw is folded, not dropped silently into a crash', () {
    expect(ReconPdfReport.safe('₹3,00,000 → T3X — “ok”…'), 'Rs 3,00,000 -> T3X - "ok"...');
    expect(ReconPdfReport.safe('ok 漢字'), 'ok ');
    expect(ReconPdfReport.money(118605), 'Rs 1,18,605');
  });
}

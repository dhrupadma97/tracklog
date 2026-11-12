import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/natrax_invoice_parser.dart';
import 'package:tracklog/services/pdf_text_extractor.dart';

/// Parsed against the real March 2026 invoice bundled in assets, so a change
/// to the extractor cannot silently start feeding wrong numbers into the PO
/// reconciliation.
void main() {
  final pdf = File('assets/documents/NATRAX_March_2026_Invoice.pdf');

  test('extracts a text layer from the real NATRAX invoice', () {
    final text = PdfTextExtractor.extractText(pdf.readAsBytesSync());
    expect(text, isNotEmpty);
    expect(text, contains('NATIONAL AUTOMOTIVE TEST TRACKS'));
    expect(text, contains('GOODYEAR SOUTH ASIA TYRES PVT LTD'));
  });

  test('reads every field off invoice INV/25-26/1869', () {
    final parsed = NatraxInvoiceParser.parse(pdf.readAsBytesSync());

    expect(parsed.isUnreadable, isFalse);
    expect(parsed.missingFields, isEmpty,
        reason: 'parser should not need any manual entry for this invoice');

    expect(parsed.invoiceNumber, 'INV/25-26/1869');
    expect(parsed.invoiceDate, DateTime(2026, 3, 31));
    expect(parsed.poNumber, '8242348442');
    expect(parsed.periodMonth, '2026-03');

    expect(parsed.amountExclGst, closeTo(193605.00, 0.01));
    expect(parsed.gstAmount, closeTo(34848.90, 0.01));
    expect(parsed.totalAmount, closeTo(228454.00, 0.01));

    expect(parsed.isComplete, isTrue);
    expect(parsed.addsUp, isTrue,
        reason: 'taxable + IGST should reconcile to the printed total');
  });

  test('matches the Analyser figures the app already reports for March 2026', () {
    final parsed = NatraxInvoiceParser.parse(pdf.readAsBytesSync());

    // monthly_invoices_screen hardcodes track+accessories and workshop rental
    // for 2026-03; together they must equal the invoice's taxable value.
    const trackAcc = 138605.0;
    const workshopRental = 55000.0;
    expect(parsed.amountExclGst, closeTo(trackAcc + workshopRental, 0.01));
    expect(parsed.gstAmount, closeTo((trackAcc + workshopRental) * 0.18, 0.01));
  });

  group('CGST + SGST invoice raised in a later month', () {
    // Mirrors the April 2026 invoice (INV/26-27/205): intra-state tax, and an
    // HSN summary table below the total whose CGST header sits directly above
    // the bare HSN code 998346. Synthetic so no real billing data is committed.
    const text = '''
Invoice No.INV/26-27/205
Buyer's Order No.8242348442
Dated
24-Jun-26
Other References
Dated5-Mar-26
Terms of DeliveryTesting Period From 01 to 30-April-2026.
PWT(Power Train Lab ) Work Shop
1,50,000.00
days
5,000.00
30 days
998346
11,62,450.00
CGST
1,04,620.50
SGST
1,04,620.50
Total 13,71,691.00
HSN/SAC
Total
SGST/UTGST
CGST
TaxableTax AmountAmountRateAmountRateValue
998346
2,08,845.00
1,04,422.50
9%''';

    test('bills the month the work was done, not the month it was raised', () {
      final parsed = NatraxInvoiceParser.parseText(text);
      expect(parsed.invoiceDate, DateTime(2026, 6, 24));
      expect(parsed.periodMonth, '2026-04',
          reason: 'April testing billed in June belongs to April');
      expect(parsed.testingPeriod, contains('01 to 30-April-2026'));
    });

    test('sums CGST + SGST without swallowing the HSN summary table', () {
      final parsed = NatraxInvoiceParser.parseText(text);
      expect(parsed.amountExclGst, closeTo(1162450.00, 0.01));
      expect(parsed.gstAmount, closeTo(209241.00, 0.01),
          reason: 'CGST 1,04,620.50 + SGST 1,04,620.50 — the HSN code 998346 '
              'below the total must not be read as money');
      expect(parsed.totalAmount, closeTo(1371691.00, 0.01));
      expect(parsed.addsUp, isTrue);
      expect(parsed.missingFields, isEmpty);
    });
  });

  test('falls back to the invoice month only when no period is stated', () {
    const text = '''
Invoice No.INV/26-27/999
Dated
24-Jun-26
1,00,000.00
IGST
18,000.00
Total 1,18,000.00''';
    final parsed = NatraxInvoiceParser.parseText(text);
    expect(parsed.periodMonth, '2026-06');
    expect(parsed.testingPeriod, isNull);
    expect(parsed.gstAmount, closeTo(18000.00, 0.01));
  });

  group('nil-rated invoices (SEZ Bond / LUT)', () {
    test('a subtotal equal to the total means zero GST, not missing GST', () {
      const text = '''
Invoice No.INV/26-27/311
Buyer's Order No.8242390552
Dated
15-Sep-26
Terms of DeliveryTesting Period From 01 to 30-September-2026.
Braking Track Testing (GVW < 3.5T) - WET
2,10,000.00
Hrs.
21,000.00
10 Hrs.
998346
2,10,000.00
Total 2,10,000.00''';
      final p = NatraxInvoiceParser.parseText(text);
      expect(p.gstAmount, 0);
      expect(p.amountExclGst, closeTo(210000, 0.01));
      expect(p.totalAmount, closeTo(210000, 0.01));
      expect(p.addsUp, isTrue);
      expect(p.missingFields, isEmpty,
          reason: 'a nil-rated invoice is complete, not unreadable');
      expect(p.isComplete, isTrue);
    });

    test('a total with no tax line and no subtotal is still nil-rated', () {
      const text = '''
Invoice No.INV/26-27/312
Dated
30-Sep-26
Total 95,000.00''';
      final p = NatraxInvoiceParser.parseText(text);
      expect(p.gstAmount, 0);
      expect(p.amountExclGst, closeTo(95000, 0.01));
      expect(p.addsUp, isTrue);
    });

    test('a genuine tax line is still never treated as nil', () {
      const text = '''
Invoice No.INV/26-27/313
Dated
30-Sep-26
1,00,000.00
IGST
18,000.00
Total 1,18,000.00''';
      final p = NatraxInvoiceParser.parseText(text);
      expect(p.gstAmount, closeTo(18000, 0.01));
      expect(p.amountExclGst, closeTo(100000, 0.01));
    });

    test('tax that does not reconcile is reported, not zeroed', () {
      // Subtotal and total disagree and there is a tax word present, so the
      // figure is genuinely unreadable rather than nil.
      const text = '''
Invoice No.INV/26-27/314
Dated
30-Sep-26
1,00,000.00
IGST
Total 1,18,000.00''';
      final p = NatraxInvoiceParser.parseText(text);
      expect(p.gstAmount, isNull);
      expect(p.missingFields, contains('GST amount'));
    });
  });

  group('other vendors (MOICARS manpower)', () {
    // MOICARS invoices differ from Tally in three ways that each broke the
    // parse: a bare "Total" above its figure, a tax label carrying its rate,
    // and line items on page one with the tax on page two.
    const text = '''
Tax Invoice
MOICARS
Invoice No.
MOI/TV-2082
Buyer's Order No.
8242356330
Dated
21-May-26
Charges for Man Power
50,400.00
Nos.
1,800.00
28 Nos.
998346
continued to page number 2
IGST @18%
9,072.00
Total
Amount Chargeable (in words)''';

    test('reads a bare Total and a rate-suffixed tax label', () {
      final p = NatraxInvoiceParser.parseText(text);
      expect(p.invoiceNumber, 'MOI/TV-2082');
      expect(p.poNumber, '8242356330');
      expect(p.invoiceDate, DateTime(2026, 5, 21));
      expect(p.gstAmount, closeTo(9072, 0.01));
    });

    test('reconciles the taxable value against the printed tax', () {
      final p = NatraxInvoiceParser.parseText(text);
      // 50,400 x 18% = 9,072 exactly, so the figure is accepted; the total
      // follows even though the document never prints it.
      expect(p.amountExclGst, closeTo(50400, 0.01));
      expect(p.totalAmount, closeTo(59472, 0.01));
      expect(p.addsUp, isTrue);
      expect(p.missingFields, isEmpty);
    });

    test('a distant figure that does not reconcile is not adopted', () {
      // The candidate sits far from the tax line, so only the reconciliation
      // path can reach it — and 12,345 x 18% is not 9,072, so it is refused
      // rather than adopted as the nearest number on the page.
      const bad = '''
Invoice No.
MOI/TV-9999
Dated
21-May-26
Charges for Man Power
12,345.00
Nos.
some description line
another description line
continued to page number 2
IGST @18%
9,072.00
Total
Amount Chargeable (in words)''';
      final p = NatraxInvoiceParser.parseText(bad);
      expect(p.amountExclGst, isNull);
      expect(p.missingFields, contains('taxable value'));
    });

    test('a derived taxable value is never negative', () {
      // Tax larger than the total means something was misread; the parser must
      // report that rather than produce a negative taxable value.
      const wrong = '''
Invoice No.
X-1
Dated
21-May-26
IGST
1,00,000.00
Total 10,000.00''';
      final p = NatraxInvoiceParser.parseText(wrong);
      expect(p.amountExclGst == null || p.amountExclGst! >= 0, isTrue);
    });
  });

  test('a PDF with no text layer is reported, not guessed at', () {
    // A minimal PDF header with no content streams at all.
    final bytes = File(pdf.path).readAsBytesSync().sublist(0, 64);
    final parsed = NatraxInvoiceParser.parse(bytes);
    expect(parsed.isUnreadable, isTrue);
    expect(parsed.missingFields, isNotEmpty);
  });

  invoiceRowsAndSez();
}

/// Line items read off position-grouped rows, and the SEZ declaration.
///
/// The rows below are shaped exactly as PdfTextExtractor.extract returns them
/// for the real invoices — 802 (September 2026, GTCI) and 205 (April 2026) —
/// so the line logic is pinned without shipping those PDFs into the repo.
void invoiceRowsAndSez() {
  group('line items from rows', () {
    // INV/26-27/802, as grouped by position. Every cell of a row lands on
    // one line; before rows existed, each cell was its own line and no real
    // invoice ever had a line item read.
    const rows802 = [
      'Sl Description of HSN/SAC GST Quantity Rate per Amount',
      '1 Braking Track Testing (GVW < 3.5T) - WET 998346 18 % 28 Hrs. 21,000.00 Hrs. 5,88,000.00',
      '2 High Speed Track Testing ( GVW< 3.5T) 998346 18 % 2 Hrs. 25,000.00 Hrs. 50,000.00',
      '3 Braking Track Testing (GVW < 3.5T) - DRY 998346 18 % 2 Hrs. 19,000.00 Hrs. 38,000.00',
      '4 General Road Track Testing(GVW <3.5T) 998346 18 % 5 Hrs. 9,000.00 Hrs. 45,000.00',
      '5 Dynamic Platform Track Testing ( GVW< 3.5 T) 998346 18 % 2 Hrs. 20,000.00 Hrs. 40,000.00',
      '6 EV Heavy Duty Charger 998346 18 % 181 Unt 25.00 Unt 4,525.00',
      '7 Weighment PAD-Passenger Car(PC) 998346 18 % 1 Nos 600.00 Nos 600.00',
      '8 Other Support Services (Refreshment) 998599 18 % 46 Nos 125.00 Nos 5,750.00',
      '9 Other Support Services (Bisleri Water 20L) 998599 18 % 7 Unt 67.80 Unt 474.60',
      '7,72,349.60',
      'Round Off/ Balance written off 0.40',
      'Total ₹ 7,72,350.00',
      // The tax analysis below the total opens with the HSN itself, so it has
      // no description and must never be read as a line.
      '998346 7,66,125.00 18% 1,37,902.50 1,37,902.50',
      '998599 6,224.60 18% 1,120.43 1,120.43',
    ];

    test('every charged line of 802 is read, and nothing else', () {
      final lines = NatraxInvoiceParser.linesFromRows(rows802);
      expect(lines.map((l) => l.matchKey).toList(), [
        'T3W', 'T1', 'T3D', 'T16', 'T2',
        'SVC_EV', 'SVC_WEIGH', 'SVC_FOOD', 'SVC_WATER',
      ]);
      expect(lines.first.quantity, 28);
      expect(lines.first.amount, 588000);
      expect(lines.last.amount, 474.60);
    });

    test('the lines add up to the taxable value, to the paisa', () {
      final lines = NatraxInvoiceParser.linesFromRows(rows802);
      final sum = lines.fold<double>(0, (s, l) => s + l.amount);
      expect(sum, closeTo(772349.60, 0.001));
      expect(lines.any((l) => l.amountDerived), isFalse);
    });

    test('a row whose amount is missing is rebuilt from qty x rate', () {
      // INV/26-27/205's wet line reaches the text layer without its amount.
      // The last figure is then the RATE — followed by its unit — and was
      // being read as a 21,000 line where the invoice charges 7,14,000.
      final lines = NatraxInvoiceParser.linesFromRows([
        '2 Braking Track Testing (GVW < 3.5T) - WET 998346 34 Hrs. 21,000.00 Hrs.',
      ]);
      expect(lines.single.amount, 714000);
      expect(lines.single.amountDerived, isTrue);
    });

    test('a rate with no quantity is left out, never guessed', () {
      final lines = NatraxInvoiceParser.linesFromRows([
        '2 Braking Track Testing (GVW < 3.5T) - WET 998346 21,000.00 Hrs.',
      ]);
      expect(lines, isEmpty);
    });

    test('an amount at the end of its row is taken as printed', () {
      final lines = NatraxInvoiceParser.linesFromRows([
        '1 Charges for Man Power 998346 27 Nos. 1,800.00 Nos. 48,600.00',
      ]);
      expect(lines.single.amount, 48600);
      expect(lines.single.amountDerived, isFalse);
    });
  });

  group('SEZ supply under bond or LUT', () {
    // The heading reaches the text broken mid-word, "WITH" / "OUT".
    const sezText = '''
GST/TAX INVOICE(SUPPLY MEANT FOR EXPORT/SUPPLY TO SEZ UNIT OR SEZ DEVELOPER FOR AUTHORISED OPERATIONS UNDER BOND OR LETTER OF UNDERTAKING WITH
OUT PAYMENT OF IGST)
Invoice No.:INV/26-27/802
Dated:
29-Oct-26
Terms of Delivery: Testing Period From 01 to 30-September-2026.
7,72,349.60
Round Off/ Balance written off
0.40
Total
7,72,350.00
HSN/SAC Taxable IGST Total
998346 7,66,125.00 18% 1,37,902.50 1,37,902.50
Total 7,72,349.60 1,39,022.93 1,39,022.93
''';

    test('the declaration means nil GST, not the IGST in the tax box', () {
      final p = NatraxInvoiceParser.parseText(sezText);
      expect(p.gstAmount, 0);
      // Never the 1,39,022.93 printed for information below the total.
      expect(p.totalAmount, 772350);
      expect(p.amountExclGst, 772350);
      expect(p.periodMonth, '2026-09');
    });
  });
}

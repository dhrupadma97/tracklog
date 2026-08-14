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
}

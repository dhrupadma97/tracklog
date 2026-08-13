import 'dart:typed_data';

import 'pdf_text_extractor.dart';

/// Everything the upload flow needs, read off the invoice itself.
///
/// [missingFields] names anything the parser could not find, so the UI can
/// point at exactly what needs a human eye instead of presenting a confident
/// but half-empty form.
class ParsedInvoice {
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final String? periodMonth; // 'YYYY-MM'
  final String? poNumber;
  final double? amountExclGst;
  final double? gstAmount;
  final double? totalAmount;
  final String? testingPeriod;
  final List<String> missingFields;
  final String rawText;

  const ParsedInvoice({
    this.invoiceNumber,
    this.invoiceDate,
    this.periodMonth,
    this.poNumber,
    this.amountExclGst,
    this.gstAmount,
    this.totalAmount,
    this.testingPeriod,
    this.missingFields = const [],
    this.rawText = '',
  });

  /// No text layer at all — almost certainly a scan rather than a real PDF.
  bool get isUnreadable => rawText.trim().isEmpty;

  /// Every field the reconciliation depends on was found.
  bool get isComplete =>
      invoiceNumber != null &&
      invoiceDate != null &&
      amountExclGst != null &&
      gstAmount != null &&
      totalAmount != null;

  /// The printed total agrees with taxable + tax, allowing for the round-off
  /// line Tally adds.
  bool get addsUp {
    if (amountExclGst == null || gstAmount == null || totalAmount == null) {
      return false;
    }
    return (amountExclGst! + gstAmount! - totalAmount!).abs() <= 1.0;
  }
}

/// Reads NATRAX's Tally-generated GST e-invoices.
///
/// Anchors on the printed field labels ("Invoice No.", "Buyer's Order No.",
/// "Total") rather than on positions, so it survives the layout shifting
/// between months. Where a label and its value land in the same extracted run
/// (Tally emits `Invoice No.INV/25-26/1869`) the value is taken from the same
/// line; otherwise the following non-empty line is used.
class NatraxInvoiceParser {
  const NatraxInvoiceParser._();

  static ParsedInvoice parse(Uint8List pdfBytes) {
    try {
      return parseText(PdfTextExtractor.extractText(pdfBytes));
    } catch (e) {
      // A malformed PDF must never take the upload flow down with it.
      return ParsedInvoice(missingFields: ['everything — could not read ($e)']);
    }
  }

  /// Split out from [parse] so the field logic can be tested without shipping
  /// real invoice PDFs into the repo.
  static ParsedInvoice parseText(String text) {
    if (text.trim().isEmpty) {
      return const ParsedInvoice(
        missingFields: ['everything — the PDF has no text layer'],
      );
    }

    final lines = text.split('\n');
    final missing = <String>[];

    final invoiceNumber = _afterLabel(lines, RegExp(r"Invoice\s*No\.?", caseSensitive: false),
        valuePattern: RegExp(r'[A-Z0-9][A-Z0-9/\-]{3,}', caseSensitive: false));
    if (invoiceNumber == null) missing.add('invoice number');

    final poNumber = _afterLabel(
        lines, RegExp(r"Buyer'?s\s*Order\s*No\.?", caseSensitive: false),
        valuePattern: RegExp(r'\d{6,}'));

    // Tally prints two "Dated" fields — the invoice's own date first, the
    // buyer's-order date second. Take the first.
    final invoiceDate = _firstDate(lines);
    if (invoiceDate == null) missing.add('invoice date');

    final testingPeriod = _afterLabel(
        lines, RegExp(r'Terms\s*of\s*Delivery', caseSensitive: false),
        valuePattern: RegExp(r'.+'));

    final totalIndex = _grandTotalIndex(lines);
    final totalAmount = totalIndex == null ? null : _money(_afterTotal(lines[totalIndex]));
    if (totalAmount == null) missing.add('invoice total');

    // Everything below the grand total is the HSN/SAC summary table, which
    // repeats the words CGST/SGST/IGST as column headers above bare HSN codes
    // like 998346. Reading those as money inflates the tax wildly, so the tax
    // and taxable figures are only ever taken from above the total line.
    final body = totalIndex == null ? lines : lines.sublist(0, totalIndex);

    var gstAmount = _tax(body);
    var amountExclGst = _taxableValue(body);

    // Supplies under SEZ Bond / LUT carry no tax, so an invoice with no IGST
    // or CGST/SGST line is legitimate rather than unreadable. Treat it as zero
    // GST only when the taxable value and the printed total agree — otherwise
    // tax really is missing and should be reported as such.
    if (gstAmount == null &&
        totalAmount != null &&
        amountExclGst != null &&
        (totalAmount - amountExclGst).abs() <= 1.0) {
      gstAmount = 0;
    }
    // Same case, read the other way round: a total with no tax line and no
    // subtotal above it is a nil-rated invoice whose taxable value is the
    // total.
    if (gstAmount == null && amountExclGst == null && totalAmount != null) {
      final hasTaxLine = body.any((l) =>
          RegExp(r'\b(IGST|CGST|SGST|UTGST)\b', caseSensitive: false)
              .hasMatch(l));
      if (!hasTaxLine) {
        gstAmount = 0;
        amountExclGst = totalAmount;
      }
    }

    if (gstAmount == null) missing.add('GST amount');

    if (amountExclGst == null && totalAmount != null && gstAmount != null) {
      // Derive it rather than fail — the two printed figures pin it down.
      amountExclGst = totalAmount - gstAmount;
    }
    if (amountExclGst == null) missing.add('taxable value');

    return ParsedInvoice(
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      periodMonth: _periodMonth(testingPeriod, invoiceDate),
      poNumber: poNumber,
      amountExclGst: amountExclGst,
      gstAmount: gstAmount,
      totalAmount: totalAmount,
      testingPeriod: testingPeriod?.trim(),
      missingFields: missing,
      rawText: text,
    );
  }

  // ── Field readers ──────────────────────────────────────────────────────────

  /// Finds [label], then returns the first [valuePattern] match either on the
  /// same line (label and value are often concatenated) or on the lines that
  /// follow it.
  static String? _afterLabel(
    List<String> lines,
    RegExp label, {
    required RegExp valuePattern,
    int lookahead = 3,
  }) {
    for (var i = 0; i < lines.length; i++) {
      final match = label.firstMatch(lines[i]);
      if (match == null) continue;

      final sameLine = lines[i].substring(match.end);
      final inline = valuePattern.firstMatch(sameLine);
      if (inline != null && inline.group(0)!.trim().isNotEmpty) {
        return inline.group(0)!.trim();
      }

      for (var j = i + 1; j < lines.length && j <= i + lookahead; j++) {
        final next = lines[j].trim();
        if (next.isEmpty) continue;
        final found = valuePattern.firstMatch(next);
        if (found != null && found.group(0)!.trim().isNotEmpty) {
          return found.group(0)!.trim();
        }
      }
    }
    return null;
  }

  static final _datePattern =
      RegExp(r'(\d{1,2})-([A-Za-z]{3})-(\d{2,4})', caseSensitive: false);

  /// The first `Dated` value in document order, which Tally uses for the
  /// invoice itself — the second is the buyer's-order date.
  ///
  /// The label and its value do not reliably share a line: this invoice emits
  /// a bare `Dated` followed by `31-Mar-26`, while the order date arrives as
  /// `Dated5-Mar-26`. Both shapes have to resolve to the first one printed.
  static DateTime? _firstDate(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!RegExp(r'Dated', caseSensitive: false).hasMatch(lines[i])) continue;

      final sameLine = _datePattern.firstMatch(lines[i]);
      if (sameLine != null) return _toDate(sameLine);

      for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
        final next = _datePattern.firstMatch(lines[j]);
        if (next != null) return _toDate(next);
      }
    }
    // Fall back to any date anywhere on the page.
    for (final line in lines) {
      final m = _datePattern.firstMatch(line);
      if (m != null) return _toDate(m);
    }
    return null;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _toDate(RegExpMatch m) {
    final day = int.tryParse(m.group(1)!);
    final month = _months[m.group(2)!.toLowerCase()];
    var year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    return DateTime(year, month, day);
  }

  /// Index of the `Total 13,71,691.00` line — the grand total including tax,
  /// and the boundary between the invoice body and the HSN summary table.
  static int? _grandTotalIndex(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^\s*Total\s+([\d,]+\.?\d*)\s*$', caseSensitive: false)
          .firstMatch(lines[i]);
      if (m != null) {
        final v = _money(m.group(1)!);
        if (v != null && v > 0) return i;
      }
    }
    return null;
  }

  /// The figure printed after the word `Total` on the grand-total line.
  static String _afterTotal(String line) =>
      RegExp(r'^\s*Total\s+(.*)$', caseSensitive: false)
          .firstMatch(line)
          ?.group(1)
          ?.trim() ??
      '';

  /// Sums the tax lines — IGST for inter-state (NATRAX MP → Goodyear MH), or
  /// CGST + SGST should an intra-state invoice ever arrive.
  static double? _tax(List<String> lines) {
    double? igst;
    double cgstSgst = 0;
    var sawCgstSgst = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final igstMatch =
          RegExp(r'^\s*IGST\s*([\d,]+\.?\d*)?\s*$', caseSensitive: false)
              .firstMatch(line);
      if (igstMatch != null && igst == null) {
        final inline = _money(igstMatch.group(1) ?? '');
        igst = inline ?? _nextMoney(lines, i);
        continue;
      }

      final cs = RegExp(r'^\s*(CGST|SGST|UTGST)\s*([\d,]+\.?\d*)?\s*$',
              caseSensitive: false)
          .firstMatch(line);
      if (cs != null) {
        final v = _money(cs.group(2) ?? '') ?? _nextMoney(lines, i);
        if (v != null) {
          cgstSgst += v;
          sawCgstSgst = true;
        }
      }
    }

    if (igst != null && igst > 0) return igst;
    if (sawCgstSgst && cgstSgst > 0) return cgstSgst;
    return null;
  }

  /// The subtotal printed directly above the first tax line.
  static double? _taxableValue(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final isTaxLine = RegExp(r'^\s*(IGST|CGST|SGST|UTGST)\b',
              caseSensitive: false)
          .hasMatch(lines[i]);
      if (!isTaxLine) continue;
      // Walk back to the nearest bare money figure.
      for (var j = i - 1; j >= 0 && j >= i - 3; j--) {
        final v = _money(lines[j]);
        if (v != null && v > 0) return v;
      }
    }
    return null;
  }

  static double? _nextMoney(List<String> lines, int from) {
    for (var j = from + 1; j < lines.length && j <= from + 2; j++) {
      final v = _money(lines[j]);
      if (v != null) return v;
    }
    return null;
  }

  /// Parses Indian-grouped money (`1,93,605.00`). Returns null for anything
  /// that is not a bare figure.
  ///
  /// Tally always prints amounts with two decimals, so requiring a decimal
  /// point keeps bare HSN/SAC codes (`998346`) and quantities (`34`) from
  /// being mistaken for money.
  static double? _money(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^[\d,]+\.\d{1,2}$').hasMatch(trimmed)) return null;
    return double.tryParse(trimmed.replaceAll(',', ''));
  }

  /// Prefers the billing period stated in Terms of Delivery ("Testing Period
  /// From 21 to 31-March-2026"), falling back to the invoice month.
  static String? _periodMonth(String? testingPeriod, DateTime? invoiceDate) {
    if (testingPeriod != null) {
      final m = RegExp(r'([A-Za-z]{3,9})[-\s]*(\d{4})', caseSensitive: false)
          .firstMatch(testingPeriod);
      if (m != null) {
        final month = _months[m.group(1)!.toLowerCase().substring(0, 3)];
        final year = int.tryParse(m.group(2)!);
        if (month != null && year != null) {
          return '$year-${month.toString().padLeft(2, '0')}';
        }
      }
    }
    if (invoiceDate != null) {
      return '${invoiceDate.year}-'
          '${invoiceDate.month.toString().padLeft(2, '0')}';
    }
    return null;
  }
}

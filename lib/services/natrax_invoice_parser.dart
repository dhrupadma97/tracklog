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
    final totalAmount = totalIndex == null ? null : _totalAt(lines, totalIndex);
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

    // Some layouts put the taxable value far from the tax line — a multi-page
    // invoice carries its line items on page one and the tax on page two. When
    // it cannot be found adjacently, look for the figure that reconciles with
    // the tax actually printed. This verifies rather than assumes: a candidate
    // is only accepted when candidate × rate lands on the printed tax.
    if (amountExclGst == null && gstAmount != null && gstAmount > 0) {
      for (final rate in const [0.18, 0.12, 0.05, 0.28]) {
        final wanted = gstAmount / rate;
        for (final line in body) {
          final v = _money(line);
          if (v == null || v <= 0) continue;
          if ((v - wanted).abs() <= 1.0) {
            amountExclGst = v;
            break;
          }
        }
        if (amountExclGst != null) break;
      }
    }

    // With taxable and tax both known the total follows, even when the
    // document never prints it as its own figure.
    var derivedTotal = totalAmount;
    if (derivedTotal == null && amountExclGst != null && gstAmount != null) {
      derivedTotal = amountExclGst + gstAmount;
      missing.remove('invoice total');
    }

    if (gstAmount == null) missing.add('GST amount');

    if (amountExclGst == null && totalAmount != null && gstAmount != null) {
      // Derive it rather than fail — the two printed figures pin it down.
      final derived = totalAmount - gstAmount;
      // Unless they do not: tax exceeding the total means one of the two was
      // misread, and a negative taxable value is never a real reading.
      if (derived >= 0) amountExclGst = derived;
    }
    if (amountExclGst == null) {
      missing.add('taxable value');
    } else {
      missing.remove('taxable value');
    }

    return ParsedInvoice(
      invoiceNumber: invoiceNumber,
      invoiceDate: invoiceDate,
      periodMonth: _periodMonth(testingPeriod, invoiceDate),
      poNumber: poNumber,
      amountExclGst: amountExclGst,
      gstAmount: gstAmount,
      totalAmount: derivedTotal,
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
  /// Index of the grand-total line, and the boundary between the invoice body
  /// and the HSN summary table.
  ///
  /// Tally prints `Total 13,71,691.00` on one line; other layouts put a bare
  /// `Total` above its figure. Both have to resolve to the same place.
  static int? _grandTotalIndex(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (!RegExp(r'^\s*Total\b', caseSensitive: false).hasMatch(lines[i])) {
        continue;
      }
      if (_totalAt(lines, i) != null) return i;
    }
    return null;
  }

  /// The grand total belonging to the `Total` line at [i], whether printed
  /// beside the word or on one of the lines below it.
  static double? _totalAt(List<String> lines, int i) {
    final inline =
        RegExp(r'^\s*Total\s+(.*)$', caseSensitive: false).firstMatch(lines[i]);
    final same = _money(inline?.group(1)?.trim() ?? '');
    if (same != null && same > 0) return same;

    for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
      final v = _money(lines[j]);
      if (v != null && v > 0) return v;
    }
    return null;
  }

  /// Sums the tax lines — IGST for inter-state (NATRAX MP → Goodyear MH), or
  /// CGST + SGST should an intra-state invoice ever arrive.
  static double? _tax(List<String> lines) {
    double? igst;
    double cgstSgst = 0;
    var sawCgstSgst = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // The label may carry its rate — "IGST @18%" — so anything between the
      // tax name and the figure is skipped.
      final igstMatch = RegExp(
              r'^\s*IGST\s*(?:@?\s*[\d.]+\s*%)?\s*([\d,]+\.?\d*)?\s*$',
              caseSensitive: false)
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

import 'dart:typed_data';

import 'pdf_text_extractor.dart';

/// What could be read off a purchase order document.
class ParsedPo {
  final String? poNumber;
  final String? vendorName;
  final DateTime? poDate;
  final DateTime? validUntil;
  final double? baseValue;
  final double? taxAmount;
  final double? totalValue;
  final String? category;
  final List<String> missingFields;
  final String rawText;

  const ParsedPo({
    this.poNumber,
    this.vendorName,
    this.poDate,
    this.validUntil,
    this.baseValue,
    this.taxAmount,
    this.totalValue,
    this.category,
    this.missingFields = const [],
    this.rawText = '',
  });

  /// No text layer at all — a scanned PO, which cannot be read.
  bool get isUnreadable => rawText.trim().isEmpty;

  bool get foundAnything =>
      poNumber != null || baseValue != null || vendorName != null;
}

/// Reads Goodyear SAP purchase orders.
///
/// Many of the POs on file are scans with no text layer and cannot be read at
/// all — [ParsedPo.isUnreadable] says so rather than returning empty fields
/// that look like a failed parse of a readable document.
class PoParser {
  const PoParser._();

  static ParsedPo parse(Uint8List pdfBytes) {
    try {
      return parseText(PdfTextExtractor.extractText(pdfBytes));
    } catch (e) {
      return ParsedPo(missingFields: ['everything — could not read ($e)']);
    }
  }

  static ParsedPo parseText(String text) {
    if (text.trim().isEmpty) {
      return const ParsedPo(
        missingFields: ['everything — the PDF has no text layer'],
      );
    }

    final lines = text.split('\n');
    final missing = <String>[];

    // SAP POs carry a 10-digit number beginning 82. Prefer one that follows a
    // PO label; fall back to the first such number anywhere.
    final poNumber = _labelled(lines,
            RegExp(r'(Purchase\s*Order|PO)\s*(No\.?|Number|#)?',
                caseSensitive: false),
            RegExp(r'\b(82\d{8})\b')) ??
        _anywhere(lines, RegExp(r'\b(82\d{8})\b'));
    if (poNumber == null) missing.add('PO number');

    final vendorName = _vendor(lines);

    final poDate = _labelled(lines,
                RegExp(r'(PO\s*Date|Order\s*Date|Document\s*Date|Dated)',
                    caseSensitive: false),
                RegExp(r'(\d{1,2}[-./]\d{1,2}[-./]\d{2,4}|'
                    r'\d{1,2}[-\s][A-Za-z]{3,9}[-\s]\d{2,4})')) !=
            null
        ? _toDate(_labelled(
            lines,
            RegExp(r'(PO\s*Date|Order\s*Date|Document\s*Date|Dated)',
                caseSensitive: false),
            RegExp(r'(\d{1,2}[-./]\d{1,2}[-./]\d{2,4}|'
                r'\d{1,2}[-\s][A-Za-z]{3,9}[-\s]\d{2,4})'))!)
        : null;

    final validUntil = _labelled(
                lines,
                RegExp(r'(Valid\s*(to|until|till)|Delivery\s*Date|End\s*Date)',
                    caseSensitive: false),
                RegExp(r'(\d{1,2}[-./]\d{1,2}[-./]\d{2,4}|'
                    r'\d{1,2}[-\s][A-Za-z]{3,9}[-\s]\d{2,4})')) !=
            null
        ? _toDate(_labelled(
            lines,
            RegExp(r'(Valid\s*(to|until|till)|Delivery\s*Date|End\s*Date)',
                caseSensitive: false),
            RegExp(r'(\d{1,2}[-./]\d{1,2}[-./]\d{2,4}|'
                r'\d{1,2}[-\s][A-Za-z]{3,9}[-\s]\d{2,4})'))!)
        : null;

    // Values. SAP prints "Total value" / "Net value" / "Total Net Order Value".
    final total = _money(_labelled(
        lines,
        RegExp(r'(Grand\s*Total|Total\s*(Value|Amount)|Total\s*incl)',
            caseSensitive: false),
        _moneyPattern));
    var base = _money(_labelled(
        lines,
        RegExp(r'(Net\s*(Value|Amount|Order\s*Value)|Basic\s*Value|'
            r'Taxable\s*Value|Value\s*excl)',
            caseSensitive: false),
        _moneyPattern));
    var tax = _money(_labelled(
        lines,
        RegExp(r'\b(GST|IGST|CGST|SGST|Tax\s*Amount|Total\s*Tax)\b',
            caseSensitive: false),
        _moneyPattern));

    // Fill in whichever leg is missing from the other two.
    if (base == null && total != null && tax != null) base = total - tax;
    if (tax == null && total != null && base != null) tax = total - base;

    if (base == null) missing.add('PO value');

    return ParsedPo(
      poNumber: poNumber,
      vendorName: vendorName,
      poDate: poDate,
      validUntil: validUntil,
      baseValue: base,
      taxAmount: tax,
      totalValue: total ?? (base != null ? base + (tax ?? 0) : null),
      category: _category(text),
      missingFields: missing,
      rawText: text,
    );
  }

  // ── Field readers ──────────────────────────────────────────────────────────

  static final _moneyPattern = RegExp(r'[\d,]+\.\d{2}');

  /// Value matching [value] on the same line as [label], or just after it.
  static String? _labelled(List<String> lines, RegExp label, RegExp value,
      {int lookahead = 2}) {
    for (var i = 0; i < lines.length; i++) {
      final m = label.firstMatch(lines[i]);
      if (m == null) continue;

      final rest = lines[i].substring(m.end);
      final inline = value.firstMatch(rest);
      if (inline != null) return inline.group(0);

      for (var j = i + 1; j < lines.length && j <= i + lookahead; j++) {
        final next = value.firstMatch(lines[j]);
        if (next != null) return next.group(0);
      }
    }
    return null;
  }

  static String? _anywhere(List<String> lines, RegExp value) {
    for (final l in lines) {
      final m = value.firstMatch(l);
      if (m != null) return m.group(0);
    }
    return null;
  }

  /// The known suppliers, matched on the document text.
  static String? _vendor(List<String> lines) {
    final joined = lines.join(' ').toUpperCase();
    if (joined.contains('NATIONAL AUTOMOTIVE TEST TRACKS') ||
        joined.contains('NATRAX')) {
      return 'NATIONAL AUTOMOTIVE TEST TRACKS (NATRAX)';
    }
    if (joined.contains('MOICARS')) return 'MOICARS';
    // Otherwise take the line after a Vendor/Supplier label.
    return _labelled(lines, RegExp(r'(Vendor|Supplier)\b', caseSensitive: false),
        RegExp(r'[A-Za-z][A-Za-z0-9 .,&()-]{4,}'));
  }

  /// Guesses what the PO covers from its wording. Only ever a starting value —
  /// the dialog leaves it editable.
  static String? _category(String text) {
    final t = text.toUpperCase();
    if (t.contains('MANPOWER') ||
        t.contains('MAN POWER') ||
        t.contains('LABOUR') ||
        t.contains('RESOURCE SUPPORT')) {
      return 'manpower';
    }
    if (t.contains('TRACK') || t.contains('TESTING') || t.contains('PROVING')) {
      return 'track_booking';
    }
    if (t.contains('WORKSHOP')) return 'workshop';
    if (t.contains('INSTRUMENT')) return 'instrumentation';
    return null;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _toDate(String raw) {
    final s = raw.trim();

    // 27.05.2026 / 27-05-2026 / 27/05/26
    final numeric =
        RegExp(r'^(\d{1,2})[-./](\d{1,2})[-./](\d{2,4})$').firstMatch(s);
    if (numeric != null) {
      final d = int.tryParse(numeric.group(1)!);
      final m = int.tryParse(numeric.group(2)!);
      var y = int.tryParse(numeric.group(3)!);
      if (d == null || m == null || y == null) return null;
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      return DateTime(y, m, d);
    }

    // 27-May-2026 / 27 May 26
    final named =
        RegExp(r'^(\d{1,2})[-\s]([A-Za-z]{3,9})[-\s](\d{2,4})$').firstMatch(s);
    if (named != null) {
      final d = int.tryParse(named.group(1)!);
      final m = _months[named.group(2)!.toLowerCase().substring(0, 3)];
      var y = int.tryParse(named.group(3)!);
      if (d == null || m == null || y == null) return null;
      if (y < 100) y += 2000;
      return DateTime(y, m, d);
    }
    return null;
  }

  static double? _money(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (!RegExp(r'^[\d,]+\.\d{2}$').hasMatch(t)) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }
}

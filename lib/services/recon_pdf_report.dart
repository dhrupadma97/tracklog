import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One line of the "why the figures differ" table.
class ReconReportLine {
  final String name;
  final double sheet;
  final double ours;
  final double? invoice;
  final double? toPay;
  final String? why;

  /// 0 neutral, 1 disputed, 2 needs an answer, 3 in our favour.
  final int tone;
  const ReconReportLine({
    required this.name,
    required this.sheet,
    required this.ours,
    this.invoice,
    this.toPay,
    this.why,
    this.tone = 0,
  });
}

class ReconReportRaise {
  final String line;
  final double charged;
  final double agreed;
  final String comment;
  const ReconReportRaise(this.line, this.charged, this.agreed, this.comment);
}

class ReconReportRemark {
  final String line;
  final String stage;
  final String decision;
  final String comment;
  final String byWhen;
  const ReconReportRemark(this.line, this.stage, this.decision, this.comment, this.byWhen);
}

class ReconReportEvent {
  final String when;
  final String action;
  final String line;
  final String detail;
  final String by;
  const ReconReportEvent(this.when, this.action, this.line, this.detail, this.by);
}

/// Everything the month's PDF shows, gathered by the Reconcile screen.
class ReconReportData {
  final String monthLabel;
  final String? sheetRef;
  final String? invoiceNumber;
  final double sheet;
  final double ours;
  final double? invoiceExcl;
  final double? invoiceGst;
  final double? invoiceTotal;
  final double toRaise;
  final double? toPay;
  final bool settled;
  final String? settledOn;
  final List<String> stillOpen;
  final List<ReconReportLine> lines;
  final List<ReconReportRaise> raise;
  final List<ReconReportRemark> remarks;
  final List<String> todos;
  final List<ReconReportEvent> history;
  final String? exportedBy;
  final DateTime exportedAt;

  const ReconReportData({
    required this.monthLabel,
    required this.sheet,
    required this.ours,
    required this.toRaise,
    required this.exportedAt,
    this.sheetRef,
    this.invoiceNumber,
    this.invoiceExcl,
    this.invoiceGst,
    this.invoiceTotal,
    this.toPay,
    this.settled = false,
    this.settledOn,
    this.stillOpen = const [],
    this.lines = const [],
    this.raise = const [],
    this.remarks = const [],
    this.todos = const [],
    this.history = const [],
    this.exportedBy,
  });
}

/// The month's reconciliation as a PDF to file or send.
///
/// Built with the PDF standard Helvetica on purpose: the project carries no
/// font files (pubspec: Google Fonts only), and fetching one at export time
/// would fail on a locked-down network. Helvetica has no ₹ glyph, so amounts
/// are written "Rs 11,86,050" — the way Indian invoices write them — and any
/// text outside its character set is folded to the nearest it has.
class ReconPdfReport {
  const ReconPdfReport._();

  static final _rs = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs ', decimalDigits: 0);

  static const _navy = PdfColor.fromInt(0xFF0A1025);
  static const _ink = PdfColor.fromInt(0xFF0F172A);
  static const _muted = PdfColor.fromInt(0xFF64748B);
  static const _line = PdfColor.fromInt(0xFFE2E8F0);
  static const _zebra = PdfColor.fromInt(0xFFF8FAFC);
  static const _teal = PdfColor.fromInt(0xFF0891B2);
  static const _green = PdfColor.fromInt(0xFF15803D);
  static const _red = PdfColor.fromInt(0xFFB91C1C);
  static const _amber = PdfColor.fromInt(0xFFB45309);
  static const _cyan = PdfColor.fromInt(0xFF00F3FF);

  static String money(double? v) => v == null ? '-' : _rs.format(v);

  /// Text Helvetica can draw: ₹ to "Rs ", arrows and dashes to ASCII, and
  /// anything else outside Latin-1 dropped rather than crashing the export.
  static String safe(String s) {
    final t = s
        .replaceAll('₹', 'Rs ')
        .replaceAll('→', '->')
        .replaceAll('←', '<-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('…', '...')
        .replaceAll('•', '-')
        .replaceAll(' ', ' ');
    return String.fromCharCodes(t.runes.where((r) => r == 10 || (r >= 32 && r <= 255)));
  }

  static pw.TextStyle _s(double size,
          {PdfColor color = _ink, bool bold = false, double? spacing}) =>
      pw.TextStyle(
        fontSize: size,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        letterSpacing: spacing,
      );

  static pw.Widget _t(String s, double size,
          {PdfColor color = _ink, bool bold = false, double? spacing, pw.TextAlign? align}) =>
      pw.Text(safe(s), style: _s(size, color: color, bold: bold, spacing: spacing), textAlign: align);

  static Future<Uint8List> build(ReconReportData d) async {
    final doc = pw.Document(
      title: 'NATRAX reconciliation - ${d.monthLabel}',
      author: d.exportedBy ?? 'TrackLog',
      creator: 'TrackLog',
    );
    final hasInvoice = d.invoiceExcl != null;
    final stamp = DateFormat('d MMM yyyy, HH:mm').format(d.exportedAt);

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 32),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6))),
        child: pw.Row(children: [
          pw.Expanded(
            child: _t('TrackLog - NATRAX reconciliation, ${d.monthLabel} - exported $stamp'
                '${d.exportedBy == null ? '' : ' by ${d.exportedBy}'}', 7.5, color: _muted),
          ),
          _t('Page ${ctx.pageNumber} of ${ctx.pagesCount}', 7.5, color: _muted),
        ]),
      ),
      build: (ctx) => [
        _header(d),
        pw.SizedBox(height: 14),
        _figures(d, hasInvoice),
        pw.SizedBox(height: 18),
        _section('Why the figures differ - line by line',
            "NATRAX's sheet = their gate log for our vehicles. Our record = what TrackLog has. "
            '${hasInvoice ? 'Invoice = what NATRAX billed. To pay = the invoice, less the lines disputed.' : 'No invoice set yet.'}'),
        _linesTable(d, hasInvoice),
        pw.SizedBox(height: 18),
        _section('To raise with NATRAX',
            d.raise.isEmpty ? 'Nothing to raise this month.' : 'Lines where NATRAX charge more than was agreed.'),
        if (d.raise.isNotEmpty) _raiseTable(d),
        pw.SizedBox(height: 18),
        _section('Remarks', d.remarks.isEmpty ? 'No comments recorded on any line.' : 'Every comment given on a line.'),
        if (d.remarks.isNotEmpty) _remarksTable(d),
        if (d.todos.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          _section('Fix in TrackLog', 'Corrections to our own record that the answers point to.'),
          for (final t in d.todos)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                _t('-  ', 9, color: _amber, bold: true),
                pw.Expanded(child: _t(t, 9)),
              ]),
            ),
        ],
        if (d.history.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          _section('History', 'Every decision on the month, newest first.'),
          _historyTable(d),
        ],
      ],
    ));
    return doc.save();
  }

  static pw.Widget _header(ReconReportData d) {
    final status = d.settled
        ? ('SETTLED${d.settledOn == null ? '' : '  ${d.settledOn}'}', _green)
        : (d.stillOpen.isEmpty ? ('READY TO SETTLE', _teal) : ('OPEN - ${d.stillOpen.length} TO DO', _amber));
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: const pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _t('NATRAX RECONCILIATION', 8, color: _cyan, bold: true, spacing: 1.6),
            pw.SizedBox(height: 4),
            _t(d.monthLabel, 22, color: PdfColors.white, bold: true),
            pw.SizedBox(height: 3),
            _t('Goodyear SightLine  ·  NATRAX Proving Ground, Indore', 9,
                color: const PdfColor.fromInt(0xFF94A3B8)),
            pw.SizedBox(height: 8),
            _t(
                [
                  if (d.sheetRef != null && d.sheetRef!.isNotEmpty) 'Sheet ${d.sheetRef}',
                  if (d.invoiceNumber != null) 'Invoice ${d.invoiceNumber}',
                ].join('     '),
                8.5,
                color: const PdfColor.fromInt(0xFFCBD5E1)),
          ]),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: pw.BoxDecoration(
            color: status.$2,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
          ),
          child: _t(status.$1, 8, color: PdfColors.white, bold: true, spacing: 0.8),
        ),
      ]),
    );
  }

  static pw.Widget _figures(ReconReportData d, bool hasInvoice) {
    pw.Widget card(String label, String sub, double? v, PdfColor accent, {bool strong = false}) =>
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 4),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: strong ? const PdfColor.fromInt(0xFFF0FDF4) : PdfColors.white,
              border: pw.Border.all(color: strong ? accent : _line, width: strong ? 1.2 : 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _t(label.toUpperCase(), 7.5, color: _muted, bold: true, spacing: 1),
              pw.SizedBox(height: 4),
              _t(money(v), 16, color: accent, bold: true),
              pw.SizedBox(height: 2),
              _t(sub, 7.5, color: _muted),
            ]),
          ),
        );
    return pw.Column(children: [
      pw.Row(children: [
        if (hasInvoice) ...[
          card('Invoice', '${d.invoiceNumber ?? ''} - before GST', d.invoiceExcl, _ink),
          card('To raise', 'lines disputed', d.toRaise, d.toRaise >= 1 ? _red : _muted),
          card('To pay', 'invoice less what is raised', d.toPay, _green, strong: true),
        ] else ...[
          card("NATRAX's sheet", 'our vehicles', d.sheet, _amber),
          card('Our record', 'TrackLog', d.ours, _teal),
          card('To raise', 'from the sheet', d.toRaise, d.toRaise >= 1 ? _red : _muted),
        ],
      ]),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        pw.SizedBox(width: 4),
        if (hasInvoice) ...[
          _t("NATRAX's sheet  ", 8.5, color: _muted),
          _t(money(d.sheet), 8.5, color: _amber, bold: true),
          _t('      Our record  ', 8.5, color: _muted),
          _t(money(d.ours), 8.5, color: _teal, bold: true),
          _t('      GST  ', 8.5, color: _muted),
          _t((d.invoiceGst ?? 0) < 1 ? 'nil (SEZ, under LUT)' : money(d.invoiceGst), 8.5, bold: true),
        ] else
          _t('Set the final invoice and it leads this report.', 8.5, color: _muted),
      ]),
      if (!d.settled && d.stillOpen.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFFFFBEB),
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: _t('Still open: ${d.stillOpen.join('  ·  ')}', 8.5, color: _amber),
        ),
      ],
    ]);
  }

  static pw.Widget _section(String title, String sub) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Container(width: 3, height: 12, color: _teal),
            pw.SizedBox(width: 6),
            _t(title.toUpperCase(), 9.5, bold: true, spacing: 1),
          ]),
          pw.SizedBox(height: 3),
          _t(sub, 8, color: _muted),
        ]),
      );

  static pw.Widget _cell(String s,
          {bool head = false, bool right = false, PdfColor? color, bool bold = false, double size = 8.5}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(safe(s),
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: head
                ? _s(7, color: _muted, bold: true, spacing: 0.6)
                : _s(size, color: color ?? _ink, bold: bold)),
      );

  static pw.Widget _linesTable(ReconReportData d, bool hasInvoice) {
    PdfColor toneColour(int t) => switch (t) {
          1 => _red,
          2 => _amber,
          3 => _teal,
          _ => _muted,
        };
    double sum(double? Function(ReconReportLine l) f) =>
        d.lines.fold<double>(0, (s, l) => s + (f(l) ?? 0));
    String m(double? v) => v == null || v.abs() < 0.5 ? '-' : money(v);
    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(3.2),
        1: const pw.FlexColumnWidth(1.3),
        2: const pw.FlexColumnWidth(1.3),
        if (hasInvoice) 3: const pw.FlexColumnWidth(1.3),
        if (hasInvoice) 4: const pw.FlexColumnWidth(1.3),
      },
      border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8))),
          children: [
            _cell('LINE', head: true),
            _cell("NATRAX'S SHEET", head: true, right: true),
            _cell('OUR RECORD', head: true, right: true),
            if (hasInvoice) _cell('INVOICE', head: true, right: true),
            if (hasInvoice) _cell('TO PAY', head: true, right: true),
          ],
        ),
        for (var i = 0; i < d.lines.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isOdd ? _zebra : PdfColors.white),
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  _t(d.lines[i].name, 8.5, bold: true),
                  if (d.lines[i].why != null)
                    _t(d.lines[i].why!, 7.2, color: toneColour(d.lines[i].tone)),
                ]),
              ),
              _cell(m(d.lines[i].sheet), right: true, color: _amber),
              _cell(m(d.lines[i].ours), right: true, color: _teal),
              if (hasInvoice) _cell(m(d.lines[i].invoice), right: true),
              if (hasInvoice)
                _cell(m(d.lines[i].toPay),
                    right: true, bold: true, color: d.lines[i].tone == 1 ? _red : _green),
            ],
          ),
        pw.TableRow(
          decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFEFF6FF),
              border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.8))),
          children: [
            _cell('Total', bold: true),
            _cell(m(sum((l) => l.sheet)), right: true, bold: true, color: _amber),
            _cell(m(sum((l) => l.ours)), right: true, bold: true, color: _teal),
            if (hasInvoice) _cell(m(sum((l) => l.invoice)), right: true, bold: true),
            if (hasInvoice) _cell(m(sum((l) => l.toPay)), right: true, bold: true, color: _green),
          ],
        ),
      ],
    );
  }

  static pw.Widget _raiseTable(ReconReportData d) => pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(2.4),
          1: pw.FlexColumnWidth(1.1),
          2: pw.FlexColumnWidth(1.1),
          3: pw.FlexColumnWidth(1.1),
          4: pw.FlexColumnWidth(2.6),
        },
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8))),
            children: [
              _cell('LINE', head: true),
              _cell('CHARGED', head: true, right: true),
              _cell('AGREED', head: true, right: true),
              _cell('TO RAISE', head: true, right: true),
              _cell('WHY', head: true),
            ],
          ),
          for (final r in d.raise)
            pw.TableRow(children: [
              _cell(r.line, bold: true),
              _cell(money(r.charged), right: true),
              _cell(money(r.agreed), right: true),
              _cell(money(r.charged - r.agreed), right: true, bold: true, color: _red),
              _cell(r.comment, size: 8),
            ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEF2F2)),
            children: [
              _cell('Total to raise', bold: true),
              _cell(''),
              _cell(''),
              _cell(money(d.toRaise), right: true, bold: true, color: _red),
              _cell(''),
            ],
          ),
        ],
      );

  static pw.Widget _remarksTable(ReconReportData d) => pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(2.2),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FlexColumnWidth(3.2),
          3: pw.FlexColumnWidth(1.6),
        },
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8))),
            children: [
              _cell('LINE', head: true),
              _cell('DECISION', head: true),
              _cell('COMMENT', head: true),
              _cell('BY / WHEN', head: true),
            ],
          ),
          for (var i = 0; i < d.remarks.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isOdd ? _zebra : PdfColors.white),
              children: [
                _cell('${d.remarks[i].line}\n${d.remarks[i].stage}', size: 8),
                _cell(d.remarks[i].decision, size: 8, color: _green),
                _cell(d.remarks[i].comment, size: 8),
                _cell(d.remarks[i].byWhen, size: 7, color: _muted),
              ],
            ),
        ],
      );

  static pw.Widget _historyTable(ReconReportData d) => pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(1.3),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(2.2),
          3: pw.FlexColumnWidth(3.2),
          4: pw.FlexColumnWidth(1.6),
        },
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8))),
            children: [
              _cell('WHEN', head: true),
              _cell('WHAT', head: true),
              _cell('LINE', head: true),
              _cell('DECISION / COMMENT', head: true),
              _cell('BY', head: true),
            ],
          ),
          for (var i = 0; i < d.history.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: i.isOdd ? _zebra : PdfColors.white),
              children: [
                _cell(d.history[i].when, size: 7.2, color: _muted),
                _cell(d.history[i].action, size: 7.6, bold: true),
                _cell(d.history[i].line, size: 7.6),
                _cell(d.history[i].detail, size: 7.6),
                _cell(d.history[i].by, size: 7, color: _muted),
              ],
            ),
        ],
      );
}

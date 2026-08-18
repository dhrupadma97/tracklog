import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/billing_baseline.dart';
import '../services/invoice_service.dart';
import '../services/natrax_invoice_parser.dart';
import '../services/project_catalog.dart';
import '../services/project_manager.dart';
import '../theme/app_theme.dart';

/// Pick an invoice PDF, read the figures off it, confirm, upload.
///
/// Extracted from the Settings screen so the PO Tracker can offer the same
/// flow — an invoice is most often added while looking at the PO it draws on,
/// and making the user go elsewhere to record it invites it being skipped.
class InvoiceUploadFlow {
  const InvoiceUploadFlow._();

  /// Runs the whole flow. Returns the stored invoice, or null if cancelled.
  ///
  /// [poOptions] are `po_trackers` rows (po_number, category, vendor_name) so
  /// the picker can name what each PO covers. [knownMonths] seed the billing
  /// period list.
  static Future<NatraxInvoice?> start(
    BuildContext context, {
    required List<Map<String, dynamic>> poOptions,
    List<String> knownMonths = const [],
    String? uploadedBy,
    void Function(String message, {bool error})? onMessage,
  }) async {
    void say(String m, {bool error = false}) =>
        onMessage?.call(m, error: error);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true, // web needs the bytes
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.first;
    if (file.bytes == null) {
      say('Could not read that file', error: true);
      return null;
    }

    final parsed = file.name.toLowerCase().endsWith('.pdf')
        ? NatraxInvoiceParser.parse(file.bytes!)
        : const ParsedInvoice(
            missingFields: ['everything — image files cannot be read'],
          );

    if (!context.mounted) return null;

    if (parsed.isUnreadable) {
      final proceed = await _unreadableDialog(context, file.name);
      if (proceed != true || !context.mounted) return null;
    }

    final draft = await _reviewSheet(
      context,
      fileName: file.name,
      parsed: parsed,
      poOptions: poOptions,
      knownMonths: knownMonths,
    );
    if (draft == null) return null;

    try {
      final created = await InvoiceService.instance.upload(
        invoiceNumber: draft.invoiceNumber,
        projectName: draft.projectName,
        amountExclGst: draft.exclGst,
        gstAmount: draft.gst,
        totalAmount: draft.total,
        invoiceDate: draft.invoiceDate,
        periodMonth: draft.periodMonth,
        poNumber: draft.poNumber,
        notes: draft.notes,
        fileBytes: file.bytes,
        fileName: file.name,
        uploadedBy: uploadedBy,
      );
      say('Invoice ${created.invoiceNumber} uploaded ✓');
      return created;
    } catch (e) {
      final msg = e.toString();
      say(
        msg.contains('natrax_invoices_unique_per_project')
            ? 'That invoice number is already uploaded for this project'
            : 'Upload failed — $msg',
        error: true,
      );
      return null;
    }
  }

  /// Shown when a PDF carries no text layer — almost always a scan.
  static Future<bool?> _unreadableDialog(BuildContext context, String fileName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1025),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFFFFB547).withAlpha(70)),
        ),
        title: Row(children: [
          const Icon(Icons.document_scanner_outlined,
              color: Color(0xFFFFB547), size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text('Nothing to read',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
        ]),
        content: Text(
          '$fileName has no text layer, so it is a scanned image rather than a '
          'digital invoice. The figures cannot be read from it automatically.\n\n'
          'A NATRAX invoice from Tally reads itself; invoices from other '
          'vendors often will not. You can continue and fill the amounts in by '
          'hand.',
          style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF8A94B0), fontSize: 12, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB547)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enter by hand',
                style: TextStyle(color: Color(0xFF1A1200))),
          ),
        ],
      ),
    );
  }

  /// Confirms what was read. Every field arrives pre-filled; editing is a
  /// correction path, not the expected way in.
  static Future<InvoiceDraft?> _reviewSheet(
    BuildContext context, {
    required String fileName,
    required ParsedInvoice parsed,
    required List<Map<String, dynamic>> poOptions,
    required List<String> knownMonths,
  }) async {
    final formKey = GlobalKey<FormState>();
    final numCtrl = TextEditingController(text: parsed.invoiceNumber ?? '');
    final exclCtrl = TextEditingController(
        text: parsed.amountExclGst?.toStringAsFixed(2) ?? '');
    final gstCtrl =
        TextEditingController(text: parsed.gstAmount?.toStringAsFixed(2) ?? '');
    final totalCtrl = TextEditingController(
        text: parsed.totalAmount?.toStringAsFixed(2) ?? '');
    final notesCtrl = TextEditingController(text: parsed.testingPeriod ?? '');

    var invoiceDate = parsed.invoiceDate ?? DateTime.now();
    var periodMonth =
        parsed.periodMonth ?? DateFormat('yyyy-MM').format(invoiceDate);
    final periodWasStated = parsed.periodMonth != null;
    var project = ProjectManager.instance.activeProject;

    final poNumbers = poOptions
        .map((r) => (r['po_number'] as String?) ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
    String? poNumber = parsed.poNumber != null &&
            poNumbers.contains(parsed.poNumber)
        ? parsed.poNumber
        : (poNumbers.isNotEmpty ? poNumbers.first : null);

    var gstTouched = parsed.gstAmount != null;
    var totalTouched = parsed.totalAmount != null;

    double parse(TextEditingController c) =>
        double.tryParse(c.text.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;

    void recompute(void Function(void Function()) setLocal) {
      final excl = parse(exclCtrl);
      if (!gstTouched) {
        gstCtrl.text =
            (excl * BillingBaseline.currentGstRate).toStringAsFixed(2);
      }
      if (!totalTouched) {
        totalCtrl.text = (excl + parse(gstCtrl)).toStringAsFixed(2);
      }
      setLocal(() {});
    }

    return showDialog<InvoiceDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final good = parsed.missingFields.isEmpty;
        final accent =
            good ? const Color(0xFF4CAF50) : const Color(0xFFFFB547);
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.primary.withAlpha(50)),
          ),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(parsed.isUnreadable ? 'Invoice details' : 'Read from invoice',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            const SizedBox(height: 2),
            Text(fileName,
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.primary, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (!parsed.isUnreadable) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withAlpha(80)),
                ),
                child: Row(children: [
                  Icon(
                      good
                          ? Icons.auto_awesome_rounded
                          : Icons.error_outline_rounded,
                      size: 14,
                      color: accent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      good
                          ? 'All fields read automatically — check and confirm'
                          : 'Could not read: ${parsed.missingFields.join(', ')}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: accent),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _field(numCtrl, 'Invoice Number *',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: invoiceDate,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setLocal(() => invoiceDate = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Invoice Date (raised on)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                      ),
                      child: Row(children: [
                        Text(DateFormat('dd MMM yyyy').format(invoiceDate),
                            style: const TextStyle(color: Colors.white)),
                        const Spacer(),
                        const Icon(Icons.calendar_today,
                            size: 14, color: Colors.white38),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: periodMonth,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0A1025),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Billing Period (work done in)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      helperText: periodWasStated
                          ? 'From the invoice: ${parsed.testingPeriod ?? ''}'
                          : 'Not stated on the invoice — defaulted to the '
                              'invoice month, check this',
                      helperMaxLines: 2,
                      helperStyle: TextStyle(
                        color: periodWasStated
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFFB547),
                        fontSize: 10,
                      ),
                      enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                    ),
                    items: _periodOptions(knownMonths, periodMonth)
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(monthLabel(m))))
                        .toList(),
                    onChanged: (v) =>
                        setLocal(() => periodMonth = v ?? periodMonth),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: project,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0A1025),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                    ),
                    items: ProjectCatalog.displayNames
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setLocal(() => project = v ?? project),
                  ),
                  const SizedBox(height: 8),
                  if (poOptions.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: poNumber,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF0A1025),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Draws down PO',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                      ),
                      items: poOptions.map((r) {
                        final n = (r['po_number'] as String?) ?? '';
                        final cat = categoryLabel(
                            (r['category'] as String?) ?? 'other');
                        final vendor = (r['vendor_name'] as String?) ?? '';
                        return DropdownMenuItem(
                          value: n,
                          child: Text(
                            'PO # $n · $cat'
                            '${vendor.isEmpty ? '' : ' · ${vendor.length > 18 ? '${vendor.substring(0, 18)}…' : vendor}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setLocal(() => poNumber = v),
                    ),
                  const SizedBox(height: 8),
                  _field(exclCtrl, 'Amount excl. GST (₹) *',
                      keyboard: true,
                      onChanged: (_) => recompute(setLocal),
                      validator: (v) => (double.tryParse((v ?? '')
                                      .replaceAll(RegExp(r'[^0-9.\-]'), '')) ??
                                  0) <=
                              0
                          ? 'Enter the ex-GST amount'
                          : null),
                  _field(gstCtrl, 'GST (₹)', keyboard: true, onChanged: (_) {
                    gstTouched = true;
                    recompute(setLocal);
                  }),
                  _field(totalCtrl, 'Invoice Total (₹) *',
                      keyboard: true,
                      onChanged: (_) {
                        totalTouched = true;
                        setLocal(() {});
                      },
                      validator: (v) => (double.tryParse((v ?? '')
                                      .replaceAll(RegExp(r'[^0-9.\-]'), '')) ??
                                  0) <=
                              0
                          ? 'Enter the invoice total'
                          : null),
                  _field(notesCtrl, 'Notes (optional)'),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(builder: (_) {
                      final off = (parse(exclCtrl) +
                              parse(gstCtrl) -
                              parse(totalCtrl))
                          .abs() >
                          1;
                      return Text(
                        'Bills ${monthLabel(periodMonth)} · '
                        '${off ? "⚠ excl + GST ≠ total" : "excl + GST = total ✓"}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10.5,
                          color: off
                              ? const Color(0xFFFFB547)
                              : const Color(0xFF6B7490),
                        ),
                      );
                    }),
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(
                  ctx,
                  InvoiceDraft(
                    invoiceNumber: numCtrl.text.trim(),
                    invoiceDate: invoiceDate,
                    periodMonth: periodMonth,
                    projectName: project,
                    poNumber: poNumber,
                    exclGst: parse(exclCtrl),
                    gst: parse(gstCtrl),
                    total: parse(totalCtrl),
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  ),
                );
              },
              child: Text(parsed.isUnreadable ? 'Upload' : 'Confirm & Upload'),
            ),
          ],
        );
      }),
    );
  }

  static Widget _field(
    TextEditingController c,
    String label, {
    bool keyboard = false,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboard
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
      ),
    );
  }

  static List<String> _periodOptions(List<String> known, String selected) {
    final options = <String>{...known, selected};
    final now = DateTime.now();
    for (var back = 0; back < 18; back++) {
      final d = DateTime(now.year, now.month - back);
      options.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    return options.toList()..sort((a, b) => b.compareTo(a));
  }

  static String monthLabel(String yyyyMm) {
    final p = yyyyMm.split('-');
    if (p.length != 2) return yyyyMm;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (y == null || m == null) return yyyyMm;
    return DateFormat('MMMM yyyy').format(DateTime(y, m));
  }

  static String categoryLabel(String c) => switch (c) {
        'track_booking' => 'Track booking',
        'manpower' => 'Manpower',
        'workshop' => 'Workshop',
        'instrumentation' => 'Instrumentation',
        _ => 'Uncategorised',
      };
}

/// What the review sheet collected off the printed invoice.
class InvoiceDraft {
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String periodMonth;
  final String projectName;
  final String? poNumber;
  final double exclGst;
  final double gst;
  final double total;
  final String? notes;

  const InvoiceDraft({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.periodMonth,
    required this.projectName,
    required this.poNumber,
    required this.exclGst,
    required this.gst,
    required this.total,
    required this.notes,
  });
}

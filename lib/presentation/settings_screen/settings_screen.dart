import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/billing_baseline.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/invoice_opener.dart';
import '../../services/invoice_service.dart';
import '../../services/natrax_invoice_parser.dart';
import '../../services/project_manager.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../core/app_version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  EngineerProfile? _profile;
  bool _loadingProfile = true;

  // Password
  final _curPassCtrl  = TextEditingController();
  final _newPassCtrl  = TextEditingController();
  final _confPassCtrl = TextEditingController();
  bool _obscureCur = true, _obscureNew = true, _obscureConf = true;
  bool _savingPass = false;

  // Notifications
  bool _notifySession = true;
  bool _notifyReport  = true;
  bool _notifyGate    = false;

  // Export
  String _exportFreq = 'monthly';

  // Original NATRAX invoices
  List<NatraxInvoice> _invoices = [];
  List<String> _poNumbers = [];
  List<String> _activeMonths = []; // 'YYYY-MM', newest first
  bool _loadingInvoices = true;
  bool _uploadingInvoice = false;
  bool _scanning = false;

  static final _inr = NumberFormat.currency(
      locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  bool get _canEditInvoices => !(_profile?.isReadOnly ?? true);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadInvoices();
  }

  @override
  void dispose() {
    _curPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted) setState(() { _profile = p; _loadingProfile = false; });
  }

  Future<void> _changePassword() async {
    final cur  = _curPassCtrl.text.trim();
    final next = _newPassCtrl.text.trim();
    final conf = _confPassCtrl.text.trim();
    if (cur.isEmpty || next.isEmpty || conf.isEmpty) {
      return _snack('Fill in all password fields', error: true);
    }
    if (next.length < 8) return _snack('New password must be ≥ 8 characters', error: true);
    if (next != conf)    return _snack('New passwords do not match', error: true);

    setState(() => _savingPass = true);
    try {
      await EngineerAuthService.instance.signIn(
          email: _profile?.email ?? '', password: cur);
      await SupabaseService.instance.client.auth.updateUser(
          UserAttributes(password: next));
      _curPassCtrl.clear(); _newPassCtrl.clear(); _confPassCtrl.clear();
      _snack('Password updated successfully ✓');
    } catch (_) {
      _snack('Incorrect current password', error: true);
    } finally {
      if (mounted) setState(() => _savingPass = false);
    }
  }

  Future<void> _sendForgotPassword() async {
    final email = _profile?.email ?? '';
    if (email.isEmpty) return _snack('No email on profile', error: true);
    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://sightlinevalidation.web.app',
      );
      _snack('Reset link sent to $email');
    } catch (_) {
      _snack('Could not send reset email', error: true);
    }
  }

  // ─── Original NATRAX invoices ──────────────────────────────────────────────

  Future<void> _loadInvoices() async {
    try {
      final client = SupabaseService.instance.client;
      final invoices = await InvoiceService.instance.list();
      final poRows =
          await client.from('po_trackers').select('po_number').order('created_at');

      // Months that actually had track activity — these are the months an
      // invoice is expected for, so a missing one is visible rather than
      // simply absent from the list.
      final sessionRows = await client
          .from('engineer_sessions')
          .select('started_at, project_name')
          .eq('session_status', 'completed');

      final pm = ProjectManager.instance;
      final months = <String>{};
      for (final row in sessionRows as List) {
        if (!pm.sessionBelongsToProject(row['project_name'] as String?)) continue;
        final started = DateTime.tryParse(row['started_at'] as String? ?? '');
        if (started != null) {
          months.add('${started.year}-'
              '${started.month.toString().padLeft(2, '0')}');
        }
      }
      months.addAll(invoices
          .map((i) => i.periodMonth ?? '')
          .where((m) => m.isNotEmpty));

      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _poNumbers = (poRows as List)
            .map((r) => (r['po_number'] as String?) ?? '')
            .where((p) => p.isNotEmpty)
            .toList();
        _activeMonths = months.toList()..sort((a, b) => b.compareTo(a));
        _loadingInvoices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingInvoices = false);
      _snack('Could not load invoices — $e', error: true);
    }
  }

  Future<void> _openInvoice(NatraxInvoice inv) async {
    final err = await openInvoice(inv);
    if (err != null) _snack(err, error: true);
  }

  Future<void> _confirmDeleteInvoice(NatraxInvoice inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1025),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withAlpha(60)),
        ),
        title: Text('Remove invoice?',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'Invoice ${inv.invoiceNumber} (${_inr.format(inv.totalAmount)}) and its '
          'stored PDF will be deleted. The PO reconciliation will change.',
          style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF8A94B0), fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InvoiceService.instance.delete(inv);
      if (!mounted) return;
      setState(() => _invoices.removeWhere((i) => i.id == inv.id));
      _snack('Invoice ${inv.invoiceNumber} removed');
    } catch (e) {
      _snack('Delete failed — $e', error: true);
    }
  }

  /// Picks the original PDF and reads the figures straight off it.
  ///
  /// Nothing needs typing: the parser fills every field, and the review sheet
  /// exists so a bad scan cannot silently feed wrong numbers into the PO
  /// reconciliation — not to make anyone re-key the invoice.
  Future<void> _uploadInvoice() async {
    if (!_canEditInvoices) {
      return _snack('Managers have read-only access to billing records',
          error: true);
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true, // required so web gets bytes
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    if (file.bytes == null) {
      return _snack('Could not read that file', error: true);
    }

    setState(() => _scanning = true);
    final parsed = file.name.toLowerCase().endsWith('.pdf')
        ? NatraxInvoiceParser.parse(file.bytes!)
        : const ParsedInvoice(
            missingFields: ['everything — image files cannot be read'],
          );
    if (!mounted) return;
    setState(() => _scanning = false);

    if (parsed.isUnreadable) {
      final proceed = await _showUnreadableDialog(file.name);
      if (proceed != true) return;
    }

    final details = await _invoiceReviewSheet(file.name, parsed);
    if (details == null) return;

    setState(() => _uploadingInvoice = true);
    try {
      final created = await InvoiceService.instance.upload(
        invoiceNumber: details.invoiceNumber,
        projectName: details.projectName,
        amountExclGst: details.exclGst,
        gstAmount: details.gst,
        totalAmount: details.total,
        invoiceDate: details.invoiceDate,
        periodMonth: details.periodMonth,
        poNumber: details.poNumber,
        notes: details.notes,
        fileBytes: file.bytes,
        fileName: file.name,
        uploadedBy: _profile?.email,
      );
      if (!mounted) return;
      setState(() {
        _invoices = [created, ..._invoices];
        _uploadingInvoice = false;
      });
      _snack('Invoice ${created.invoiceNumber} uploaded ✓');
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingInvoice = false);
      final msg = e.toString();
      _snack(
        msg.contains('natrax_invoices_unique_per_project')
            ? 'That invoice number is already uploaded for this project'
            : 'Upload failed — $msg',
        error: true,
      );
    }
  }

  /// Shown when a PDF carries no text layer — almost always a scan.
  Future<bool?> _showUnreadableDialog(String fileName) {
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
          'Ask NATRAX for the original PDF from Tally — that one reads itself. '
          'Otherwise you can continue and fill the amounts in by hand.',
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

  /// Shows what was read off the invoice for confirmation.
  ///
  /// Every field arrives pre-filled from [parsed]; the fields stay editable
  /// only as a correction path, not as the expected way in.
  Future<_InvoiceDraft?> _invoiceReviewSheet(
      String fileName, ParsedInvoice parsed) async {
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
    // The billing period is what the work belongs to, which is not the month
    // the invoice was raised in — April testing was billed on 24 June. Keep
    // the period the parser read off "Terms of Delivery" and only fall back to
    // the invoice month when the invoice does not state one.
    var periodMonth = parsed.periodMonth ??
        DateFormat('yyyy-MM').format(invoiceDate);
    final periodWasStated = parsed.periodMonth != null;
    var project = ProjectManager.instance.activeProject;
    String? poNumber = parsed.poNumber != null &&
            _poNumbers.contains(parsed.poNumber)
        ? parsed.poNumber
        : (_poNumbers.isNotEmpty ? _poNumbers.first : null);
    var gstTouched = parsed.gstAmount != null;
    var totalTouched = parsed.totalAmount != null;

    double parse(TextEditingController c) =>
        double.tryParse(c.text.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;

    void recompute(void Function(void Function()) setLocal) {
      final excl = parse(exclCtrl);
      // Nil-rated under SEZ Bond / LUT, so GST defaults to zero rather than
      // 18%. The field stays editable — what the invoice prints always wins.
      if (!gstTouched) {
        gstCtrl.text =
            (excl * BillingBaseline.currentGstRate).toStringAsFixed(2);
      }
      if (!totalTouched) {
        totalCtrl.text = (excl + parse(gstCtrl)).toStringAsFixed(2);
      }
      setLocal(() {});
    }

    return showDialog<_InvoiceDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: (parsed.missingFields.isEmpty
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFFB547))
                        .withAlpha(22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (parsed.missingFields.isEmpty
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFFB547))
                            .withAlpha(80)),
                  ),
                  child: Row(children: [
                    Icon(
                        parsed.missingFields.isEmpty
                            ? Icons.auto_awesome_rounded
                            : Icons.error_outline_rounded,
                        size: 14,
                        color: parsed.missingFields.isEmpty
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFFB547)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        parsed.missingFields.isEmpty
                            ? 'All fields read automatically — check and confirm'
                            : 'Could not read: ${parsed.missingFields.join(', ')}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: parsed.missingFields.isEmpty
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFFB547),
                        ),
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
                    _dialogField(
                      controller: numCtrl,
                      label: 'Invoice Number *',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 4),
                    // When the invoice was raised.
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
                    // Which month the work belongs to — this is what the
                    // month-wise status and the reconciliation key off.
                    DropdownButtonFormField<String>(
                      value: periodMonth,
                      dropdownColor: const Color(0xFF0A1025),
                      style: const TextStyle(color: Colors.white),
                      isExpanded: true,
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
                      items: _periodOptions(periodMonth)
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(_monthLabel(m)),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setLocal(() => periodMonth = v ?? periodMonth),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: project,
                      dropdownColor: const Color(0xFF0A1025),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Project',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                      ),
                      items: const [
                        'Mahindra EV PoC',
                        'Mahindra ICE PoC',
                        'Hyundai PoC',
                      ]
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) =>
                          setLocal(() => project = v ?? project),
                    ),
                    const SizedBox(height: 8),
                    if (_poNumbers.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: poNumber,
                        dropdownColor: const Color(0xFF0A1025),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Draws down PO',
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24)),
                        ),
                        items: _poNumbers
                            .map((p) => DropdownMenuItem(
                                value: p, child: Text('PO # $p')))
                            .toList(),
                        onChanged: (v) => setLocal(() => poNumber = v),
                      ),
                    const SizedBox(height: 8),
                    _dialogField(
                      controller: exclCtrl,
                      label: 'Amount excl. GST (₹) *',
                      keyboard: true,
                      onChanged: (_) => recompute(setLocal),
                      validator: (v) => (double.tryParse(
                                  (v ?? '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ??
                              0) <=
                              0
                          ? 'Enter the ex-GST amount'
                          : null,
                    ),
                    _dialogField(
                      controller: gstCtrl,
                      label: 'GST (₹)',
                      keyboard: true,
                      onChanged: (_) {
                        gstTouched = true;
                        recompute(setLocal);
                      },
                    ),
                    _dialogField(
                      controller: totalCtrl,
                      label: 'Invoice Total (₹) *',
                      keyboard: true,
                      onChanged: (_) {
                        totalTouched = true;
                        setLocal(() {});
                      },
                      validator: (v) => (double.tryParse(
                                  (v ?? '').replaceAll(RegExp(r'[^0-9.\-]'), '')) ??
                              0) <=
                              0
                          ? 'Enter the invoice total'
                          : null,
                    ),
                    _dialogField(
                      controller: notesCtrl,
                      label: 'Notes (optional)',
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Bills ${_monthLabel(periodMonth)} · '
                        '${(parse(exclCtrl) + parse(gstCtrl) - parse(totalCtrl)).abs() > 1 ? "⚠ excl + GST ≠ total" : "excl + GST = total ✓"}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10.5,
                          color: (parse(exclCtrl) +
                                          parse(gstCtrl) -
                                          parse(totalCtrl))
                                      .abs() >
                                  1
                              ? const Color(0xFFFFB547)
                              : const Color(0xFF6B7490),
                        ),
                      ),
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
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(
                    ctx,
                    _InvoiceDraft(
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
        },
      ),
    );
  }

  /// Months offered as the billing period: every month with track activity,
  /// plus a couple either side, with [selected] guaranteed present.
  List<String> _periodOptions(String selected) {
    final options = <String>{..._activeMonths, selected};
    final now = DateTime.now();
    for (var back = 0; back < 18; back++) {
      final d = DateTime(now.year, now.month - back);
      options.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    return options.toList()..sort((a, b) => b.compareTo(a));
  }

  String _monthLabel(String yyyyMm) {
    final parts = yyyyMm.split('-');
    if (parts.length != 2) return yyyyMm;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null) return yyyyMm;
    return DateFormat('MMMM yyyy').format(DateTime(y, m));
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    bool keyboard = false,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
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

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.spaceGrotesk(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background ambient glows
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 480,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.12), // Primary/Cyan glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: Container(
              width: 400,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFA855F7).withOpacity(0.10), // Purple glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: _loadingProfile
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildPageHeader()),
                      SliverToBoxAdapter(child: _buildProfileCard()),
                      SliverToBoxAdapter(child: _sectionLabel('COMMUNICATION')),
                      SliverToBoxAdapter(child: _buildCommunicationSection()),
                      SliverToBoxAdapter(child: _sectionLabel('PREFERENCES')),
                      SliverToBoxAdapter(child: _buildNotificationsSection()),
                      SliverToBoxAdapter(child: _buildExportSection()),
                      SliverToBoxAdapter(child: _sectionLabel('BILLING')),
                      SliverToBoxAdapter(child: _buildInvoicesSection()),
                      SliverToBoxAdapter(child: _sectionLabel('SECURITY')),
                      SliverToBoxAdapter(child: _buildSecuritySection()),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Page header ───────────────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(70)),
          ),
          child: const Icon(Icons.settings_rounded, color: AppTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Settings', style: GoogleFonts.spaceGrotesk(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: const Color(0xFFdfe2f0))),
            Text('Account, preferences & communication',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: const Color(0xFF6B7490))),
          ]),
        ),
        Image.asset(
          'assets/images/goodyear_sightline_logo.png',
          height: 18,
          color: Colors.white70,
          fit: BoxFit.contain,
        ),
      ]),
    );
  }

  // ─── Section label ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Text(label, style: GoogleFonts.spaceGrotesk(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: const Color(0xFF6B7490), letterSpacing: 2)),
  );

  // ─── Profile card ──────────────────────────────────────────────────────────

  Widget _buildProfileCard() {
    final name    = _profile?.engineerName ?? 'Engineer';
    final email   = _profile?.email ?? '';
    final dept    = _profile?.department ?? 'Tyre Testing';
    final isAdmin = _profile?.isManager ?? false;

    return _card(
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withAlpha(90), AppTheme.primary.withAlpha(30)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withAlpha(100)),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'E',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.spaceGrotesk(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: const Color(0xFFdfe2f0)),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(email, style: GoogleFonts.spaceGrotesk(
              fontSize: 12, color: const Color(0xFFA8B0C8)),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            _badge(dept, AppTheme.info),
            _badge(isAdmin ? 'Manager' : 'Engineer',
                isAdmin ? const Color(0xFFFFB547) : AppTheme.primary),
          ]),
        ])),
      ]),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withAlpha(80)),
    ),
    child: Text(label, style: GoogleFonts.spaceGrotesk(
        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );

  // ─── Account section (Change Password) ────────────────────────────────────

  Widget _buildAccountSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.lock_outline_rounded, 'Change Password'),
        const SizedBox(height: 16),
        _passField(_curPassCtrl,  'Current Password',     _obscureCur,
            () => setState(() => _obscureCur  = !_obscureCur)),
        const SizedBox(height: 12),
        _passField(_newPassCtrl,  'New Password',         _obscureNew,
            () => setState(() => _obscureNew  = !_obscureNew)),
        const SizedBox(height: 12),
        _passField(_confPassCtrl, 'Confirm New Password', _obscureConf,
            () => setState(() => _obscureConf = !_obscureConf)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingPass ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF001A10),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _savingPass
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF001A10)))
                : Text('Update Password', style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _passField(TextEditingController ctrl, String label, bool obscure,
      VoidCallback onToggle) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 12),
        filled: true,
        fillColor: Colors.white.withAlpha(6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        suffixIcon: GestureDetector(
          onTap: onToggle,
          child: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: const Color(0xFF6B7490), size: 18),
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(20))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(15))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }

  // ─── Communication section ─────────────────────────────────────────────────

  Widget _buildCommunicationSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.hub_outlined, 'Communication Hub'),
        const SizedBox(height: 4),
        Text('Purchase orders, email reports and team communication',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
        const SizedBox(height: 16),
        _navRow(
          icon: Icons.receipt_long_rounded,
          iconColor: const Color(0xFF4A9EFF),
          title: 'PO Tracker',
          subtitle: 'Purchase orders, utilisation & attachments',
          onTap: () => context.push(AppRoutes.poTracker),
        ),
        _divider(),
        _navRow(
          icon: Icons.email_rounded,
          iconColor: const Color(0xFF4CAF50),
          title: 'Email Reports',
          subtitle: 'Send NATRAX expense updates to Harsh & team',
          onTap: () => context.push(AppRoutes.emailReports),
        ),
        _divider(),
        _navRow(
          icon: Icons.location_on_rounded,
          iconColor: const Color(0xFFFF9800),
          title: 'Gate Management',
          subtitle: 'Configure geofenced track entry gates',
          onTap: () => context.go(AppRoutes.gateManagement),
        ),
        _divider(),
        _navRow(
          icon: Icons.campaign_rounded,
          iconColor: AppTheme.primary,
          title: 'Project Updates',
          subtitle: 'Bulletin board — milestones, alerts, attachments',
          onTap: () => context.go(AppRoutes.projectUpdates),
        ),
      ]),
    );
  }

  Widget _navRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconColor.withAlpha(50)),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.spaceGrotesk(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0))),
            Text(subtitle, style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
          ])),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: const Color(0xFF4A5470)),
        ]),
      ),
    );
  }

  Widget _divider() => Container(
    height: 1, color: const Color(0xFF2A3450),
    margin: const EdgeInsets.symmetric(vertical: 2),
  );

  // ─── Notifications section ─────────────────────────────────────────────────

  Widget _buildNotificationsSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.notifications_outlined, 'Notification Preferences'),
        const SizedBox(height: 14),
        _toggleRow(
          icon: Icons.timer_outlined,
          color: AppTheme.primary,
          label: 'Session Alerts',
          subtitle: 'Session start and end notifications',
          value: _notifySession,
          onChanged: (v) => setState(() => _notifySession = v),
        ),
        _toggleRow(
          icon: Icons.email_outlined,
          color: const Color(0xFF4CAF50),
          label: 'Report Ready',
          subtitle: 'Notify when an email report is sent',
          value: _notifyReport,
          onChanged: (v) => setState(() => _notifyReport = v),
        ),
        _toggleRow(
          icon: Icons.location_on_outlined,
          color: const Color(0xFFFFB547),
          label: 'Gate Alerts',
          subtitle: 'Entry / exit gate notifications',
          value: _notifyGate,
          onChanged: (v) => setState(() => _notifyGate = v),
        ),
      ]),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: const Color(0xFFdfe2f0))),
          Text(subtitle, style: GoogleFonts.spaceGrotesk(
              fontSize: 11, color: const Color(0xFF6B7490))),
        ])),
        Switch(
          value: value, onChanged: onChanged,
          activeColor: AppTheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }

  // ─── Export section ────────────────────────────────────────────────────────

  Widget _buildExportSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.download_rounded, 'Export Frequency'),
        const SizedBox(height: 6),
        Text('How often activity reports are exported and sent.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _freqChip('monthly', 'Monthly',
              Icons.calendar_month_outlined, 'Every month')),
          const SizedBox(width: 10),
          Expanded(child: _freqChip('yearly', 'Yearly',
              Icons.calendar_today_outlined, 'Once a year')),
        ]),
      ]),
    );
  }

  Widget _freqChip(String val, String label, IconData icon, String sub) {
    final sel = _exportFreq == val;
    return GestureDetector(
      onTap: () => setState(() => _exportFreq = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primary.withAlpha(25) : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? AppTheme.primary.withAlpha(150) : Colors.white.withAlpha(15),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon,
                color: sel ? AppTheme.primary : const Color(0xFF6B7490), size: 18),
            const Spacer(),
            if (sel) Container(
              width: 16, height: 16,
              decoration: const BoxDecoration(
                  color: AppTheme.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 10, color: Color(0xFF001A10)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: sel ? AppTheme.primary : const Color(0xFFdfe2f0))),
          Text(sub, style: GoogleFonts.spaceGrotesk(
              fontSize: 10, color: const Color(0xFF6B7490))),
        ]),
      ),
    );
  }

  // ─── Original invoices ─────────────────────────────────────────────────────

  Widget _buildInvoicesSection() {
    final totals = InvoiceTotals.from(_invoices);

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: _cardTitle(
                  Icons.receipt_long_rounded, 'Original NATRAX Invoices')),
          if (_canEditInvoices)
            GestureDetector(
              onTap: (_uploadingInvoice || _scanning) ? null : _uploadInvoice,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withAlpha(90)),
                ),
                child: (_uploadingInvoice || _scanning)
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary)),
                        const SizedBox(width: 7),
                        Text(_scanning ? 'Reading…' : 'Uploading…',
                            style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ])
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.document_scanner_outlined,
                            size: 13, color: AppTheme.primary),
                        const SizedBox(width: 5),
                        Text('Scan & Upload',
                            style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          _canEditInvoices
              ? 'Pick the PDF and the figures are read off it — no typing. The '
                  'PO Tracker reconciles its computed spend against these '
                  'billed amounts.'
              : 'Invoices raised by NATRAX. Read-only for managers.',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 11, color: const Color(0xFF6B7490), height: 1.45),
        ),
        const SizedBox(height: 14),

        if (!_loadingInvoices && _activeMonths.isNotEmpty) ...[
          _buildMonthStatusGrid(),
          const SizedBox(height: 16),
        ],

        if (_loadingInvoices)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))),
          )
        else if (_invoices.isEmpty && _activeMonths.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Column(children: [
              Icon(Icons.description_outlined,
                  size: 26, color: Colors.white.withAlpha(50)),
              const SizedBox(height: 8),
              Text('No invoices uploaded yet',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8A94B0))),
              const SizedBox(height: 3),
              Text(
                  'Until an original is uploaded, the PO balance rests on '
                  'app-computed costs alone.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10.5, color: const Color(0xFF6B7490))),
            ]),
          )
        else ...[
          ..._invoices.map(_invoiceTile),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2A3450), height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Text('${totals.count} invoice${totals.count == 1 ? '' : 's'}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8A94B0))),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Total billed  ${_inr.format(totals.total)}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary)),
              Text(
                  '${_inr.format(totals.exclGst)} excl. GST  ·  '
                  '${_inr.format(totals.gst)} GST',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, color: const Color(0xFF6B7490))),
            ]),
          ]),
        ],
      ]),
    );
  }

  /// One row per month that had track activity, so a month with no invoice
  /// reads as a gap rather than simply being absent from the list.
  Widget _buildMonthStatusGrid() {
    final byMonth = <String, List<NatraxInvoice>>{};
    for (final inv in _invoices) {
      final m = inv.periodMonth;
      if (m == null || m.isEmpty) continue;
      byMonth.putIfAbsent(m, () => []).add(inv);
    }

    final covered = _activeMonths.where(byMonth.containsKey).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('MONTH-WISE STATUS',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: const Color(0xFF6B7490))),
        const Spacer(),
        Text('$covered of ${_activeMonths.length} invoiced',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: covered == _activeMonths.length
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFFB547))),
      ]),
      const SizedBox(height: 9),
      ..._activeMonths.map((month) => _monthRow(month, byMonth[month])),
    ]);
  }

  Widget _monthRow(String month, List<NatraxInvoice>? invoices) {
    final has = invoices != null && invoices.isNotEmpty;
    final total = has ? invoices.fold(0.0, (s, i) => s + i.totalAmount) : 0.0;
    final accent =
        has ? const Color(0xFF4CAF50) : const Color(0xFFFFB547);

    final parts = month.split('-');
    final label = parts.length == 2
        ? DateFormat('MMM yyyy').format(
            DateTime(int.parse(parts[0]), int.parse(parts[1])))
        : month;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GestureDetector(
        onTap: has && invoices.first.hasFile
            ? () => _openInvoice(invoices.first)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withAlpha(has ? 14 : 10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withAlpha(has ? 55 : 45)),
          ),
          child: Row(children: [
            Icon(has ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 15, color: accent),
            const SizedBox(width: 10),
            SizedBox(
              width: 66,
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text(
                has
                    ? invoices.map((i) => i.invoiceNumber).join(', ')
                    : 'No invoice uploaded',
                style: GoogleFonts.spaceGrotesk(
                    color: has ? const Color(0xFF8A94B0) : accent,
                    fontSize: 10.5,
                    fontWeight: has ? FontWeight.w500 : FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(has ? _inr.format(total) : '—',
                style: GoogleFonts.spaceGrotesk(
                    color: has ? Colors.white : const Color(0xFF4A5470),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            if (has && invoices.first.hasFile) ...[
              const SizedBox(width: 6),
              Icon(Icons.remove_red_eye_outlined,
                  size: 13, color: AppTheme.primary.withAlpha(160)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _invoiceTile(NatraxInvoice inv) {
    final flagged = inv.isInternallyInconsistent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: flagged
                  ? const Color(0xFFFFB547).withAlpha(90)
                  : Colors.white.withAlpha(15)),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                inv.hasFile
                    ? Icons.picture_as_pdf_rounded
                    : Icons.receipt_outlined,
                size: 17,
                color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Invoice ${inv.invoiceNumber}',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                [
                  if (inv.invoiceDate != null)
                    DateFormat('dd MMM yyyy').format(inv.invoiceDate!),
                  if ((inv.periodMonth ?? '').isNotEmpty) inv.periodMonth!,
                  if ((inv.poNumber ?? '').isNotEmpty) 'PO ${inv.poNumber}',
                ].join(' · '),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: const Color(0xFF6B7490)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (flagged)
                Text('⚠ excl + GST ≠ total',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 9.5, color: const Color(0xFFFFB547))),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_inr.format(inv.totalAmount),
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            Text('${_inr.format(inv.amountExclGst)} + GST',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9.5, color: const Color(0xFF6B7490))),
          ]),
          if (inv.hasFile)
            IconButton(
              onPressed: () => _openInvoice(inv),
              icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
              color: AppTheme.primary,
              tooltip: 'View original',
              visualDensity: VisualDensity.compact,
            ),
          if (_canEditInvoices)
            IconButton(
              onPressed: () => _confirmDeleteInvoice(inv),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              color: Colors.redAccent.withAlpha(180),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
        ]),
      ),
    );
  }

  // ─── Security / Forgot Password ────────────────────────────────────────────

  Widget _buildSecuritySection() {
    return _card(
      borderColor: Colors.redAccent.withAlpha(60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.security_rounded, 'Security', color: Colors.redAccent),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.redAccent.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withAlpha(40)),
          ),
          child: Row(children: [
            const Icon(Icons.lock_reset_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Forgot Password',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              Text('Send a reset link to ${_profile?.email ?? 'your email'}',
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF8A94B0), fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendForgotPassword,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withAlpha(80)),
                ),
                child: Text('Send Link',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.redAccent, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // Sign out row
        GestureDetector(
          onTap: () async {
            await EngineerAuthService.instance.signOut();
            if (mounted) context.go('/login');
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(10)),
            ),
            child: Row(children: [
              Icon(Icons.logout_rounded,
                  color: Colors.white.withAlpha(150), size: 18),
              const SizedBox(width: 12),
              Text('Sign Out',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white.withAlpha(150),
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: Colors.white.withAlpha(60)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('TrackLog v${AppVersion.display} · NATRAX Proving Ground',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, color: const Color(0xFF3A4060))),
        ),
      ]),
    );
  }

  // ─── Shared helpers ────────────────────────────────────────────────────────

  Widget _card({required Widget child, Color? borderColor}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: borderColor ?? const Color(0xFF849495).withAlpha(80)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _cardTitle(IconData icon, String title, {Color? color}) {
    final c = color ?? AppTheme.primary;
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: c.withAlpha(22),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.withAlpha(60)),
        ),
        child: Icon(icon, color: c, size: 15),
      ),
      const SizedBox(width: 10),
      Text(title, style: GoogleFonts.spaceGrotesk(
          fontSize: 14, fontWeight: FontWeight.w800,
          color: const Color(0xFFdfe2f0))),
    ]);
  }
}

/// What the upload dialog collected off the printed invoice.
class _InvoiceDraft {
  final String invoiceNumber;
  final DateTime invoiceDate;
  final String periodMonth;
  final String projectName;
  final String? poNumber;
  final double exclGst;
  final double gst;
  final double total;
  final String? notes;

  const _InvoiceDraft({
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

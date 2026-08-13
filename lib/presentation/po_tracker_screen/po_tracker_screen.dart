import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_export.dart';
import '../../routes/app_routes.dart';
import '../../services/supabase_service.dart';
import '../../services/project_manager.dart';
import '../../services/invoice_service.dart';
import '../../services/invoice_opener.dart';
import '../../services/billing_baseline.dart';
import '../../services/po_document_service.dart';
import '../../services/engineer_auth_service.dart';
import '../../widgets/invoice_upload_flow.dart';

class PoTrackerScreen extends StatefulWidget {
  const PoTrackerScreen({super.key});

  @override
  State<PoTrackerScreen> createState() => _PoTrackerScreenState();
}

class _PoTrackerScreenState extends State<PoTrackerScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;

  // PO data
  List<Map<String, dynamic>> _poList = [];
  List<_PoAttachment> _customAttachments = [];

  // Spend data
  double _trackSessionsSpend = 0;
  double _additionalServicesSpend = 0;
  double _workshopSpend = 0;
  double _vehicleValidationSpend = 0;
  double _instrumentationSpend = 0;
  int _totalSessions = 0;

  /// Sessions whose live cost was actually added. Sessions in months the
  /// baseline covers are counted in [_totalSessions] but not costed, so the
  /// two must not be conflated in the UI.
  int _costedSessions = 0;

  bool _uploadingInvoice = false;

  /// GST rate the computed spend is grossed up at. Session costs and the
  /// hardcoded overrides are all stored ex-GST, while PO values carry tax
  /// separately — the two must be compared on the same basis.
  static const double _gstRate = 0.18;

  /// Originals for the active project — used against the monthly baseline.
  List<NatraxInvoice> _invoices = [];

  /// Every original on file, whichever vehicle it was raised for. POs are
  /// shared funding pools, so their drawdown must count all of them.
  List<NatraxInvoice> _allInvoices = [];

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = SupabaseService.instance.client;

      // Load PO details
      final poData = await client
          .from('po_trackers')
          .select()
          .order('created_at');

      _poList = List<Map<String, dynamic>>.from(poData);

      // Load cumulative track session costs
      final sessionsData = await client
          .from('engineer_sessions')
          .select('id, total_cost, session_status, project_name, started_at')
          .eq('session_status', 'completed');

      // Load additional services spend
      final servicesData = await client
          .from('session_additional_services')
          .select('session_id, total_cost');

      final Map<String, double> svcCostMap = {};
      for (final s in servicesData as List) {
        final sid = s['session_id'] as String;
        final cost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        svcCostMap[sid] = (svcCostMap[sid] ?? 0.0) + cost;
      }

      final pm = ProjectManager.instance;
      final activeProjName = pm.activeProject;

      double trackTotal = 0;
      double servicesTotal = 0;
      int sessionCount = 0;

      // Months the baseline already accounts for — their live session costs
      // must be suppressed or they would be counted twice.
      final covered = BillingBaseline.coveredMonths(activeProjName);
      var costedSessions = 0;

      for (final s in sessionsData as List) {
        final rawProj = (s['project_name'] as String?)?.trim() ?? '';
        if (!pm.sessionBelongsToProject(rawProj)) continue;

        final sid = s['id'] as String;
        final track = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        final svc = svcCostMap[sid] ?? 0.0;
        final startDt = DateTime.tryParse(s['started_at'] as String? ?? '');

        sessionCount++;

        final monthKey = startDt == null
            ? null
            : '${startDt.year}-${startDt.month.toString().padLeft(2, '0')}';
        if (monthKey != null && covered.contains(monthKey)) continue;

        costedSessions++;
        trackTotal += track;
        servicesTotal += svc;
      }

      // The baseline is split track/accessories the same way the Analyser
      // reports it; the PO Tracker shows the two lines separately.
      final accessories = BillingBaseline.accessoriesTotal(activeProjName);
      trackTotal +=
          BillingBaseline.trackAndAccessoriesTotal(activeProjName) - accessories;
      servicesTotal += accessories;
      _workshopSpend = BillingBaseline.workshopTotal(activeProjName);

      final extras = BillingBaseline.extrasForProject(activeProjName);
      _vehicleValidationSpend = extras.isNotEmpty ? extras[0].exclGst : 0.0;
      _instrumentationSpend = extras.length > 1 ? extras[1].exclGst : 0.0;

      _trackSessionsSpend = trackTotal;
      _additionalServicesSpend = servicesTotal;
      _totalSessions = sessionCount;
      _costedSessions = costedSessions;

      // Two views of the same invoices, and the distinction matters.
      //
      // A PO is drawn down by every invoice that names it, whichever vehicle
      // was on test — that is what makes the remaining amount bookable. The
      // month-by-month reconciliation, by contrast, compares against a
      // baseline that only exists for this project, so it uses the scoped set.
      try {
        _allInvoices = await InvoiceService.instance.list();
        _invoices = _allInvoices
            .where((i) =>
                i.projectName.toLowerCase().trim() ==
                pm.activeProject.toLowerCase().trim())
            .toList();
      } catch (_) {
        _allInvoices = [];
        _invoices = [];
      }

      setState(() => _loading = false);
      _animController.forward();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Everything the app has costed, **before tax** — session `total_cost`, the
  /// additional-services rows and the historical overrides are all ex-GST.
  double get _totalSpend =>
      _trackSessionsSpend +
      _additionalServicesSpend +
      _workshopSpend +
      _vehicleValidationSpend +
      _instrumentationSpend;

  /// The same spend grossed up, so it can be set against a tax-inclusive PO.
  double get _totalSpendInclGst => _totalSpend * (1 + _gstRate);

  /// Every PO is a funding pool, not a programme allocation.
  ///
  /// Track booking runs back to back against whatever is left, so a PO is
  /// drawn down by whichever vehicle is on test at the time. Only the original
  /// Mahindra EV PoC PO was raised against a named programme. Scoping the
  /// balance by project would therefore hide funding that is genuinely
  /// available for the next booking.
  List<Map<String, dynamic>> get _projectPos => _poList;

  /// The PO that uninvoiced work will be billed against.
  ///
  /// Only inferred when the programme has exactly one funded PO — with more
  /// than one it is genuinely ambiguous which will be drawn on, and guessing
  /// would put a forecast on the wrong PO.
  String? get _forecastPo {
    final funded = _projectPos.where((p) {
      final val = (p['total_po_value'] as num?)?.toDouble() ?? 0;
      final tax = (p['tax_amount'] as num?)?.toDouble() ?? 0;
      return val + tax > 0;
    }).toList();
    if (funded.length != 1) return null;
    return (funded.first['po_number'] as String? ?? '').trim();
  }

  /// A PO that has been fully consumed offers nothing for future booking.
  ///
  /// It stays on the list because its invoices are real history, but it is
  /// excluded from the funding maths entirely — recording its value later must
  /// not make spent money reappear as headroom.
  static bool _isExhausted(Map<String, dynamic> po) {
    final s = (po['po_status'] as String? ?? '').toLowerCase().trim();
    return s == 'used' || s == 'closed' || s == 'exhausted';
  }

  /// POs that can still be booked against: not exhausted, and with a value on
  /// record. A PO whose value is unknown cannot be counted as funding.
  List<Map<String, dynamic>> get _bookablePos => _poList.where((p) {
        if (_isExhausted(p)) return false;
        final val = (p['total_po_value'] as num?)?.toDouble() ?? 0;
        final tax = (p['tax_amount'] as num?)?.toDouble() ?? 0;
        return val + tax > 0;
      }).toList();

  double get _totalPoWithTax {
    double total = 0;
    for (final po in _bookablePos) {
      final val = (po['total_po_value'] as num?)?.toDouble() ?? 0;
      final tax = (po['tax_amount'] as num?)?.toDouble() ?? 0;
      total += val + tax;
    }
    return total;
  }

  /// Drawdown against bookable POs only — the counterpart to
  /// [_totalPoWithTax]. Invoices against an exhausted PO are history, not a
  /// claim on what remains.
  double get _drawdownAgainstBookable {
    var sum = 0.0;
    for (final po in _bookablePos) {
      sum += _invoicedAgainst((po['po_number'] as String? ?? '').trim());
    }
    return sum;
  }

  /// Drawdown across every PO — all invoices, all vehicles.
  InvoiceTotals get _invoiceTotals => InvoiceTotals.from(_allInvoices);
  bool get _hasInvoices => _allInvoices.isNotEmpty;

  /// Invoices grouped by the PO they name, so each PO's own drawdown is
  /// visible. Tally prints this as "Buyer's Order No."; the parser stores it.
  Map<String, List<NatraxInvoice>> get _invoicesByPo {
    final map = <String, List<NatraxInvoice>>{};
    for (final inv in _allInvoices) {
      final po = (inv.poNumber ?? '').trim();
      if (po.isEmpty) continue;
      map.putIfAbsent(po, () => []).add(inv);
    }
    return map;
  }

  double _invoicedAgainst(String poNumber) =>
      (_invoicesByPo[poNumber] ?? const [])
          .fold(0.0, (s, i) => s + i.totalAmount);

  /// Invoices naming a PO that is not loaded in the tracker — their spend is
  /// real but cannot be attributed, so it must not be silently dropped.
  List<NatraxInvoice> get _unattributedInvoices {
    final known = _poList
        .map((p) => (p['po_number'] as String? ?? '').trim())
        .where((p) => p.isNotEmpty)
        .toSet();
    return _allInvoices
        .where((i) => !known.contains((i.poNumber ?? '').trim()))
        .toList();
  }

  /// Invoiced totals keyed by billing period.
  Map<String, double> get _invoicedByMonth {
    final map = <String, double>{};
    for (final inv in _invoices) {
      final m = inv.periodMonth;
      if (m == null || m.isEmpty) continue;
      map[m] = (map[m] ?? 0) + inv.totalAmount;
    }
    return map;
  }

  /// Months the baseline costs but NATRAX has not invoiced yet.
  ///
  /// Keeping these out of the drawdown is the whole point: three months of
  /// computed spend measured against two months of invoices is not an overrun,
  /// it is work that has not been billed.
  List<MonthBaseline> get _uninvoicedMonths {
    final invoiced = _invoicedByMonth;
    return BillingBaseline.forProject(ProjectManager.instance.activeProject)
        .where((m) => !invoiced.containsKey(m.month))
        .toList()
      ..sort((a, b) => a.month.compareTo(b.month));
  }

  double get _notYetBilledInclGst =>
      _uninvoicedMonths.fold(0.0, (s, m) => s + m.inclGst);

  /// Costs carried against the project that no invoice covers.
  double get _extrasInclGst =>
      BillingBaseline.extrasTotal(ProjectManager.instance.activeProject) *
          (1 + _gstRate);

  /// Variance for invoiced months only — the one comparison that is like for
  /// like. Positive means NATRAX billed more than the baseline expected.
  double get _invoicedMonthsVariance {
    final invoiced = _invoicedByMonth;
    var variance = 0.0;
    for (final m
        in BillingBaseline.forProject(ProjectManager.instance.activeProject)) {
      final billed = invoiced[m.month];
      if (billed == null) continue;
      variance += billed - m.inclGst;
    }
    return variance;
  }

  /// What the balance becomes once the uninvoiced months are billed at the
  /// baseline rate.
  double get _projectedBalance => _remainingBalance - _notYetBilledInclGst;

  /// What the PO has actually been drawn down by, tax inclusive.
  ///
  /// Uploaded originals are authoritative whenever they exist — they are what
  /// NATRAX billed. Without them we fall back to the app's computed spend,
  /// which is an estimate built from durations and rate cards.
  double get _drawdownInclGst =>
      _hasInvoices ? _drawdownAgainstBookable : _totalSpendInclGst;

  double get _remainingBalance => _totalPoWithTax - _drawdownInclGst;

  double get _utilizationPercent => _totalPoWithTax > 0
      ? (_drawdownInclGst / _totalPoWithTax).clamp(0.0, 1.0)
      : 0.0;

  /// Records an invoice against one of the POs on this screen.
  Future<void> _addInvoice() async {
    setState(() => _uploadingInvoice = true);
    final created = await InvoiceUploadFlow.start(
      context,
      poOptions: _poList,
      knownMonths: BillingBaseline.forProject(
              ProjectManager.instance.activeProject)
          .map((m) => m.month)
          .toList(),
      uploadedBy: EngineerAuthService.instance.currentUser?.email,
      onMessage: (m, {bool error = false}) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(m),
          backgroundColor: error ? AppTheme.error : AppTheme.success,
        ));
      },
    );
    if (!mounted) return;
    setState(() => _uploadingInvoice = false);
    // Reload so the PO drawdown, reconciliation and balance all move together.
    if (created != null) _loadData();
  }

  Future<void> _showAddPoDialog() async {
    final formKey = GlobalKey<FormState>();
    String poNumber = '';
    String vendorName = '';
    String description = '';
    double totalPoValue = 0;
    double taxAmount = 0;
    DateTime deliveryDate = DateTime.now().add(const Duration(days: 30));

    // What the PO covers and where it stands. Without these a new PO lands as
    // uncategorised, and the track-versus-manpower split cannot be answered.
    var category = 'track_booking';
    var poStatus = 'active';
    PlatformFile? attachment;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.primary.withAlpha(50)),
          ),
          title: Text(
            'Add New PO',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: category,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0A1025),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'What does this PO cover?',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'track_booking', child: Text('Track booking')),
                      DropdownMenuItem(
                          value: 'manpower', child: Text('Manpower')),
                      DropdownMenuItem(
                          value: 'workshop', child: Text('Workshop')),
                      DropdownMenuItem(
                          value: 'instrumentation',
                          child: Text('Instrumentation')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setLocal(() => category = v ?? category),
                  ),
                  DropdownButtonFormField<String>(
                    value: poStatus,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF0A1025),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'active', child: Text('Active — can be booked against')),
                      DropdownMenuItem(
                          value: 'upcoming', child: Text('Upcoming — not yet live')),
                      DropdownMenuItem(
                          value: 'used', child: Text('Used — fully consumed')),
                      DropdownMenuItem(
                          value: 'closed', child: Text('Closed')),
                    ],
                    onChanged: (v) => setLocal(() => poStatus = v ?? poStatus),
                  ),
                  TextFormField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'PO Number',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    onSaved: (val) => poNumber = val ?? '',
                    validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Vendor Name',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    onSaved: (val) => vendorName = val ?? '',
                    validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description (e.g. Track Usage)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    onSaved: (val) => description = val ?? '',
                  ),
                  TextFormField(
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Base Value (₹)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    onSaved: (val) => totalPoValue = double.tryParse(val ?? '0') ?? 0,
                  ),
                  TextFormField(
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tax Amount (₹)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    onSaved: (val) => taxAmount = double.tryParse(val ?? '0') ?? 0,
                  ),
                  const SizedBox(height: 16),
                  // The PO document itself, so the figures above can be
                  // checked against the paperwork they came from.
                  GestureDetector(
                    onTap: () async {
                      final res = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                        withData: true,
                      );
                      if (res != null && res.files.isNotEmpty) {
                        setLocal(() => attachment = res.files.first);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(18),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: AppTheme.primary.withAlpha(80)),
                      ),
                      child: Row(children: [
                        Icon(
                            attachment == null
                                ? Icons.attach_file_rounded
                                : Icons.picture_as_pdf_rounded,
                            size: 15,
                            color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            attachment?.name ?? 'Attach PO document (optional)',
                            style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (attachment != null)
                          GestureDetector(
                            onTap: () => setLocal(() => attachment = null),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: Colors.white54),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () async {
                if (formKey.currentState?.validate() == true) {
                  formKey.currentState?.save();
                  try {
                    final row = <String, dynamic>{
                      'po_number': poNumber,
                      'vendor_name': vendorName,
                      'description': description,
                      'total_po_value': totalPoValue,
                      'tax_amount': taxAmount,
                      'delivery_date': deliveryDate.toIso8601String().split('T')[0],
                      'category': category,
                      'po_status': poStatus,
                    };

                    // Upload the document first — if that fails the PO is not
                    // created, rather than landing without the paperwork it
                    // was meant to carry.
                    final file = attachment;
                    if (file?.bytes != null) {
                      row.addAll(await PoDocumentService.instance.upload(
                        poNumber: poNumber,
                        bytes: file!.bytes!,
                        fileName: file.name,
                      ));
                    }

                    await SupabaseService.instance.client
                        .from('po_trackers')
                        .insert(row);
                    if (mounted) {
                      Navigator.of(ctx).pop();
                      _loadData();
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      // Both actions live here permanently. An invoice is nearly always added
      // while looking at the PO it draws on, and sending the user to Settings
      // to record it invites it being put off.
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add_invoice',
            onPressed: _uploadingInvoice ? null : _addInvoice,
            backgroundColor: const Color(0xFF0A1025),
            foregroundColor: AppTheme.primary,
            elevation: 3,
            icon: _uploadingInvoice
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))
                : const Icon(Icons.document_scanner_outlined, size: 17),
            label: Text('Add invoice',
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_po',
            onPressed: _showAddPoDialog,
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.post_add_rounded, size: 18),
            label: Text('Add PO',
                style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Goodyear background
          Positioned.fill(
            child: Image.asset(
              'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(color: const Color(0xFF050811).withAlpha(215)),
          ),
          SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
            : _error != null
            ? _buildError()
            : FadeTransition(
                opacity: _fadeAnim,
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppTheme.primary,
                  backgroundColor: const Color(0xFF0A1025),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 20),
                              if (_poList.isEmpty)
                                Center(
                                  child: Text('No POs found', style: GoogleFonts.spaceGrotesk(color: Colors.white54)),
                                ),
                              ..._projectPos.map((po) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildPoInfoCard(po),
                              )),
                              _buildUnattributedWarning(),
                              _buildBalanceSummaryCard(),
                              const SizedBox(height: 16),
                              _buildReconciliationCard(),
                              const SizedBox(height: 16),
                              _buildProgressBar(),
                              const SizedBox(height: 16),
                              _buildSpendBreakdown(),
                              const SizedBox(height: 16),
                              _buildPoAttachmentsCard(),
                              const SizedBox(height: 100),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ),  // SafeArea
        ],     // Stack children
      ),       // Stack
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Failed to load PO data',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadData,
            child: Text(
              'Retry',
              style: GoogleFonts.spaceGrotesk(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(77)),
          ),
          child: const Icon(
            Icons.receipt_long,
            color: AppTheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PO Tracker',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Purchase Order Utilisation — ${ProjectManager.instance.activeProject}',
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _loadData,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
            ),
            child: const Icon(
              Icons.refresh,
              color: Color(0xFF6B7490),
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPoInfoCard(Map<String, dynamic> po) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0057e6).withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF0057e6).withAlpha(100),
                      ),
                    ),
                    child: Text(
                      'PO # ${po['po_number'] ?? ''}',
                      style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF4D9FFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _categoryChip(po['category'] as String? ?? 'other'),
                  if ((po['storage_path'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () async {
                        final err = await PoDocumentService.instance.open(
                          storagePath: po['storage_path'] as String,
                          fileName: po['file_name'] as String?,
                        );
                        if (err != null && mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(err)));
                        }
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.picture_as_pdf_rounded,
                            size: 13, color: AppTheme.primary.withAlpha(200)),
                        const SizedBox(width: 3),
                        Text('PO doc',
                            style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.primary.withAlpha(200),
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ],
                  const Spacer(),
                  if (po['delivery_date'] != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF6B7490),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Due ${DateTime.tryParse(po['delivery_date']!)?.day.toString().padLeft(2, '0') ?? ''}.${DateTime.tryParse(po['delivery_date']!)?.month.toString().padLeft(2, '0') ?? ''}.${DateTime.tryParse(po['delivery_date']!)?.year ?? ''}',
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF6B7490),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                po['vendor_name'] as String? ?? '',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 4),
              Text(
                po['description'] as String? ?? '',
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2A3450), height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildPoValueItem(
                      label: 'Base Value',
                      amount: (po['total_po_value'] as num?)?.toDouble() ?? 0,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: const Color(0xFF2A3450),
                  ),
                  Expanded(
                    child: _buildPoValueItem(
                      label: 'Tax (GST)',
                      amount: (po['tax_amount'] as num?)?.toDouble() ?? 0,
                      color: const Color(0xFFFFB74D),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: const Color(0xFF2A3450),
                  ),
                  Expanded(
                    child: _buildPoValueItem(
                      label: 'Total PO Value',
                      amount: ((po['total_po_value'] as num?)?.toDouble() ?? 0) + ((po['tax_amount'] as num?)?.toDouble() ?? 0),
                      color: AppTheme.primary,
                      bold: true,
                    ),
                  ),
                ],
              ),
              _buildPoDrawdown(po),
            ],
          ),
        ),
      ),
    );
  }

  /// What this specific PO has been drawn down by, from the invoices that name
  /// it. Aggregate figures hide which PO paid for what; this does not.
  Widget _buildPoDrawdown(Map<String, dynamic> po) {
    final number = (po['po_number'] as String? ?? '').trim();
    final total = ((po['total_po_value'] as num?)?.toDouble() ?? 0) +
        ((po['tax_amount'] as num?)?.toDouble() ?? 0);
    final invoices = _invoicesByPo[number] ?? const <NatraxInvoice>[];
    final drawn = _invoicedAgainst(number);
    final balance = total - drawn;
    final pct = total <= 0 ? 0.0 : (drawn / total).clamp(0.0, 1.0);
    final over = balance < 0;

    // Spent POs are stated as spent. Falling through to the value-pending
    // branch would read as "we don't know", when in fact we know exactly:
    // there is nothing left.
    if (_isExhausted(po)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2A3450), height: 1),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 14, color: Color(0xFF6B7490)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              total > 0
                  ? 'Fully consumed — no funding remaining'
                  : 'Fully consumed — no funding remaining. PO value not '
                      'recorded, so spend against it cannot be totalled.',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4),
            ),
          ),
        ]),
        if (invoices.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('₹${_formatAmount(drawn)} invoiced across ${invoices.length} '
              'invoice${invoices.length == 1 ? '' : 's'}',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490), fontSize: 10.5)),
        ],
      ]);
    }

    // A PO recorded before its value is known must not render as ₹0 of
    // funding — that reads like a real, empty PO rather than a missing figure.
    if (total <= 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF2A3450), height: 1),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.help_outline_rounded,
              size: 14, color: Color(0xFFFFB547)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'PO value not recorded yet — this PO is not counted in the '
              'balance above',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFFFFB547),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.4),
            ),
          ),
        ]),
        if (drawn > 0) ...[
          const SizedBox(height: 6),
          Text('₹${_formatAmount(drawn)} already invoiced against it',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFFFF6B6B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      const Divider(color: Color(0xFF2A3450), height: 1),
      const SizedBox(height: 10),
      Row(children: [
        Text(
          invoices.isEmpty
              ? 'Nothing invoiced against this PO yet'
              : 'Drawn down by ${invoices.length} invoice'
                  '${invoices.length == 1 ? '' : 's'}',
          style: GoogleFonts.spaceGrotesk(
            color: const Color(0xFF8A94B0),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          '${(pct * 100).toStringAsFixed(0)}% used',
          style: GoogleFonts.spaceGrotesk(
            color: over
                ? const Color(0xFFFF6B6B)
                : pct > 0.85
                    ? const Color(0xFFFFB547)
                    : const Color(0xFF4CAF50),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: const Color(0xFF2A3450),
          valueColor: AlwaysStoppedAnimation<Color>(over
              ? const Color(0xFFFF6B6B)
              : pct > 0.85
                  ? const Color(0xFFFFB547)
                  : AppTheme.primary),
          minHeight: 6,
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Text('Invoiced  ₹${_formatAmount(drawn)}',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
        Text(
          '${over ? 'Over by' : 'Available'}  ₹${_formatAmount(balance.abs())}',
          style: GoogleFonts.spaceGrotesk(
              color: over ? const Color(0xFFFF6B6B) : const Color(0xFF4CAF50),
              fontSize: 11.5,
              fontWeight: FontWeight.w800),
        ),
      ]),

      // Work already done but not yet invoiced will come off this PO when
      // NATRAX raises it, so the forecast sits beside the current figure
      // rather than being a surprise later.
      if (_forecastPo == number && _notYetBilledInclGst > 0) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB547).withAlpha(18),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFFFB547).withAlpha(60)),
          ),
          child: Row(children: [
            const Icon(Icons.schedule_rounded,
                size: 13, color: Color(0xFFFFB547)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_uninvoicedMonths.map((m) => _monthShort(m.month)).join(', ')} '
                'not yet invoiced — ₹${_formatAmount(_notYetBilledInclGst)}',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFFFFB547),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'then ₹${_formatAmount(balance - _notYetBilledInclGst)}',
              style: GoogleFonts.spaceGrotesk(
                  color: (balance - _notYetBilledInclGst) < 0
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF4CAF50),
                  fontSize: 11,
                  fontWeight: FontWeight.w800),
            ),
          ]),
        ),
      ],
      if (invoices.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...invoices.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Icon(Icons.subdirectory_arrow_right_rounded,
                    size: 11, color: Colors.white.withAlpha(60)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      '${i.invoiceNumber}'
                      '${(i.periodMonth ?? '').isEmpty ? '' : ' · ${_monthShort(i.periodMonth!)}'}',
                      style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF6B7490), fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Text('₹${_formatAmount(i.totalAmount)}',
                    style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF8A94B0),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ]),
            )),
      ],
    ]);
  }

  /// A PO's purpose, shown as a chip so "which PO paid for manpower" is
  /// answerable at a glance.
  Widget _categoryChip(String category) {
    final (label, color) = switch (category) {
      'track_booking' => ('TRACK BOOKING', AppTheme.primary),
      'manpower' => ('MANPOWER', const Color(0xFF9C88FF)),
      'workshop' => ('WORKSHOP', const Color(0xFFFFB547)),
      'instrumentation' => ('INSTRUMENTATION', const Color(0xFFFF8A65)),
      _ => ('UNCATEGORISED', const Color(0xFF6B7490)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(label,
          style: GoogleFonts.spaceGrotesk(
              color: color, fontSize: 8.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildPoValueItem({
    required String label,
    required double amount,
    required Color color,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF6B7490),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_formatAmount(amount)}',
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: bold ? 13 : 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// An invoice naming a PO that is not loaded means real spend the tracker
  /// cannot attribute. Silence here would understate what has been consumed.
  Widget _buildUnattributedWarning() {
    final orphans = _unattributedInvoices;
    if (orphans.isEmpty) return const SizedBox.shrink();

    final total = orphans.fold(0.0, (s, i) => s + i.totalAmount);
    final missingPos = orphans
        .map((i) => (i.poNumber ?? '').trim())
        .where((p) => p.isNotEmpty)
        .toSet();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB547).withAlpha(20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFB547).withAlpha(90)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.link_off_rounded,
              color: Color(0xFFFFB547), size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '₹${_formatAmount(total)} invoiced against a PO not in '
                      'the tracker',
                      style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFFFFB547),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      missingPos.isEmpty
                          ? '${orphans.length} invoice(s) name no PO at all.'
                          : 'Add PO ${missingPos.join(', ')} so this spend is '
                              'attributed and the balance is complete.',
                      style: GoogleFonts.spaceGrotesk(
                          color: const Color(0xFF8A94B0),
                          fontSize: 10.5,
                          height: 1.45)),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildBalanceSummaryCard() {
    final isOverBudget = _remainingBalance < 0;
    final balanceColor = isOverBudget
        ? Colors.redAccent
        : _remainingBalance < _totalPoWithTax * 0.2
        ? const Color(0xFFFFB74D)
        : const Color(0xFF4CAF50);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Balance Summary',
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryMetric(
                      label: _hasInvoices ? 'Invoiced' : 'Total Spend',
                      value: '₹${_formatAmount(_drawdownInclGst)}',
                      icon: Icons.payments_outlined,
                      color: const Color(0xFFFF6B6B),
                      subtitle: _hasInvoices
                          ? '${_invoiceTotals.count} invoices · incl. GST'
                          : '$_totalSessions sessions · incl. GST',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryMetric(
                      label: 'Balance',
                      value: '₹${_formatAmount(_remainingBalance.abs())}',
                      icon: isOverBudget
                          ? Icons.warning_amber_rounded
                          : Icons.account_balance_wallet_outlined,
                      color: balanceColor,
                      subtitle: isOverBudget ? 'Over budget' : 'Remaining',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _hasInvoices
                    ? 'Balance = PO incl. tax − invoices raised by NATRAX.'
                    : 'Balance = PO incl. tax − computed spend grossed up at '
                        '${(_gstRate * 100).toStringAsFixed(0)}% GST. Upload the '
                        'originals in Settings → Billing to verify it.',
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490),
                  fontSize: 10,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: color.withAlpha(200),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.spaceGrotesk(
              color: color.withAlpha(160),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Invoice reconciliation ────────────────────────────────────────────────

  /// Sets the app's computed spend against the originals NATRAX raised, so a
  /// gap between the two is visible rather than buried in the balance.
  Widget _buildReconciliationCard() {
    final totals = _invoiceTotals;
    // Only invoiced months are compared — see [_invoicedMonthsVariance].
    final variance = _invoicedMonthsVariance;
    final matched = variance.abs() < 1.0;
    final varianceColor = !_hasInvoices
        ? const Color(0xFF6B7490)
        : matched
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFFB547);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.fact_check_outlined,
                    color: Color(0xFF6B7490), size: 15),
                const SizedBox(width: 8),
                Text(
                  'Invoice Reconciliation',
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: varianceColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: varianceColor.withAlpha(80)),
                  ),
                  child: Text(
                    !_hasInvoices
                        ? 'UNVERIFIED'
                        : matched
                            ? 'MATCHED'
                            : 'VARIANCE',
                    style: GoogleFonts.spaceGrotesk(
                        color: varianceColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
              const SizedBox(height: 14),

              // Month by month, so invoiced and not-yet-billed never get
              // conflated. All figures GST inclusive.
              _monthCompareHeader(),
              ...BillingBaseline.forProject(ProjectManager.instance.activeProject)
                  .map((m) => _monthCompareRow(m, _invoicedByMonth[m.month])),

              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2A3450), height: 1),
              const SizedBox(height: 10),

              if (!_hasInvoices) ...[
                Text(
                  'No original invoices uploaded for '
                  '${ProjectManager.instance.activeProject}. The balance above '
                  'is an estimate from session durations and rate cards — it '
                  'has not been checked against what NATRAX actually billed.',
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF8A94B0),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.settings),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(22),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: AppTheme.primary.withAlpha(90)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.upload_file_rounded,
                            size: 14, color: AppTheme.primary),
                        const SizedBox(width: 7),
                        Text(
                          'Upload originals in Settings → Billing',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                _reconRow(
                  'Invoiced by NATRAX (${totals.count} invoice'
                  '${totals.count == 1 ? '' : 's'})',
                  totals.total,
                  AppTheme.primary,
                  bold: true,
                ),
                if (_notYetBilledInclGst > 0)
                  _reconRow(
                    'Not yet billed (${_uninvoicedMonths.map((m) => _monthShort(m.month)).join(', ')})',
                    _notYetBilledInclGst,
                    const Color(0xFFFFB547),
                  ),
                if (_extrasInclGst > 0)
                  _reconRow(
                    'Carried costs on no invoice',
                    _extrasInclGst,
                    const Color(0xFF8A94B0),
                  ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: _headroomChip(
                        'Balance now', _totalPoWithTax - totals.total),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _headroomChip(
                        'After ${_uninvoicedMonths.isEmpty ? 'all' : _uninvoicedMonths.map((m) => _monthShort(m.month)).join('/')} billed',
                        _projectedBalance),
                  ),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: varianceColor.withAlpha(18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: varianceColor.withAlpha(60)),
                  ),
                  child: Row(children: [
                    Icon(
                        matched
                            ? Icons.check_circle_outline
                            : Icons.report_problem_outlined,
                        color: varianceColor,
                        size: 17),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            matched
                                ? 'Invoiced months match the computed spend'
                                : variance > 0
                                    ? 'NATRAX billed ₹${_formatAmount(variance.abs())} more than computed for the invoiced months'
                                    : 'NATRAX billed ₹${_formatAmount(variance.abs())} less than computed for the invoiced months',
                            style: GoogleFonts.spaceGrotesk(
                              color: varianceColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!matched)
                            Text(
                              'Balance is drawn from the invoices, not the '
                              'computed figure.',
                              style: GoogleFonts.spaceGrotesk(
                                color: const Color(0xFF8A94B0),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                ..._invoices.map(_reconInvoiceTile),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _monthShort(String yyyyMm) {
    final p = yyyyMm.split('-');
    if (p.length != 2) return yyyyMm;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (y == null || m == null) return yyyyMm;
    return DateFormat('MMM').format(DateTime(y, m));
  }

  Widget _monthCompareHeader() {
    TextStyle s() => GoogleFonts.spaceGrotesk(
        color: const Color(0xFF4A5470),
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 52, child: Text('MONTH', style: s())),
        Expanded(
            child: Text('COMPUTED', style: s(), textAlign: TextAlign.right)),
        const SizedBox(width: 10),
        Expanded(
            child: Text('INVOICED', style: s(), textAlign: TextAlign.right)),
      ]),
    );
  }

  /// One month's computed baseline against what was actually billed for it.
  Widget _monthCompareRow(MonthBaseline m, double? invoiced) {
    final billed = invoiced != null;
    final diff = billed ? invoiced - m.inclGst : 0.0;
    final matched = diff.abs() < 1.0;
    final color = !billed
        ? const Color(0xFFFFB547)
        : matched
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFFB547);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 52,
          child: Text(_monthShort(m.month),
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Text('₹${_formatAmount(m.inclGst)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(billed ? '₹${_formatAmount(invoiced)}' : 'not billed',
              textAlign: TextAlign.right,
              style: GoogleFonts.spaceGrotesk(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          width: 62,
          child: Text(
              billed
                  ? (matched
                      ? '  ✓'
                      : '  ${diff > 0 ? '+' : '−'}${_formatAmount(diff.abs())}')
                  : '',
              textAlign: TextAlign.right,
              style: GoogleFonts.spaceGrotesk(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _headroomChip(String label, double headroom) {
    final over = headroom < 0;
    final c = over ? const Color(0xFFFF6B6B) : const Color(0xFF4CAF50);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: c.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF8A94B0),
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${over ? '−' : '+'}₹${_formatAmount(headroom.abs())}',
            style: GoogleFonts.spaceGrotesk(
              color: c,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            over ? 'over PO' : 'headroom',
            style: GoogleFonts.spaceGrotesk(
              color: c.withAlpha(170),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reconRow(String label, double amount, Color color,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: bold ? color : const Color(0xFF8A94B0),
                fontSize: bold ? 12.5 : 11.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${_formatAmount(amount)}',
            style: GoogleFonts.spaceGrotesk(
              color: color,
              fontSize: bold ? 13.5 : 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reconInvoiceTile(NatraxInvoice inv) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: inv.hasFile
            ? () async {
                final err = await openInvoice(inv);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(err)));
                }
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(15)),
          ),
          child: Row(children: [
            Icon(
                inv.hasFile
                    ? Icons.picture_as_pdf_rounded
                    : Icons.receipt_outlined,
                size: 15,
                color: AppTheme.primary.withAlpha(190)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoice ${inv.invoiceNumber}',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      if (inv.invoiceDate != null)
                        DateFormat('dd MMM yyyy').format(inv.invoiceDate!),
                      if ((inv.poNumber ?? '').isNotEmpty)
                        'PO ${inv.poNumber}',
                    ].join(' · '),
                    style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490), fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '₹${_formatAmount(inv.totalAmount)}',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (inv.hasFile) ...[
              const SizedBox(width: 6),
              Icon(Icons.remove_red_eye_outlined,
                  size: 13, color: AppTheme.primary.withAlpha(160)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final pct = (_utilizationPercent * 100).toStringAsFixed(1);
    final barColor = _utilizationPercent > 0.9
        ? Colors.redAccent
        : _utilizationPercent > 0.7
        ? const Color(0xFFFFB74D)
        : AppTheme.primary;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PO Utilisation',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF6B7490),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    '$pct% used',
                    style: GoogleFonts.spaceGrotesk(
                      color: barColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _utilizationPercent,
                  backgroundColor: const Color(0xFF2A3450),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹0',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF4A5470),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    '₹${_formatAmount(_totalPoWithTax)} (incl. tax)',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF4A5470),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpendBreakdown() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spend Breakdown',
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 14),
              _buildBreakdownRow(
                icon: Icons.speed_outlined,
                label: 'Track Sessions',
                amount: _trackSessionsSpend,
                color: AppTheme.primary,
                subtitle: _costedSessions == _totalSessions
                    ? '$_totalSessions completed sessions'
                    : '$_totalSessions sessions · '
                        '${_totalSessions - _costedSessions} billed via monthly baseline',
              ),
              const SizedBox(height: 10),
              _buildBreakdownRow(
                icon: Icons.miscellaneous_services_outlined,
                label: 'Additional Services',
                amount: _additionalServicesSpend,
                color: const Color(0xFFFFB74D),
                subtitle: 'EV charging, labour, refreshments, etc.',
              ),
              const SizedBox(height: 10),
              _buildBreakdownRow(
                icon: Icons.warehouse_outlined,
                label: 'Workshop Rent',
                amount: _workshopSpend,
                color: const Color(0xFF9C88FF),
                subtitle: 'Monthly workshop booking (2 months)',
              ),
              const SizedBox(height: 10),
              _buildBreakdownRow(
                icon: Icons.directions_car_filled_outlined,
                label: 'Vehicle Validation Learning',
                amount: _vehicleValidationSpend,
                color: const Color(0xFF4FC3F7),
                subtitle: 'Learning and testing validation',
              ),
              const SizedBox(height: 10),
              _buildBreakdownRow(
                icon: Icons.precision_manufacturing_outlined,
                label: 'Instrumentation Parts',
                amount: _instrumentationSpend,
                color: const Color(0xFFFF8A65),
                subtitle: 'Materials and assets upkeeping',
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF2A3450), height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Cumulative Spend',
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '₹${_formatAmount(_totalSpend)}',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFFFF6B6B),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreakdownRow({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
    required String subtitle,
  }) {
    final pct = _totalSpend > 0 ? (amount / _totalSpend * 100) : 0.0;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490),
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${_formatAmount(amount)}',
              style: GoogleFonts.spaceGrotesk(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF6B7490),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }


  Future<void> _pickAttachmentFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        await _showAttachmentDetailsDialog(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  Future<void> _showAttachmentDetailsDialog(PlatformFile file) async {
    final formKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController(text: file.name);
    final descCtrl = TextEditingController(text: 'Custom Uploaded PDF');
    final amountCtrl = TextEditingController(text: '₹1,50,000');
    final poNumCtrl = TextEditingController(text: 'GY-PO-${DateTime.now().year}-${100 + _customAttachments.length}');
    String selectedStatus = 'Active';

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppTheme.primary.withAlpha(50)),
          ),
          title: Text(
            'Enter PDF Attachment Details',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: labelCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Document Name / Label',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: poNumCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'PO / Invoice Number',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  TextFormField(
                    controller: descCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  TextFormField(
                    controller: amountCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Amount / Value (₹)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    dropdownColor: const Color(0xFF0A1025),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    ),
                    items: ['Active', 'Paid', 'Pending', 'Used'].map((st) {
                      return DropdownMenuItem(value: st, child: Text(st));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) selectedStatus = val;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Color sColor = const Color(0xFF94A3B8);
                  if (selectedStatus == 'Paid' || selectedStatus == 'Used') {
                    sColor = const Color(0xFF4CAF50);
                  } else if (selectedStatus == 'Upcoming' || selectedStatus == 'Pending') {
                    sColor = const Color(0xFFFFB547);
                  } else if (selectedStatus == 'Active') {
                    sColor = const Color(0xFF4A9EFF);
                  }

                  String baseAmount = amountCtrl.text.trim();
                  if (!baseAmount.startsWith('₹')) baseAmount = '₹$baseAmount';

                  final newAttachment = _PoAttachment(
                    label: labelCtrl.text.trim(),
                    subtitle: descCtrl.text.trim(),
                    amount: baseAmount,
                    status: selectedStatus,
                    statusColor: sColor,
                    assetPath: file.name,
                    icon: Icons.upload_file_rounded,
                    color: AppTheme.primary,
                    vendorName: 'Custom Uploaded Vendor',
                    poNumber: poNumCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    date: DateFormat('dd MMM yyyy').format(DateTime.now()),
                    isCustom: true,
                  );

                  setState(() {
                    _customAttachments.add(newAttachment);
                  });

                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Attachment "${labelCtrl.text}" added successfully.')),
                  );
                }
              },
              child: const Text('Attach'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPdfDocument(BuildContext context, _PoAttachment attachment) async {
    // Show loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Opening ${attachment.label}...'),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF0A1025),
      ),
    );

    try {
      String filePath;

      if (attachment.isCustom && attachment.filePath != null) {
        // Custom uploaded PDF — use device path directly
        filePath = attachment.filePath!;
      } else {
        // Bundled asset PDF — extract to cache and open
        final byteData = await rootBundle.load(attachment.assetPath);
        final cacheDir = await getTemporaryDirectory();
        final fileName = attachment.assetPath.split('/').last;
        final tempFile = File('${cacheDir.path}/$fileName');
        await tempFile.writeAsBytes(
          byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        filePath = tempFile.path;
      }

      final result = await OpenFile.open(filePath);

      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open PDF: ${result.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildPoAttachmentsCard() {
    final staticAttachments = [
      _PoAttachment(
        label: 'PO # 8242348442',
        subtitle: 'Track Usage — Used PO',
        amount: '₹17,99,712',
        status: 'Used',
        statusColor: const Color(0xFF4CAF50),
        assetPath: 'assets/documents/PO_8242348442_Track_Usage.pdf',
        icon: Icons.receipt_long_rounded,
        color: AppTheme.primary,
      ),
      _PoAttachment(
        label: 'PO # 8242390552',
        subtitle: 'Track Usage — Upcoming PO',
        amount: 'Pending',
        status: 'Upcoming',
        statusColor: const Color(0xFFFFB547),
        assetPath: 'assets/documents/PO_8242390552_Upcoming.pdf',
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFFFFB547),
      ),
      _PoAttachment(
        label: 'Manpower PO',
        subtitle: 'NATRAX Lab / Workshop Manpower',
        amount: 'See document',
        status: 'Active',
        statusColor: const Color(0xFF4A9EFF),
        assetPath: 'assets/documents/used_po.pdf',
        icon: Icons.engineering_rounded,
        color: const Color(0xFF4A9EFF),
      ),
      _PoAttachment(
        label: 'March 2026 Invoice',
        subtitle: 'GOODYEAR SOUTH ASIA TYRES PVT LTD',
        amount: '₹2,28,453.90',
        status: 'Paid',
        statusColor: const Color(0xFF4CAF50),
        assetPath: 'assets/documents/NATRAX_March_2026_Invoice.pdf',
        icon: Icons.description_rounded,
        color: const Color(0xFF94A3B8),
      ),
    ];

    final allAttachments = [...staticAttachments, ..._customAttachments];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.attach_file_rounded, color: Color(0xFF6B7490), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'PO Documents & Attachments',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF6B7490),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _pickAttachmentFile,
                    child: Row(
                      children: [
                        const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Attach PDF',
                          style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...allAttachments.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => _openPdfDocument(context, a),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: a.color.withAlpha(12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: a.color.withAlpha(50)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: a.color.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(a.icon, color: a.color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(a.label,
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white, fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        Text(a.subtitle,
                            style: GoogleFonts.spaceGrotesk(
                                color: const Color(0xFF6B7490), fontSize: 10)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.statusColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: a.statusColor.withAlpha(70)),
                          ),
                          child: Text(a.status,
                              style: GoogleFonts.spaceGrotesk(
                                  color: a.statusColor,
                                  fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 4),
                        Text(a.amount,
                            style: GoogleFonts.spaceGrotesk(
                                color: a.color, fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(width: 8),
                      Icon(Icons.remove_red_eye_outlined,
                          color: a.color.withAlpha(150), size: 14),
                    ]),
                  ),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      final formatted = amount.toStringAsFixed(0);
      if (formatted.length > 3) {
        return '${formatted.substring(0, formatted.length - 3)},${formatted.substring(formatted.length - 3)}';
      }
      return formatted;
    }
    return amount.toStringAsFixed(0);
  }
}

class _PoAttachment {
  final String label;
  final String subtitle;
  final String amount;
  final String status;
  final Color statusColor;
  final String assetPath;  // asset path OR display label
  final IconData icon;
  final Color color;
  final bool isCustom;
  final String? filePath;  // actual device file path for custom uploads
  final String? vendorName;
  final String? poNumber;
  final String? description;
  final String? date;

  const _PoAttachment({
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.statusColor,
    required this.assetPath,
    required this.icon,
    required this.color,
    this.isCustom = false,
    this.filePath,
    this.vendorName,
    this.poNumber,
    this.description,
    this.date,
  });
}

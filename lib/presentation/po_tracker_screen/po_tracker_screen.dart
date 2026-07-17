import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_export.dart';
import '../../services/supabase_service.dart';
import '../../services/project_manager.dart';

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
      final isMahindraEV = activeProjName.toLowerCase() == 'mahindra ev poc';

      double trackTotal = 0;
      double servicesTotal = 0;
      int sessionCount = 0;

      for (final s in sessionsData as List) {
        final rawProj = (s['project_name'] as String?)?.trim() ?? '';
        if (!pm.sessionBelongsToProject(rawProj)) continue;

        final sid = s['id'] as String;
        final track = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        final svc = svcCostMap[sid] ?? 0.0;
        final startStr = s['started_at'] as String? ?? '';
        final startDt = DateTime.tryParse(startStr);

        sessionCount++;

        if (startDt != null) {
          final isHistorical = isMahindraEV &&
              startDt.year == 2026 &&
              (startDt.month == 3 || startDt.month == 4 || startDt.month == 5);
          if (!isHistorical) {
            trackTotal += track;
            servicesTotal += svc;
          }
        } else {
          trackTotal += track;
          servicesTotal += svc;
        }
      }

      if (isMahindraEV) {
        // Add historical overrides (Track = 1,263,500, Accessories = 215,219, Workshop = 245,000)
        trackTotal += 1263500.0;
        servicesTotal += 215219.0;
        _workshopSpend = 245000.0;
        _vehicleValidationSpend = 120000.0;
        _instrumentationSpend = 85000.0;
      } else {
        _workshopSpend = 0.0;
        _vehicleValidationSpend = 0.0;
        _instrumentationSpend = 0.0;
      }

      _trackSessionsSpend = trackTotal;
      _additionalServicesSpend = servicesTotal;
      _totalSessions = sessionCount;

      setState(() => _loading = false);
      _animController.forward();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  double get _totalSpend =>
      _trackSessionsSpend +
      _additionalServicesSpend +
      _workshopSpend +
      _vehicleValidationSpend +
      _instrumentationSpend;

  double get _totalPoWithTax {
    double total = 0;
    for (final po in _poList) {
      final val = (po['total_po_value'] as num?)?.toDouble() ?? 0;
      final tax = (po['tax_amount'] as num?)?.toDouble() ?? 0;
      total += val + tax;
    }
    return total;
  }

  double get _remainingBalance => _totalPoWithTax - _totalSpend;

  double get _utilizationPercent => _totalPoWithTax > 0
      ? (_totalSpend / _totalPoWithTax).clamp(0.0, 1.0)
      : 0.0;

  Future<void> _showAddPoDialog() async {
    final formKey = GlobalKey<FormState>();
    String poNumber = '';
    String vendorName = '';
    String description = '';
    double totalPoValue = 0;
    double taxAmount = 0;
    DateTime deliveryDate = DateTime.now().add(const Duration(days: 30));

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
                    await SupabaseService.instance.client.from('po_trackers').insert({
                      'po_number': poNumber,
                      'vendor_name': vendorName,
                      'description': description,
                      'total_po_value': totalPoValue,
                      'tax_amount': taxAmount,
                      'delivery_date': deliveryDate.toIso8601String().split('T')[0],
                    });
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPoDialog,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
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
                              ..._poList.map((po) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _buildPoInfoCard(po),
                              )),
                              _buildBalanceSummaryCard(),
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
            ],
          ),
        ),
      ),
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
                      label: 'Total Spend',
                      value: '₹${_formatAmount(_totalSpend)}',
                      icon: Icons.payments_outlined,
                      color: const Color(0xFFFF6B6B),
                      subtitle: '$_totalSessions sessions',
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
                subtitle: '$_totalSessions completed sessions',
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

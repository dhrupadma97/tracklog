import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';

import '../../core/app_export.dart';
import '../../services/supabase_service.dart';

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
  String _poNumber = '';
  String _vendorName = '';
  String _description = '';
  double _totalPoValue = 0;
  double _taxAmount = 0;
  DateTime? _deliveryDate;

  // Spend data
  double _trackSessionsSpend = 0;
  double _additionalServicesSpend = 0;
  double _workshopSpend = 0;
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
          .eq('po_number', '8242348442')
          .maybeSingle();

      if (poData != null) {
        _poNumber = poData['po_number'] as String? ?? '';
        _vendorName = poData['vendor_name'] as String? ?? '';
        _description = poData['description'] as String? ?? '';
        _totalPoValue = (poData['total_po_value'] as num?)?.toDouble() ?? 0;
        _taxAmount = (poData['tax_amount'] as num?)?.toDouble() ?? 0;
        final deliveryStr = poData['delivery_date'] as String?;
        _deliveryDate = deliveryStr != null
            ? DateTime.tryParse(deliveryStr)
            : null;
      }

      // Load cumulative track session costs
      final sessionsData = await client
          .from('engineer_sessions')
          .select('total_cost, session_status')
          .eq('session_status', 'completed');

      double trackTotal = 0;
      int sessionCount = 0;
      for (final s in sessionsData as List) {
        trackTotal += (s['total_cost'] as num?)?.toDouble() ?? 0;
        sessionCount++;
      }
      _trackSessionsSpend = trackTotal;
      _totalSessions = sessionCount;

      // Load additional services spend
      final servicesData = await client
          .from('session_additional_services')
          .select('total_cost');

      double servicesTotal = 0;
      for (final s in servicesData as List) {
        servicesTotal += (s['total_cost'] as num?)?.toDouble() ?? 0;
      }
      _additionalServicesSpend = servicesTotal;

      // Workshop monthly cost — from monthly_invoices or fixed
      // Use 2 months (March + April) × ₹50,000
      _workshopSpend = 100000.0;

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
      _trackSessionsSpend + _additionalServicesSpend + _workshopSpend;

  double get _totalPoWithTax => _totalPoValue + _taxAmount;

  double get _remainingBalance => _totalPoWithTax - _totalSpend;

  double get _utilizationPercent => _totalPoWithTax > 0
      ? (_totalSpend / _totalPoWithTax).clamp(0.0, 1.0)
      : 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
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
                  backgroundColor: const Color(0xFF1A2236),
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
                              _buildPoInfoCard(),
                              const SizedBox(height: 16),
                              _buildBalanceSummaryCard(),
                              const SizedBox(height: 16),
                              _buildProgressBar(),
                              const SizedBox(height: 16),
                              _buildSpendBreakdown(),
                              const SizedBox(height: 100),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
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
            style: GoogleFonts.manrope(
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
              style: GoogleFonts.manrope(color: AppTheme.primary),
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
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Purchase Order Utilisation',
                style: GoogleFonts.manrope(
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
              color: const Color(0xFF1A2236).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
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

  Widget _buildPoInfoCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
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
                      'PO # $_poNumber',
                      style: GoogleFonts.manrope(
                        color: const Color(0xFF4D9FFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_deliveryDate != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF6B7490),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Due ${_deliveryDate!.day.toString().padLeft(2, '0')}.${_deliveryDate!.month.toString().padLeft(2, '0')}.${_deliveryDate!.year}',
                          style: GoogleFonts.manrope(
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
                _vendorName,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 4),
              Text(
                _description,
                style: GoogleFonts.manrope(
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
                      amount: _totalPoValue,
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
                      amount: _taxAmount,
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
                      amount: _totalPoWithTax,
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
            style: GoogleFonts.manrope(
              color: const Color(0xFF6B7490),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '₹${_formatAmount(amount)}',
            style: GoogleFonts.manrope(
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
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Balance Summary',
                style: GoogleFonts.manrope(
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
                style: GoogleFonts.manrope(
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
            style: GoogleFonts.manrope(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.manrope(
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
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PO Utilisation',
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF6B7490),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    '$pct% used',
                    style: GoogleFonts.manrope(
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
                    style: GoogleFonts.manrope(
                      color: const Color(0xFF4A5470),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    '₹${_formatAmount(_totalPoWithTax)} (incl. tax)',
                    style: GoogleFonts.manrope(
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
            color: const Color(0xFF1A2236).withAlpha(200),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF3A4460).withAlpha(120)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spend Breakdown',
                style: GoogleFonts.manrope(
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
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF2A3450), height: 1),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Cumulative Spend',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '₹${_formatAmount(_totalSpend)}',
                    style: GoogleFonts.manrope(
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
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.manrope(
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
              style: GoogleFonts.manrope(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: GoogleFonts.manrope(
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

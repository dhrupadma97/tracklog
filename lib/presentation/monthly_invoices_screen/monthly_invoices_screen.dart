import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

import '../../services/engineer_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class MonthlyInvoicesScreen extends StatefulWidget {
  const MonthlyInvoicesScreen({super.key});

  @override
  State<MonthlyInvoicesScreen> createState() => _MonthlyInvoicesScreenState();
}

class _MonthlyInvoicesScreenState extends State<MonthlyInvoicesScreen> {
  bool _isLoading = true;
  List<_InvoiceMonth> _invoiceMonths = [];
  int _selectedMonthIndex = 0;
  final _currencyFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final uid = EngineerAuthService.instance.currentUser?.id;
      if (uid == null) return;

      final client = Supabase.instance.client;

      // Fetch sessions
      final sessionsRaw = await client
          .from('engineer_sessions')
          .select(
            'id, track_name, track_code, started_at, ended_at, duration_minutes, total_cost, session_status',
          )
          .eq('engineer_id', uid)
          .eq('session_status', 'completed')
          .order('started_at', ascending: false);

      // Fetch additional services for those sessions
      final sessionIds = (sessionsRaw as List)
          .map((s) => s['id'] as String)
          .toList();
      List<dynamic> servicesRaw = [];
      if (sessionIds.isNotEmpty) {
        servicesRaw = await client
            .from('session_additional_services')
            .select('session_id, service_name, quantity, rate, total_cost')
            .inFilter('session_id', sessionIds);
      }

      // Group services by session
      final Map<String, List<Map<String, dynamic>>> servicesBySession = {};
      for (final svc in servicesRaw) {
        final sid = svc['session_id'] as String;
        servicesBySession
            .putIfAbsent(sid, () => [])
            .add(Map<String, dynamic>.from(svc));
      }

      // Build invoice line items per session
      final List<_InvoiceLineItem> allItems = [];
      for (final s in sessionsRaw) {
        final sessionId = s['id'] as String;
        final startedAt =
            DateTime.tryParse(s['started_at'] as String? ?? '') ??
            DateTime.now();
        final durationMin = (s['duration_minutes'] as int?) ?? 0;
        final sessionCost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        final trackName = s['track_name'] as String? ?? '';

        // Session charge
        allItems.add(
          _InvoiceLineItem(
            date: startedAt,
            category: 'Session',
            description: '$trackName (${_formatDuration(durationMin)})',
            quantity: durationMin / 60.0,
            unit: 'hrs',
            rate: sessionCost > 0 && durationMin > 0
                ? sessionCost / (durationMin / 60.0)
                : 0,
            amount: sessionCost,
          ),
        );

        // Additional services
        final svcs = servicesBySession[sessionId] ?? [];
        for (final svc in svcs) {
          final svcName = svc['service_name'] as String? ?? '';
          final qty = (svc['quantity'] as num?)?.toDouble() ?? 0;
          final rate = (svc['rate'] as num?)?.toDouble() ?? 0;
          final total = (svc['total_cost'] as num?)?.toDouble() ?? (qty * rate);

          String category = 'Additional';
          if (svcName.toLowerCase().contains('ev') ||
              svcName.toLowerCase().contains('charger')) {
            category = 'EV kWh';
          } else if (svcName.toLowerCase().contains('sand')) {
            category = 'Sand Bags';
          } else if (svcName.toLowerCase().contains('rental') ||
              svcName.toLowerCase().contains('instrument')) {
            category = 'Rental Instruments';
          }

          allItems.add(
            _InvoiceLineItem(
              date: startedAt,
              category: category,
              description: svcName,
              quantity: qty,
              unit: _unitForService(svcName),
              rate: rate,
              amount: total,
            ),
          );
        }
      }

      // Group by month
      final Map<String, List<_InvoiceLineItem>> byMonth = {};
      for (final item in allItems) {
        final key = DateFormat('MMMM yyyy').format(item.date);
        byMonth.putIfAbsent(key, () => []).add(item);
      }

      final months = byMonth.entries.map((e) {
        final items = e.value;
        items.sort((a, b) => b.date.compareTo(a.date));
        return _InvoiceMonth(label: e.key, items: items);
      }).toList();

      // Sort months newest first
      months.sort((a, b) {
        final da = DateFormat('MMMM yyyy').parse(a.label);
        final db = DateFormat('MMMM yyyy').parse(b.label);
        return db.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _invoiceMonths = months;
          _selectedMonthIndex = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _unitForService(String name) {
    final n = name.toLowerCase();
    if (n.contains('ev') || n.contains('charger')) return 'kWh';
    if (n.contains('sand')) return 'bag-days';
    if (n.contains('labour')) return 'days';
    if (n.contains('electricity')) return 'units';
    if (n.contains('hall')) return 'days';
    if (n.contains('lunch') || n.contains('refresh')) return 'nos';
    return 'units';
  }

  void _exportCSV() {
    if (_invoiceMonths.isEmpty) return;
    final month = _invoiceMonths[_selectedMonthIndex];
    final sb = StringBuffer();
    sb.writeln('Monthly Invoice - ${month.label}');
    sb.writeln('');
    sb.writeln('Date,Category,Description,Quantity,Unit,Rate (₹),Amount (₹)');
    for (final item in month.items) {
      sb.writeln(
        '${DateFormat('dd/MM/yyyy').format(item.date)},'
        '${item.category},'
        '"${item.description}",'
        '${item.quantity.toStringAsFixed(2)},'
        '${item.unit},'
        '${item.rate.toStringAsFixed(2)},'
        '${item.amount.toStringAsFixed(2)}',
      );
    }
    sb.writeln('');
    sb.writeln(',,,,,,');
    sb.writeln('Subtotal,,,,,,"${month.subtotal.toStringAsFixed(2)}"');
    sb.writeln('GST (18%),,,,,,"${month.gst.toStringAsFixed(2)}"');
    sb.writeln('Total (incl. GST),,,,,,"${month.total.toStringAsFixed(2)}"');

    if (kIsWeb) {
      final bytes = utf8.encode(sb.toString());
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
          'download',
          'invoice_${month.label.replaceAll(' ', '_')}.csv',
        )
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              )
            else if (_invoiceMonths.isEmpty)
              _buildEmptyState()
            else
              Expanded(
                child: Column(
                  children: [
                    _buildMonthSelector(),
                    Expanded(child: _buildInvoiceContent()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 2.h, 4.w, 1.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Invoices',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFdfe2f0),
                  ),
                ),
                Text(
                  'Sessions, EV kWh, Sand Bags & Rentals',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11.sp,
                    color: const Color(0xFF6B7490),
                  ),
                ),
              ],
            ),
          ),
          if (_invoiceMonths.isNotEmpty)
            GestureDetector(
              onTap: _exportCSV,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CustomIconWidget(
                      iconName: 'download',
                      color: AppTheme.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Export CSV',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 4.w),
        itemCount: _invoiceMonths.length,
        itemBuilder: (context, i) {
          final isSelected = i == _selectedMonthIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedMonthIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary.withAlpha(30)
                    : const Color(0xFF0A1025),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primary.withAlpha(120)
                      : const Color(0xFF849495),
                ),
              ),
              child: Text(
                _invoiceMonths[i].label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11.sp,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.primary
                      : const Color(0xFFA8B0C8),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInvoiceContent() {
    final month = _invoiceMonths[_selectedMonthIndex];
    final categories = [
      'Session',
      'EV kWh',
      'Sand Bags',
      'Rental Instruments',
      'Additional',
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(4.w, 1.5.h, 4.w, 12.h),
      children: [
        const SizedBox(height: 12),
        // Summary cards row
        _buildSummaryRow(month),
        const SizedBox(height: 16),
        // Category breakdown
        ...categories.map((cat) {
          final catItems = month.items.where((i) => i.category == cat).toList();
          if (catItems.isEmpty) return const SizedBox.shrink();
          return _buildCategorySection(cat, catItems);
        }),
        const SizedBox(height: 8),
        _buildTotalsCard(month),
      ],
    );
  }

  Widget _buildSummaryRow(_InvoiceMonth month) {
    final sessionTotal = month.items
        .where((i) => i.category == 'Session')
        .fold(0.0, (s, i) => s + i.amount);
    final evTotal = month.items
        .where((i) => i.category == 'EV kWh')
        .fold(0.0, (s, i) => s + i.amount);
    final sandTotal = month.items
        .where((i) => i.category == 'Sand Bags')
        .fold(0.0, (s, i) => s + i.amount);
    final rentalTotal = month.items
        .where((i) => i.category == 'Rental Instruments')
        .fold(0.0, (s, i) => s + i.amount);

    return Row(
      children: [
        _SummaryChip(
          label: 'Sessions',
          amount: sessionTotal,
          icon: 'timer',
          color: AppTheme.primary,
        ),
        const SizedBox(width: 8),
        _SummaryChip(
          label: 'EV kWh',
          amount: evTotal,
          icon: 'electric_bolt',
          color: const Color(0xFF4A9EFF),
        ),
        const SizedBox(width: 8),
        _SummaryChip(
          label: 'Sand Bags',
          amount: sandTotal,
          icon: 'inventory_2',
          color: AppTheme.accent,
        ),
        const SizedBox(width: 8),
        _SummaryChip(
          label: 'Rentals',
          amount: rentalTotal,
          icon: 'build',
          color: AppTheme.secondary,
        ),
      ],
    );
  }

  Widget _buildCategorySection(String category, List<_InvoiceLineItem> items) {
    final categoryTotal = items.fold(0.0, (s, i) => s + i.amount);
    final color = _colorForCategory(category);
    final icon = _iconForCategory(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3a494b)),
      ),
      child: Column(
        children: [
          // Category header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CustomIconWidget(
                    iconName: icon,
                    color: color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFdfe2f0),
                    ),
                  ),
                ),
                Text(
                  _currencyFmt.format(categoryTotal),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3a494b)),
          // Line items
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.description,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFb9cacb),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat('dd MMM').format(item.date)}  ·  ${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2)} ${item.unit}  ·  ₹${item.rate.toStringAsFixed(0)}/${item.unit}',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 10.sp,
                                color: const Color(0xFF6B7490),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currencyFmt.format(item.amount),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFdfe2f0),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < items.length - 1)
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: Color(0xFF181B25),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTotalsCard(_InvoiceMonth month) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withAlpha(60)),
      ),
      child: Column(
        children: [
          _TotalRow(
            label: 'Subtotal',
            value: _currencyFmt.format(month.subtotal),
            isBold: false,
          ),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'GST (18%)',
            value: _currencyFmt.format(month.gst),
            isBold: false,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFF3a494b)),
          ),
          _TotalRow(
            label: 'Total (incl. GST)',
            value: _currencyFmt.format(month.total),
            isBold: true,
            valueColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1025),
                shape: BoxShape.circle,
              ),
              child: const CustomIconWidget(
                iconName: 'receipt_long',
                color: Color(0xFF6B7490),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No invoices yet',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Complete sessions to see monthly invoices',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11.sp,
                color: const Color(0xFF6B7490),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorForCategory(String cat) {
    switch (cat) {
      case 'Session':
        return AppTheme.primary;
      case 'EV kWh':
        return const Color(0xFF4A9EFF);
      case 'Sand Bags':
        return AppTheme.accent;
      case 'Rental Instruments':
        return AppTheme.secondary;
      default:
        return const Color(0xFFA8B0C8);
    }
  }

  String _iconForCategory(String cat) {
    switch (cat) {
      case 'Session':
        return 'timer';
      case 'EV kWh':
        return 'electric_bolt';
      case 'Sand Bags':
        return 'inventory_2';
      case 'Rental Instruments':
        return 'build';
      default:
        return 'add_circle';
    }
  }
}

// ─── Data Models ────────────────────────────────────────────────────────────

class _InvoiceLineItem {
  final DateTime date;
  final String category;
  final String description;
  final double quantity;
  final String unit;
  final double rate;
  final double amount;

  const _InvoiceLineItem({
    required this.date,
    required this.category,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.rate,
    required this.amount,
  });
}

class _InvoiceMonth {
  final String label;
  final List<_InvoiceLineItem> items;

  _InvoiceMonth({required this.label, required this.items});

  double get subtotal => items.fold(0.0, (s, i) => s + i.amount);
  double get gst => subtotal * 0.18;
  double get total => subtotal + gst;
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final double amount;
  final String icon;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomIconWidget(iconName: icon, color: color, size: 14),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 9,
                color: const Color(0xFF6B7490),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              amount == 0 ? '—' : '₹${(amount / 1000).toStringAsFixed(1)}k',
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _TotalRow({
    required this.label,
    required this.value,
    required this.isBold,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? const Color(0xFFdfe2f0) : const Color(0xFFA8B0C8),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: isBold ? 14 : 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color:
                valueColor ??
                (isBold ? const Color(0xFFdfe2f0) : const Color(0xFFb9cacb)),
          ),
        ),
      ],
    );
  }
}

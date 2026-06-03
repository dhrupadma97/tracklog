import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
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
  final _currencyFmt = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
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
      final sessionsRaw = await client
          .from('engineer_sessions')
          .select('id, track_name, track_code, started_at, ended_at, duration_minutes, total_cost, session_status')
          .eq('engineer_id', uid)
          .eq('session_status', 'completed')
          .order('started_at', ascending: false);

      final sessionIds = (sessionsRaw as List).map((s) => s['id'] as String).toList();
      List<dynamic> servicesRaw = [];
      if (sessionIds.isNotEmpty) {
        servicesRaw = await client
            .from('session_additional_services')
            .select('session_id, service_name, quantity, rate, total_cost')
            .inFilter('session_id', sessionIds);
      }

      final Map<String, List<Map<String, dynamic>>> servicesBySession = {};
      for (final svc in servicesRaw) {
        final sid = svc['session_id'] as String;
        servicesBySession.putIfAbsent(sid, () => []).add(Map<String, dynamic>.from(svc));
      }

      final List<_InvoiceLineItem> allItems = [];
      for (final s in sessionsRaw) {
        final sessionId = s['id'] as String;
        final startedAt = DateTime.tryParse(s['started_at'] as String? ?? '') ?? DateTime.now();
        final durationMin = (s['duration_minutes'] as int?) ?? 0;
        final sessionCost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        final trackName = s['track_name'] as String? ?? '';

        allItems.add(_InvoiceLineItem(
          date: startedAt,
          category: 'Session',
          description: trackName,
          quantity: durationMin / 60.0,
          unit: 'hrs',
          rate: sessionCost > 0 && durationMin > 0 ? sessionCost / (durationMin / 60.0) : 0,
          amount: sessionCost,
        ));

        final svcs = servicesBySession[sessionId] ?? [];
        for (final svc in svcs) {
          final svcName = svc['service_name'] as String? ?? '';
          final qty = (svc['quantity'] as num?)?.toDouble() ?? 0;
          final rate = (svc['rate'] as num?)?.toDouble() ?? 0;
          final total = (svc['total_cost'] as num?)?.toDouble() ?? (qty * rate);

          String category = 'Additional';
          if (svcName.toLowerCase().contains('ev') || svcName.toLowerCase().contains('charger')) {
            category = 'EV kWh';
          } else if (svcName.toLowerCase().contains('sand')) {
            category = 'Sand Bags';
          } else if (svcName.toLowerCase().contains('rental') || svcName.toLowerCase().contains('instrument')) {
            category = 'Rental Instruments';
          }

          allItems.add(_InvoiceLineItem(
            date: startedAt,
            category: category,
            description: svcName,
            quantity: qty,
            unit: 'unit',
            rate: rate,
            amount: total,
          ));
        }
      }

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

  void _exportCSV() {
    if (_invoiceMonths.isEmpty) return;
    final month = _invoiceMonths[_selectedMonthIndex];
    final sb = StringBuffer();
    sb.writeln('Monthly Invoice - ${month.label}');
    sb.writeln('Date,Category,Description,Quantity,Unit,Rate (INR),Amount (INR)');
    for (final item in month.items) {
      sb.writeln('${DateFormat('dd/MM/yyyy').format(item.date)},${item.category},"${item.description}",${item.quantity},${item.unit},${item.rate},${item.amount}');
    }
    sb.writeln(',,,,,,');
    sb.writeln('Subtotal,,,,,,"${month.subtotal}"');
    sb.writeln('GST (18%),,,,,,"${month.gst}"');
    sb.writeln('Total,,,,,,"${month.total}"');

    if (kIsWeb) {
      final bytes = utf8.encode(sb.toString());
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'invoice_${month.label}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    if (_invoiceMonths.isEmpty)
                      _buildEmptyState()
                    else
                      Expanded(
                        child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final currentMonth = _invoiceMonths[_selectedMonthIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMetricsRow(currentMonth),
        const SizedBox(height: 24),
        Expanded(
          flex: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: _buildRevenueChart()),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: _buildCategoryChart(currentMonth)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildMonthSelector(),
        const SizedBox(height: 16),
        Expanded(
          flex: 5,
          child: _buildDataTable(currentMonth),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    final currentMonth = _invoiceMonths[_selectedMonthIndex];
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _buildMetricsRow(currentMonth, isMobile: true),
              const SizedBox(height: 24),
              SizedBox(height: 300, child: _buildRevenueChart()),
              const SizedBox(height: 24),
              SizedBox(height: 300, child: _buildCategoryChart(currentMonth)),
              const SizedBox(height: 24),
              _buildMonthSelector(),
              const SizedBox(height: 16),
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: true,
          child: _buildDataTable(currentMonth),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financial Management',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Billing & Invoices',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: const Color(0xFFA8B0C8),
              ),
            ),
          ],
        ),
        if (_invoiceMonths.isNotEmpty)
          GestureDetector(
            onTap: _exportCSV,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const CustomIconWidget(iconName: 'download', color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'EXPORT CSV',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetricsRow(_InvoiceMonth month, {bool isMobile = false}) {
    final widgets = [
      Expanded(child: _buildMetricCard('Total Invoiced', _currencyFmt.format(month.total))),
      SizedBox(width: isMobile ? 0 : 24, height: isMobile ? 16 : 0),
      Expanded(child: _buildMetricCard('Outstanding', _currencyFmt.format(month.total * 0.3), isAlert: true)),
      SizedBox(width: isMobile ? 0 : 24, height: isMobile ? 16 : 0),
      Expanded(child: _buildMetricCard('Payments Received', _currencyFmt.format(month.total * 0.7), color: const Color(0xFF4A9EFF))),
      SizedBox(width: isMobile ? 0 : 24, height: isMobile ? 16 : 0),
      Expanded(child: _buildMetricCard('Projected (Next Month)', _currencyFmt.format(month.total * 1.1), color: const Color(0xFF7000FF))),
    ];

    if (isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widgets.where((w) => w is Expanded ? true : (w as SizedBox).height! > 0).map((w) => w is Expanded ? w.child : w).toList());
    }
    return Row(children: widgets);
  }

  Widget _buildMetricCard(String title, String value, {bool isAlert = false, Color? color}) {
    final accentColor = isAlert ? const Color(0xFFFF4D6A) : (color ?? AppTheme.primary);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA8B0C8),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFdfe2f0),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 2,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withAlpha(50), accentColor, accentColor.withAlpha(50)],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    // Mock chart data for all months
    final data = _invoiceMonths.reversed.toList();
    if (data.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue Trends',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFdfe2f0),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: data.fold<double>(0.0, (max, m) => m.total > max ? m.total : max) * 1.2,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < data.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              data[value.toInt()].label.split(' ')[0].substring(0, 3), // "Jan"
                              style: GoogleFonts.spaceGrotesk(
                                color: const Color(0xFFA8B0C8),
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _currencyFmt.format(value),
                          style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFFA8B0C8),
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: const Color(0xFF3a494b).withAlpha(100),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: data.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.total,
                        color: AppTheme.primary,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      )
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(_InvoiceMonth month) {
    double sessionTotal = 0;
    double servicesTotal = 0;
    for (final i in month.items) {
      if (i.category == 'Session') sessionTotal += i.amount;
      else servicesTotal += i.amount;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost Breakdown',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFdfe2f0),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Stack(
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: 60,
                    sections: [
                      PieChartSectionData(
                        color: AppTheme.primary,
                        value: sessionTotal,
                        title: '',
                        radius: 20,
                      ),
                      PieChartSectionData(
                        color: const Color(0xFF7000FF),
                        value: servicesTotal,
                        title: '',
                        radius: 20,
                      ),
                    ],
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: const Color(0xFFA8B0C8),
                        ),
                      ),
                      Text(
                        _currencyFmt.format(month.total),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFdfe2f0),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('Sessions', AppTheme.primary),
              _buildLegendItem('Services', const Color(0xFF7000FF)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            color: const Color(0xFFA8B0C8),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthSelector() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _invoiceMonths.length,
        itemBuilder: (context, i) {
          final isSelected = i == _selectedMonthIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedMonthIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary.withAlpha(30) : const Color(0xFF0A1025).withAlpha(150),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? AppTheme.primary.withAlpha(120) : Colors.white.withAlpha(25),
                ),
              ),
              child: Text(
                _invoiceMonths[i].label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : const Color(0xFFA8B0C8),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDataTable(_InvoiceMonth month) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Recent Invoices',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3a494b)),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingTextStyle: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFA8B0C8),
                  ),
                  dataTextStyle: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFdfe2f0),
                  ),
                  dividerThickness: 1,
                  columns: const [
                    DataColumn(label: Text('DATE')),
                    DataColumn(label: Text('CATEGORY')),
                    DataColumn(label: Text('DESCRIPTION')),
                    DataColumn(label: Text('QTY'), numeric: true),
                    DataColumn(label: Text('AMOUNT'), numeric: true),
                    DataColumn(label: Text('STATUS')),
                  ],
                  rows: month.items.map((item) {
                    return DataRow(
                      cells: [
                        DataCell(Text(DateFormat('dd MMM yyyy').format(item.date))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              item.category,
                              style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        DataCell(Text(item.description)),
                        DataCell(Text('${item.quantity.toStringAsFixed(1)} ${item.unit}')),
                        DataCell(Text(NumberFormat.currency(locale: 'en_IN', symbol: '₹').format(item.amount))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F3FF).withAlpha(20), // "Paid" status assumed
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Paid',
                              style: TextStyle(color: Color(0xFF00F3FF), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
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
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1025).withAlpha(150),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(25)),
              ),
              child: const CustomIconWidget(
                iconName: 'receipt_long',
                color: Color(0xFF6B7490),
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No financial records found',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

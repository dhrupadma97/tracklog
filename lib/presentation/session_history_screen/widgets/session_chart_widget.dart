import 'package:fl_chart/fl_chart.dart';

import '../../../core/app_export.dart';

// Anatomy locked: card with period tab selector inside top + LineChart + value label bottom
class SessionChartWidget extends StatefulWidget {
  final List<Map<String, dynamic>> sessions;

  const SessionChartWidget({super.key, required this.sessions});

  @override
  State<SessionChartWidget> createState() => _SessionChartWidgetState();
}

class _SessionChartWidgetState extends State<SessionChartWidget> {
  int _selectedPeriod = 0; // 0 = This Month, 1 = Last Month
  int? _touchedIndex;

  // Build daily hours data for the chart
  List<FlSpot> _buildSpots() {
    // Group sessions by day of month
    final Map<int, double> dailyHours = {};
    for (final s in widget.sessions) {
      final start = DateTime.parse(s['startTime'] as String);
      final day = start.day;
      final hours = (s['durationMinutes'] as int) / 60.0;
      dailyHours[day] = (dailyHours[day] ?? 0) + hours;
    }

    // Fill 20 days of data with 0 for days without sessions
    final spots = <FlSpot>[];
    for (int d = 1; d <= 20; d++) {
      spots.add(FlSpot(d.toDouble(), dailyHours[d] ?? 0.0));
    }
    return spots;
  }

  List<FlSpot> _buildLastMonthSpots() {
    // Simulated last month data
    return [
      const FlSpot(1, 0),
      const FlSpot(2, 2.1),
      const FlSpot(3, 0),
      const FlSpot(4, 4.5),
      const FlSpot(5, 3.2),
      const FlSpot(6, 0),
      const FlSpot(7, 1.8),
      const FlSpot(8, 5.0),
      const FlSpot(9, 2.7),
      const FlSpot(10, 0),
      const FlSpot(11, 3.3),
      const FlSpot(12, 4.1),
      const FlSpot(13, 1.2),
      const FlSpot(14, 0),
      const FlSpot(15, 6.0),
      const FlSpot(16, 2.8),
      const FlSpot(17, 0),
      const FlSpot(18, 3.5),
      const FlSpot(19, 4.2),
      const FlSpot(20, 1.0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = _selectedPeriod == 0 ? _buildSpots() : _buildLastMonthSpots();
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final chartMax = (maxY + 1).ceilToDouble();

    // Find max day label
    final maxSpot = spots.reduce((a, b) => a.y > b.y ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF3a494b), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period tab selector — anatomy locked: inside card top
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _PeriodTab(
                    label: 'This Month',
                    isSelected: _selectedPeriod == 0,
                    onTap: () => setState(() => _selectedPeriod = 0),
                  ),
                  const SizedBox(width: 4),
                  _PeriodTab(
                    label: 'Last Month',
                    isSelected: _selectedPeriod == 1,
                    onTap: () => setState(() => _selectedPeriod = 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: chartMax,
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 2,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: Color(0xFF3a494b),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 2,
                          reservedSize: 32,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}h',
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 10,
                              color: Color(0xFF6B7490),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 5,
                          reservedSize: 24,
                          getTitlesWidget: (v, _) => Text(
                            v.toInt().toString(),
                            style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 10,
                              color: Color(0xFF6B7490),
                            ),
                          ),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        color: AppTheme.primary,
                        barWidth: 2.5,
                        isCurved: true,
                        curveSmoothness: 0.3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary.withAlpha(51),
                              AppTheme.primary.withAlpha(0),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        tooltipRoundedRadius: 10,
                        tooltipBgColor: const Color(0xFF181B25),
                        getTooltipItems: (spots) => spots
                            .map(
                              (s) => LineTooltipItem(
                                '${s.y.toStringAsFixed(1)}h',
                                const TextStyle(
                                  fontFamily: 'Space Grotesk',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFdfe2f0),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Value label bottom — anatomy locked
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Peak: ${maxSpot.y.toStringAsFixed(1)} hrs on Day ${maxSpot.x.toInt()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _PeriodTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFFdfe2f0)
                  : const Color(0xFF6B7490),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            width: isSelected ? label.length * 7.5 : 0,
            decoration: BoxDecoration(
              color: AppTheme.secondary,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

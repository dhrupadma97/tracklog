import 'package:fl_chart/fl_chart.dart';

import '../../../core/app_export.dart';

// Anatomy locked: card with period tab selector inside top + LineChart + value label bottom
class SessionChartWidget extends StatefulWidget {
  final List<Map<String, dynamic>> sessions;
  final int selectedPeriod;
  final ValueChanged<int> onPeriodChanged;

  const SessionChartWidget({
    super.key,
    required this.sessions,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  @override
  State<SessionChartWidget> createState() => _SessionChartWidgetState();
}

class _SessionChartWidgetState extends State<SessionChartWidget> {
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

    // Fill 30 days of data with 0 for days without sessions
    final spots = <FlSpot>[];
    for (int d = 1; d <= 30; d++) {
      spots.add(FlSpot(d.toDouble(), dailyHours[d] ?? 0.0));
    }
    return spots;
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // NO SIMULATED DATA. This used to fall back to a hardcoded curve --
    // peak 6.0 hrs on day 15 -- whenever the selected period had no
    // sessions. A closed programme therefore drew a full month of track
    // time it never ran, directly beside a counter correctly reading
    // "0 sessions". Every figure on this screen has to come from a session.
    final spots = _buildSpots();
    final hasData = widget.sessions.isNotEmpty && spots.any((s) => s.y > 0);
    final maxY = hasData
        ? spots.map((s) => s.y).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final chartMax = hasData ? (maxY + 1).ceilToDouble() : 4.0;
    final maxSpot = hasData
        ? spots.reduce((a, b) => a.y > b.y ? a : b)
        : const FlSpot(0, 0);

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
                    isSelected: widget.selectedPeriod == 0,
                    onTap: () => widget.onPeriodChanged(0),
                  ),
                  const SizedBox(width: 4),
                  _PeriodTab(
                    label: 'Last Month',
                    isSelected: widget.selectedPeriod == 1,
                    onTap: () => widget.onPeriodChanged(1),
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
                    hasData
                        ? 'Peak: ${maxSpot.y.toStringAsFixed(1)} hrs on Day '
                            '${maxSpot.x.toInt()}'
                        : 'No sessions in this period',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasData ? AppTheme.primary : Colors.white38,
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

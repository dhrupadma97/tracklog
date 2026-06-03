import '../../../core/app_export.dart';

// Anatomy locked: large number top-left + subtitle below + icon button top-right
class HeroMetricWidget extends StatelessWidget {
  final double totalHours;
  final double totalCost;
  final int sessionCount;

  const HeroMetricWidget({
    super.key,
    required this.totalHours,
    required this.totalCost,
    required this.sessionCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${totalHours.toStringAsFixed(1)} hrs',
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFdfe2f0),
                    fontFeatures: [FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total track usage this month',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _HeroChip(
                      label:
                          '₹${(totalCost / 1000).toStringAsFixed(0)}K total cost',
                      color: AppTheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    _HeroChip(
                      label: '$sessionCount sessions',
                      color: AppTheme.info,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withAlpha(38),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.secondary.withAlpha(77),
                width: 1,
              ),
            ),
            child: Center(
              child: CustomIconWidget(
                iconName: 'bolt',
                color: AppTheme.secondary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final Color color;
  const _HeroChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Space Grotesk',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

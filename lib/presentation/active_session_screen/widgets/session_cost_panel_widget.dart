import '../../../core/app_export.dart';

// Tracks that have the 2-hour daily minimum billing rule
const _minBillingTrackCodes = {'T1', 'T2', 'T3', 'T3D', 'T3W'};

class SessionCostPanelWidget extends StatelessWidget {
  final double estimatedCost;
  final Duration elapsed;
  final bool sessionActive;
  final double hourlyRate;
  final String trackCode;
  final Duration dailyCumulativeDuration;

  const SessionCostPanelWidget({
    super.key,
    required this.estimatedCost,
    required this.elapsed,
    required this.sessionActive,
    required this.hourlyRate,
    this.trackCode = '',
    this.dailyCumulativeDuration = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMinBillingTrack = _minBillingTrackCodes.contains(trackCode);

    // For T1/T2/T3: cumulative daily billing with 2-hour minimum
    final totalDailyDuration = dailyCumulativeDuration + elapsed;
    final totalDailyHours = totalDailyDuration.inSeconds / 3600.0;

    final double billedHours;
    final double billedCost;
    final String billingNote;

    if (isMinBillingTrack) {
      if (totalDailyHours <= 2.0) {
        billedHours = 2.0;
        billedCost = 2.0 * hourlyRate;
        billingNote = '2h min · daily cumulative';
      } else {
        billedHours = totalDailyHours;
        billedCost = totalDailyHours * hourlyRate;
        billingNote = 'Per hour beyond 2h minimum';
      }
    } else {
      final billableHours = elapsed.inSeconds / 3600.0;
      billedHours = billableHours.ceilToDouble();
      billedCost = billedHours * hourlyRate;
      billingNote = 'Rounded to next hour';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sessionActive
                ? AppTheme.secondary.withAlpha(51)
                : const Color(0xFF3a494b),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withAlpha(38),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CustomIconWidget(
                    iconName: 'currency_rupee',
                    color: AppTheme.secondary,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Estimated Cost',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFA8B0C8),
                  ),
                ),
                const Spacer(),
                Text(billingNote, style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${estimatedCost.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontFamily: 'Space Grotesk',
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFdfe2f0),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'running',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: const Color(0xFF3a494b)),
            const SizedBox(height: 12),
            Row(
              children: [
                _CostSubItem(
                  label: isMinBillingTrack ? 'Daily Usage' : 'Actual Duration',
                  value: isMinBillingTrack
                      ? '${totalDailyHours.toStringAsFixed(2)} hrs'
                      : '${(elapsed.inSeconds / 3600.0).toStringAsFixed(2)} hrs',
                  color: const Color(0xFFA8B0C8),
                ),
                const SizedBox(width: 16),
                _CostSubItem(
                  label: isMinBillingTrack
                      ? 'Billed Hours'
                      : 'Billable (rounded)',
                  value:
                      '${billedHours.toStringAsFixed(isMinBillingTrack ? 2 : 0)} hr${billedHours != 1 ? 's' : ''}',
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 16),
                _CostSubItem(
                  label: 'Billed Est.',
                  value: '₹${billedCost.toStringAsFixed(0)}',
                  color: AppTheme.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CostSubItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CostSubItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

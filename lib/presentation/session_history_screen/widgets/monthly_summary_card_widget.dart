import 'package:intl/intl.dart';
import '../../../core/app_export.dart';

// Anatomy locked: value top + label bottom + accent icon, horizontal scroll (or vertical on tablet)
class MonthlySummaryCardWidget extends StatelessWidget {
  final double totalCost;
  final double totalHours;
  final int sessionCount;
  final int avgDurationMinutes;
  final bool vertical;
  final bool isLastMonth;

  /// The month actually on screen. The History tabs are anchored on the
  /// programme's last month of testing, which for a closed programme is not
  /// this month or last month, so it has to be passed in rather than worked
  /// out from today.
  final DateTime? month;

  const MonthlySummaryCardWidget({
    super.key,
    required this.totalCost,
    required this.totalHours,
    required this.sessionCount,
    required this.avgDurationMinutes,
    this.vertical = false,
    this.isLastMonth = false,
    this.month,
  });

  /// The month this card is describing.
  String get monthLabel {
    final m = month ??
        () {
          final now = DateTime.now();
          return DateTime(now.year, now.month - (isLastMonth ? 1 : 0));
        }();
    return DateFormat('MMMM yyyy').format(m);
  }

  String _formatAvgDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cards = [
      _SummaryData(
        label: 'Total Cost',
        value: '₹${(totalCost / 1000).toStringAsFixed(1)}K',
        iconName: 'currency_rupee',
        color: AppTheme.secondary,
        // Named from the date, not pinned. This read 'May 2026' whatever the
        // month actually was, so the card labelled live figures with a month
        // four months gone.
        subtitle: monthLabel,
      ),
      _SummaryData(
        label: 'Track Hours',
        value: '${totalHours.toStringAsFixed(1)}h',
        iconName: 'access_time',
        color: AppTheme.primary,
        subtitle: '$sessionCount sessions',
      ),
      _SummaryData(
        label: 'Avg Duration',
        value: _formatAvgDuration(avgDurationMinutes),
        iconName: 'timer',
        color: AppTheme.info,
        subtitle: 'per session',
      ),
      _SummaryData(
        label: 'Avg Cost/Session',
        value: sessionCount > 0
            ? '₹${(totalCost / sessionCount).toStringAsFixed(0)}'
            : '₹0',
        iconName: 'trending_up',
        color: AppTheme.accent,
        subtitle: 'per session',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20, bottom: 12),
            child: Row(
              children: [
                Text(
                  'Summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFdfe2f0),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1025),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF849495),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Monthly',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFdfe2f0),
                        ),
                      ),
                      const SizedBox(width: 4),
                      CustomIconWidget(
                        iconName: 'chevron_right',
                        color: const Color(0xFFA8B0C8),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (vertical)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cards
                  .map(
                    (d) => SizedBox(width: 140, child: _SummaryCard(data: d)),
                  )
                  .toList(),
            )
          else
            SizedBox(
              // 110 was 7 to 36 pixels short of the content, so the cards
              // showed overflow stripes on a narrow window. Found by the
              // widget test, not on screen.
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 20),
                itemCount: cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) =>
                    SizedBox(width: 130, child: _SummaryCard(data: cards[i])),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryData {
  final String label;
  final String value;
  final String iconName;
  final Color color;
  final String subtitle;
  const _SummaryData({
    required this.label,
    required this.value,
    required this.iconName,
    required this.color,
    required this.subtitle,
  });
}

class _SummaryCard extends StatelessWidget {
  final _SummaryData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: data.color.withAlpha(18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: data.color.withAlpha(51), width: 1),
      ),
      // Scales down rather than overflowing. The card sits in a strip of
      // fixed height, and the content is within a few pixels of it: a
      // larger OS text size, or a substituted font, tips it over and the
      // user gets yellow-and-black stripes. Found by a widget test.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 102,
          child: Column(
        // Sizes to its content. It used to rely on a Spacer, which needs a
        // bounded height: in a short row - a phone, or a narrow window - the
        // card overflowed and showed the yellow-and-black stripes.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CustomIconWidget(
                iconName: data.iconName,
                color: data.color,
                size: 16,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            data.subtitle,
            style: theme.textTheme.labelSmall?.copyWith(color: data.color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
        ),
      ),
    );
  }
}

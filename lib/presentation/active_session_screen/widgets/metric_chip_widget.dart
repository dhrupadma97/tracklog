import '../../../core/app_export.dart';

// Anatomy locked: pill container, icon + 2-line text (label + value)
class MetricChipWidget extends StatelessWidget {
  final String iconName;
  final String label;
  final String value;
  final bool isActive;

  const MetricChipWidget({
    super.key,
    required this.iconName,
    required this.label,
    required this.value,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AppTheme.primary.withAlpha(51)
                : const Color(0xFF849495),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primary.withAlpha(38)
                    : const Color(0xFF3a494b),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CustomIconWidget(
                  iconName: iconName,
                  color: isActive ? AppTheme.primary : const Color(0xFF6B7490),
                  size: 14,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFdfe2f0),
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

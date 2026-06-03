import 'package:intl/intl.dart';

import '../../../core/app_export.dart';

// V1 Rich Data Row — status badge + date + gate + engineer + duration + cost badge
class SessionListWidget extends StatelessWidget {
  final List<Map<String, dynamic>> sessions;

  const SessionListWidget({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyStateWidget(
          iconName: 'history',
          title: 'No sessions found',
          subtitle:
              'Sessions matching your filter will appear here. Track time starts automatically on NATRAX entry.',
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return _SessionListItem(session: sessions[index], index: index);
      }, childCount: sessions.length),
    );
  }
}

class _SessionListItem extends StatefulWidget {
  final Map<String, dynamic> session;
  final int index;

  const _SessionListItem({required this.session, required this.index});

  @override
  State<_SessionListItem> createState() => _SessionListItemState();
}

class _SessionListItemState extends State<_SessionListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + widget.index * 40),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    Future.delayed(
      Duration(milliseconds: widget.index * 50),
      () => mounted ? _entranceController.forward() : null,
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.session;
    final startTime = DateTime.parse(s['startTime'] as String);
    final dateStr = DateFormat('dd MMM').format(startTime);
    final timeStr = DateFormat('HH:mm').format(startTime);
    final status = s['status'] as String;
    final isWarning = status == 'warning';
    final cost = s['costINR'] as double;
    final durationMin = s['durationMinutes'] as int;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Container(
            decoration: BoxDecoration(
              color: isWarning
                  ? AppTheme.warning.withAlpha(13)
                  : const Color(0xFF0A1025),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isWarning
                    ? AppTheme.warning.withAlpha(64)
                    : const Color(0xFF3a494b),
                width: 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              splashColor: AppTheme.primary.withAlpha(13),
              highlightColor: AppTheme.primary.withAlpha(8),
              onTap: () {
                // TODO: Navigate to session detail
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Session ID + date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['id'] as String,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: const Color(0xFF6B7490),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${s['gate']}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: const Color(0xFFdfe2f0),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Status badge
                        StatusBadgeWidget(
                          status: isWarning
                              ? SessionStatus.warning
                              : SessionStatus.completed,
                          compact: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Metadata row
                    Row(
                      children: [
                        _MetaItem(
                          iconName: 'person',
                          value: s['engineer'] as String,
                          color: const Color(0xFFA8B0C8),
                        ),
                        const SizedBox(width: 14),
                        _MetaItem(
                          iconName: 'calendar_today',
                          value: '$dateStr · $timeStr',
                          color: const Color(0xFFA8B0C8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MetaItem(
                          iconName: 'timer',
                          value: _formatDuration(durationMin),
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 14),
                        _MetaItem(
                          iconName: 'map',
                          value: s['trackType'] as String,
                          color: const Color(0xFF4A9EFF),
                        ),
                        const Spacer(),
                        // Cost badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isWarning
                                ? AppTheme.warning.withAlpha(38)
                                : AppTheme.secondary.withAlpha(31),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isWarning
                                  ? AppTheme.warning.withAlpha(77)
                                  : AppTheme.secondary.withAlpha(64),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '₹${cost.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isWarning
                                  ? AppTheme.warning
                                  : AppTheme.secondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isWarning) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomIconWidget(
                              iconName: 'warning',
                              color: AppTheme.warning,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                s['notes'] as String,
                                style: TextStyle(
                                  fontFamily: 'Space Grotesk',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.warning,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final String iconName;
  final String value;
  final Color color;
  const _MetaItem({
    required this.iconName,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomIconWidget(iconName: iconName, color: color, size: 12),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

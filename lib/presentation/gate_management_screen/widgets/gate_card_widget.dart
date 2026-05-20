import 'package:intl/intl.dart';

import '../../../core/app_export.dart';
import './geofence_setup_screen.dart';

// Anatomy locked (adapted from RoomCard): zone label small top + gate name bold
// + GPS coords + track type chip + radius + active toggle + last used
class GateCardWidget extends StatefulWidget {
  final Map<String, dynamic> gate;
  final int index;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final void Function(double lat, double lng, int radiusMeters)?
  onGeofenceUpdated;

  const GateCardWidget({
    super.key,
    required this.gate,
    required this.index,
    required this.onToggleActive,
    required this.onDelete,
    required this.onEdit,
    this.onGeofenceUpdated,
  });

  @override
  State<GateCardWidget> createState() => _GateCardWidgetState();
}

class _GateCardWidgetState extends State<GateCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  final bool _swiping = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 280 + widget.index * 45),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          ),
        );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    Future.delayed(
      Duration(milliseconds: widget.index * 60),
      () => mounted ? _entranceController.forward() : null,
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  static const Map<String, Color> _trackTypeColors = {
    'HST': Color(0xFF4A9EFF),
    'DYN': Color(0xFF00C896),
    'BRK': Color(0xFFFF6B4A),
    'HC': Color(0xFFFFB547),
    'WSP': Color(0xFF9B7FFF),
    'GEN': Color(0xFF6B7490),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.gate;
    final isActive = g['isActive'] as bool;
    final trackType = g['trackType'] as String;
    final typeColor = _trackTypeColors[trackType] ?? const Color(0xFF6B7490);
    final lastUsed = DateTime.parse(g['lastUsed'] as String);
    final lastUsedStr = DateFormat('dd MMM, HH:mm').format(lastUsed);
    final lat = (g['lat'] as double).toStringAsFixed(4);
    final lng = (g['lng'] as double).toStringAsFixed(4);
    final radius = g['radiusMeters'] as int;
    final rate = g['hourlyRateINR'] as double;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Dismissible(
          key: Key(g['id'] as String),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: AppTheme.error.withAlpha(38),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomIconWidget(
                  iconName: 'delete',
                  color: AppTheme.error,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  'Delete',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1A2236),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text('Delete Gate', style: theme.textTheme.titleMedium),
                content: Text(
                  'Remove "${g['name']}"? This cannot be undone.',
                  style: theme.textTheme.bodyMedium,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: const Color(0xFFA8B0C8),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        color: AppTheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => widget.onDelete(),
          child: Container(
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF131929)
                  : const Color(0xFF0F1520),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isActive
                    ? typeColor.withAlpha(51)
                    : const Color(0xFF252E45),
                width: 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              splashColor: typeColor.withAlpha(13),
              onTap: widget.onEdit,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Zone label + track type chip + active toggle
                    Row(
                      children: [
                        // Zone label — anatomy locked: small label top
                        Row(
                          children: [
                            CustomIconWidget(
                              iconName: 'location_on',
                              color: typeColor,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              g['zone'] as String,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: typeColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        // Track type chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withAlpha(31),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: typeColor.withAlpha(77),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            trackType,
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: typeColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Active toggle
                        GestureDetector(
                          onTap: widget.onToggleActive,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 42,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppTheme.primary.withAlpha(51)
                                  : const Color(0xFF252E45),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isActive
                                    ? AppTheme.primary.withAlpha(128)
                                    : const Color(0xFF3A4460),
                                width: 1,
                              ),
                            ),
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOutCubic,
                              alignment: isActive
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AppTheme.primary
                                      : const Color(0xFF6B7490),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Gate name — anatomy locked: bold name
                    Text(
                      g['name'] as String,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isActive
                            ? const Color(0xFFE8EAF0)
                            : const Color(0xFF6B7490),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    // GPS coordinates row — anatomy locked: coords below name
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF252E45),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CustomIconWidget(
                            iconName: 'gps_fixed',
                            color: const Color(0xFF6B7490),
                            size: 12,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$lat° N, $lng° E',
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFA8B0C8),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 1,
                            height: 12,
                            color: const Color(0xFF3A4460),
                          ),
                          const SizedBox(width: 8),
                          CustomIconWidget(
                            iconName: 'fence',
                            color: const Color(0xFF6B7490),
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${radius}m',
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFA8B0C8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Bottom row: last used + rate + sessions
                    Row(
                      children: [
                        CustomIconWidget(
                          iconName: 'access_time',
                          color: const Color(0xFF6B7490),
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last: $lastUsedStr',
                          style: theme.textTheme.labelSmall,
                        ),
                        const Spacer(),
                        if (rate > 0) ...[
                          CustomIconWidget(
                            iconName: 'currency_rupee',
                            color: AppTheme.secondary,
                            size: 11,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${rate.toStringAsFixed(0)}/hr',
                            style: TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2236),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${g['totalSessionsThisMonth']} sessions',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFE8EAF0),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Set Geofence button
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => GeofenceSetupScreen(
                              existingGate: g,
                              onSave: (lat, lng, radius) {
                                widget.onGeofenceUpdated?.call(
                                  lat,
                                  lng,
                                  radius,
                                );
                              },
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9EFF).withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF4A9EFF).withAlpha(60),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              color: Color(0xFF4A9EFF),
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Set Geofence Boundary',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A9EFF),
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF4A9EFF),
                              size: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
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

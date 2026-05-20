import 'package:intl/intl.dart';

import '../../../core/app_export.dart';
import '../../../services/engineer_auth_service.dart';

class SessionStatusHeaderWidget extends StatelessWidget {
  final bool sessionActive;
  final bool gpsLocked;
  final bool inGeofence;
  final DateTime currentDate;
  final String engineerName;

  const SessionStatusHeaderWidget({
    super.key,
    required this.sessionActive,
    required this.gpsLocked,
    required this.inGeofence,
    required this.currentDate,
    required this.engineerName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('EEE, dd MMM').format(currentDate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // Goodyear SightLine logo
          Container(
            height: 32,
            width: 90,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6.0),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Image.asset(
              'assets/images/goodyear-sightline-logo-single-black-1779279917234.png',
              fit: BoxFit.contain,
              semanticLabel: 'Goodyear SightLine logo',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr, style: theme.textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  'NATRAX TrackLog',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFE8EAF0),
                  ),
                ),
              ],
            ),
          ),
          // GPS Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: gpsLocked
                  ? AppTheme.primary.withAlpha(38)
                  : AppTheme.warning.withAlpha(38),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: gpsLocked
                    ? AppTheme.primary.withAlpha(77)
                    : AppTheme.warning.withAlpha(77),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomIconWidget(
                  iconName: gpsLocked ? 'gps_fixed' : 'gps_not_fixed',
                  color: gpsLocked ? AppTheme.primary : AppTheme.warning,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  gpsLocked ? 'GPS Locked' : 'Searching',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: gpsLocked ? AppTheme.primary : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Engineer avatar with sign-out on long press
          GestureDetector(
            onLongPress: () => _showSignOutDialog(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1C2438),
                shape: BoxShape.circle,
                border: Border.all(
                  color: sessionActive
                      ? AppTheme.primary.withAlpha(128)
                      : const Color(0xFF3A4460),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  engineerName.isNotEmpty ? engineerName[0].toUpperCase() : 'E',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8EAF0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2236),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Sign Out',
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w700,
            color: Color(0xFFE8EAF0),
          ),
        ),
        content: Text(
          'Sign out of $engineerName\'s profile?',
          style: const TextStyle(
            fontFamily: 'Manrope',
            color: Color(0xFFA8B0C8),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(fontFamily: 'Manrope', color: Color(0xFFA8B0C8)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await EngineerAuthService.instance.signOut();
              if (context.mounted) context.go('/login');
            },
            child: const Text(
              'Sign Out',
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
  }
}

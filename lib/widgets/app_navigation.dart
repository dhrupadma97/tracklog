import 'dart:ui';

import '../core/app_export.dart';
import '../services/engineer_auth_service.dart';

// V3 Liquid Glass — BackdropFilter blur + frosted surface + animated pill — LOCKED
class AppNavigation extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppNavigation({required this.navigationShell, super.key});

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation>
    with SingleTickerProviderStateMixin {
  late AnimationController _pillController;
  late Animation<double> _pillAnimation;
  int _lastIndex = 0;
  bool _isManager = false;

  static const List<_TabSpec> _allTabs = [
    _TabSpec(
      icon: 'timer',
      selectedIcon: 'timer',
      label: 'Session',
      branchIndex: 0,
    ),
    _TabSpec(
      icon: 'history',
      selectedIcon: 'history',
      label: 'History',
      branchIndex: 1,
    ),
    _TabSpec(
      icon: 'location_on',
      selectedIcon: 'location_on',
      label: 'Gates',
      branchIndex: 2,
    ),
    _TabSpec(
      icon: 'receipt_long',
      selectedIcon: 'receipt_long',
      label: 'PO',
      branchIndex: 3,
    ),
    _TabSpec(
      icon: 'email',
      selectedIcon: 'email',
      label: 'Reports',
      branchIndex: 4,
    ),
    _TabSpec(
      icon: 'settings',
      selectedIcon: 'settings',
      label: 'Settings',
      branchIndex: 5,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _pillAnimation = CurvedAnimation(
      parent: _pillController,
      curve: Curves.easeInOutCubic,
    );
    _loadRole();
  }

  Future<void> _loadRole() async {
    final profile = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted) {
      setState(() {
        _isManager = profile?.userRole == 'manager';
      });
    }
  }

  @override
  void dispose() {
    _pillController.dispose();
    super.dispose();
  }

  void _onTap(int visualIndex) {
    final spec = _allTabs[visualIndex];
    if (spec.branchIndex == null) return;
    if (visualIndex != _lastIndex) {
      _lastIndex = visualIndex;
      _pillController.forward(from: 0);
    }
    setState(() {});
    widget.navigationShell.goBranch(
      spec.branchIndex!,
      initialLocation: spec.branchIndex == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBranch = widget.navigationShell.currentIndex;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2236).withAlpha(217),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: const Color(0xFF3A4460).withAlpha(153),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(102),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_allTabs.length, (i) {
                  final spec = _allTabs[i];
                  final isActive =
                      spec.branchIndex != null &&
                      spec.branchIndex == currentBranch;
                  final isStub = spec.branchIndex == null;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _onTap(i),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedOpacity(
                        opacity: isStub ? 0.4 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeInOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppTheme.primary.withAlpha(51)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: CustomIconWidget(
                                iconName: isActive
                                    ? spec.selectedIcon
                                    : spec.icon,
                                color: isActive
                                    ? AppTheme.primary
                                    : const Color(0xFF6B7490),
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 10,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isActive
                                    ? AppTheme.primary
                                    : const Color(0xFF6B7490),
                              ),
                              child: Text(spec.label),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  final String icon;
  final String selectedIcon;
  final String label;
  final int? branchIndex;
  const _TabSpec({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.branchIndex,
  });
}

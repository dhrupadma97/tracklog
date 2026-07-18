import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/app_export.dart';
import '../services/engineer_auth_service.dart';

// V4 Premium — Glow Pill + Bounce + Gradient + Teal top-accent — LOCKED
class AppNavigation extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppNavigation({required this.navigationShell, super.key});

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation>
    with TickerProviderStateMixin {
  late AnimationController _pillController;
  final Map<int, AnimationController> _bounceControllers = {};
  int _lastIndex = 0;
  bool _isManager = false;

  List<_TabSpec> get _tabs {
    final list = <_TabSpec>[];

    // 0. Projects
    list.add(const _TabSpec(
      icon: 'workspaces_outlined',
      selectedIcon: 'workspaces',
      label: 'Projects',
      branchIndex: -1,
    ));

    // 1. Analyser
    list.add(const _TabSpec(
      icon: 'analytics',
      selectedIcon: 'analytics',
      label: 'Analyser',
      branchIndex: 4,
    ));

    // 2. Sessions (mobile only, center tab)
    if (!kIsWeb) {
      list.add(const _TabSpec(
        icon: 'play_circle_outline',
        selectedIcon: 'play_circle',
        label: 'Sessions',
        branchIndex: 0,
      ));
    }

    // 3. Tracks (web only)
    if (kIsWeb) {
      list.add(const _TabSpec(
        icon: 'map',
        selectedIcon: 'map',
        label: 'Tracks',
        branchIndex: 1,
      ));
    }

    // 4. Manual Entry
    list.add(const _TabSpec(
      icon: 'edit_note',
      selectedIcon: 'edit_note',
      label: 'Manual Entry',
      branchIndex: 3,
    ));

    // 5. Settings
    list.add(const _TabSpec(
      icon: 'settings',
      selectedIcon: 'settings',
      label: 'Settings',
      branchIndex: 5,
    ));

    // 6. Admin
    if (_isManager) {
      list.add(const _TabSpec(
        icon: 'admin_panel_settings',
        selectedIcon: 'admin_panel_settings',
        label: 'Admin',
        branchIndex: 6,
      ));
    }

    // 7. Updates & Trends (web only)
    if (kIsWeb) {
      list.addAll([
        const _TabSpec(
          icon: 'campaign',
          selectedIcon: 'campaign',
          label: 'Updates',
          branchIndex: 7,
        ),
        const _TabSpec(
          icon: 'trending_up',
          selectedIcon: 'trending_up',
          label: 'Trends',
          branchIndex: 8,
        ),
      ]);
    }

    // 8. Instruments (web + mobile) — instrumentation setup planner
    list.add(const _TabSpec(
      icon: 'precision_manufacturing',
      selectedIcon: 'precision_manufacturing',
      label: 'Instruments',
      branchIndex: 9,
    ));

    return list;
  }

  @override
  void initState() {
    super.initState();
    _pillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _loadRole();
  }

  void _ensureBounceController(int index) {
    if (!_bounceControllers.containsKey(index)) {
      _bounceControllers[index] = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
    }
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
    for (final c in _bounceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTap(int visualIndex) {
    final spec = _tabs[visualIndex];
    if (spec.branchIndex == null) return;

    // Trigger bounce
    _ensureBounceController(visualIndex);
    _bounceControllers[visualIndex]!.forward(from: 0);

    if (visualIndex != _lastIndex) {
      _lastIndex = visualIndex;
      _pillController.forward(from: 0);
    }
    setState(() {});
    if (spec.branchIndex == -1) {
      context.go('/project-selection');
    } else {
      widget.navigationShell.goBranch(
        spec.branchIndex!,
        initialLocation: spec.branchIndex == widget.navigationShell.currentIndex,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentBranch = widget.navigationShell.currentIndex;
    final tabs = _tabs;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Stack(
          children: [
            // Ambient glow under active tab
            _buildAmbientGlow(tabs, currentBranch, context),
            // Main nav container
            ClipRRect(
              borderRadius: BorderRadius.circular(36),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: const Color(0xFF080E1E).withAlpha(210),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(
                      color: const Color(0xFF00F3FF).withAlpha(28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(140),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: const Color(0xFF7000FF).withAlpha(18),
                        blurRadius: 24,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // Teal top-accent gradient line
                      Positioned(
                        top: 0,
                        left: 24,
                        right: 24,
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF00F3FF).withAlpha(180),
                                const Color(0xFF7000FF).withAlpha(120),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.35, 0.65, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Tab items
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: List.generate(tabs.length, (i) {
                          _ensureBounceController(i);
                          final spec = tabs[i];
                          final state = GoRouterState.of(context);
                          final isProjectSelection =
                              state.matchedLocation == '/project-selection';
                          final isActive = spec.branchIndex == -1
                              ? isProjectSelection
                              : (spec.branchIndex != null &&
                                  spec.branchIndex == currentBranch &&
                                  !isProjectSelection);
                          final isStub = spec.branchIndex == null;

                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _onTap(i),
                              behavior: HitTestBehavior.opaque,
                              child: AnimatedOpacity(
                                opacity: isStub ? 0.35 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: _buildTabItem(
                                  spec: spec,
                                  isActive: isActive,
                                  bounceController: _bounceControllers[i]!,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmbientGlow(
      List<_TabSpec> tabs, int currentBranch, BuildContext context) {
    // Find active tab position for glow
    final state = GoRouterState.of(context);
    final isProjectSelection = state.matchedLocation == '/project-selection';
    int activeIdx = 0;
    for (int i = 0; i < tabs.length; i++) {
      final spec = tabs[i];
      final active = spec.branchIndex == -1
          ? isProjectSelection
          : (spec.branchIndex != null &&
              spec.branchIndex == currentBranch &&
              !isProjectSelection);
      if (active) {
        activeIdx = i;
        break;
      }
    }
    final fraction = tabs.isEmpty ? 0.5 : (activeIdx + 0.5) / tabs.length;

    return Positioned(
      bottom: 4,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        height: 40,
        child: Align(
          alignment: Alignment(fraction * 2 - 1, 0),
          child: Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF00F3FF).withAlpha(55),
                  const Color(0xFF7000FF).withAlpha(20),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required _TabSpec spec,
    required bool isActive,
    required AnimationController bounceController,
  }) {
    return AnimatedBuilder(
      animation: bounceController,
      builder: (context, child) {
        // Elastic bounce: scale 1 → 1.2 → 0.95 → 1.0
        final t = bounceController.value;
        double scale = 1.0;
        if (t < 0.3) {
          scale = 1.0 + (t / 0.3) * 0.2;
        } else if (t < 0.6) {
          scale = 1.2 - ((t - 0.3) / 0.3) * 0.25;
        } else {
          scale = 0.95 + ((t - 0.6) / 0.4) * 0.05;
        }
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon with glow pill
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              gradient: isActive
                  ? LinearGradient(
                      colors: [
                        const Color(0xFF00F3FF).withAlpha(40),
                        const Color(0xFF7000FF).withAlpha(25),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isActive ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: isActive
                  ? Border.all(
                      color: const Color(0xFF00F3FF).withAlpha(70),
                      width: 1,
                    )
                  : null,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00F3FF).withAlpha(45),
                        blurRadius: 12,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: isActive
                ? ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00F3FF), Color(0xFF7000FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    blendMode: BlendMode.srcIn,
                    child: CustomIconWidget(
                      iconName: spec.selectedIcon,
                      color: Colors.white,
                      size: 23,
                    ),
                  )
                : CustomIconWidget(
                    iconName: spec.icon,
                    color: const Color(0xFF8892B0),
                    size: 22,
                  ),
          ),
          const SizedBox(height: 3),
          // Label with animated style
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: isActive ? 9.5 : 9,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              color: isActive
                  ? const Color(0xFF00F3FF)
                  : const Color(0xFF5A6480),
              letterSpacing: isActive ? 0.2 : 0,
            ),
            child: Text(spec.label),
          ),
          // Teal dot underline for active tab
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            margin: const EdgeInsets.only(top: 2),
            width: isActive ? 16 : 0,
            height: 2,
            decoration: BoxDecoration(
              gradient: isActive
                  ? const LinearGradient(
                      colors: [Color(0xFF00F3FF), Color(0xFF7000FF)],
                    )
                  : null,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
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

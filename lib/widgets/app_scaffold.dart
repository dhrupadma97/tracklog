import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import './app_navigation.dart';
import '../services/engineer_auth_service.dart';

class AppScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 900;

    if (isWide) {
      return _WideScaffold(navigationShell: navigationShell);
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFF050811),
      body: Stack(
        children: [
          // Goodyear background image with dark overlay — applied globally
          Positioned.fill(
            child: Image.asset(
              'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
              fit: BoxFit.cover,
              semanticLabel: 'Goodyear racing team wallpaper',
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF042024).withAlpha(225), // Premium deep teal-green gradient start
                    const Color(0xFF030712).withAlpha(245), // Dark space black gradient end
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          navigationShell,
        ],
      ),
      bottomNavigationBar: AppNavigation(navigationShell: navigationShell),
    );
  }
}

/// Wide-screen layout: persistent left rail navigation + content area.
class _WideScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const _WideScaffold({required this.navigationShell});

  @override
  State<_WideScaffold> createState() => _WideScaffoldState();
}

class _WideScaffoldState extends State<_WideScaffold> {
  bool _isManager = false;
  EngineerProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final profile = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _isManager = profile?.userRole == 'manager';
      });
    }
  }

  List<_NavItem> _getItems() {
    final items = <_NavItem>[];
    
    // 0. Projects
    items.add(const _NavItem(
      icon: Icons.workspaces_outlined,
      activeIcon: Icons.workspaces,
      label: 'Projects',
      branch: 10,
    ));

    // 1. Analyser
    items.add(const _NavItem(
      icon: Icons.analytics_outlined,
      activeIcon: Icons.analytics_rounded,
      label: 'Analyser',
      branch: 4,
    ));

    // 2. Sessions (mobile only, center tab)
    if (!kIsWeb) {
      items.add(const _NavItem(
        icon: Icons.play_circle_outline_rounded,
        activeIcon: Icons.play_circle_filled_rounded,
        label: 'Sessions',
        branch: 0,
      ));
    }

    // 3. Tracks (web only)
    if (kIsWeb) {
      items.add(const _NavItem(
        icon: Icons.map_outlined,
        activeIcon: Icons.map,
        label: 'Tracks',
        branch: 1,
      ));
    }

    // 4. Manual Entry
    items.add(const _NavItem(
      icon: Icons.edit_note_outlined,
      activeIcon: Icons.edit_note_rounded,
      label: 'Manual Entry',
      branch: 3,
    ));

    // 5. Settings
    items.add(const _NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
      branch: 5,
    ));

    // 6. Admin
    if (_isManager) {
      items.add(const _NavItem(
        icon: Icons.admin_panel_settings_outlined,
        activeIcon: Icons.admin_panel_settings_rounded,
        label: 'Admin',
        branch: 6,
      ));
    }

    // 7. Updates & Trends & Instruments
    if (kIsWeb) {
      items.addAll([
        const _NavItem(
          icon: Icons.campaign_outlined,
          activeIcon: Icons.campaign_rounded,
          label: 'Updates',
          branch: 7,
        ),
        const _NavItem(
          icon: Icons.trending_up_outlined,
          activeIcon: Icons.trending_up_rounded,
          label: 'Trends',
          branch: 8,
        ),
        const _NavItem(
          icon: Icons.precision_manufacturing_outlined,
          activeIcon: Icons.precision_manufacturing,
          label: 'Instruments',
          branch: 9,
        ),
      ]);
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.navigationShell.currentIndex;
    final items = _getItems();

    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
              fit: BoxFit.cover,
              semanticLabel: 'Goodyear racing team wallpaper',
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF042024).withAlpha(225), // Premium deep teal-green gradient start
                    const Color(0xFF030712).withAlpha(245), // Dark space black gradient end
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          Row(
            children: [
              // Left rail
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1025).withAlpha(153),
                      border: Border(
                        right: BorderSide(
                          color: const Color(0xFF849495).withAlpha(50),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF00F3FF,
                                    ).withAlpha(30),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF00F3FF,
                                      ).withAlpha(80),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.track_changes,
                                    color: Color(0xFF00F3FF),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'TrackLog',
                                  style: TextStyle(
                                    fontFamily: 'Space Grotesk',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFdfe2f0),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          ...List.generate(items.length, (i) {
                            final item = items[i];
                            final state = GoRouterState.of(context);
                            final isActive = item.branch == current;
                            return _RailItem(
                              item: item,
                              isActive: isActive,
                              onTap: () {
                                widget.navigationShell.goBranch(
                                  item.branch,
                                  initialLocation: item.branch == current,
                                );
                              },
                            );
                          }),
                          const Spacer(),
                          if (_profile != null || EngineerAuthService.instance.currentUser != null)
                            _buildProfileSection(context),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(child: widget.navigationShell),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    final name = _profile?.engineerName ??
        EngineerAuthService.instance.currentUser?.email?.split('@').first ??
        'User';
    final role = _profile?.department ?? (_isManager ? 'Manager' : 'Engineer');
    final initials = name.isNotEmpty
        ? name.substring(0, name.length < 2 ? name.length : 2).toUpperCase()
        : 'U';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF849495).withAlpha(60),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF00F3FF).withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00F3FF).withAlpha(85),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00F3FF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFdfe2f0),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      role,
                      style: const TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7490),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF3a494b)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              await EngineerAuthService.instance.signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFFFB4AB),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Logout',
                    style: TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFFB4AB),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _RailItem extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _RailItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF00F3FF).withAlpha(30)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: const Color(0xFF00F3FF).withAlpha(80))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive
                  ? const Color(0xFF00F3FF)
                  : const Color(0xFF6B7490),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFF00F3FF)
                    : const Color(0xFF6B7490),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int branch;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.branch,
  });
}

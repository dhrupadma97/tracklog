import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import './app_navigation.dart';

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
      backgroundColor: const Color(0xFF0A0E1A),
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
            child: Container(color: const Color(0xFF0A0E1A).withAlpha(215)),
          ),
          navigationShell,
        ],
      ),
      bottomNavigationBar: AppNavigation(navigationShell: navigationShell),
    );
  }
}

/// Wide-screen layout: persistent left rail navigation + content area.
class _WideScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const _WideScaffold({required this.navigationShell});

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.timer_outlined,
      activeIcon: Icons.timer,
      label: 'Session',
      branch: 0,
    ),
    _NavItem(
      icon: Icons.history_outlined,
      activeIcon: Icons.history,
      label: 'History',
      branch: 1,
    ),
    _NavItem(
      icon: Icons.location_on_outlined,
      activeIcon: Icons.location_on,
      label: 'Gates',
      branch: 2,
    ),
    _NavItem(
      icon: Icons.email_outlined,
      activeIcon: Icons.email,
      label: 'Reports',
      branch: 3,
    ),
    _NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Invoices',
      branch: 4,
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Settings',
      branch: 5,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
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
            child: Container(color: const Color(0xFF0A0E1A).withAlpha(215)),
          ),
          Row(
            children: [
              // Left rail
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1520).withAlpha(230),
                      border: Border(
                        right: BorderSide(
                          color: const Color(0xFF3A4460).withAlpha(120),
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
                                      0xFF00C896,
                                    ).withAlpha(30),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF00C896,
                                      ).withAlpha(80),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.track_changes,
                                    color: Color(0xFF00C896),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text(
                                  'TrackLog',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFE8EAF0),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          ...List.generate(_items.length, (i) {
                            final item = _items[i];
                            final isActive = item.branch == current;
                            return _RailItem(
                              item: item,
                              isActive: isActive,
                              onTap: () => navigationShell.goBranch(
                                item.branch,
                                initialLocation: item.branch == current,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Expanded(child: navigationShell),
            ],
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
              ? const Color(0xFF00C896).withAlpha(30)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: const Color(0xFF00C896).withAlpha(80))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? item.activeIcon : item.icon,
              color: isActive
                  ? const Color(0xFF00C896)
                  : const Color(0xFF6B7490),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFF00C896)
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import './app_navigation.dart';

class AppScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const AppScaffold({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context) {
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

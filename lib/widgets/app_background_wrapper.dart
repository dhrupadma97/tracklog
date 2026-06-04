import 'package:flutter/material.dart';

class AppBackgroundWrapper extends StatelessWidget {
  final Widget child;

  const AppBackgroundWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 0: Background Texture
        Positioned.fill(
          child: Container(
            color: const Color(0xFF030712), // background-deep
          ),
        ),
        Positioned.fill(
          child: Image.asset(
            'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
            fit: BoxFit.cover,
            color: const Color(0xFF030712).withAlpha(220),
            colorBlendMode: BlendMode.srcOver,
          ),
        ),
        
        // Brand Identity Overlay (Persistent)
        Positioned(
          top: 24,
          right: 24,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color(0xFF00F3FF),
              BlendMode.srcIn,
            ),
            child: Image.asset(
              'assets/images/goodyear-sightline-logo-single-black-1779279917234.png',
              height: 32,
            ),
          ),
        ),

        // Main Content Layer
        Positioned.fill(child: child),
      ],
    );
  }
}

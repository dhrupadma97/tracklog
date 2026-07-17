import 'package:flutter/material.dart';

class AppBackgroundWrapper extends StatelessWidget {
  final Widget child;

  const AppBackgroundWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Layer 0: Background Image
        Positioned.fill(
          child: Image.asset(
            'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
            fit: BoxFit.cover,
            semanticLabel: 'Goodyear racing team wallpaper',
          ),
        ),
        // Layer 1: Gradient Overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF042024).withAlpha(225),
                  const Color(0xFF030712).withAlpha(245),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
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

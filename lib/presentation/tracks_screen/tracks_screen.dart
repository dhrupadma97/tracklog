import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/app_export.dart';
import '../../services/project_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';
import 'track_details_widgets.dart';

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> with TickerProviderStateMixin {
  int _selectedTrackIndex = 0; // 0 = HST, 1 = T2, 2 = T3, 3 = T7, 4 = T8, 5 = T11
  String _activeProject = '';

  // Proving Ground Configuration - Kept as variables to allow easy extension to other Indian test tracks in the future
  final String _provingGroundName = 'NATRAX';
  final String _provingGroundLogo = 'assets/images/NATRAX LOGO.png';
  late AnimationController _painterAnimController;
  late AnimationController _uiAnimController;

  final List<Map<String, dynamic>> _tracks = [
    {
      'code': 'HST',
      'name': 'High Speed Track',
      'number': 'T1',
      'icon': 'speed',
      'color': const Color(0xFF00F3FF),
      'desc': '11.36 km oval track designed for high-speed tyre intelligence, neutral steering at bends, and lane stability testing.',
      'length': '11.36 km',
      'width': '4 Lanes',
      'speed': '350 km/h max',
    },
    {
      'code': 'DYN',
      'name': 'Dynamic Platform',
      'number': 'T2',
      'icon': 'adjust',
      'color': const Color(0xFFFFB547),
      'desc': '300m diameter circular platform connected to a 1.5 km long vehicle dynamics test straight for extreme handling.',
      'length': '300m dia',
      'width': 'Slalom Area',
      'speed': 'Variable',
    },
    {
      'code': 'BRK',
      'name': 'Straight Braking Track',
      'number': 'T3',
      'icon': 'merge_type',
      'color': const Color(0xFFFF4D6A),
      'desc': 'Multi-friction braking track with 8 specialized lanes (polished concrete, asphalt, ceramic, basalt) and sprinkler wetting.',
      'length': '250m - 350m',
      'width': '8 Lanes',
      'speed': '8T Max Axle',
    },
    {
      'code': 'HDL',
      'name': 'Dry Handling Track',
      'number': 'T7',
      'icon': 'gesture',
      'color': const Color(0xFFA855F7),
      'desc': '3.6 km curvy circuit with multiple configurations for tyre lateral grip, transient response, and steering feel testing.',
      'length': '3.63 km',
      'width': '8.0m Width',
      'speed': '5 Cars Max',
    },
    {
      'code': 'CMF',
      'name': 'Ride Comfort Track',
      'number': 'T8',
      'icon': 'waves',
      'color': const Color(0xFF4ADE80),
      'desc': 'Ride evaluation track featuring structured obstacles (washboards, rough concrete, steps, potholes) for tyre noise/harshness.',
      'length': '150m - 800m',
      'width': '4.0m Width',
      'speed': '150 km/h max',
    },
    {
      'code': 'WSP',
      'name': 'Wet Skid Pad',
      'number': 'T11',
      'icon': 'water',
      'color': const Color(0xFF38BDF8),
      'desc': 'Circular test track featuring two low-friction surfaces (Basalt and Asphalt) with an active watering system, designed for ESP, TCS, and tyre lateral adhesion testing.',
      'length': 'Radius 45m / 80m',
      'width': '2 Lanes (Concentric)',
      'speed': '80 km/h max',
    },
  ];

  @override
  void initState() {
    super.initState();
    _activeProject = ProjectManager.instance.activeProject;
    ProjectManager.instance.addListener(_onProjectChanged);

    _painterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _uiAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _uiAnimController.forward();
  }

  @override
  void dispose() {
    ProjectManager.instance.removeListener(_onProjectChanged);
    _painterAnimController.dispose();
    _uiAnimController.dispose();
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted && _activeProject != ProjectManager.instance.activeProject) {
      setState(() => _activeProject = ProjectManager.instance.activeProject);
    }
  }

  void _onTrackSelected(int index) {
    if (index != _selectedTrackIndex) {
      setState(() {
        _selectedTrackIndex = index;
      });
      _uiAnimController.reset();
      _uiAnimController.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 900;
    final track = _tracks[_selectedTrackIndex];
    final color = track['color'] as Color;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dynamic ambient glows in the background matching selected track's color
          Positioned(
            top: -150,
            left: -100,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 500,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withOpacity(0.09),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 450,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00F3FF).withOpacity(0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: isTablet ? _buildDesktopLayout(theme) : _buildMobileLayout(theme),
          ),
        ],
      ),
    );
  }

  // ── Desktop/Wide Layout (Top horizontal selector, narration details scrollable under) ──────────────
  Widget _buildDesktopLayout(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme),
        // Horizontal sliding track selection bar
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: _tracks.length,
            itemBuilder: (context, i) {
              final track = _tracks[i];
              final isSelected = i == _selectedTrackIndex;
              final color = track['color'] as Color;
              return GestureDetector(
                onTap: () => _onTrackSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  margin: const EdgeInsets.only(right: 14),
                  padding: const EdgeInsets.all(12),
                  width: 220,
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withOpacity(0.25),
                              color.withOpacity(0.06),
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF0A1025).withAlpha(160),
                              const Color(0xFF0A1025).withAlpha(110),
                            ],
                          ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? color : const Color(0xFF3a494b).withOpacity(0.4),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withOpacity(0.12),
                              blurRadius: 10,
                              spreadRadius: 1,
                              offset: const Offset(0, 3),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected ? color.withOpacity(0.2) : const Color(0xFF1E293B).withOpacity(0.4),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? color.withOpacity(0.6) : const Color(0xFF3a494b).withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            _getIconData(track['icon'] as String),
                            color: isSelected ? color : const Color(0xFF6B7490),
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Text(
                                  track['number'] as String,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    track['code'] as String,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track['name'] as String,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : const Color(0xFFdfe2f0).withOpacity(0.8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Expanded narration detail panel scrollable below track list
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: AnimatedBuilder(
              animation: _uiAnimController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _uiAnimController,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.02),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _uiAnimController,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: _buildDetailPanel(theme),
            ),
          ),
        ),
      ],
    );
  }

  // ── Mobile/Phone Layout (Horizontal tabs top, detail view scrollable below)
  Widget _buildMobileLayout(ThemeData theme) {
    return Column(
      children: [
        _buildHeader(theme),
        // Horizontal sliding track list
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _tracks.length,
            itemBuilder: (context, i) {
              final track = _tracks[i];
              final isSelected = i == _selectedTrackIndex;
              final color = track['color'] as Color;
              return GestureDetector(
                onTap: () => _onTrackSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  width: 140,
                  decoration: BoxDecoration(
                    color: isSelected ? color.withAlpha(30) : const Color(0xFF0A1025).withAlpha(200),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? color : const Color(0xFF3a494b),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            track['number'] as String,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                          Icon(
                            _getIconData(track['icon'] as String),
                            color: color,
                            size: 14,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        track['name'] as String,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Detail panel
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: _buildDetailPanel(theme),
          ),
        ),
      ],
    );
  }

  // ── Header Section ─────────────────────────────────────────────────────────
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (kIsWeb)
                GestureDetector(
                  onTap: () => context.go('/project-selection'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF94A3B8), size: 14),
                      const SizedBox(width: 4),
                      Text('Projects',
                          style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF94A3B8))),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              Text(
                '$_provingGroundName Facilities',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: const Color(0xFFFF6B00),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Test Tracks',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Image.asset(
                'assets/images/goodyear_sightline_logo.png',
                height: 24,
                color: Colors.white70,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Image.asset(
                _provingGroundLogo,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withAlpha(80)),
                ),
                child: Text(
                  _activeProject,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Right/Main Detail Panel ────────────────────────────────────────────────
  Widget _buildDetailPanel(ThemeData theme) {
    final track = _tracks[_selectedTrackIndex];
    final color = track['color'] as Color;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWidePanel = constraints.maxWidth >= 700;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Track Banner Details
            _buildTrackBanner(track, color, theme),
            const SizedBox(height: 20),

            // Dynamic layout based on selected track
            if (_selectedTrackIndex == 0) ...[
              HstDetails(theme: theme, color: color, isWide: isWidePanel, animation: _painterAnimController)
            ] else if (_selectedTrackIndex == 1) ...[
              T2Details(theme: theme, color: color, isWide: isWidePanel, animation: _painterAnimController)
            ] else if (_selectedTrackIndex == 2) ...[
              T3Details(theme: theme, color: color, isWide: isWidePanel, animation: _painterAnimController)
            ] else if (_selectedTrackIndex == 3) ...[
              T7Details(theme: theme, color: color, isWide: isWidePanel, animation: _painterAnimController)
            ] else if (_selectedTrackIndex == 4) ...[
              T8Details(theme: theme, color: color, isWide: isWidePanel, animation: _painterAnimController)
            ] else if (_selectedTrackIndex == 5) ...[
              T11Details(theme: theme, color: color, isWide: isWidePanel, animation: _painterAnimController)
            ],
          ],
        );
      },
    );
  }

  // ── Track Summary Banner Card ──────────────────────────────────────────────
  Widget _buildTrackBanner(Map<String, dynamic> track, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.08),
            const Color(0xFF0D1520).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withAlpha(100)),
                ),
                child: Text(
                  '${track['number']} · ${track['code']}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const Spacer(),
              _buildQuickMetric('LENGTH', track['length'] as String, color),
              const SizedBox(width: 16),
              _buildQuickMetric('CONFIG', track['width'] as String, color),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            track['name'] as String,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            track['desc'] as String,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: const Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: const Color(0xFF6B7490),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'speed':
        return Icons.speed_rounded;
      case 'adjust':
        return Icons.adjust_rounded;
      case 'merge_type':
        return Icons.merge_type_rounded;
      case 'gesture':
        return Icons.gesture_rounded;
      case 'waves':
        return Icons.waves_rounded;
      default:
        return Icons.map_rounded;
    }
  }
}

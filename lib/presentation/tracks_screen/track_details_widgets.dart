import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Moving Tiles / Animated Stats Card ─────────────────────────────────────
class MovingStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const MovingStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(160),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3a494b)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: const Color(0xFF6B7490),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              sub,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: const Color(0xFF6B7490),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildTextDetailRow(String label, String value, Color color) {
  return Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.04),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: color.withOpacity(0.12),
        width: 0.8,
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490))),
        Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    ),
  );
}

// ── T1 - HST Detail Section (High Speed Lane Visualisation + Details) ───────
class HstDetails extends StatelessWidget {
  final ThemeData theme;
  final Color color;
  final bool isWide;
  final Animation<double> animation;

  const HstDetails({
    super.key,
    required this.theme,
    required this.color,
    required this.isWide,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final lanes = [
      {'lane': 'Lane 1', 'speed': '50 - 100 km/h', 'desc': 'Slow/Transition lane for entry/exit runs.'},
      {'lane': 'Lane 2', 'speed': '100 - 150 km/h', 'desc': 'General highway speed tyre intelligence testing.'},
      {'lane': 'Lane 3', 'speed': '150 - 200 km/h', 'desc': 'High-speed lane changes and transients.'},
      {'lane': 'Lane 4', 'speed': '200 - 250 km/h', 'desc': 'Extreme high-speed and tyre durability tests.'},
    ];

    Widget laneChart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(4, (idx) {
        final l = lanes[idx];
        final laneColor = color.withOpacity(0.3 + (idx * 0.22));
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(160),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: laneColor, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '${idx + 1}',
                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l['lane']!,
                        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(l['desc']!,
                        style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('SPEED LIMIT',
                      style: GoogleFonts.spaceGrotesk(fontSize: 8, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
                  Text(l['speed']!,
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, color: color)),
                ],
              ),
            ],
          ),
        );
      }),
    );

    Widget schematic = Column(
      children: [
        // Live animated track schematic
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(150),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3a494b)),
          ),
          child: CustomPaint(
            painter: HstTrackPainter(animation: animation, themeColor: color),
          ),
        ),
        const SizedBox(height: 14),
        // Additional SOP specs as tiles
        Row(
          children: [
            MovingStatTile(label: 'NEUTRAL BENDS', value: '250 km/h', sub: 'Hands-off steer speed', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'MAX BENDS', value: '350 km/h', sub: 'Bends design limit', color: color),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            MovingStatTile(label: 'BANKING', value: '37.4% (20.5º)', sub: 'Parabolic slope', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'RADIUS', value: '1,000 m', sub: 'Curve radius bends', color: color),
          ],
        ),
      ],
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: laneChart),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: schematic),
            ],
          )
        : Column(
            children: [schematic, const SizedBox(height: 20), laneChart],
          );
  }
}

// ── T2 - Dynamic Platform Section (Concentric Circles + Applications) ───────
class T2Details extends StatefulWidget {
  final ThemeData theme;
  final Color color;
  final bool isWide;
  final Animation<double> animation;

  const T2Details({
    super.key,
    required this.theme,
    required this.color,
    required this.isWide,
    required this.animation,
  });

  @override
  State<T2Details> createState() => _T2DetailsState();
}

class _T2DetailsState extends State<T2Details> {
  int _t2SelectedCircle = 0; // 0 = 25m, 1 = 50m, 2 = 100m, 3 = 150m
  int _t2SelectedApp = 0; // 0 = Constant Radius, 1 = Slalom, 2 = J-Turn, 3 = Fish-hook

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isWide = widget.isWide;
    final animation = widget.animation;

    final circles = [
      {'radius': 'R = 25m', 'dia': '50m Diameter', 'usage': 'Low speed steering compliance, Ackerman testing.'},
      {'radius': 'R = 50m', 'dia': '100m Diameter', 'usage': 'Constant radius tyre slip angle calibration.'},
      {'radius': 'R = 100m', 'dia': '200m Diameter', 'usage': 'Mid speed steering effort and stability.'},
      {'radius': 'R = 150m', 'dia': '300m Diameter', 'usage': 'Max speed lateral acceleration & load transfer.'},
    ];

    final apps = [
      {'title': 'Constant Radius Test', 'desc': 'Steady-state cornering tyre slip characteristics.'},
      {'title': 'Double Lane Change', 'desc': 'Transient emergency tyre intelligence response (Moose test).'},
      {'title': 'J-Turn Maneuver', 'desc': 'Evaluating tyre roll stability and lateral force buildup.'},
      {'title': 'Fish-hook Test', 'desc': 'Anti-roll stability testing under rapid steering reversal.'},
    ];

    Widget circleSelector = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SELECT CIRCLE FOR SPECIFICATIONS',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(4, (idx) {
            final c = circles[idx];
            final isSelected = _t2SelectedCircle == idx;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: idx == 3 ? 0 : 8),
                child: GestureDetector(
                  onTap: () => setState(() => _t2SelectedCircle = idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withAlpha(30) : const Color(0xFF0A1025).withAlpha(160),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? color : const Color(0xFF3a494b)),
                    ),
                    child: Center(
                      child: Text(
                        c['radius']!.split(' ').last,
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w800,
                          color: isSelected ? color : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(160),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(circles[_t2SelectedCircle]['radius']!,
                  style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Text(circles[_t2SelectedCircle]['dia']!,
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 6),
              Text(circles[_t2SelectedCircle]['usage']!,
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('APPLICATIONS',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...List.generate(4, (idx) {
          final isSelected = _t2SelectedApp == idx;
          final app = apps[idx];
          return GestureDetector(
            onTap: () => setState(() => _t2SelectedApp = idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color.withAlpha(20) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color.withAlpha(100) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: isSelected ? color : const Color(0xFF6B7490),
                    size: 14,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app['title']!,
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w800,
                              color: isSelected ? color : Colors.white,
                              fontSize: 12,
                            )),
                        if (isSelected) ...[
                          const SizedBox(height: 2),
                          Text(app['desc']!,
                              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8))),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );

    Widget schematic = Column(
      children: [
        Container(
          height: 200,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(150),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3a494b)),
          ),
          child: CustomPaint(
            painter: T2PlatformPainter(
              animation: animation,
              themeColor: color,
              selectedCircleRadius: _t2SelectedCircle,
              selectedApp: _t2SelectedApp,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            MovingStatTile(label: 'LONG. GRADIENT', value: '0.0 %', sub: 'Perfect flat platform', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'EVENNESS', value: '± 2 mm', sub: 'Laser graded concrete', color: color),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            MovingStatTile(label: 'ARRESTER BED', value: '4 m width', sub: 'Gravel pits on both sides', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'LEVEL TOLERANCE', value: '± 3 mm', sub: 'Geometric flatness', color: color),
          ],
        ),
      ],
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: circleSelector),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: schematic),
            ],
          )
        : Column(
            children: [schematic, const SizedBox(height: 20), circleSelector],
          );
  }
}

// ── T3 - Straight Braking Section (Lanes Adherence Bar Chart + Wet/Dry Config) ───────
class T3Details extends StatefulWidget {
  final ThemeData theme;
  final Color color;
  final bool isWide;
  final Animation<double> animation;

  const T3Details({
    super.key,
    required this.theme,
    required this.color,
    required this.isWide,
    required this.animation,
  });

  @override
  State<T3Details> createState() => _T3DetailsState();
}

class _T3DetailsState extends State<T3Details> {
  int _t3SelectedLane = 0; // 0 to 7 (8 lanes)

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isWide = widget.isWide;
    final animation = widget.animation;

    final lanes = [
      {'name': 'Polished Concrete', 'mu': 0.44, 'w': '3.6m', 'l': '250m', 'water': '1.0 mm (Sprinkler)'},
      {'name': 'Asphalt (Wet)', 'mu': 0.34, 'w': '3.2m', 'l': '250m', 'water': '0.34 mm'},
      {'name': 'Ceramic Tiles', 'mu': 0.15, 'w': '6.7m', 'l': '350m', 'water': '1.0 mm (Sprinkler)'},
      {'name': 'High-Adherence Certified Asphalt', 'mu': 0.90, 'w': '3.2m', 'l': '250m', 'water': '1.0 - 2.0 mm'},
      {'name': 'Basalt Tiles', 'mu': 0.34, 'w': '7.1m', 'l': '250m', 'water': '1.0 mm (Sprinkler)'},
      {'name': 'Asphalt (Dry)', 'mu': 0.90, 'w': '6.7m', 'l': '250m', 'water': '1.0 mm'},
      {'name': 'Aquaplaning Lane', 'mu': 0.05, 'w': '3.5m', 'l': '150m', 'water': '6.0 - 8.0 mm (Flooded)'},
      {'name': 'Dry Asphalt', 'mu': 0.85, 'w': '3.2m', 'l': '250m', 'water': 'Dry'},
    ];

    final currentLane = lanes[_t3SelectedLane];

    Widget laneFrictionChart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('WET ADHERENCE COEFFICIENT (μ)',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        // Custom vertical/horizontal bar graph
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(160),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3a494b)),
          ),
          child: Column(
            children: List.generate(8, (idx) {
              final isSelected = _t3SelectedLane == idx;
              final lane = lanes[idx];
              final mu = lane['mu'] as double;
              final barPct = mu;
              final barColor = idx == 2 || idx == 6
                  ? const Color(0xFFFF4D6A) // low friction
                  : (idx == 3 || idx == 5 ? const Color(0xFF4ADE80) : color); // high/mid friction

              return GestureDetector(
                onTap: () => setState(() => _t3SelectedLane = idx),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text('Lane ${idx + 1}: ${lane['name']}',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                  )),
                              if (idx == 6) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF4D6A).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFF4D6A), width: 0.5),
                                  ),
                                  child: Text(
                                    'CRITICAL AQUAPLANING',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 6.5,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFFFF4D6A),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text('μ = ${mu.toStringAsFixed(2)}',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? barColor : const Color(0xFF94A3B8),
                              )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(12),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: barPct,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: isSelected ? barColor : barColor.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(3),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: barColor.withAlpha(100), blurRadius: 6)]
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );

    Widget detailCard = Column(
      children: [
        // Live animated lane drawing
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(150),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3a494b)),
          ),
          child: CustomPaint(
            painter: T3BrakePainter(
              animation: animation,
              themeColor: color,
              selectedLaneIndex: _t3SelectedLane,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(160),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color),
                    ),
                    child: Text('LANE ${_t3SelectedLane + 1}',
                        style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      currentLane['name'] as String,
                      style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextDetailRow('Friction Coefficient (μ)', 'μ = ${(currentLane['mu'] as double).toStringAsFixed(2)}', color),
              _buildTextDetailRow('Lane Dimensions', '${currentLane['w']} Width x ${currentLane['l']} Length', color),
              _buildTextDetailRow('Water Condition', currentLane['water'] as String, color),
              _buildTextDetailRow('Gradient (Transversal)', _t3SelectedLane == 6 ? '0.0 %' : '0.3 - 0.5 %', color),
              if (_t3SelectedLane == 6) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38BDF8).withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.water, color: Color(0xFF38BDF8), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'AQUAPLANING TEST CRITERIA',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF38BDF8),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'This lane is flooded with a controlled water depth of 6 to 8 mm to evaluate hydroplaning threshold speed, tread pattern water evacuation efficiency, and wet tyre intelligence.',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color: const Color(0xFFBAE6FD),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Regulations alert
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB547).withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB547).withAlpha(40)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFFFFB547), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Braking tests are strictly restricted to East-West direction only. Only 1 vehicle is permitted to run on the platform at any time.',
                  style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFFFFB547), height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: laneFrictionChart),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: detailCard),
            ],
          )
        : Column(
            children: [detailCard, const SizedBox(height: 20), laneFrictionChart],
          );
  }
}

// ── T7 - Dry Handling Circuit Section (Occupancy + Configs) ─────────────────
class T7Details extends StatelessWidget {
  final ThemeData theme;
  final Color color;
  final bool isWide;
  final Animation<double> animation;

  const T7Details({
    super.key,
    required this.theme,
    required this.color,
    required this.isWide,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    // Occupancy (SOP says max 5)
    const int currentVehicles = 3;
    const int maxVehicles = 5;

    Widget statusTile = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(160),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('TRACK OCCUPANCY STATUS',
              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('GO-AHEAD',
                  style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF4ADE80))),
              const Spacer(),
              Text('$currentVehicles / $maxVehicles VEHICLES',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(4)),
              ),
              FractionallySizedBox(
                widthFactor: currentVehicles / maxVehicles,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADE80),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Color(0xFF4ADE80), blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Free access. Track has fewer than 5 users. Initial warm-up lap is mandatory.',
              style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8), height: 1.4)),
        ],
      ),
    );

    Widget configs = Column(
      children: [
        Row(
          children: [
            MovingStatTile(label: 'TOTAL LENGTH', value: '3,630 m', sub: 'Full circuit length', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'CONFIG 1', value: '2,100 m', sub: 'Short circuit track', color: color),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            MovingStatTile(label: 'CONFIG 2', value: '1,500 m', sub: 'Inner loop section', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'RUN-OFF WIDTH', value: '3m - 5m', sub: 'Variable both sides', color: color),
          ],
        ),
      ],
    );

    Widget schematic = Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3a494b)),
      ),
      child: CustomPaint(
        painter: T7HandlingPainter(
          animation: animation,
          themeColor: color,
        ),
      ),
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: Column(children: [statusTile, const SizedBox(height: 16), configs])),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: schematic),
            ],
          )
        : Column(
            children: [schematic, const SizedBox(height: 20), statusTile, const SizedBox(height: 16), configs],
          );
  }
}

// ── T8 - Ride Comfort Section (Surface Obstacles List + Details) ─────────────
class T8Details extends StatefulWidget {
  final ThemeData theme;
  final Color color;
  final bool isWide;
  final Animation<double> animation;

  const T8Details({
    super.key,
    required this.theme,
    required this.color,
    required this.isWide,
    required this.animation,
  });

  @override
  State<T8Details> createState() => _T8DetailsState();
}

class _T8DetailsState extends State<T8Details> {
  int _t8SelectedObstacle = 0; // 0 to 5 (6 obstacles)

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isWide = widget.isWide;
    final animation = widget.animation;

    final obstacles = [
      {'name': 'Rough Concrete', 'w': '4.0 m', 'l': '260m', 'rem': 'Random texturing, ±20mm variation.'},
      {'name': 'Smooth Pave', 'w': '2x 1.0 m', 'l': '800m', 'rem': 'Two parallel strips, ±10mm variation.'},
      {'name': 'Belgian Pave (Low Severity)', 'w': '4.0 m', 'l': '2017m', 'rem': '18mm aggregates, low amplitude vibrations.'},
      {'name': 'Belgian Pave (High Severity)', 'w': '4.0 m', 'l': '1250m', 'rem': '32mm aggregates, heavy impact severity.'},
      {'name': 'Washboard (P-700mm, Amp-25mm)', 'w': '4.0 m', 'l': '200m', 'rem': 'Periodic sinusoidal bumps.'},
      {'name': 'Big Step (20mm High)', 'w': '4.0 m', 'l': '180m', 'rem': 'Single step impact evaluation.'},
    ];

    final currentObstacle = obstacles[_t8SelectedObstacle];

    Widget obstacleList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SELECT COMFORT SURFACE OR OBSTACLE',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...List.generate(6, (idx) {
          final obs = obstacles[idx];
          final isSelected = _t8SelectedObstacle == idx;
          return GestureDetector(
            onTap: () => setState(() => _t8SelectedObstacle = idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color.withAlpha(26) : const Color(0xFF0A1025).withAlpha(160),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? color : const Color(0xFF3a494b)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.white24,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      obs['name']!,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    obs['l']!,
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: isSelected ? color : const Color(0xFF6B7490)),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );

    Widget schematic = Column(
      children: [
        Container(
          height: 130,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(150),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3a494b)),
          ),
          child: CustomPaint(
            painter: T8ComfortPainter(
              animation: animation,
              themeColor: color,
              selectedObstacleIndex: _t8SelectedObstacle,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(160),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(currentObstacle['name']!,
                  style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 12),
              _buildTextDetailRow('Obstacle Section Length', currentObstacle['l']!, color),
              _buildTextDetailRow('Surface Width', currentObstacle['w']!, color),
              _buildTextDetailRow('Profile Description', currentObstacle['rem']!, color),
              _buildTextDetailRow('Max Allowed Speed', '150 km/h', color),
            ],
          ),
        ),
      ],
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: obstacleList),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: schematic),
            ],
          )
        : Column(
            children: [schematic, const SizedBox(height: 20), obstacleList],
          );
  }
}

// ── T11 - Wet Skid Pad Section (Basalt / Asphalt circular lanes + ESP) ─────
class T11Details extends StatefulWidget {
  final ThemeData theme;
  final Color color;
  final bool isWide;
  final Animation<double> animation;

  const T11Details({
    super.key,
    required this.theme,
    required this.color,
    required this.isWide,
    required this.animation,
  });

  @override
  State<T11Details> createState() => _T11DetailsState();
}

class _T11DetailsState extends State<T11Details> {
  int _t11SelectedLane = 0; // 0 = Basalt (Inner), 1 = Asphalt (Outer)

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isWide = widget.isWide;
    final animation = widget.animation;

    final lanes = [
      {'name': 'Basalt Lane (Inner)', 'mu': 0.30, 'radius': '45m', 'usage': 'ESP, Traction Control, and low-friction drift/yaw testing.'},
      {'name': 'Asphalt Lane (Outer)', 'mu': 0.60, 'radius': '80m', 'usage': 'Standard wet handling, tyre cornering force buildup.'},
    ];

    final currentLane = lanes[_t11SelectedLane];

    Widget laneSelector = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SELECT SURFACE FOR SPECIFICATIONS',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490), fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: List.generate(2, (idx) {
            final l = lanes[idx];
            final isSelected = _t11SelectedLane == idx;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: idx == 1 ? 0 : 8),
                child: GestureDetector(
                  onTap: () => setState(() => _t11SelectedLane = idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withAlpha(30) : const Color(0xFF0A1025).withAlpha(160),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? color : const Color(0xFF3a494b)),
                    ),
                    child: Center(
                      child: Text(
                        (l['name'] as String).split(' ').first,
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w800,
                          color: isSelected ? color : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(160),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(currentLane['name'] as String,
                  style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              Text('Lane Radius: ${currentLane['radius']!}',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 6),
              Text(currentLane['usage'] as String,
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            MovingStatTile(label: 'FRICTION (Basalt)', value: 'μ = 0.30', sub: 'Low friction wet surface', color: color),
            const SizedBox(width: 12),
            MovingStatTile(label: 'FRICTION (Asphalt)', value: 'μ = 0.60', sub: 'Standard wet surface', color: color),
          ],
        ),
      ],
    );

    Widget schematic = Column(
      children: [
        // Live animated track schematic
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(150),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3a494b)),
          ),
          child: CustomPaint(
            painter: T11SkidPadPainter(
              animation: animation,
              themeColor: color,
              selectedLane: _t11SelectedLane,
            ),
          ),
        ),
        const SizedBox(height: 14),
        // Regulations alert
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4D6A).withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF4D6A).withAlpha(40)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF4D6A), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Safety SOP: Under any circumstances, only 1 vehicle can be on the Wet Skid Pad at a time. All runs must be conducted in an ANTICLOCKWISE direction. Inform Track Access Control and obtain RFID permission before entry.',
                  style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFFFF4D6A), height: 1.4, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: laneSelector),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: schematic),
            ],
          )
        : Column(
            children: [schematic, const SizedBox(height: 20), laneSelector],
          );
  }
}

// ─── Custom Track Painters for Schematic Graphics ───────────────────────────

// T1 - HST Oval Painter
class HstTrackPainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;

  HstTrackPainter({required this.animation, required this.themeColor}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = themeColor.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = themeColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final dashPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;
    final double radius = h * 0.28;
    final double straightLength = w * 0.44;

    final path = Path()
      ..moveTo(cx - straightLength / 2, cy - radius)
      ..lineTo(cx + straightLength / 2, cy - radius)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx + straightLength / 2, cy), radius: radius),
        -math.pi / 2,
        math.pi,
        false,
      )
      ..lineTo(cx - straightLength / 2, cy + radius)
      ..arcTo(
        Rect.fromCircle(center: Offset(cx - straightLength / 2, cy), radius: radius),
        math.pi / 2,
        math.pi,
        false,
      );

    canvas.drawPath(path, paint);
    canvas.drawPath(path, glowPaint);

    // Draw dash lanes
    for (double i = -1.0; i <= 1.0; i += 1.0) {
      if (i == 0.0) continue;
      final laneRadius = radius + i * 8.0;
      final lanePath = Path()
        ..moveTo(cx - straightLength / 2, cy - laneRadius)
        ..lineTo(cx + straightLength / 2, cy - laneRadius)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx + straightLength / 2, cy), radius: laneRadius),
          -math.pi / 2,
          math.pi,
          false,
        )
        ..lineTo(cx - straightLength / 2, cy + laneRadius)
        ..arcTo(
          Rect.fromCircle(center: Offset(cx - straightLength / 2, cy), radius: laneRadius),
          math.pi / 2,
          math.pi,
          false,
        );
      canvas.drawPath(lanePath, dashPaint);
    }

    // Draw animated test car moving around track
    final pathMetrics = path.computeMetrics();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;
      final length = metric.length;
      final currentPos = (animation.value * length) % length;
      final tangent = metric.getTangentForOffset(currentPos);
      if (tangent != null) {
        final carPaint = Paint()
          ..color = const Color(0xFFFF6B00)
          ..style = PaintingStyle.fill;
        final carGlow = Paint()
          ..color = const Color(0xFFFF6B00).withOpacity(0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

        canvas.drawCircle(tangent.position, 6, carGlow);
        canvas.drawCircle(tangent.position, 4, carPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// T2 - Dynamic Platform Concentric Circles Painter
class T2PlatformPainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;
  final int selectedCircleRadius;
  final int selectedApp;

  T2PlatformPainter({
    required this.animation,
    required this.themeColor,
    required this.selectedCircleRadius,
    required this.selectedApp,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double baseRadius = size.height * 0.18;

    final trackPaint = Paint()
      ..color = themeColor.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    // Draw overall circular platform
    canvas.drawCircle(Offset(cx, cy), baseRadius * 2.2, trackPaint);

    final linePaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final activeLinePaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final activeGlowPaint = Paint()
      ..color = themeColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Draw concentric circles
    final radii = [0.4, 0.8, 1.4, 2.0];
    for (int idx = 0; idx < radii.length; idx++) {
      final isSelected = selectedCircleRadius == idx;
      final r = baseRadius * radii[idx];

      canvas.drawCircle(Offset(cx, cy), r, isSelected ? activeGlowPaint : linePaint);
      canvas.drawCircle(Offset(cx, cy), r, isSelected ? activeLinePaint : linePaint);
    }

    // Draw animating vehicle path based on selected application
    final path = Path();
    if (selectedApp == 0) {
      // Constant Radius: moving in the selected circle
      final double selectedR = baseRadius * radii[selectedCircleRadius];
      final double angle = animation.value * 2 * math.pi;
      final Offset pos = Offset(cx + selectedR * math.cos(angle), cy + selectedR * math.sin(angle));

      _drawVehicle(canvas, pos);
    } else if (selectedApp == 1) {
      // Slalom: waving back and forth along the horizontal axis
      final double totalLength = size.width * 0.7;
      final double startX = cx - totalLength / 2;
      final double x = startX + animation.value * totalLength;
      final double y = cy + 16.0 * math.sin(x * 0.08);

      // Draw slalom cones
      final conePaint = Paint()..color = const Color(0xFFFFB547);
      for (double cxPos = startX + 40; cxPos < startX + totalLength; cxPos += 50) {
        canvas.drawCircle(Offset(cxPos, cy), 3, conePaint);
      }

      _drawVehicle(canvas, Offset(x, y));
    } else if (selectedApp == 2) {
      // J-Turn: straight then sharp hook
      final double len = animation.value;
      double x, y;
      if (len < 0.6) {
        // Straight run
        x = (cx - 100) + len * 250;
        y = cy + 30;
      } else {
        // Hook turn
        final t = (len - 0.6) / 0.4;
        final angle = t * math.pi;
        x = (cx + 50) + 30 * math.sin(angle);
        y = (cy) + 30 * math.cos(angle);
      }
      _drawVehicle(canvas, Offset(x, y));
    } else if (selectedApp == 3) {
      // Fish-hook: quick steer left then right
      final double t = animation.value;
      double x = (cx - 120) + t * 240;
      double y = cy;
      if (t > 0.3 && t < 0.6) {
        final pt = (t - 0.3) / 0.3;
        y = cy - 25 * math.sin(pt * math.pi);
      } else if (t >= 0.6) {
        final pt = (t - 0.6) / 0.4;
        y = cy + 25 * math.sin(pt * math.pi);
      }
      _drawVehicle(canvas, Offset(x, y));
    }
  }

  void _drawVehicle(Canvas canvas, Offset pos) {
    final carPaint = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.fill;
    final carGlow = Paint()
      ..color = const Color(0xFFFF6B00).withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(pos, 6, carGlow);
    canvas.drawCircle(pos, 4, carPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// T3 - Straight Braking Lane Painter
class T3BrakePainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;
  final int selectedLaneIndex;

  T3BrakePainter({
    required this.animation,
    required this.themeColor,
    required this.selectedLaneIndex,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;
    final double startY = h * 0.15;
    final double endY = h * 0.85;
    final double laneHeight = (endY - startY) / 8;

    final paint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.fill;

    // Draw braking track background
    canvas.drawRect(Rect.fromLTRB(w * 0.1, startY, w * 0.9, endY), paint);

    // Draw 8 lanes division lines
    final linePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 8; i++) {
      final y = startY + i * laneHeight;
      canvas.drawLine(Offset(w * 0.1, y), Offset(w * 0.9, y), linePaint);
    }

    // Draw water blue background and wave ripples for Lane 7 (index 6, Aquaplaning)
    final aqY = startY + 6 * laneHeight;
    final aqWaterPaint = Paint()
      ..color = const Color(0xFF38BDF8).withAlpha(30)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTRB(w * 0.1, aqY, w * 0.9, aqY + laneHeight), aqWaterPaint);

    final wavePaint = Paint()
      ..color = const Color(0xFF38BDF8).withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final wavePath = Path();
    bool first = true;
    for (double wx = w * 0.1; wx <= w * 0.9; wx += 5) {
      final double wy = aqY + laneHeight / 2 + 2 * math.sin(wx * 0.1 + animation.value * 2 * math.pi);
      if (first) {
        wavePath.moveTo(wx, wy);
        first = false;
      } else {
        wavePath.lineTo(wx, wy);
      }
    }
    canvas.drawPath(wavePath, wavePaint);

    // Highlight selected lane
    final highlightY = startY + selectedLaneIndex * laneHeight;
    final highlightPaint = Paint()
      ..color = themeColor.withAlpha(26)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(
      Rect.fromLTRB(w * 0.1, highlightY, w * 0.9, highlightY + laneHeight),
      highlightPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.1, highlightY, w * 0.9, highlightY + laneHeight),
      borderPaint,
    );

    // Draw animating braking car on the selected lane
    final double carX = w * 0.1 + (animation.value * w * 0.8);
    final Offset pos = Offset(carX, highlightY + laneHeight / 2);

    final carPaint = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.fill;

    // Simulate braking deceleration visual: particle tail fades out as car advances
    if (animation.value > 0.1) {
      final tailPaint = Paint()
        ..color = const Color(0xFFFF6B00).withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawLine(Offset(pos.dx - 16, pos.dy), Offset(pos.dx, pos.dy), tailPaint);
    }

    canvas.drawCircle(pos, 4.5, carPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// T7 - Dry Handling Track Curly Loop Painter
class T7HandlingPainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;

  T7HandlingPainter({required this.animation, required this.themeColor}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;

    final trackPaint = Paint()
      ..color = themeColor.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18.0
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = themeColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw curly race track path
    final path = Path()
      ..moveTo(cx - 100, cy + 20)
      ..cubicTo(cx - 80, cy - 60, cx - 40, cy - 60, cx - 20, cy - 20)
      ..cubicTo(cx, cy + 20, cx + 40, cy + 40, cx + 60, cy - 20)
      ..cubicTo(cx + 80, cy - 80, cx + 120, cy - 40, cx + 100, cy + 30)
      ..cubicTo(cx + 80, cy + 80, cx - 20, cy + 60, cx - 60, cy + 50)
      ..close();

    canvas.drawPath(path, trackPaint);
    canvas.drawPath(path, glowPaint);

    // Draw animated car on the handling track
    final pathMetrics = path.computeMetrics();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;
      final length = metric.length;
      final currentPos = (animation.value * length) % length;
      final tangent = metric.getTangentForOffset(currentPos);
      if (tangent != null) {
        final carPaint = Paint()
          ..color = const Color(0xFFFF6B00)
          ..style = PaintingStyle.fill;
        final carGlow = Paint()
          ..color = const Color(0xFFFF6B00).withOpacity(0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

        canvas.drawCircle(tangent.position, 6, carGlow);
        canvas.drawCircle(tangent.position, 4, carPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// T8 - Ride Comfort Obstacles (Wavy Road / Step / Bumpy Profile) Painter
class T8ComfortPainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;
  final int selectedObstacleIndex;

  T8ComfortPainter({
    required this.animation,
    required this.themeColor,
    required this.selectedObstacleIndex,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cy = h / 2;

    final surfacePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final obstaclePaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final glowPaint = Paint()
      ..color = themeColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path()..moveTo(w * 0.1, cy);

    if (selectedObstacleIndex == 0 || selectedObstacleIndex == 1) {
      // Rough Concrete / Pave: small noise
      final rand = math.Random(42);
      for (double x = w * 0.1; x <= w * 0.9; x += 4) {
        final noise = (rand.nextDouble() - 0.5) * (selectedObstacleIndex == 0 ? 5.0 : 8.0);
        path.lineTo(x, cy + noise);
      }
    } else if (selectedObstacleIndex == 2 || selectedObstacleIndex == 3) {
      // Belgian Pave: larger peaks
      final rand = math.Random(13);
      for (double x = w * 0.1; x <= w * 0.9; x += 6) {
        final peak = (rand.nextDouble() - 0.5) * (selectedObstacleIndex == 2 ? 8.0 : 16.0);
        path.lineTo(x, cy + peak);
      }
    } else if (selectedObstacleIndex == 4) {
      // Washboard: periodic sine waves
      for (double x = w * 0.1; x <= w * 0.9; x += 2) {
        final wave = 12.0 * math.sin((x - w * 0.1) * 0.08);
        path.lineTo(x, cy + wave);
      }
    } else if (selectedObstacleIndex == 5) {
      // Big Step: straight line then sharp vertical step down/up
      path.lineTo(w * 0.45, cy);
      path.lineTo(w * 0.45, cy + 18.0); // 20mm step
      path.lineTo(w * 0.55, cy + 18.0);
      path.lineTo(w * 0.55, cy);
      path.lineTo(w * 0.9, cy);
    }

    // Draw baseline
    canvas.drawLine(Offset(w * 0.05, cy), Offset(w * 0.1, cy), surfacePaint);
    canvas.drawLine(Offset(w * 0.9, cy), Offset(w * 0.95, cy), surfacePaint);

    // Draw obstacle profile
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, obstaclePaint);

    // Draw vehicle tyre rolling on the comfort path
    final pathMetrics = path.computeMetrics();
    if (pathMetrics.isNotEmpty) {
      final metric = pathMetrics.first;
      final length = metric.length;
      final currentPos = (animation.value * length) % length;
      final tangent = metric.getTangentForOffset(currentPos);
      if (tangent != null) {
        // Draw tyre circle
        final tyrePaint = Paint()
          ..color = const Color(0xFFFF6B00)
          ..style = PaintingStyle.fill;
        final tyreRim = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

        canvas.drawCircle(Offset(tangent.position.dx, tangent.position.dy - 6.0), 6, tyrePaint);
        canvas.drawCircle(Offset(tangent.position.dx, tangent.position.dy - 6.0), 3, tyreRim);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// T11 - Wet Skid Pad Painter
class T11SkidPadPainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;
  final int selectedLane; // 0 = Basalt (Inner), 1 = Asphalt (Outer)

  T11SkidPadPainter({
    required this.animation,
    required this.themeColor,
    required this.selectedLane,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double baseRadius = size.height * 0.22;

    final trackPaint = Paint()
      ..color = themeColor.withOpacity(0.06)
      ..style = PaintingStyle.fill;

    // Draw overall circular platform area
    canvas.drawCircle(Offset(cx, cy), baseRadius * 2.2, trackPaint);

    final linePaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final activeLinePaint = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final activeGlowPaint = Paint()
      ..color = themeColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    // Two lanes: Inner (Basalt, radii = 1.0), Outer (Asphalt, radii = 1.7)
    final radii = [1.0, 1.7];
    final laneNames = ['Basalt', 'Asphalt'];

    for (int idx = 0; idx < radii.length; idx++) {
      final isSelected = selectedLane == idx;
      final r = baseRadius * radii[idx];

      canvas.drawCircle(Offset(cx, cy), r, isSelected ? activeGlowPaint : linePaint);
      canvas.drawCircle(Offset(cx, cy), r, isSelected ? activeLinePaint : linePaint);
      
      // Draw text label on track
      final textPainter = TextPainter(
        text: TextSpan(
          text: laneNames[idx],
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: isSelected ? themeColor : const Color(0xFF6B7490),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(cx - textPainter.width / 2, cy - r - 10));
    }

    // Draw watering spraying effect (water flow facility)
    final sprayPaint = Paint()
      ..color = themeColor.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round;
    
    // Draw some blue arcs indicating water sprays on the low friction basalt lane
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: baseRadius * radii[0]),
      animation.value * 2 * math.pi,
      math.pi / 2,
      false,
      sprayPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: baseRadius * radii[0]),
      (animation.value + 0.5) * 2 * math.pi,
      math.pi / 2,
      false,
      sprayPaint,
    );

    // Draw animating vehicle moving in an ANTICLOCKWISE direction
    final double selectedR = baseRadius * radii[selectedLane];
    final double angle = -animation.value * 2 * math.pi; // negative sign for anticlockwise
    final Offset pos = Offset(cx + selectedR * math.cos(angle), cy + selectedR * math.sin(angle));

    _drawVehicle(canvas, pos);
  }

  void _drawVehicle(Canvas canvas, Offset pos) {
    final carPaint = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.fill;
    final carGlow = Paint()
      ..color = const Color(0xFFFF6B00).withOpacity(0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(pos, 6, carGlow);
    canvas.drawCircle(pos, 4, carPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:math' as math;

import '../../services/project_manager.dart';

// ─── Project metadata registry ────────────────────────────────────────────────
class _CarDetail {
  final String name;
  final IconData icon;
  const _CarDetail(this.name, this.icon);
}

class _ProjectMeta {
  final String displayName;
  final String vehicle;
  final String vehicleType;
  final String description;
  final String? imagePath;
  final Color accentColor;
  final Color glowColor;
  final List<String> specs;
  final List<_CarDetail> details;
  const _ProjectMeta({
    required this.displayName,
    required this.vehicle,
    required this.vehicleType,
    required this.description,
    this.imagePath,
    required this.accentColor,
    required this.glowColor,
    this.specs = const [],
    this.details = const [],
  });
}

const _knownProjects = {
  'mahindra ev poc': _ProjectMeta(
    displayName: 'Mahindra EV PoC',
    vehicle: 'Mahindra XEV 9e',
    vehicleType: 'Battery Electric Vehicle',
    description: 'Goodyear SightLine validation on the Mahindra XEV 9e BEV platform. '
        'Real-time tire-road friction estimation, aquaplaning onset detection and tire health '
        'monitoring integrated with the vehicle\'s ADAS stack at NATRAX proving ground.',
    imagePath: 'assets/images/mahindra_xev9e_hero.png',
    accentColor: Color(0xFFE8002D),
    glowColor: Color(0xFFE8002D),
    specs: ['INGLO Architecture', '79 kWh Battery', 'AWD · 285 kW'],
    details: [
      _CarDetail('Approved OEM Size: 235/55 R19', Icons.circle_outlined),
      _CarDetail('INGLO EV Architecture Platform', Icons.layers_rounded),
      _CarDetail('79 kWh LFP Battery (175 kW DC Fast)', Icons.battery_charging_full_rounded),
      _CarDetail('Dual-Motor AWD · 285 kW (382 hp)', Icons.bolt_rounded),
      _CarDetail('MIDC Certified Range: 560 km', Icons.map_rounded),
    ],
  ),
  'mahindra ice poc': _ProjectMeta(
    displayName: 'Mahindra ICE PoC',
    vehicle: 'Mahindra XUV 7XO',
    vehicleType: 'Internal Combustion Engine SUV',
    description: 'SightLine sensor fusion and friction estimation benchmarking on the Mahindra XUV 7XO ICE platform. '
        'Validating pressure & load sensing, predictive maintenance alerts, and tire wear state '
        'measurement across dynamic handling tracks.',
    imagePath: 'assets/images/mahindra_7xo.webp',
    accentColor: Color(0xFF4A9EFF),
    glowColor: Color(0xFF4A9EFF),
    specs: ['mStallion 3.0 Turbo', 'AdrenoX 5.0', '4WD · 206 kW'],
    details: [
      _CarDetail('Approved OEM Size: 235/60 R18', Icons.circle_outlined),
      _CarDetail('mStallion 2.0L TGDi Turbo Petrol', Icons.settings_suggest_rounded),
      _CarDetail('Output: 200 hp @ 380 Nm Torque', Icons.speed_rounded),
      _CarDetail('Transmission: 6-Speed AT / 4WD', Icons.settings_input_component_rounded),
      _CarDetail('Frequency Selective Damping (FSD)', Icons.build_circle_rounded),
    ],
  ),
  'hyundai poc': _ProjectMeta(
    displayName: 'Hyundai PoC',
    vehicle: 'Hyundai CRETA EV',
    vehicleType: 'Battery Electric Crossover',
    description: 'Goodyear SightLine proof-of-concept on Hyundai\'s CRETA EV. '
        'Evaluating aquaplaning detection speed recommendations, real-time inflation pressure '
        'monitoring, and predictive maintenance data relay to fleet management systems.',
    imagePath: 'assets/images/hyundai_creta_ev.png',
    accentColor: Color(0xFF00F3FF),
    glowColor: Color(0xFF00B4D8),
    specs: ['51.4 kWh Battery', 'Smart Regen', 'ADAS Level 2+'],
    details: [
      _CarDetail('Approved OEM Size: 215/60 R17', Icons.circle_outlined),
      _CarDetail('51.4 kWh High-Density LFP Battery', Icons.battery_charging_full_rounded),
      _CarDetail('Motor: 138 hp (102 kW) / 255 Nm', Icons.bolt_rounded),
      _CarDetail('Platform: e-GMP derived K2 Platform', Icons.layers_rounded),
      _CarDetail('Features: Smart Regen & V2L Power Output', Icons.settings_backup_restore_rounded),
    ],
  ),
};

// Goodyear SightLine tire intelligence features
const _tireFeatures = [
  _TireFeature('Friction Estimation', Icons.speed_rounded),
  _TireFeature('Aquaplaning Detection', Icons.water_rounded),
  _TireFeature('Tire Health Monitoring', Icons.monitor_heart_rounded),
  _TireFeature('Pressure & Load Sensing', Icons.compress_rounded),
  _TireFeature('Predictive Maintenance', Icons.build_circle_rounded),
];

class _TireFeature {
  final String name;
  final IconData icon;
  const _TireFeature(this.name, this.icon);
}

// ─── Data model ───────────────────────────────────────────────────────────────
class _ProjectCard {
  final String projectKey;
  final String displayName;
  final _ProjectMeta meta;
  double totalInclGst = 0;
  double subtotalExcl = 0;
  int sessions = 0;
  DateTime? lastActivity;

  _ProjectCard({
    required this.projectKey,
    required this.displayName,
    required this.meta,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class ProjectSelectionScreen extends StatefulWidget {
  const ProjectSelectionScreen({super.key});
  @override
  State<ProjectSelectionScreen> createState() => _ProjectSelectionScreenState();
}

class _ProjectSelectionScreenState extends State<ProjectSelectionScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  List<_ProjectCard> _projects = [];
  int? _hoveredIndex;

  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;

  final _usdFmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _inrCompact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹', decimalDigits: 1);

  String _fmtUsd(double inrWithGst) {
    if (inrWithGst == 0) return '\$0';
    return _usdFmt.format(inrWithGst / 83.0);
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _loadProjects();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final sessionsRaw = await client
          .from('engineer_sessions')
          .select('id, started_at, total_cost, project_name, session_status')
          .eq('session_status', 'completed')
          .order('started_at', ascending: false);

      final sessionIds = (sessionsRaw as List).map((s) => s['id'] as String).toList();
      List<dynamic> svcsRaw = [];
      if (sessionIds.isNotEmpty) {
        svcsRaw = await client
            .from('session_additional_services')
            .select('session_id, total_cost')
            .inFilter('session_id', sessionIds);
      }

      final Map<String, double> svcCostMap = {};
      for (final s in svcsRaw) {
        final sid = s['session_id'] as String;
        final cost = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        svcCostMap[sid] = (svcCostMap[sid] ?? 0) + cost;
      }

      // Pre-populate with the 3 known projects (in display order)
      final Map<String, _ProjectCard> cardMap = {};
      for (final entry in _knownProjects.entries) {
        cardMap[entry.key] = _ProjectCard(
          projectKey: entry.value.displayName,
          displayName: entry.value.displayName,
          meta: entry.value,
        );
      }

      // ── Canonical totals from NATRAX_Comprehensive_Billing_Final_V15 ──────
      // Grand Total Incl 18% GST = ₹20,33,988.42
      // Track+Acc (excl) = ₹14,78,719 | Workshop (excl) = ₹2,45,000
      // Subtotal excl = ₹17,23,719 | GST = ₹3,10,269.42
      const double mahindraEvSubtotalExcl = 1723719.0;
      const double mahindraEvTotalInclGst = 2033988.42;

      // For non-EV projects, still compute from Supabase (future PoCs)
      for (final s in sessionsRaw) {
        final rawName = (s['project_name'] as String?)?.trim() ?? '';
        final projName = (rawName.isEmpty || rawName.toLowerCase() == 'general')
            ? 'Mahindra EV PoC'
            : rawName;
        final key = projName.toLowerCase();
        if (!cardMap.containsKey(key)) continue;
        // Skip Mahindra EV PoC — we use hardcoded Excel total below
        if (key == 'mahindra ev poc') {
          // Still count sessions and track last activity date
          cardMap[key]!.sessions += 1;
          final startDt = DateTime.tryParse(s['started_at'] as String? ?? '');
          if (startDt != null) {
            if (cardMap[key]!.lastActivity == null ||
                startDt.isAfter(cardMap[key]!.lastActivity!)) {
              cardMap[key]!.lastActivity = startDt;
            }
          }
          continue;
        }

        final sid = s['id'] as String;
        final track = (s['total_cost'] as num?)?.toDouble() ?? 0.0;
        final svc = svcCostMap[sid] ?? 0.0;
        final excl = track + svc;
        cardMap[key]!.subtotalExcl += excl;
        cardMap[key]!.totalInclGst += excl * 1.18;
        cardMap[key]!.sessions += 1;
        final startDt = DateTime.tryParse(s['started_at'] as String? ?? '');
        if (startDt != null) {
          if (cardMap[key]!.lastActivity == null ||
              startDt.isAfter(cardMap[key]!.lastActivity!)) {
            cardMap[key]!.lastActivity = startDt;
          }
        }
      }

      // Set Mahindra EV PoC to exact Excel grand total
      final evCard = cardMap['mahindra ev poc'];
      if (evCard != null) {
        evCard.subtotalExcl = mahindraEvSubtotalExcl;
        evCard.totalInclGst = mahindraEvTotalInclGst;
      }

      // Maintain fixed order
      final ordered = [
        cardMap['mahindra ev poc']!,
        cardMap['mahindra ice poc']!,
        cardMap['hyundai poc']!,
      ];

      if (mounted) {
        setState(() {
          _projects = ordered;
          _isLoading = false;
        });
        _fadeCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectProject(_ProjectCard p) {
    ProjectManager.instance.setProject(p.displayName);
    context.push('/monthly-invoices-screen', extra: p.displayName);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      body: Stack(
        children: [
          // Animated starfield / deep space background
          Positioned.fill(child: _DeepSpaceBackground(pulseAnim: _pulseAnim)),
          // Content
          SafeArea(
            child: _isLoading ? _buildLoader() : FadeTransition(
              opacity: _fadeAnim,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 56, height: 56,
          child: CircularProgressIndicator(color: const Color(0xFF00F3FF), strokeWidth: 1.5),
        ),
        const SizedBox(height: 20),
        Text('INITIALISING R&D SUITE…',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF94A3B8), letterSpacing: 2)),
      ]),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero headline
                _buildHeroHeadline(),
                const SizedBox(height: 36),
                // Project cards
                LayoutBuilder(builder: (ctx, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return _buildThreeColumnGrid(constraints.maxWidth);
                  }
                  if (constraints.maxWidth >= 600) {
                    return _buildTwoColumnGrid(constraints.maxWidth);
                  }
                  return Column(
                    children: _projects.asMap().entries.map((e) =>
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: _buildProjectCard(e.value, e.key),
                      ),
                    ).toList(),
                  );
                }),
                const SizedBox(height: 32),
                // All projects button
                _buildAllProjectsButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF030712).withOpacity(0.6),
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Brand
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('NATRAX TRACK LOG',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: const Color(0xFF00F3FF), letterSpacing: 3)),
                const SizedBox(height: 3),
                Text('Vehicle Validation Team',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),

              const Spacer(),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F3FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00F3FF).withOpacity(0.3)),
                ),
                child: Row(children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F3FF),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: const Color(0xFF00F3FF).withOpacity(0.4 + _pulseAnim.value * 0.4),
                          blurRadius: 6,
                        )],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('LIVE · ${_projects.length} Projects',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: const Color(0xFF00F3FF))),
                ]),
              ),

              Container(margin: const EdgeInsets.symmetric(horizontal: 20), width: 1, height: 36,
                color: Colors.white.withOpacity(0.1)),

              // Goodyear SightLine logo
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text('POWERED BY',
                    style: GoogleFonts.spaceGrotesk(fontSize: 8, color: const Color(0xFF94A3B8), letterSpacing: 2)),
                const SizedBox(height: 6),
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    -1, 0, 0, 0, 255,
                     0,-1, 0, 0, 255,
                     0, 0,-1, 0, 255,
                     0, 0, 0, 1,   0,
                  ]),
                  child: Image.asset('assets/images/goodyear_sightline_logo.png', height: 28, fit: BoxFit.contain),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeadline() {
    // Compute totals across all loaded projects
    final totalSessions = _projects.fold(0, (s, p) => s + p.sessions);
    final totalSpendInclGst = _projects.fold(0.0, (s, p) => s + p.totalInclGst);
    final activeCount = _projects.where((p) => p.sessions > 0).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Label
      Row(children: [
        Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF00F3FF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text('ACTIVE PROJECTS',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: const Color(0xFF00F3FF), letterSpacing: 3)),
      ]),
      const SizedBox(height: 10),

      // Main headline
      RichText(
        text: TextSpan(children: [
          TextSpan(
            text: 'Select your\n',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 34, fontWeight: FontWeight.w800,
                color: Colors.white, height: 1.15),
          ),
          TextSpan(
            text: 'Project',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 34, fontWeight: FontWeight.w800, height: 1.15,
              foreground: Paint()..shader = const LinearGradient(
                colors: [Color(0xFF00F3FF), Color(0xFF4A9EFF)],
              ).createShader(const Rect.fromLTWH(0, 0, 260, 42)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
        'Goodyear SightLine PoC validation · NATRAX Proving Ground, Indore',
        style: GoogleFonts.spaceGrotesk(
            fontSize: 13, color: const Color(0xFF94A3B8)),
      ),

      const SizedBox(height: 20),

      // Live stats strip
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              const Color(0xFF00F3FF).withOpacity(0.07),
              const Color(0xFF4A9EFF).withOpacity(0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00F3FF).withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Stats row
          Row(children: [
            _statItem(
              label: 'ACTIVE PoCs',
              value: '$activeCount / ${_projects.length}',
              color: const Color(0xFF00F3FF),
              icon: Icons.science_rounded,
            ),
            _statDivider(),
            _statItem(
              label: 'TOTAL SESSIONS',
              value: '$totalSessions',
              color: const Color(0xFF4A9EFF),
              icon: Icons.directions_car_rounded,
            ),
            _statDivider(),
            _statItem(
              label: 'TOTAL SPEND',
              value: _inrCompact.format(totalSpendInclGst),
              color: const Color(0xFFE8002D),
              icon: Icons.currency_rupee_rounded,
            ),
            _statDivider(),
            _statItem(
              label: 'LOCATION',
              value: 'NATRAX',
              color: const Color(0xFFF59E0B),
              icon: Icons.location_on_rounded,
            ),
          ]),

          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 12),

          // Feature pills
          Wrap(
            spacing: 6, runSpacing: 6,
            children: _tireFeatures.map((f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF00F3FF).withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00F3FF).withOpacity(0.18)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(f.icon, color: const Color(0xFF00F3FF), size: 11),
                const SizedBox(width: 5),
                Text(f.name,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: const Color(0xFF00F3FF).withOpacity(0.9))),
              ]),
            )).toList(),
          ),
        ]),
      ),
    ]);
  }

  Widget _statItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 8, fontWeight: FontWeight.w700,
                  color: color.withOpacity(0.7), letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      ]),
    );
  }

  Widget _statDivider() => Container(
        width: 1, height: 36, color: Colors.white.withOpacity(0.08),
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );

  Widget _buildThreeColumnGrid(double totalWidth) {
    final cardWidth = (totalWidth - 48) / 3;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _projects.asMap().entries.map((e) => Padding(
        padding: EdgeInsets.only(right: e.key < _projects.length - 1 ? 24 : 0),
        child: SizedBox(width: cardWidth, child: _buildProjectCard(e.value, e.key)),
      )).toList(),
    );
  }

  Widget _buildTwoColumnGrid(double totalWidth) {
    final cardWidth = (totalWidth - 20) / 2;
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: cardWidth, child: _buildProjectCard(_projects[0], 0)),
        const SizedBox(width: 20),
        SizedBox(width: cardWidth, child: _buildProjectCard(_projects[1], 1)),
      ]),
      const SizedBox(height: 20),
      SizedBox(width: cardWidth * 2 + 20, child: _buildProjectCard(_projects[2], 2)),
    ]);
  }

  Widget _buildProjectCard(_ProjectCard p, int idx) {
    final isHovered = _hoveredIndex == idx;
    final meta = p.meta;
    final accent = meta.accentColor;
    final glow = meta.glowColor;
    final lastAct = p.lastActivity != null
        ? DateFormat('dd MMM yyyy').format(p.lastActivity!)
        : '—';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredIndex = idx),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: GestureDetector(
        onTap: () => _selectProject(p),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isHovered
                ? accent.withOpacity(0.08)
                : const Color(0xFF0D1520).withOpacity(0.75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isHovered ? accent.withOpacity(0.6) : Colors.white.withOpacity(0.07),
              width: isHovered ? 1.5 : 1,
            ),
            boxShadow: isHovered
                ? [BoxShadow(color: glow.withOpacity(0.25), blurRadius: 40, spreadRadius: -4)]
                : [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Floating vehicle hero image ──
                  _buildVehicleHero(meta, accent, p, isHovered),

                  // ── Card body ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Project name
                        Text(p.displayName,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                        const SizedBox(height: 4),
                        // Vehicle info
                        Row(children: [
                          Icon(
                            meta.vehicleType.contains('Electric') ? Icons.electric_bolt_rounded : Icons.local_gas_station_rounded,
                            color: accent, size: 13),
                          const SizedBox(width: 4),
                          Flexible(child: Text('${meta.vehicle}  ·  ${meta.vehicleType}',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11, fontWeight: FontWeight.w600, color: accent),
                              overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 10),
                        // Description
                        Text(meta.description,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: const Color(0xFF94A3B8), height: 1.5),
                            maxLines: 3, overflow: TextOverflow.ellipsis),

                        const SizedBox(height: 10),
                        // Vehicle spec chips
                        Wrap(spacing: 6, runSpacing: 6,
                          children: meta.specs.map((s) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: accent.withOpacity(0.25)),
                            ),
                            child: Text(s,
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 9, fontWeight: FontWeight.w700,
                                    color: accent, letterSpacing: 1)),
                          )).toList(),
                        ),

                        const SizedBox(height: 14),
                        // Vehicle details
                        ...(meta.details.map((d) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: accent.withOpacity(0.12),
                              width: 0.8,
                            ),
                          ),
                          child: Row(children: [
                            Icon(d.icon, color: accent, size: 12),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(d.name,
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10, color: const Color(0xFFDFE2F0))),
                            ),
                          ]),
                        ))),

                        const SizedBox(height: 14),
                        Container(height: 1, color: Colors.white.withOpacity(0.06)),
                        const SizedBox(height: 14),

                        // KPI row
                        Row(children: [
                          _miniKpi('TOTAL (USD)', p.totalInclGst > 0 ? _fmtUsd(p.totalInclGst) : 'Upcoming', accent),
                          const SizedBox(width: 16),
                          _miniKpi('SESSIONS', '${p.sessions}', const Color(0xFF94A3B8)),
                          const SizedBox(width: 16),
                          _miniKpi('LAST ACTIVE', lastAct, const Color(0xFF94A3B8)),
                          const Spacer(),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: isHovered ? accent.withOpacity(0.25) : accent.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: accent.withOpacity(isHovered ? 0.7 : 0.35)),
                              boxShadow: isHovered ? [BoxShadow(color: glow.withOpacity(0.5), blurRadius: 12)] : [],
                            ),
                            child: Icon(Icons.arrow_forward_rounded, color: accent, size: 16),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleHero(_ProjectMeta meta, Color accent, _ProjectCard p, bool isHovered) {
    return SizedBox(
      height: 190,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withOpacity(0.15),
                    const Color(0xFF030712).withOpacity(0.85),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
          ),
          // Grid lines overlay
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter(color: accent.withOpacity(0.05))),
          ),
          // Floating vehicle image – background stripped via gradient mask
          if (meta.imagePath != null)
            Positioned(
              bottom: -30,
              right: -10,
              left: 20,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                transform: Matrix4.translationValues(0, isHovered ? -8 : 0, 0),
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, Colors.white, Colors.white],
                    stops: [0.0, 0.22, 1.0],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0.0, 0.55, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: Image.asset(
                      meta.imagePath!,
                      height: 170,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            )
          else
            Center(child: Icon(Icons.directions_car_outlined, color: accent.withOpacity(0.4), size: 64)),

          // Edge-blend overlays to dissolve image into card background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF0D1520).withOpacity(0.85),
                    const Color(0xFF0D1520).withOpacity(0.2),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 0.65],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    accent.withOpacity(0.55),
                    accent.withOpacity(0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.25, 0.6],
                ),
              ),
            ),
          ),

          // Status badge
          Positioned(
            left: 18, top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: accent, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: accent, blurRadius: 4)],
                  ),
                ),
                const SizedBox(width: 6),
                Text(p.sessions > 0 ? 'ACTIVE' : 'UPCOMING',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 8, fontWeight: FontWeight.w700,
                        color: accent, letterSpacing: 1.5)),
              ]),
            ),
          ),

          // INR value badge (top right)
          if (p.totalInclGst > 0)
            Positioned(
              right: 16, top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF030712).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  _inrCompact.format(p.totalInclGst),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllProjectsButton() {
    return GestureDetector(
      onTap: () => context.push('/monthly-invoices-screen', extra: null),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              const Color(0xFF00F3FF).withOpacity(0.06),
              const Color(0xFF4A9EFF).withOpacity(0.04),
            ]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00F3FF).withOpacity(0.25)),
            boxShadow: [BoxShadow(color: const Color(0xFF00F3FF).withOpacity(0.06), blurRadius: 20)],
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF00F3FF).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF00F3FF).withOpacity(0.3)),
              ),
              child: const Icon(Icons.analytics_outlined, color: Color(0xFF00F3FF), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('All Projects — Consolidated View',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('Combined KPIs, expense trends, and session logs across all PoCs',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8))),
            ])),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF00F3FF), size: 16),
          ]),
        ),
      ),
    );
  }

  Widget _miniKpi(String label, String value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.spaceGrotesk(
          fontSize: 8, fontWeight: FontWeight.w700, color: color.withOpacity(0.7), letterSpacing: 1.5)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
    ]);
  }
}

// ─── Deep Space Background ─────────────────────────────────────────────────────
class _DeepSpaceBackground extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _DeepSpaceBackground({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) => CustomPaint(
        painter: _SpacePainter(pulse: pulseAnim.value),
      ),
    );
  }
}

class _SpacePainter extends CustomPainter {
  final double pulse;
  const _SpacePainter({required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    // Background base
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF042024),
          Color(0xFF030712),
        ],
        stops: [0.0, 0.7],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Cyan glow — top-left
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.15),
      size.width * 0.35 + pulse * 30,
      Paint()
        ..color = const Color(0xFF00F3FF).withOpacity(0.018 + pulse * 0.012)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 140),
    );
    // Red glow — bottom-right
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.85),
      size.width * 0.3 + pulse * 20,
      Paint()
        ..color = const Color(0xFFE8002D).withOpacity(0.025 + pulse * 0.01)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100),
    );
    // Blue glow — centre-right
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.3),
      size.width * 0.25,
      Paint()
        ..color = const Color(0xFF4A9EFF).withOpacity(0.015 + pulse * 0.008)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100),
    );
  }

  @override
  bool shouldRepaint(_SpacePainter old) => old.pulse != pulse;
}

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 0.5;
    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}
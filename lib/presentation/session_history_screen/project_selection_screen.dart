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

/// Explicit lifecycle state for a PoC. Set per project below rather than
/// inferred from session count, so a finished project (Mahindra EV) can read
/// "Completed" while keeping its billing history.
enum ProjectStatus { active, upcoming, completed }

extension ProjectStatusExt on ProjectStatus {
  String get label {
    switch (this) {
      case ProjectStatus.active: return 'ACTIVE';
      case ProjectStatus.upcoming: return 'UPCOMING';
      case ProjectStatus.completed: return 'COMPLETED';
    }
  }

  /// Badge colour. Active/Upcoming follow the card accent; Completed is green.
  Color color(Color accent) {
    switch (this) {
      case ProjectStatus.active: return accent;
      case ProjectStatus.upcoming: return accent;
      case ProjectStatus.completed: return const Color(0xFF22C55E);
    }
  }
}

class _ProjectMeta {
  final String displayName;
  final String vehicle;
  final String vehicleType;
  final String description;
  final String? imagePath;

  /// True when [imagePath] is a photograph that carries its own scenery rather
  /// than a vehicle cut out on a dark ground.
  ///
  /// The cutouts are floated over the card and dissolved at the edges, which
  /// only works because there is nothing behind the vehicle to dissolve. A
  /// photograph run through the same treatment reads as a bright rectangle
  /// pasted onto a dark card, so it is laid in full-bleed and dimmed instead —
  /// deliberate backdrop rather than failed cutout. Swap in a background-free
  /// image and this can go back to false.
  final bool imageHasBackdrop;

  final Color accentColor;
  final Color glowColor;
  final List<String> specs;
  final List<_CarDetail> details;
  final ProjectStatus status;
  const _ProjectMeta({
    required this.displayName,
    required this.vehicle,
    required this.vehicleType,
    required this.description,
    this.imagePath,
    this.imageHasBackdrop = false,
    required this.accentColor,
    required this.glowColor,
    this.specs = const [],
    this.details = const [],
    this.status = ProjectStatus.upcoming,
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
    status: ProjectStatus.completed,
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
    status: ProjectStatus.active,
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
  'kia sonet poc': _ProjectMeta(
    displayName: 'Kia Sonet PoC',
    vehicle: 'Kia Sonet',
    vehicleType: 'Turbo Petrol Compact SUV',
    description: 'Goodyear SightLine proof-of-concept on the Kia Sonet. The first sub-4m '
        'compact SUV in the programme and the smallest wheel diameter tested so far, which '
        'makes it the reference case for friction estimation and inflation pressure '
        'monitoring on a higher-profile tyre.',
    imagePath: 'assets/images/kia_sonet.jpg',
    imageHasBackdrop: true,
    status: ProjectStatus.upcoming,
    accentColor: Color(0xFFF5A524),
    glowColor: Color(0xFFD97706),
    specs: ['1.0L T-GDi Turbo', '7-Speed DCT', 'Sub-4m Compact SUV'],
    details: [
      _CarDetail('Approved OEM Size: 215/60 R16', Icons.circle_outlined),
      _CarDetail('1.0L T-GDi Turbo Petrol', Icons.settings_suggest_rounded),
      _CarDetail('Output: 120 PS @ 172 Nm Torque', Icons.speed_rounded),
      _CarDetail('Transmission: 7-Speed DCT / 6-Speed iMT', Icons.settings_input_component_rounded),
      _CarDetail('Smallest wheel and highest profile in the programme', Icons.circle_outlined),
    ],
  ),
  'tata harrier ev poc': _ProjectMeta(
    displayName: 'Tata Harrier EV PoC',
    vehicle: 'Tata Harrier.ev QWD',
    vehicleType: 'Dual-Motor Battery Electric SUV',
    description: 'Goodyear SightLine validation on the Tata Harrier.ev in Quad Wheel Drive form. '
        'Dual-motor torque split makes this the first programme where friction estimation and '
        'tire health monitoring are exercised against independently driven axles, alongside '
        'aquaplaning onset detection across the wet handling and braking tracks.',
    imagePath: 'assets/images/tata_harrier_ev.webp',
    imageHasBackdrop: true,
    status: ProjectStatus.active,
    accentColor: Color(0xFF9BC53D),
    glowColor: Color(0xFF6FA320),
    specs: ['acti.ev+ Architecture', '75 kWh Battery', 'QWD · Dual Motor'],
    details: [
      _CarDetail('Approved OEM Size: 245/55 R19', Icons.circle_outlined),
      _CarDetail('acti.ev+ EV Architecture Platform', Icons.layers_rounded),
      _CarDetail('75 kWh Battery (120 kW DC Fast)', Icons.battery_charging_full_rounded),
      _CarDetail('Quad Wheel Drive · Dual Motor · 504 Nm', Icons.bolt_rounded),
      _CarDetail('MIDC Certified Range: 622 km', Icons.map_rounded),
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
// Card geometry. Fixed rather than intrinsic: the rail lays every card out
// at one height, so a long description or an extra spec chip can no longer
// change how much of the page the projects take up.
const double _kCardHeight = 336;
const double _kHeroHeight = 152;

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

  // Horizontal project rail. _railScroll mirrors the controller offset so
  // the arrows and dots rebuild as it moves.
  final ScrollController _railCtrl = ScrollController();
  double _railScroll = 0;

  // Completed programmes are kept out of the main rail but not dropped:
  // they still carry the bulk of the spend and their own billing history.
  List<_ProjectCard> _completed = [];
  bool _showCompleted = false;

  /// What the rail is currently laying out.
  List<_ProjectCard> get _rail => _showCompleted ? _completed : _projects;

  /// Every programme regardless of state, for the headline totals.
  List<_ProjectCard> get _allProjects => [..._projects, ..._completed];

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
    _railCtrl.addListener(() {
      if (!mounted || !_railCtrl.hasClients) return;
      setState(() => _railScroll = _railCtrl.position.pixels);
    });
    _loadProjects();
  }

  @override
  void dispose() {
    _railCtrl.dispose();
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

      // Maintain fixed order — cardMap was filled from _knownProjects in
      // order, so reading its values back keeps that order without naming
      // each project again here.
      final ordered = cardMap.values.toList();

      // Active programmes lead, upcoming ones bring up the rear, and
      // completed programmes move to their own tab. Partitioning rather
      // than sorting keeps catalogue order inside each group - List.sort
      // is not stable, so a comparator on status alone could shuffle two
      // active programmes past each other between loads.
      List<_ProjectCard> withStatus(ProjectStatus s) =>
          ordered.where((p) => p.meta.status == s).toList();
      final live = [
        ...withStatus(ProjectStatus.active),
        ...withStatus(ProjectStatus.upcoming),
      ];
      final done = withStatus(ProjectStatus.completed);

      if (mounted) {
        setState(() {
          _projects = live;
          _completed = done;
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
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Headline and live stats, side by side where there is room.
                _buildHeroHeadline(),
                const SizedBox(height: 18),
                // Running vs completed - two views of the same rail.
                _buildRailTabs(),
                const SizedBox(height: 14),
                // Every programme on one rail.
                LayoutBuilder(
                    builder: (ctx, c) => _buildProjectCarousel(c.maxWidth)),
                const SizedBox(height: 20),
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
    final all = _allProjects;
    final totalSessions = all.fold(0, (s, p) => s + p.sessions);
    final totalSpendInclGst = all.fold(0.0, (s, p) => s + p.totalInclGst);
    final activeCount =
        all.where((p) => p.meta.status == ProjectStatus.active).length;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        const SizedBox(height: 8),
        // One line rather than two — the headline used to eat 78px of the
        // height the cards need.
        RichText(
          text: TextSpan(children: [
            TextSpan(
              text: 'Select your ',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 30, fontWeight: FontWeight.w800,
                  color: Colors.white, height: 1.1),
            ),
            TextSpan(
              text: 'Project',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 30, fontWeight: FontWeight.w800, height: 1.1,
                foreground: Paint()..shader = const LinearGradient(
                  colors: [Color(0xFF00F3FF), Color(0xFF4A9EFF)],
                ).createShader(const Rect.fromLTWH(0, 0, 220, 38)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
          'Goodyear SightLine PoC validation · NATRAX Proving Ground, Indore',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
      ],
    );

    final stats = Container(
      padding: const EdgeInsets.all(14),
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
        Row(children: [
          _statItem(
            label: 'ACTIVE PoCs',
            value: '$activeCount / ${all.length}',
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
        const SizedBox(height: 12),
        Container(height: 1, color: Colors.white.withOpacity(0.06)),
        const SizedBox(height: 10),
        // Feature pills on a single scrollable line. They used to wrap onto
        // two or three rows and push the cards below the fold.
        SizedBox(
          height: 24,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _tireFeatures.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final f = _tireFeatures[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F3FF).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00F3FF).withOpacity(0.18)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(f.icon, color: const Color(0xFF00F3FF), size: 11),
                  const SizedBox(width: 5),
                  Text(f.name,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: const Color(0xFF00F3FF).withOpacity(0.9))),
                ]),
              );
            },
          ),
        ),
      ]),
    );

    return LayoutBuilder(builder: (ctx, c) {
      // Below ~900 the two blocks stop fitting beside each other legibly.
      if (c.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          title,
          const SizedBox(height: 16),
          stats,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: 330, child: title),
        const SizedBox(width: 28),
        Expanded(child: stats),
      ]);
    });
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

  /// Every programme on a single horizontal rail.
  ///
  /// This replaced a wrapping grid. The grid was correct — it flowed into as
  /// many columns as fit and wrapped — but each card was ~590px tall, so the
  /// moment a fourth programme pushed onto a second row nothing below the
  /// first row was visible without scrolling, and on a laptop even the first
  /// row was clipped. The rail keeps every programme on one line: as many as
  /// fit are shown at once, and any beyond that are one arrow, or one swipe,
  /// away. The card itself is now a fixed [_kCardHeight] summary, with the
  /// description and spec sheet revealed on hover instead of always printed.
  Widget _buildProjectCarousel(double totalWidth) {
    if (_rail.isEmpty) return const SizedBox.shrink();

    const gap = 20.0;
    final perView = totalWidth >= 1360
        ? 4
        : totalWidth >= 1040
            ? 3
            : totalWidth >= 700
                ? 2
                : 1;
    // Never stretch fewer cards than fit across the full width, or two
    // programmes on a wide monitor would each take half the screen.
    final shown = math.min(perView, _rail.length);
    final cardWidth = (totalWidth - gap * (shown - 1)) / shown;
    final extent = cardWidth + gap;
    final overflows = _rail.length > shown;
    final steps = overflows ? _rail.length - shown : 0;
    final atStart = _railScroll <= 1;
    final atEnd = steps == 0 || _railScroll >= extent * steps - 1;

    return Column(children: [
      SizedBox(
        height: _kCardHeight,
        child: Stack(clipBehavior: Clip.none, children: [
          ListView.separated(
            controller: _railCtrl,
            scrollDirection: Axis.horizontal,
            physics: overflows
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: _rail.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (ctx, i) => SizedBox(
              width: cardWidth,
              child: _buildProjectCard(_rail[i], i),
            ),
          ),
          if (overflows) ...[
            Positioned(
              left: -6, top: 0, bottom: 0,
              child: Center(
                child: _railArrow(
                  Icons.chevron_left_rounded,
                  enabled: !atStart,
                  onTap: () => _nudgeRail(-extent),
                ),
              ),
            ),
            Positioned(
              right: -6, top: 0, bottom: 0,
              child: Center(
                child: _railArrow(
                  Icons.chevron_right_rounded,
                  enabled: !atEnd,
                  onTap: () => _nudgeRail(extent),
                ),
              ),
            ),
          ],
        ]),
      ),
      if (overflows) ...[
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(steps + 1, (i) {
            final active = (_railScroll / extent).round() == i;
            return GestureDetector(
              onTap: () => _scrollRailTo(extent * i),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF00F3FF)
                        : Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: active
                        ? [
                            BoxShadow(
                                color: const Color(0xFF00F3FF).withOpacity(0.5),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    ]);
  }

  /// Running programmes and finished ones answer different questions, so the
  /// rail shows one set at a time. The default view is only what is live;
  /// completed programmes keep their billing history one click away.
  Widget _buildRailTabs() {
    if (_completed.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      _railTab(
        label: 'RUNNING',
        count: _projects.length,
        selected: !_showCompleted,
        color: const Color(0xFF00F3FF),
        onTap: () => _switchRail(false),
      ),
      const SizedBox(width: 10),
      _railTab(
        label: 'COMPLETED',
        count: _completed.length,
        selected: _showCompleted,
        color: const Color(0xFF22C55E),
        onTap: () => _switchRail(true),
      ),
    ]);
  }

  Widget _railTab({
    required String label,
    required int count,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color.withOpacity(0.55) : Colors.white.withOpacity(0.08),
            ),
            boxShadow: selected
                ? [BoxShadow(color: color.withOpacity(0.18), blurRadius: 14)]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: selected ? color : const Color(0xFF5A6480),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                    color: selected ? color : const Color(0xFF8892B0))),
            const SizedBox(width: 8),
            Text('$count',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : const Color(0xFF5A6480))),
          ]),
        ),
      ),
    );
  }

  void _switchRail(bool completed) {
    if (_showCompleted == completed) return;
    if (_railCtrl.hasClients) _railCtrl.jumpTo(0);
    setState(() {
      _showCompleted = completed;
      _hoveredIndex = null;
    });
  }

  Widget _railArrow(IconData icon,
      {required bool enabled, required VoidCallback onTap}) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.25,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1520).withOpacity(0.9),
              shape: BoxShape.circle,
              border:
                  Border.all(color: const Color(0xFF00F3FF).withOpacity(0.35)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 16),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF00F3FF), size: 22),
          ),
        ),
      ),
    );
  }

  void _nudgeRail(double delta) {
    if (!_railCtrl.hasClients) return;
    _scrollRailTo(_railCtrl.position.pixels + delta);
  }

  void _scrollRailTo(double offset) {
    if (!_railCtrl.hasClients) return;
    _railCtrl.animateTo(
      offset.clamp(_railCtrl.position.minScrollExtent,
          _railCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildProjectCard(_ProjectCard p, int idx) {
    final isHovered = _hoveredIndex == idx;
    final meta = p.meta;
    final accent = meta.accentColor;
    final glow = meta.glowColor;
    final lastAct = p.lastActivity != null
        ? DateFormat('dd MMM yy').format(p.lastActivity!)
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
          height: _kCardHeight,
          decoration: BoxDecoration(
            color: isHovered
                ? accent.withOpacity(0.08)
                : const Color(0xFF0D1520).withOpacity(0.75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isHovered
                  ? accent.withOpacity(0.6)
                  : Colors.white.withOpacity(0.07),
              width: isHovered ? 1.5 : 1,
            ),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                        color: glow.withOpacity(0.25),
                        blurRadius: 40,
                        spreadRadius: -4)
                  ]
                : [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: _cardResting(p, meta, accent, glow, lastAct, isHovered),
            ),
          ),
        ),
      ),
    );
  }

  /// The card at rest: hero image, identity, and the three numbers a manager
  /// scans for. Fixed height, so a long spec string cannot change it.
  Widget _cardResting(_ProjectCard p, _ProjectMeta meta, Color accent,
      Color glow, String lastAct, bool isHovered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVehicleHero(meta, accent, p, isHovered),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(
                      meta.vehicleType.contains('Electric')
                          ? Icons.electric_bolt_rounded
                          : Icons.local_gas_station_rounded,
                      color: accent,
                      size: 12),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text('${meta.vehicle}  ·  ${meta.vehicleType}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: accent)),
                  ),
                ]),
                const SizedBox(height: 11),
                _specChips(meta, accent),
                const Spacer(),
                Container(height: 1, color: Colors.white.withOpacity(0.06)),
                const SizedBox(height: 12),
                _kpiRow(p, accent, glow, lastAct, isHovered),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Spec chips on one scrollable line. Wrapping them made the card height
  /// depend on how long a given set of spec strings happened to be.
  Widget _specChips(_ProjectMeta meta, Color accent) {
    return SizedBox(
      height: 21,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: meta.specs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: Text(meta.specs[i],
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  letterSpacing: 1)),
        ),
      ),
    );
  }

  Widget _kpiRow(_ProjectCard p, Color accent, Color glow, String lastAct,
      bool isHovered) {
    return Row(children: [
      _miniKpi('TOTAL (USD)',
          p.totalInclGst > 0 ? _fmtUsd(p.totalInclGst) : 'Upcoming', accent),
      const SizedBox(width: 12),
      _miniKpi('SESSIONS', '${p.sessions}', const Color(0xFF94A3B8)),
      const SizedBox(width: 12),
      _miniKpi('LAST ACTIVE', lastAct, const Color(0xFF94A3B8)),
      const Spacer(),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isHovered ? accent.withOpacity(0.25) : accent.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: accent.withOpacity(isHovered ? 0.7 : 0.35)),
          boxShadow: isHovered
              ? [BoxShadow(color: glow.withOpacity(0.5), blurRadius: 12)]
              : [],
        ),
        child: Icon(Icons.arrow_forward_rounded, color: accent, size: 15),
      ),
    ]);
  }

  Widget _buildVehicleHero(_ProjectMeta meta, Color accent, _ProjectCard p, bool isHovered) {
    return SizedBox(
      height: _kHeroHeight,
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
          // Photographic image — laid in full-bleed and dimmed into the card's
          // palette, then faded out towards the bottom so the text below it
          // keeps its contrast. See _ProjectMeta.imageHasBackdrop.
          if (meta.imagePath != null && meta.imageHasBackdrop)
            Positioned.fill(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.45, 0.95],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: ColorFiltered(
                    // Pulls the scenery down towards the card's own darkness so
                    // it sits behind the copy rather than competing with it.
                    colorFilter: ColorFilter.mode(
                      const Color(0xFF030712).withOpacity(0.55),
                      BlendMode.srcOver,
                    ),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 300),
                      scale: isHovered ? 1.06 : 1.0,
                      child: Image.asset(
                        meta.imagePath!,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                ),
              ),
            )
          // Floating vehicle image – background stripped via gradient mask
          else if (meta.imagePath != null)
            Positioned(
              bottom: -24,
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
                      height: 138,
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

          // Status badge — driven by the project's explicit lifecycle status.
          Builder(builder: (_) {
            final statusColor = meta.status.color(accent);
            return Positioned(
              left: 18, top: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  meta.status == ProjectStatus.completed
                      ? Icon(Icons.check_circle,
                          size: 9, color: statusColor)
                      : Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            color: statusColor, shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: statusColor, blurRadius: 4)
                            ],
                          ),
                        ),
                  const SizedBox(width: 6),
                  Text(meta.status.label,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 8, fontWeight: FontWeight.w700,
                          color: statusColor, letterSpacing: 1.5)),
                ]),
              ),
            );
          }),

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
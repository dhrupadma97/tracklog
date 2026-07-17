/// TrackLog — Instrumentation Intelligence Screen
/// 3-tab screen: Catalog · Compatibility · Schematic

import 'dart:ui';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_export.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_background_wrapper.dart';
import '../../data/instrumentation_data.dart';
import '../../data/compatibility_engine.dart';

// ─── Icon Mapper ────────────────────────────────────────────────────────────
IconData _mapIcon(String name) {
  switch (name) {
    case 'sd_storage':
      return Icons.sd_storage;
    case 'usb':
      return Icons.usb;
    case 'computer':
      return Icons.computer;
    case 'sensors':
      return Icons.sensors;
    case 'memory':
      return Icons.memory;
    case 'settings_input_antenna':
      return Icons.settings_input_antenna;
    case 'tablet_android':
      return Icons.tablet_android;
    case 'power':
      return Icons.power;
    case 'cable':
      return Icons.cable;
    case 'precision_manufacturing':
      return Icons.precision_manufacturing;
    default:
      return Icons.device_unknown;
  }
}

IconData _severityIcon(WarningSeverity s) {
  switch (s) {
    case WarningSeverity.error:
      return Icons.error;
    case WarningSeverity.warning:
      return Icons.warning;
    case WarningSeverity.info:
      return Icons.info;
    case WarningSeverity.success:
      return Icons.check_circle;
  }
}

// ─── Gradient helpers ───────────────────────────────────────────────────────
const _kTeal = Color(0xFF00F3FF);
const _kPurple = Color(0xFF7000FF);

Gradient get _tealPurpleGradient => const LinearGradient(
      colors: [_kTeal, _kPurple],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

// ═════════════════════════════════════════════════════════════════════════════
//  INSTRUMENTATION SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class InstrumentationScreen extends StatefulWidget {
  const InstrumentationScreen({super.key});

  @override
  State<InstrumentationScreen> createState() => _InstrumentationScreenState();
}

class _InstrumentationScreenState extends State<InstrumentationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      body: AppBackgroundWrapper(
        child: Column(
          children: [
            const SizedBox(height: 48),
            // ── Title ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => _tealPurpleGradient.createShader(b),
                    child: Text(
                      'Instrumentation Intelligence',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.precision_manufacturing,
                      color: _kTeal.withAlpha(180), size: 28),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── Tab Bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1025).withAlpha(180),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF00F3FF).withAlpha(25)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: _tealPurpleGradient,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(text: 'Catalog'),
                    Tab(text: 'Compatibility'),
                    Tab(text: 'Schematic'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── Tab Views ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _CatalogTab(),
                  _CompatibilityTab(),
                  _SchematicTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TAB 1 — INSTRUMENT CATALOG
// ═════════════════════════════════════════════════════════════════════════════
class _CatalogTab extends StatefulWidget {
  const _CatalogTab();

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> {
  String _filter = 'All';
  String? _expandedId;

  static const _filters = [
    'All',
    'Loggers',
    'Interfaces',
    'ECUs',
    'Sensors',
    'CAN FD Only',
  ];

  List<Instrument> get _filteredCatalog {
    switch (_filter) {
      case 'Loggers':
        return instrumentCatalog
            .where((i) => i.category == InstrumentCategory.logger)
            .toList();
      case 'Interfaces':
        return instrumentCatalog
            .where((i) => i.category == InstrumentCategory.interfaceDevice)
            .toList();
      case 'ECUs':
        return instrumentCatalog
            .where((i) => i.category == InstrumentCategory.ecu)
            .toList();
      case 'Sensors':
        return instrumentCatalog
            .where((i) => i.category == InstrumentCategory.sensor)
            .toList();
      case 'CAN FD Only':
        return instrumentCatalog
            .where((i) => i.supportsCAnFD)
            .toList();
      default:
        return instrumentCatalog;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredCatalog;
    return Column(
      children: [
        // ── Filter Chips ──
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _filters[i];
              final sel = _filter == f;
              return GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: sel ? _tealPurpleGradient : null,
                    color: sel ? null : const Color(0xFF0A1025).withAlpha(180),
                    border: sel
                        ? null
                        : Border.all(
                            color: const Color(0xFF00F3FF).withAlpha(35)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    f,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // ── Grid ──
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final crossCount = constraints.maxWidth > 900
                  ? 3
                  : constraints.maxWidth > 550
                      ? 2
                      : 1;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.05,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) =>
                    _InstrumentCard(
                      instrument: items[i],
                      isExpanded: _expandedId == items[i].id,
                      onTap: () => setState(() {
                        _expandedId =
                            _expandedId == items[i].id ? null : items[i].id;
                      }),
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Instrument Card ─────────────────────────────────────────────────────────
class _InstrumentCard extends StatelessWidget {
  final Instrument instrument;
  final bool isExpanded;
  final VoidCallback onTap;

  const _InstrumentCard({
    required this.instrument,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cat = instrument.category;
    final statusCol = Color(instrument.status.colorValue);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(230),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isExpanded
                ? _kTeal.withAlpha(90)
                : const Color(0xFF00F3FF).withAlpha(35),
            width: isExpanded ? 1.2 : 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Icon + Name
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _kTeal.withAlpha(18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_mapIcon(cat.icon),
                            color: _kTeal, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${instrument.brand} ${instrument.name}',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // Category badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kPurple.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                cat.label,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _kPurple,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Quantity
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(8),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'x${instrument.quantity}',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: instrument.quantity > 0
                                ? Colors.white70
                                : Colors.red.shade300,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Protocol chips
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: instrument.supportedProtocols.map((p) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Color(p.colorValue).withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Color(p.colorValue).withAlpha(60)),
                        ),
                        child: Text(
                          p.shortLabel,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(p.colorValue),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // CAN FD + Status + Channels
                  Row(
                    children: [
                      // CAN FD badge
                      Icon(
                        instrument.supportsCAnFD
                            ? Icons.check_circle
                            : Icons.cancel,
                        size: 14,
                        color: instrument.supportsCAnFD
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF4D6A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'CAN FD',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Status
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusCol.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          instrument.status.label,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: statusCol,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Channel count
                      if (instrument.totalChannels > 0)
                        Text(
                          '${instrument.totalChannels} ch',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            color: Colors.white38,
                          ),
                        ),
                    ],
                  ),
                  // ── Expanded Details ──
                  if (isExpanded) ...[
                    const SizedBox(height: 10),
                    Divider(color: _kTeal.withAlpha(30), height: 1),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              instrument.description,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                            if (instrument.notes != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Notes: ${instrument.notes}',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  color: _kTeal.withAlpha(180),
                                  fontStyle: FontStyle.italic,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (instrument.calibrationDueDate != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.event,
                                      size: 12,
                                      color: Colors.white38),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Cal due: ${instrument.calibrationDueDate!.toIso8601String().substring(0, 10)}',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            // Channel breakdown
                            if (instrument.channelCount.isNotEmpty) ...[
                              Text(
                                'Channels:',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white54,
                                ),
                              ),
                              const SizedBox(height: 3),
                              ...instrument.channelCount.entries.map((e) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(e.key.colorValue),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${e.key.label}: ${e.value}',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 10,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TAB 2 — COMPATIBILITY CHECKER
// ═════════════════════════════════════════════════════════════════════════════
class _CompatibilityTab extends StatefulWidget {
  const _CompatibilityTab();

  @override
  State<_CompatibilityTab> createState() => _CompatibilityTabState();
}

class _CompatibilityTabState extends State<_CompatibilityTab> {
  final Set<BusProtocol> _selectedProtocols = {
    BusProtocol.can2A,
    BusProtocol.can2B,
    BusProtocol.canFD,
  };
  int _requiredChannels = 3;
  final Set<String> _selectedInstrumentIds = {};
  ValidationReport? _report;

  void _runValidation() {
    final instruments = instrumentCatalog
        .where((i) => _selectedInstrumentIds.contains(i.id))
        .toList();
    setState(() {
      _report = CompatibilityEngine.validateSetup(
        vehicleProtocols: _selectedProtocols,
        selectedInstruments: instruments,
        requiredCANChannels: _requiredChannels,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section 1: Protocol Selection ──
          _sectionTitle('Vehicle Protocol Requirements'),
          const SizedBox(height: 8),
          _frostedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: BusProtocol.values.map((p) {
                    final sel = _selectedProtocols.contains(p);
                    return GestureDetector(
                      onTap: () => setState(() {
                        sel
                            ? _selectedProtocols.remove(p)
                            : _selectedProtocols.add(p);
                        _report = null;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: sel
                              ? Color(p.colorValue).withAlpha(30)
                              : const Color(0xFF0A1025),
                          border: Border.all(
                            color: sel
                                ? Color(p.colorValue)
                                : Colors.white.withAlpha(20),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              sel
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 14,
                              color: sel
                                  ? Color(p.colorValue)
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              p.label,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Color(p.colorValue)
                                    : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                // Required CAN channels
                Row(
                  children: [
                    Text(
                      'Required CAN Channels:',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _channelButton(Icons.remove, () {
                      if (_requiredChannels > 1) {
                        setState(() {
                          _requiredChannels--;
                          _report = null;
                        });
                      }
                    }),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_requiredChannels',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _kTeal,
                        ),
                      ),
                    ),
                    _channelButton(Icons.add, () {
                      setState(() {
                        _requiredChannels++;
                        _report = null;
                      });
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Section 2: Instrument Selection ──
          _sectionTitle('Select Instruments'),
          const SizedBox(height: 8),
          _frostedCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: instrumentCatalog.map((inst) {
                final sel = _selectedInstrumentIds.contains(inst.id);
                final catColor = Color(inst.category == InstrumentCategory.logger
                    ? 0xFF00F3FF
                    : inst.category == InstrumentCategory.interfaceDevice
                        ? 0xFF7000FF
                        : inst.category == InstrumentCategory.ecu
                            ? 0xFFFFB547
                            : inst.category == InstrumentCategory.sensor
                                ? 0xFF4CAF50
                                : 0xFF42A5F5);
                return GestureDetector(
                  onTap: () => setState(() {
                    sel
                        ? _selectedInstrumentIds.remove(inst.id)
                        : _selectedInstrumentIds.add(inst.id);
                    _report = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: sel
                          ? catColor.withAlpha(25)
                          : const Color(0xFF0A1025),
                      border: Border.all(
                        color: sel ? catColor : Colors.white.withAlpha(15),
                        width: sel ? 1.2 : 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _mapIcon(inst.category.icon),
                          size: 14,
                          color: sel ? catColor : Colors.white38,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${inst.brand} ${inst.name}',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: sel ? catColor : Colors.white54,
                          ),
                        ),
                        if (sel) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check, size: 12, color: catColor),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Validate Button ──
          Center(
            child: GestureDetector(
              onTap: _selectedInstrumentIds.isEmpty ? null : _runValidation,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: _selectedInstrumentIds.isEmpty
                      ? null
                      : _tealPurpleGradient,
                  color: _selectedInstrumentIds.isEmpty
                      ? Colors.white.withAlpha(10)
                      : null,
                  boxShadow: _selectedInstrumentIds.isEmpty
                      ? null
                      : [
                          BoxShadow(
                            color: _kTeal.withAlpha(40),
                            blurRadius: 20,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user,
                        size: 18,
                        color: _selectedInstrumentIds.isEmpty
                            ? Colors.white30
                            : Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Validate Setup',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _selectedInstrumentIds.isEmpty
                            ? Colors.white30
                            : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Section 3: Results ──
          if (_report != null) ...[
            // Summary banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Color(_report!.overallSeverity.colorValue).withAlpha(20),
                border: Border.all(
                  color:
                      Color(_report!.overallSeverity.colorValue).withAlpha(80),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _severityIcon(_report!.overallSeverity),
                    color: Color(_report!.overallSeverity.colorValue),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _report!.isFullyCompatible
                          ? 'Fully Compatible ✓'
                          : '${_report!.errorCount} errors, ${_report!.warningCount} warnings',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(_report!.overallSeverity.colorValue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Result cards
            ...(_report!.results.map((r) => _resultCard(r))),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return ShaderMask(
      shaderCallback: (b) => _tealPurpleGradient.createShader(b),
      child: Text(
        text,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _frostedCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(230),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: const Color(0xFF00F3FF).withAlpha(35)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _channelButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kTeal.withAlpha(60)),
          color: _kTeal.withAlpha(15),
        ),
        child: Icon(icon, size: 16, color: _kTeal),
      ),
    );
  }

  Widget _resultCard(CompatibilityResult r) {
    final col = Color(r.severity.colorValue);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: col.withAlpha(12),
          border: Border.all(color: col.withAlpha(50)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_severityIcon(r.severity), size: 18, color: col),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: col,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.message,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: Colors.white70,
                      height: 1.35,
                    ),
                  ),
                  if (r.recommendation != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 12, color: _kTeal.withAlpha(180)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            r.recommendation!,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: _kTeal.withAlpha(200),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TAB 3 — INTERACTIVE SCHEMATIC
// ═════════════════════════════════════════════════════════════════════════════
class _SchematicTab extends StatefulWidget {
  const _SchematicTab();

  @override
  State<_SchematicTab> createState() => _SchematicTabState();
}

class _SchematicTabState extends State<_SchematicTab>
    with SingleTickerProviderStateMixin {
  late VehicleProfile _profile;
  String? _selectedNodeId;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _profile = allVehicleProfiles.first;
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Top Bar: Profile Selector + Legend ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Row(
            children: [
              // Dropdown
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1025).withAlpha(230),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF00F3FF).withAlpha(35)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _profile.id,
                    dropdownColor: const Color(0xFF0A1025),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _kTeal,
                    ),
                    icon: const Icon(Icons.arrow_drop_down,
                        color: _kTeal, size: 18),
                    items: allVehicleProfiles.map((p) {
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.name),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _profile = allVehicleProfiles
                              .firstWhere((p) => p.id == v);
                          _selectedNodeId = null;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Legend
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _legendItems(),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Schematic Canvas ──
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1025).withAlpha(200),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: const Color(0xFF00F3FF).withAlpha(25)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final h = constraints.maxHeight;
                      return AnimatedBuilder(
                        animation: _glowCtrl,
                        builder: (context, _) {
                          return Stack(
                            children: [
                              // Painted connections
                              CustomPaint(
                                size: Size(w, h),
                                painter: _SchematicPainter(
                                  nodes: _profile.schematicNodes,
                                  connections:
                                      _profile.schematicConnections,
                                  canvasWidth: w,
                                  canvasHeight: h,
                                  animValue: _glowCtrl.value,
                                  selectedNodeId: _selectedNodeId,
                                ),
                              ),
                              // Interactive node overlays
                              ..._profile.schematicNodes.map((node) {
                                final nx = node.x * w;
                                final ny = node.y * h;
                                const nw = 120.0;
                                const nh = 60.0;
                                final isSel =
                                    _selectedNodeId == node.id;
                                return Positioned(
                                  left: nx - nw / 2,
                                  top: ny - nh / 2,
                                  width: nw,
                                  height: nh,
                                  child: GestureDetector(
                                    onTap: () =>
                                        _onNodeTap(context, node),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 200),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        color: isSel
                                            ? _kTeal.withAlpha(12)
                                            : const Color(0xFF0A1025),
                                        border: Border.all(
                                          color: isSel
                                              ? _kTeal
                                              : _kTeal.withAlpha(60),
                                          width: isSel ? 1.5 : 0.8,
                                        ),
                                        boxShadow: isSel
                                            ? [
                                                BoxShadow(
                                                  color: _kTeal
                                                      .withAlpha(30),
                                                  blurRadius: 16,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            _mapIcon(
                                                node.nodeType.icon),
                                            size: 14,
                                            color: _kTeal,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            node.label,
                                            textAlign:
                                                TextAlign.center,
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: GoogleFonts
                                                .spaceGrotesk(
                                              fontSize: 9,
                                              fontWeight:
                                                  FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (node.sublabel != null)
                                            Text(
                                              node.sublabel!,
                                              textAlign:
                                                  TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow
                                                  .ellipsis,
                                              style: GoogleFonts
                                                  .spaceGrotesk(
                                                fontSize: 7,
                                                color: Colors.white38,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _legendItems() {
    final protocols = <BusProtocol>{};
    for (final c in _profile.schematicConnections) {
      protocols.add(c.protocol);
    }
    return protocols.map((p) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 3,
              decoration: BoxDecoration(
                color: Color(p.colorValue),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              p.label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Color(p.colorValue).withAlpha(200),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  void _onNodeTap(BuildContext context, SchematicNode node) {
    setState(() => _selectedNodeId = node.id);

    // Find linked instrument
    Instrument? inst;
    if (node.instrumentId != null) {
      inst = instrumentCatalog
          .where((i) => i.id == node.instrumentId)
          .firstOrNull;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _nodeDetailSheet(node, inst),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedNodeId = null);
    });
  }

  Widget _nodeDetailSheet(SchematicNode node, Instrument? inst) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(245),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: _kTeal.withAlpha(40)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kTeal.withAlpha(18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_mapIcon(node.nodeType.icon),
                      color: _kTeal, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (b) =>
                            _tealPurpleGradient.createShader(b),
                        child: Text(
                          node.label,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (node.sublabel != null)
                        Text(
                          node.sublabel!,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (inst != null) ...[
              const SizedBox(height: 16),
              Divider(color: _kTeal.withAlpha(25), height: 1),
              const SizedBox(height: 14),
              _detailRow('Brand', inst.brand),
              _detailRow('Category', inst.category.label),
              _detailRow('Status', inst.status.label),
              _detailRow('CAN FD', inst.supportsCAnFD ? 'Yes' : 'No'),
              _detailRow('Quantity', '${inst.quantity}'),
              _detailRow('Total Channels', '${inst.totalChannels}'),
              const SizedBox(height: 10),
              Text(
                inst.description,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              if (inst.notes != null) ...[
                const SizedBox(height: 8),
                Text(
                  inst.notes!,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: _kTeal.withAlpha(180),
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Protocol badges
              Text(
                'Supported Protocols',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: inst.supportedProtocols.map((p) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(p.colorValue).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Color(p.colorValue).withAlpha(50)),
                    ),
                    child: Text(
                      p.label,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(p.colorValue),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (inst == null) ...[
              const SizedBox(height: 14),
              Text(
                'Node type: ${node.nodeType.label}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: Colors.white38,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SCHEMATIC PAINTER
// ═════════════════════════════════════════════════════════════════════════════
class _SchematicPainter extends CustomPainter {
  final List<SchematicNode> nodes;
  final List<SchematicConnection> connections;
  final double canvasWidth;
  final double canvasHeight;
  final double animValue;
  final String? selectedNodeId;

  _SchematicPainter({
    required this.nodes,
    required this.connections,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.animValue,
    this.selectedNodeId,
  });

  Offset _nodeCenter(String nodeId) {
    final n = nodes.firstWhere((n) => n.id == nodeId);
    return Offset(n.x * canvasWidth, n.y * canvasHeight);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final conn in connections) {
      final from = _nodeCenter(conn.fromNodeId);
      final to = _nodeCenter(conn.toNodeId);
      final color = Color(conn.protocol.colorValue);

      // Curved path
      final path = Path()..moveTo(from.dx, from.dy);
      final midX = (from.dx + to.dx) / 2;
      final midY = (from.dy + to.dy) / 2;
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      // Control point offset perpendicular to the line
      final dist = sqrt(dx * dx + dy * dy);
      final curvature = dist * 0.15;
      final cpX = midX - (dy / dist) * curvature;
      final cpY = midY + (dx / dist) * curvature;
      path.quadraticBezierTo(cpX, cpY, to.dx, to.dy);

      // Glow layer
      final glowPaint = Paint()
        ..color = color.withAlpha((20 + (animValue * 25).toInt()))
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(path, glowPaint);

      // Main line — animated dash
      final linePaint = Paint()
        ..color = color.withAlpha(140)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      _drawDashedPath(canvas, path, linePaint, 8, 4, animValue);

      // Label on the midpoint
      final labelOffset = Offset(cpX, cpY - 8);
      _drawLabel(canvas, conn.label, labelOffset, color);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, double dashLen,
      double gapLen, double phase) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final total = metric.length;
      final phaseOffset = phase * (dashLen + gapLen);
      double dist = -phaseOffset % (dashLen + gapLen);
      if (dist < 0) dist += (dashLen + gapLen);
      while (dist < total) {
        final start = dist;
        final end = (dist + dashLen).clamp(0, total);
        if (start < total) {
          final extracted =
              metric.extractPath(start.toDouble(), end.toDouble());
          canvas.drawPath(extracted, paint);
        }
        dist += dashLen + gapLen;
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: color.withAlpha(180),
          fontFamily: 'Space Grotesk',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Background
    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: pos,
        width: tp.width + 10,
        height: tp.height + 6,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(
        bg, Paint()..color = const Color(0xFF050811).withAlpha(200));

    tp.paint(
        canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_SchematicPainter old) =>
      old.animValue != animValue ||
      old.selectedNodeId != selectedNodeId ||
      old.nodes != nodes ||
      old.connections != connections;
}

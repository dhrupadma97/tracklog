/// TrackLog — Instrumentation Intelligence Screen
/// 3-tab screen: Catalog · Compatibility · Schematic

import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_export.dart';
import '../../widgets/app_background_wrapper.dart';
import '../../data/instrumentation_data.dart';
import '../../data/compatibility_engine.dart';
import '../../data/schematic_repository.dart';
import '../../data/dbc_parser.dart';
import '../../services/engineer_auth_service.dart';

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

  // Purpose-first filters: the 3 activity verticals (plus All).
  static const _filters = [
    'All',
    'Calibration',
    'Validation',
    'Data Collection',
  ];

  List<Instrument> get _filteredCatalog {
    switch (_filter) {
      case 'Calibration':
        return instrumentsForVertical(InstrumentVertical.calibration);
      case 'Validation':
        return instrumentsForVertical(InstrumentVertical.validation);
      case 'Data Collection':
        return instrumentsForVertical(InstrumentVertical.dataCollection);
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
        if (_filter == 'Validation') _tireModelsBanner(),
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

  // Banner shown under the Validation filter: the SightLine models run on Raptor.
  Widget _tireModelsBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: _kPurple.withAlpha(20),
        border: Border.all(color: _kPurple.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.model_training, size: 16, color: _kTeal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tire Intelligence Models — run on Raptor CAL → Display',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Raptor CAL is mandatory for validation — vehicle CAN signals feed the models here.',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white54),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tireIntelligenceModels.map((m) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF0A1025).withAlpha(200),
                  border: Border.all(color: _kTeal.withAlpha(50)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: _kTeal),
                    const SizedBox(width: 6),
                    Text(
                      m.name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (m.sensor != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${m.sensor}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
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
  final SchematicRepository _repo = SchematicRepository();

  List<InstrConfig> _configs = [];
  InstrConfig? _config; // selected cloud config (null → built-in template)
  bool _loading = true;
  String? _cloudError;

  String? _selectedNodeId;
  bool _showPinout = false; // Schematic ⇄ OBD Pinout toggle
  bool _editMode = false;
  bool _linking = false; // link-mode: tap two nodes to connect them
  String? _linkFromId;
  bool _dirty = false;
  bool _saving = false;
  late final AnimationController _glowCtrl;

  /// The profile currently displayed — cloud config if available, else the
  /// built-in template (read-only).
  VehicleProfile get _profile =>
      _config?.toProfile() ?? allVehicleProfiles.first;

  bool get _canEdit => _config != null && !_config!.isLocked;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    setState(() {
      _loading = true;
      _cloudError = null;
    });
    try {
      var configs = await _repo.fetchConfigs();
      if (configs.isEmpty) {
        // First run: seed a draft from the built-in template.
        final seeded = await _repo.createFromProfile(allVehicleProfiles.first);
        configs = [seeded];
      }
      if (!mounted) return;
      setState(() {
        _configs = configs;
        final keepId = _config?.id;
        _config = configs.firstWhere(
          (c) => c.id == keepId,
          orElse: () => configs.first,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _config = null;
        _cloudError =
            'Cloud sync unavailable — showing built-in template (read-only). '
            'Apply the instrumentation_configs migration in Supabase to enable editing.';
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.white)),
      backgroundColor: const Color(0xFF0A1025),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _saveNow() async {
    final c = _config;
    if (c == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _repo.saveConfig(c);
      _dirty = false;
      _toast('Schematic saved');
    } catch (e) {
      _toast('Save failed — $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startNewVersion() async {
    final c = _config;
    if (c == null) return;
    try {
      final draft = await _repo.newVersionFrom(c);
      setState(() {
        _configs.insert(0, draft);
        _config = draft;
        _editMode = true;
        _linking = false;
        _linkFromId = null;
      });
      _toast('Draft v${draft.version} created — now editable');
    } catch (e) {
      _toast('Could not create new version — $e');
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kTeal, strokeWidth: 2),
      );
    }
    return Column(
      children: [
        // ── Top Bar: Profile Selector + Legend ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Row(
            children: [
              _vehicleSelector(),
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
        // ── View toggle + edit toolbar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _viewToggle('Schematic', Icons.account_tree, !_showPinout,
                    () => setState(() => _showPinout = false)),
                const SizedBox(width: 8),
                _viewToggle('OBD Pinout', Icons.settings_input_hdmi,
                    _showPinout, () => setState(() => _showPinout = true)),
                if (_config != null && !_showPinout) ...[
                  const SizedBox(width: 14),
                  Container(width: 1, height: 22, color: Colors.white12),
                  const SizedBox(width: 14),
                  ..._toolbarItems(),
                ],
              ],
            ),
          ),
        ),
        if (_cloudError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                const Icon(Icons.cloud_off,
                    size: 12, color: Color(0xFFFFB547)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _cloudError!,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9.5,
                      color: const Color(0xFFFFB547),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // ── Schematic Canvas / OBD Pinout ──
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
                  child: _showPinout
                      ? _ObdPinoutView(
                          pins: _profile.obdPinout, glow: _glowCtrl)
                      : LayoutBuilder(
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
                                final isSel = _selectedNodeId == node.id ||
                                    _linkFromId == node.id;
                                return Positioned(
                                  left: nx - nw / 2,
                                  top: ny - nh / 2,
                                  width: nw,
                                  height: nh,
                                  child: GestureDetector(
                                    onTap: () =>
                                        _onNodeTap(context, node),
                                    onPanUpdate: (_editMode && _canEdit)
                                        ? (d) => setState(() {
                                              node.x = ((node.x * w +
                                                          d.delta.dx) /
                                                      w)
                                                  .clamp(0.04, 0.96);
                                              node.y = ((node.y * h +
                                                          d.delta.dy) /
                                                      h)
                                                  .clamp(0.04, 0.96);
                                              _dirty = true;
                                            })
                                        : null,
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

  // ── Vehicle / config selector ─────────────────────────────────────────────
  Widget _vehicleSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(230),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color(0xFF00F3FF).withAlpha(35)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _config?.id ?? _profile.id,
              dropdownColor: const Color(0xFF0A1025),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _kTeal,
              ),
              icon: const Icon(Icons.arrow_drop_down,
                  color: _kTeal, size: 18),
              items: _config == null
                  ? allVehicleProfiles
                      .map((p) => DropdownMenuItem<String>(
                          value: p.id, child: Text(p.name)))
                      .toList()
                  : _configs
                      .map((c) => DropdownMenuItem<String>(
                          value: c.id, child: Text(c.displayName)))
                      .toList(),
              onChanged: (v) {
                if (v == null || _config == null) return;
                setState(() {
                  _config = _configs.firstWhere((c) => c.id == v);
                  _selectedNodeId = null;
                  _editMode = false;
                  _linking = false;
                  _linkFromId = null;
                  _dirty = false;
                });
              },
            ),
          ),
        ),
        if (_config != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _createNewVehicle,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: _kTeal.withAlpha(15),
                border: Border.all(color: _kTeal.withAlpha(60)),
              ),
              child: const Icon(Icons.add, size: 16, color: _kTeal),
            ),
          ),
        ],
      ],
    );
  }

  /// Create a new vehicle config (seeded from the template, then renamed).
  Future<void> _createNewVehicle() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1025),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('New Vehicle Setup',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: GoogleFonts.spaceGrotesk(fontSize: 13, color: Colors.white),
          decoration: const InputDecoration(
              labelText: 'Vehicle name (e.g. XEV 9e PoC)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final created = await _repo.createFromProfile(allVehicleProfiles.first);
      if (nameCtrl.text.trim().isNotEmpty) {
        created.name = nameCtrl.text.trim();
        await _repo.saveConfig(created);
      }
      setState(() {
        _configs.insert(0, created);
        _config = created;
        _editMode = true;
      });
      _toast('Created "${created.name}" — starts from the standard backbone');
    } catch (e) {
      _toast('Could not create vehicle — $e');
    }
  }

  // ── Edit toolbar ──────────────────────────────────────────────────────────
  List<Widget> _toolbarItems() {
    final c = _config!;
    if (c.isLocked) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFF4CAF50).withAlpha(20),
            border: Border.all(color: const Color(0xFF4CAF50).withAlpha(90)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 13, color: Color(0xFF4CAF50)),
              const SizedBox(width: 6),
              Text(
                'LOCKED v${c.version}'
                '${c.lockedBy != null ? ' · ${c.lockedBy!.split('@').first}' : ''}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _tbBtn(Icons.settings_ethernet, 'Buses', false, _busesSheet),
        const SizedBox(width: 8),
        _tbBtn(Icons.copy_all, 'New Version', false, _startNewVersion),
      ];
    }
    return [
      _tbBtn(Icons.edit, 'Edit', _editMode, () {
        setState(() {
          _editMode = !_editMode;
          if (!_editMode) {
            _linking = false;
            _linkFromId = null;
          }
        });
      }),
      if (_editMode) ...[
        const SizedBox(width: 8),
        _tbBtn(Icons.add_box_outlined, 'Add', false, _addNodeDialog),
        const SizedBox(width: 8),
        _tbBtn(Icons.timeline, _linking ? 'Linking…' : 'Link', _linking, () {
          setState(() {
            _linking = !_linking;
            _linkFromId = null;
          });
        }),
        const SizedBox(width: 8),
        _tbBtn(Icons.cable, 'Wires', false, _connectionsSheet),
      ],
      const SizedBox(width: 8),
      _tbBtn(Icons.settings_ethernet, 'Buses', false, _busesSheet),
      const SizedBox(width: 8),
      _tbBtn(
        _saving ? Icons.hourglass_top : Icons.save_outlined,
        _saving ? 'Saving…' : (_dirty ? 'Save*' : 'Save'),
        _dirty,
        _saveNow,
      ),
      const SizedBox(width: 8),
      _tbBtn(Icons.verified_user, 'Validate & Lock', false,
          _validateAndLockSheet),
    ];
  }

  Widget _tbBtn(
      IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: active ? _tealPurpleGradient : null,
          color: active ? null : const Color(0xFF0A1025).withAlpha(180),
          border: active
              ? null
              : Border.all(color: const Color(0xFF00F3FF).withAlpha(35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13, color: active ? Colors.white : Colors.white54),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add node ──────────────────────────────────────────────────────────────
  Future<void> _addNodeDialog() async {
    String? instId = instrumentCatalog.first.id;
    final labelCtrl =
        TextEditingController(text: instrumentCatalog.first.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('Add Node',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: instId,
                dropdownColor: const Color(0xFF0A1025),
                decoration: const InputDecoration(labelText: 'Instrument'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.white),
                items: [
                  ...instrumentCatalog.map((i) => DropdownMenuItem<String?>(
                        value: i.id,
                        child: Text('${i.brand} ${i.name}'),
                      )),
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Custom / Bus node'),
                  ),
                ],
                onChanged: (v) => setD(() {
                  instId = v;
                  final inst = instrumentCatalog
                      .where((i) => i.id == v)
                      .firstOrNull;
                  if (inst != null) labelCtrl.text = inst.name;
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: labelCtrl,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.white),
                decoration: const InputDecoration(labelText: 'Label'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && _config != null) {
      final inst =
          instrumentCatalog.where((i) => i.id == instId).firstOrNull;
      setState(() {
        _config!.nodes.add(SchematicNode(
          id: 'n${DateTime.now().microsecondsSinceEpoch}',
          label: labelCtrl.text.trim().isEmpty
              ? (inst?.name ?? 'Node')
              : labelCtrl.text.trim(),
          sublabel: inst?.category.label,
          nodeType: inst?.category ?? InstrumentCategory.connector,
          instrumentId: instId,
          x: 0.5,
          y: 0.5,
        ));
        _dirty = true;
      });
      _toast('Node added — drag it into place');
    }
  }

  // ── Connections list (delete wires here) ──────────────────────────────────
  void _connectionsSheet() {
    String nodeLabel(String id) =>
        _profile.schematicNodes.where((n) => n.id == id).firstOrNull?.label ??
        id;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(245),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _kTeal.withAlpha(40)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connections',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 10),
              Flexible(
                child: _profile.schematicConnections.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('No connections yet.',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12, color: Colors.white38)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _profile.schematicConnections.length,
                        itemBuilder: (_, i) {
                          final conn = _profile.schematicConnections[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Color(conn.protocol.colorValue),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${conn.label} · '
                                    '${nodeLabel(conn.fromNodeId)} → '
                                    '${nodeLabel(conn.toNodeId)}',
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 11,
                                        color: Colors.white70),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setSheet(() {});
                                    setState(() {
                                      _config?.connections.remove(conn);
                                      _dirty = true;
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.delete_outline,
                                        size: 16, color: Color(0xFFFF4D6A)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Validate & Lock ───────────────────────────────────────────────────────
  void _validateAndLockSheet() {
    final c = _config;
    if (c == null) return;
    final profile = _profile;
    final instruments = instrumentCatalog
        .where((i) => profile.schematicNodes.any((n) => n.instrumentId == i.id))
        .toList();
    final report = CompatibilityEngine.validateVehicle(
      vehicle: profile,
      selectedInstruments: instruments,
    );
    final canLock = report.errorCount == 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(245),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: _kTeal.withAlpha(40)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Validate & Lock — ${c.name} v${c.version}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              'Locking freezes this schematic and instrument list for the test. '
              'A locked version cannot be edited — start a New Version instead.',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10.5, color: Colors.white54, height: 1.4),
            ),
            const SizedBox(height: 12),
            // Summary banner
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color:
                    Color(report.overallSeverity.colorValue).withAlpha(20),
                border: Border.all(
                    color: Color(report.overallSeverity.colorValue)
                        .withAlpha(80)),
              ),
              child: Row(
                children: [
                  Icon(_severityIcon(report.overallSeverity),
                      size: 18,
                      color: Color(report.overallSeverity.colorValue)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      report.isFullyCompatible
                          ? 'Setup checks out — ready to lock'
                          : '${report.errorCount} error(s), '
                              '${report.warningCount} warning(s)',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(report.overallSeverity.colorValue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: report.results.length,
                itemBuilder: (_, i) {
                  final r = report.results[i];
                  final col = Color(r.severity.colorValue);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_severityIcon(r.severity),
                            size: 13, color: col),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${r.title} — ${r.message}',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10.5,
                                color: Colors.white70,
                                height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(sheetCtx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text('Cancel',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: canLock
                        ? () async {
                            Navigator.pop(sheetCtx);
                            try {
                              final by = EngineerAuthService
                                      .instance.currentUser?.email ??
                                  'engineer';
                              await _repo.lockConfig(c, lockedBy: by);
                              await _loadConfigs();
                              _toast(
                                  '${c.name} v${c.version} locked ✓');
                            } catch (e) {
                              _toast('Lock failed — $e');
                            }
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: canLock ? _tealPurpleGradient : null,
                        color:
                            canLock ? null : Colors.white.withAlpha(10),
                      ),
                      child: Text(
                        canLock ? 'Confirm Lock 🔒' : 'Fix errors to lock',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              canLock ? Colors.white : Colors.white30,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Buses & Pins editor (+ DBC per bus) ───────────────────────────────────
  /// Rebuild the OBD pinout from the bus list: bus pins glow with their
  /// protocol, pins losing their bus become "Unused", power/ground stay.
  void _syncPinoutFromBuses(InstrConfig c) {
    final byPin = {for (final p in c.obdPinout) p.pinNumber: p};
    final fromBuses = <int, OBDPin>{};
    for (final b in c.buses) {
      if (b.obdPinHigh != null) {
        fromBuses[b.obdPinHigh!] = OBDPin(
          pinNumber: b.obdPinHigh!,
          description: b.protocol.isCan ? '${b.name} CANH' : b.name,
          protocol: b.protocol,
          isHighLine: true,
        );
      }
      if (b.obdPinLow != null) {
        fromBuses[b.obdPinLow!] = OBDPin(
          pinNumber: b.obdPinLow!,
          description: b.protocol.isCan ? '${b.name} CANL' : b.name,
          protocol: b.protocol,
          isHighLine: false,
        );
      }
    }
    final result = <OBDPin>[];
    for (var pin = 1; pin <= 16; pin++) {
      if (fromBuses.containsKey(pin)) {
        result.add(fromBuses[pin]!);
      } else {
        final existing = byPin[pin];
        if (existing != null && existing.protocol == null) {
          result.add(existing); // power / ground / ignition — keep as-is
        } else {
          result.add(OBDPin(pinNumber: pin, description: 'Unused'));
        }
      }
    }
    c.obdPinout = result;
  }

  void _busesSheet() {
    final c = _config;
    if (c == null) return;
    final readOnly = c.isLocked;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(245),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _kTeal.withAlpha(40)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Vehicle Buses',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const Spacer(),
                  if (!readOnly)
                    GestureDetector(
                      onTap: () async {
                        final bus = await _busDialog(null);
                        if (bus != null) {
                          setState(() {
                            c.buses.add(bus);
                            _syncPinoutFromBuses(c);
                            _dirty = true;
                          });
                          setSheet(() {});
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: _tealPurpleGradient,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('Add Bus',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'These are this vehicle\'s CAN/LIN buses — edit them when the '
                'PoC vehicle arrives. Pins update the OBD pinout automatically. '
                'Attach the OEM DBC to each bus.',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: Colors.white38, height: 1.4),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: c.buses.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('No buses defined yet.',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12, color: Colors.white38)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: c.buses.length,
                        itemBuilder: (_, i) {
                          final bus = c.buses[i];
                          final col = Color(bus.protocol.colorValue);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0xFF060B1A),
                              border:
                                  Border.all(color: col.withAlpha(60)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: col,
                                    borderRadius:
                                        BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(bus.name,
                                          style: GoogleFonts.spaceGrotesk(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white),
                                          overflow:
                                              TextOverflow.ellipsis),
                                      Text(
                                        '${bus.protocol.label}'
                                        '${bus.obdPinHigh != null ? ' · pins ${bus.obdPinHigh}/${bus.obdPinLow ?? '—'}' : ''}',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 10, color: col),
                                      ),
                                    ],
                                  ),
                                ),
                                // DBC chip
                                GestureDetector(
                                  onTap: () => bus.dbcFile == null
                                      ? (readOnly
                                          ? null
                                          : _attachDbc(c, i, setSheet))
                                      : _dbcViewerSheet(
                                          c, i, setSheet, readOnly),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      color: bus.dbcFile != null
                                          ? _kTeal.withAlpha(18)
                                          : Colors.white.withAlpha(8),
                                      border: Border.all(
                                          color: bus.dbcFile != null
                                              ? _kTeal.withAlpha(80)
                                              : Colors.white24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          bus.dbcFile != null
                                              ? Icons.description
                                              : Icons.upload_file,
                                          size: 12,
                                          color: bus.dbcFile != null
                                              ? _kTeal
                                              : Colors.white38,
                                        ),
                                        const SizedBox(width: 4),
                                        ConstrainedBox(
                                          constraints:
                                              const BoxConstraints(
                                                  maxWidth: 90),
                                          child: Text(
                                            bus.dbcFile ?? 'DBC',
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style:
                                                GoogleFonts.spaceGrotesk(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              color: bus.dbcFile != null
                                                  ? _kTeal
                                                  : Colors.white38,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!readOnly) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () async {
                                      final edited =
                                          await _busDialog(bus);
                                      if (edited != null) {
                                        setState(() {
                                          c.buses[i] = edited;
                                          _syncPinoutFromBuses(c);
                                          _dirty = true;
                                        });
                                        setSheet(() {});
                                      }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.edit,
                                          size: 15,
                                          color: Colors.white38),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      final removed = c.buses[i];
                                      setState(() {
                                        c.buses.removeAt(i);
                                        _syncPinoutFromBuses(c);
                                        _dirty = true;
                                      });
                                      // best-effort DBC cleanup
                                      _repo
                                          .removeDbc(c.id, removed.id)
                                          .catchError((_) {});
                                      setSheet(() {});
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_outline,
                                          size: 15,
                                          color: Color(0xFFFF4D6A)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Add/edit one bus. Returns the new [VehicleBus], or null on cancel.
  Future<VehicleBus?> _busDialog(VehicleBus? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final pinHCtrl = TextEditingController(
        text: existing?.obdPinHigh?.toString() ?? '');
    final pinLCtrl =
        TextEditingController(text: existing?.obdPinLow?.toString() ?? '');
    BusProtocol proto = existing?.protocol ?? BusProtocol.can2A;
    const vehicleProtocols = [
      BusProtocol.can2A,
      BusProtocol.can2B,
      BusProtocol.canFD,
      BusProtocol.lin,
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Add Bus' : 'Edit Bus',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: existing == null,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Bus name (e.g. PT_CAN)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<BusProtocol>(
                initialValue: proto,
                dropdownColor: const Color(0xFF0A1025),
                decoration: const InputDecoration(labelText: 'Protocol'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.white),
                items: vehicleProtocols
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.label,
                            style:
                                TextStyle(color: Color(p.colorValue)))))
                    .toList(),
                onChanged: (v) => setD(() => proto = v ?? proto),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pinHCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'OBD pin H (1–16)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: pinLCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'OBD pin L (1–16)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: Text(existing == null ? 'Add' : 'Save')),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    int? parsePin(String s) {
      final v = int.tryParse(s.trim());
      return (v != null && v >= 1 && v <= 16) ? v : null;
    }

    final name = nameCtrl.text.trim();
    return VehicleBus(
      id: existing?.id ??
          'bus${DateTime.now().microsecondsSinceEpoch}',
      name: name.isEmpty ? proto.label : name,
      protocol: proto,
      obdPinHigh: parsePin(pinHCtrl.text),
      obdPinLow: parsePin(pinLCtrl.text),
      description: existing?.description,
      dbcFile: existing?.dbcFile,
    );
  }

  // ── DBC attach / view ─────────────────────────────────────────────────────
  Future<void> _attachDbc(InstrConfig c, int busIndex,
      void Function(void Function()) setSheet) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dbc'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      _toast('Could not read the file');
      return;
    }
    final content = utf8.decode(bytes, allowMalformed: true);
    final msgs = parseDbc(content);
    final sigCount = dbcSignalCount(msgs);
    try {
      await _repo.upsertDbc(
        configId: c.id,
        busId: c.buses[busIndex].id,
        fileName: f.name,
        content: content,
        messageCount: msgs.length,
        signalCount: sigCount,
        uploadedBy: EngineerAuthService.instance.currentUser?.email,
      );
      setState(() {
        c.buses[busIndex] = c.buses[busIndex].copyWith(dbcFile: f.name);
      });
      await _repo.saveConfig(c);
      setSheet(() {});
      _toast('${f.name} attached — ${msgs.length} messages, '
          '$sigCount signals');
    } catch (e) {
      _toast('DBC upload failed — $e');
    }
  }

  void _dbcViewerSheet(InstrConfig c, int busIndex,
      void Function(void Function()) setBusSheet, bool readOnly) {
    final bus = c.buses[busIndex];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(245),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: _kTeal.withAlpha(40)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, size: 16, color: _kTeal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${bus.dbcFile} — ${bus.name}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!readOnly) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _attachDbc(c, busIndex, setBusSheet);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.upload_file,
                          size: 16, color: Colors.white54),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        await _repo.removeDbc(c.id, bus.id);
                        setState(() {
                          c.buses[busIndex] =
                              c.buses[busIndex].copyWith(clearDbc: true);
                        });
                        await _repo.saveConfig(c);
                        setBusSheet(() {});
                        _toast('DBC removed');
                      } catch (e) {
                        _toast('Remove failed — $e');
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 16, color: Color(0xFFFF4D6A)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: FutureBuilder<String?>(
                future: _repo.getDbcContent(c.id, bus.id),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: _kTeal, strokeWidth: 2)),
                    );
                  }
                  final content = snap.data;
                  if (content == null) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('DBC content not found in cloud.',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 12, color: Colors.white38)),
                    );
                  }
                  final msgs = parseDbc(content);
                  if (msgs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('No messages parsed from this DBC.',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 12, color: Colors.white38)),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final m = msgs[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0xFF060B1A),
                          border: Border.all(
                              color: _kTeal.withAlpha(25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m.name,
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${m.idHex} · ${m.dlc}B',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9.5, color: _kTeal),
                                ),
                              ],
                            ),
                            if (m.signals.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                m.signals.join(' · '),
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 9.5,
                                    color: Colors.white38,
                                    height: 1.3),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _viewToggle(
      String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: active ? _tealPurpleGradient : null,
          color: active ? null : const Color(0xFF0A1025).withAlpha(180),
          border: active
              ? null
              : Border.all(color: const Color(0xFF00F3FF).withAlpha(35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? Colors.white : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
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
    // Link mode: first tap picks the source, second tap creates a connection.
    if (_editMode && _linking) {
      if (_linkFromId == null) {
        setState(() => _linkFromId = node.id);
        return;
      }
      if (_linkFromId == node.id) {
        setState(() => _linkFromId = null); // tap again to deselect
        return;
      }
      _finishLink(node);
      return;
    }

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
      builder: (sheetCtx) => _nodeDetailSheet(sheetCtx, node, inst),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedNodeId = null);
    });
  }

  /// Complete a link started in link mode: pick protocol + label, then add.
  Future<void> _finishLink(SchematicNode toNode) async {
    final fromId = _linkFromId!;
    BusProtocol proto = BusProtocol.can2A;
    final labelCtrl = TextEditingController(text: 'CAN');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('New Connection',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<BusProtocol>(
                initialValue: proto,
                dropdownColor: const Color(0xFF0A1025),
                decoration: const InputDecoration(labelText: 'Protocol'),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.white),
                items: BusProtocol.values
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.label,
                            style: TextStyle(
                                color: Color(p.colorValue)))))
                    .toList(),
                onChanged: (v) => setD(() {
                  if (v != null) {
                    proto = v;
                    labelCtrl.text = v.label;
                  }
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: labelCtrl,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: Colors.white),
                decoration: const InputDecoration(labelText: 'Label'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dCtx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && _config != null) {
      setState(() {
        _config!.connections.add(SchematicConnection(
          fromNodeId: fromId,
          toNodeId: toNode.id,
          label: labelCtrl.text.trim().isEmpty
              ? proto.label
              : labelCtrl.text.trim(),
          protocol: proto,
        ));
        _dirty = true;
        _linkFromId = null;
      });
    } else {
      setState(() => _linkFromId = null);
    }
  }

  Widget _nodeDetailSheet(
      BuildContext sheetCtx, SchematicNode node, Instrument? inst) {
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
            if (_editMode && _canEdit) ...[
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    setState(() {
                      _config!.nodes.removeWhere((n) => n.id == node.id);
                      _config!.connections.removeWhere((con) =>
                          con.fromNodeId == node.id ||
                          con.toNodeId == node.id);
                      _dirty = true;
                    });
                    _toast('Node removed');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFFFF4D6A).withAlpha(20),
                      border: Border.all(
                          color: const Color(0xFFFF4D6A).withAlpha(90)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.delete_outline,
                            size: 15, color: Color(0xFFFF4D6A)),
                        const SizedBox(width: 6),
                        Text(
                          'Remove from Schematic',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFF4D6A),
                          ),
                        ),
                      ],
                    ),
                  ),
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


// ═════════════════════════════════════════════════════════════════════════════
//  OBD-II PINOUT VIEW — animated, per-vehicle
// ═════════════════════════════════════════════════════════════════════════════
class _ObdPinoutView extends StatelessWidget {
  final List<OBDPin> pins;
  final AnimationController glow;
  const _ObdPinoutView({required this.pins, required this.glow});

  @override
  Widget build(BuildContext context) {
    final sorted = [...pins]..sort((a, b) => a.pinNumber.compareTo(b.pinNumber));
    final top = sorted.where((p) => p.pinNumber <= 8).toList();
    final bottom = sorted.where((p) => p.pinNumber >= 9).toList();

    return AnimatedBuilder(
      animation: glow,
      builder: (context, _) {
        final t = glow.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_input_hdmi, color: _kTeal, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'OBD-II Diagnostic Connector · 16-pin',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Connector housing (trapezoid-ish)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF060B1A).withAlpha(230),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                      bottom: Radius.circular(22),
                    ),
                    border: Border.all(color: _kTeal.withAlpha(60)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [for (final p in top) _pinCell(p, t)],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [for (final p in bottom) _pinCell(p, t)],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Glowing pins carry an active bus on this vehicle. '
                'Grey pins are power, ground or unused.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: Colors.white38,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pinCell(OBDPin p, double t) {
    final active = p.protocol != null;
    final col =
        active ? Color(p.protocol!.colorValue) : const Color(0xFF6B7490);
    final pulse = active ? (0.35 + t * 0.55) : 0.0;
    return Container(
      width: 96,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: col.withAlpha(active ? (16 + (t * 22).toInt()) : 10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: col.withAlpha(active ? 150 : 45),
          width: active ? 1.2 : 0.8,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: col.withAlpha((pulse * 110).toInt()),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: col.withAlpha(40),
              border: Border.all(color: col.withAlpha(170)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${p.pinNumber}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: col,
              ),
            ),
          ),
          const SizedBox(height: 5),
          if (p.protocol != null)
            Text(
              p.protocol!.shortLabel,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: col,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            p.description,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 8.5,
              color: Colors.white54,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

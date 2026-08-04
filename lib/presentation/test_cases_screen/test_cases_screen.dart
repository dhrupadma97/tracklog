import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/test_case_model.dart';
import '../../data/services/test_case_service.dart';

class TestCasesScreen extends StatefulWidget {
  const TestCasesScreen({Key? key}) : super(key: key);

  @override
  State<TestCasesScreen> createState() => _TestCasesScreenState();
}

class _TestCasesScreenState extends State<TestCasesScreen> {
  // ─── Goodyear palette ────────────────────────────────────────────────────────
  static const Color gold = Color(0xFFC6A15B);
  static const Color darkNavy = Color(0xFF0A2342);
  static const Color navy = Color(0xFF12325C);
  static const Color cream = Color(0xFFECE3CE);
  static const Color evColor = Color(0xFF1E88E5);
  static const Color iceColor = Color(0xFFE65100);

  // ─── Road-surface colour key (shared by the filter chips, the Road Surface
  // cell, and the per-row tint so a surface CHANGE is obvious while scrolling
  // the full sheet) ────────────────────────────────────────────────────────
  static const Map<String, Color> surfaceColors = {
    'Jump Mu':     Color(0xFF6A1B9A),
    'Split Mu':    Color(0xFF283593),
    'Wet Basalt':  Color(0xFF00695C),
    'Wet Ceramic': Color(0xFF00838F),
    'Wet Asphalt': Color(0xFF0277BD),
    'Dry Asphalt': Color(0xFF558B2F),
    'Dry':         Color(0xFF827717),
    'Dry Handling':Color(0xFFBF360C),
    'N/A':         Color(0xFF607D8B),
  };

  Color _surfaceColor(String type) =>
      surfaceColors[type] ?? const Color(0xFF37474F);

  /// Solid pale tint of the surface colour on white — used as the row
  /// background so black cell text stays readable while surface bands are
  /// still easy to tell apart.
  Color _surfaceRowTint(String type) =>
      Color.alphaBlend(_surfaceColor(type).withOpacity(0.13), Colors.white);

  /// Curved aquaplaning can't be run at NATRAX / in India, so any curve-based
  /// case is hidden everywhere. One predicate ⇒ trivial to re-enable later.
  bool _isCurveCase(TestCase t) =>
      '${t.testCasesName} ${t.testDescription}'.toLowerCase().contains('curve');

  // ─── State ───────────────────────────────────────────────────────────────────
  late List<TestCase> _allTestCases;

  String _selectedDrivetrain = 'All'; // 'EV' | 'ICE' | 'All'
  String _selectedActivity = 'All';   // 'Validation' | 'Calibration' | 'All'
  String _selectedFeature = 'All';    // 'AQD' | 'DFE' | 'Leak Detection' | 'All'
  String _selectedWaterDepth = 'All'; // '4mm' | '8mm' | 'All'
  String _selectedLoad = 'All';       // 'Driver Only' | 'Full' | 'Unload' | 'Driver + Ballast' | 'All'
  String _selectedSurface = 'All';    // 'Jump Mu' | 'Split Mu' | 'Wet Basalt' | etc. | 'All'

  // ─── Strategy info — accurate NATRAX / India context ─────────────────────────
  // EV vs ICE key difference: EV has regen + coast-down; ICE has downshift/upshift.
  // Most test cases are IDENTICAL for both drivetrains at NATRAX.
  final Map<String, Map<String, String>> _strategyInfo = {
    'AQD': {
      'EV':  'EV-Specific (AQD): The algorithm must distinguish true aquaplaning signals '
             'from EV regenerative braking deceleration and coast-down torque profiles. '
             'Regen events create deceleration similar to aquaplaning — additional '
             'signal filtering thresholds are required.',
      'ICE': 'ICE-Specific (AQD): The algorithm must reject false triggers from downshift '
             'and upshift torque spikes during gear changes. Tip-in/tip-out transients '
             'and engine braking events are characterised separately to prevent '
             'mis-classification as aquaplaning.',
      'All': 'AQD Strategy (NATRAX): Most test cases are identical for EV and ICE. '
             'EV adds regen/coast-down rejection; ICE adds downshift/upshift transient '
             'rejection. Calibration covers 4mm and 8mm water depths on Asphalt.',
    },
    'DFE': {
      'EV':  'EV-Specific (DFE): Motor torque feedback and regen braking events provide '
             'additional high-resolution data for mu estimation. Coast-down deceleration '
             'is also used as a supplementary surface-estimation trigger.',
      'ICE': 'ICE-Specific (DFE): Relies solely on hydraulic braking pressure and '
             'wheel-speed differential for mu estimation. Downshift/upshift gear-change '
             'transients must be filtered out to isolate road-surface signatures.',
      'All': 'DFE Strategy (NATRAX): Core maneuvers (Cruising, Light/Heavy Acceleration, '
             'Light/Heavy Braking) are identical for EV and ICE. The only drivetrain '
             'difference is the regen source for EV vs. hydraulic braking for ICE.',
    },
    'Leak Detection': {
      'EV':  'EV-Specific (Leak Detection): The quieter EV cabin amplifies low-frequency '
             'rolling-resistance vibration signals, improving detection sensitivity. '
             'No gear-change interference. Coast-down events supplement leak signatures.',
      'ICE': 'ICE-Specific (Leak Detection): Higher NVH baseline from combustion engine '
             'requires bandpass filtering on rolling-resistance signals. Gear-change '
             'vibration transients are masked to prevent false leak detection.',
      'All': 'Leak Detection (NATRAX): All 10 calibration cases map specific Leak Rates '
             '(1000–30000) against Interval limits (375ms–13250ms). Test procedure is '
             'the same for EV and ICE — only the noise floor differs.',
    },
    'All': {
      'EV':  'EV Strategy (Global): Across all features, EV-specific tests address '
             'regenerative braking and coast-down deceleration. These events are unique '
             'to EVs and require separate algorithm thresholds. All other test cases '
             'are shared with ICE.',
      'ICE': 'ICE Strategy (Global): Across all features, ICE-specific tests address '
             'downshift/upshift gear-change transients and engine braking behaviour. '
             'These are unique to ICE drivetrains. All other test cases are shared '
             'with EV.',
      'All': 'NATRAX DVP Strategy: Most test cases (836/926) apply identically to both '
             'EV and ICE. Key difference — EV: regen + coast-down events. ICE: '
             'downshift + upshift transients. Select EV or ICE above to see the '
             'drivetrain-specific strategy.',
    },
  };

  @override
  void initState() {
    super.initState();
    // Drop curve-based cases up front so every count, filter and the strategy
    // banner reflect only what NATRAX can actually test.
    _allTestCases = TestCaseService.getMockTestCases()
        .where((t) => !_isCurveCase(t))
        .toList();
  }

  List<TestCase> get _filteredCases {
    return _allTestCases.where((tc) {
      final drivetrainMatch = _selectedDrivetrain == 'All' ||
          tc.drivetrain == _selectedDrivetrain ||
          tc.drivetrain == 'Both';
      final activityMatch =
          _selectedActivity == 'All' || tc.activityType == _selectedActivity;
      final featureMatch =
          _selectedFeature == 'All' || tc.feature == _selectedFeature;
      final waterDepthMatch =
          _selectedWaterDepth == 'All' || tc.waterDepth == _selectedWaterDepth;
      final loadMatch =
          _selectedLoad == 'All' || tc.loadCategory == _selectedLoad;
      final surfaceMatch =
          _selectedSurface == 'All' || tc.roadSurfaceType == _selectedSurface;
      return drivetrainMatch && activityMatch && featureMatch &&
          waterDepthMatch && loadMatch && surfaceMatch;
    }).toList();
  }

  String get _strategyTextResolved {
    final featureKey =
        _strategyInfo.containsKey(_selectedFeature) ? _selectedFeature : 'All';
    final map = _strategyInfo[featureKey] ?? {};
    if (_selectedDrivetrain != 'All' && map.containsKey(_selectedDrivetrain)) {
      return map[_selectedDrivetrain]!;
    }
    return map['All'] ?? '';
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCases;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Test Cases Repository',
          style: GoogleFonts.barlow(
              fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          _buildStrategyBanner(),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMainTitle(),
                      _buildSubtitle(),
                      const SizedBox(height: 12),
                      _buildScopeRow(filtered.length),
                      const SizedBox(height: 12),
                      filtered.isEmpty
                          ? _buildEmptyState()
                          : _buildDataTable(filtered),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Filter bar ───────────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: darkNavy,
        border: const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Drivetrain
          Row(mainAxisSize: MainAxisSize.min, children: [
            _sectionLabel('Drivetrain:'),
            const SizedBox(width: 8),
            _drivetrainToggle(),
          ]),

          // Feature
          Row(mainAxisSize: MainAxisSize.min, children: [
            _sectionLabel('Feature:'),
            const SizedBox(width: 8),
            _featureChips(),
          ]),

          // Activity
          Row(mainAxisSize: MainAxisSize.min, children: [
            _sectionLabel('Activity:'),
            const SizedBox(width: 8),
            _activityChips(),
          ]),

          // Water Depth
          Row(mainAxisSize: MainAxisSize.min, children: [
            _sectionLabel('Water Depth:'),
            const SizedBox(width: 8),
            _waterDepthChips(),
          ]),

          // Load
          Row(mainAxisSize: MainAxisSize.min, children: [
            _sectionLabel('Load:'),
            const SizedBox(width: 8),
            _loadChips(),
          ]),

          // Road Surface
          Row(mainAxisSize: MainAxisSize.min, children: [
            _sectionLabel('Surface:'),
            const SizedBox(width: 8),
            _surfaceChips(),
          ]),

          // Reset
          TextButton.icon(
            onPressed: () => setState(() {
              _selectedDrivetrain = 'All';
              _selectedActivity = 'All';
              _selectedFeature = 'All';
              _selectedWaterDepth = 'All';
              _selectedLoad = 'All';
              _selectedSurface = 'All';
            }),
            icon: const Icon(Icons.refresh, size: 14, color: Colors.white54),
            label: const Text('Reset',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontFamily: 'Arial',
            fontSize: 11,
            color: Colors.white60,
            fontWeight: FontWeight.bold),
      );

  Widget _drivetrainToggle() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['EV', 'ICE', 'All'].map((dt) {
          final selected = _selectedDrivetrain == dt;
          Color bgColor;
          if (selected && dt == 'EV') bgColor = evColor;
          else if (selected && dt == 'ICE') bgColor = iceColor;
          else if (selected) bgColor = Colors.white24;
          else bgColor = Colors.transparent;

          return GestureDetector(
            onTap: () => setState(() => _selectedDrivetrain = dt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dt == 'EV') const Icon(Icons.electric_bolt, size: 13, color: Colors.white),
                  if (dt == 'ICE') const Icon(Icons.local_fire_department, size: 13, color: Colors.white),
                  if (dt != 'All') const SizedBox(width: 4),
                  Text(dt,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        color: Colors.white,
                      )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _featureChips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['All', 'AQD', 'DFE', 'Leak Detection'].map((f) {
        final selected = _selectedFeature == f;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(f,
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? darkNavy : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            selected: selected,
            selectedColor: gold,
            backgroundColor: Colors.white12,
            side: BorderSide(color: selected ? gold : Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            onSelected: (_) => setState(() {
              _selectedFeature = f;
              // Reset water depth when switching away from AQD
              if (f != 'AQD' && f != 'All') _selectedWaterDepth = 'All';
            }),
          ),
        );
      }).toList(),
    );
  }

  Widget _activityChips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['All', 'Validation', 'Calibration'].map((a) {
        final selected = _selectedActivity == a;
        final color = a == 'Validation'
            ? const Color(0xFF43A047)
            : a == 'Calibration'
                ? const Color(0xFF7B1FA2)
                : Colors.blueGrey;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(a,
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
            selected: selected,
            selectedColor: color,
            backgroundColor: Colors.white12,
            side: BorderSide(color: selected ? color : Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            onSelected: (_) => setState(() => _selectedActivity = a),
          ),
        );
      }).toList(),
    );
  }

  Widget _waterDepthChips() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['All', '4mm', '8mm'].map((wd) {
        final selected = _selectedWaterDepth == wd;
        const waterColor = Color(0xFF0288D1);
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wd != 'All') const Icon(Icons.water_drop, size: 11, color: Colors.white70),
                if (wd != 'All') const SizedBox(width: 3),
                Text(wd,
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              ],
            ),
            selected: selected,
            selectedColor: waterColor,
            backgroundColor: Colors.white12,
            side: BorderSide(color: selected ? waterColor : Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            onSelected: (_) => setState(() => _selectedWaterDepth = wd),
          ),
        );
      }).toList(),
    );
  }

  Widget _loadChips() {
    const options = ['All', 'Driver Only', 'Full', 'Unload', 'Driver + Ballast'];
    const loadColor = Color(0xFF00838F); // teal
    return Wrap(
      spacing: 6,
      children: options.map((l) {
        final selected = _selectedLoad == l;
        return ChoiceChip(
          label: Text(l,
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          selected: selected,
          selectedColor: loadColor,
          backgroundColor: Colors.white12,
          side: BorderSide(color: selected ? loadColor : Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          onSelected: (_) => setState(() => _selectedLoad = l),
        );
      }).toList(),
    );
  }

  Widget _surfaceChips() {
    // Surface options — ordered by relevance (DFE-centric first)
    const options = [
      'All',
      'Jump Mu',
      'Split Mu',
      'Wet Basalt',
      'Wet Ceramic',
      'Wet Asphalt',
      'Dry Asphalt',
      'Dry',
      'Dry Handling',
      'N/A',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: options.map((s) {
        final selected = _selectedSurface == s;
        final color = _surfaceColor(s);
        return ChoiceChip(
          label: Text(s,
              style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          selected: selected,
          selectedColor: color,
          backgroundColor: Colors.white12,
          side: BorderSide(color: selected ? color : Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          onSelected: (_) => setState(() => _selectedSurface = s),
        );
      }).toList(),
    );
  }


  // ─── Strategy banner ──────────────────────────────────────────────────────────

  Widget _buildStrategyBanner() {
    final isEV = _selectedDrivetrain == 'EV';
    final isICE = _selectedDrivetrain == 'ICE';
    final Color leftBar = isEV ? evColor : isICE ? iceColor : navy;
    final IconData icon = isEV
        ? Icons.electric_bolt
        : isICE
            ? Icons.local_fire_department
            : Icons.info_outline;

    final featureLabel =
        _selectedFeature == 'All' ? 'Global' : _selectedFeature;
    final dtLabel = _selectedDrivetrain == 'All' ? '' : '$_selectedDrivetrain ';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: darkNavy.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: leftBar, width: 4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: leftBar, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dtLabel$featureLabel Testing Strategy — NATRAX',
                  style: TextStyle(
                      fontFamily: 'Arial',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: leftBar),
                ),
                const SizedBox(height: 3),
                Text(
                  _strategyTextResolved,
                  style: const TextStyle(
                      fontFamily: 'Arial', fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          // Pill showing Both / EV / ICE specific counts
          if (_selectedDrivetrain != 'All') ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _countPill('Both', _allTestCases
                    .where((t) => t.drivetrain == 'Both').length, Colors.white38),
                const SizedBox(height: 4),
                _countPill(
                    _selectedDrivetrain,
                    _allTestCases
                        .where((t) => t.drivetrain == _selectedDrivetrain)
                        .length,
                    leftBar),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
            fontFamily: 'Arial',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color == Colors.white38 ? Colors.white60 : color),
      ),
    );
  }

  // ─── Header widgets ──────────────────────────────────────────────────────────

  Widget _buildMainTitle() {
    return Container(
      width: 1450,
      padding: const EdgeInsets.all(12),
      color: darkNavy,
      child: Text(
        'GOODYEAR DVP TEST CASE GENERATION & MAPPING SUMMARY',
        style: TextStyle(
          fontFamily: 'Arial',
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: gold,
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return Container(
      width: 1450,
      padding: const EdgeInsets.all(8),
      color: navy,
      child: const Text(
        'Summary of logic, mappings, and formatting rules established for Goodyear DVP — NATRAX Test Track',
        style: TextStyle(fontFamily: 'Arial', fontSize: 9, color: Colors.white),
      ),
    );
  }

  Widget _buildScopeRow(int count) {
    final driveLabel = _selectedDrivetrain == 'All' ? 'EV + ICE' : _selectedDrivetrain;
    final featureLabel = _selectedFeature == 'All' ? 'All Features' : _selectedFeature;
    final actLabel = _selectedActivity == 'All' ? 'All Activities' : _selectedActivity;
    final wdLabel = _selectedWaterDepth == 'All' ? 'All' : _selectedWaterDepth;

    return Container(
      width: 1450,
      decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
      child: Row(
        children: [
          _scopeCell('Project Scope', 160, isLabel: true),
          _scopeCell('Goodyear DVP — NATRAX Validation & Calibration', 340),
          _scopeCell('Drivetrain', 90, isLabel: true),
          _scopeCell(driveLabel, 80,
              textColor: _selectedDrivetrain == 'EV'
                  ? evColor
                  : _selectedDrivetrain == 'ICE'
                      ? iceColor
                      : Colors.black87),
          _scopeCell('Feature', 70, isLabel: true),
          _scopeCell(featureLabel, 110),
          _scopeCell('Activity', 70, isLabel: true),
          _scopeCell(actLabel, 120),
          _scopeCell('Water Depth', 90, isLabel: true),
          _scopeCell(wdLabel, 60,
              textColor: wdLabel != 'All' ? const Color(0xFF0288D1) : Colors.black87),
          _scopeCell('Showing', 70, isLabel: true),
          _scopeCell('$count cases', 80,
              textColor: const Color(0xFF2E7D32)),
        ],
      ),
    );
  }

  Widget _scopeCell(String text, double width,
      {bool isLabel = false, Color? textColor}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: isLabel ? cream : Colors.white,
      child: Text(
        text,
        style: GoogleFonts.barlow(
          fontSize: 11,
          fontWeight: isLabel ? FontWeight.bold : FontWeight.normal,
          color: textColor ?? Colors.black87,
        ),
      ),
    );
  }

  // ─── Data Table ───────────────────────────────────────────────────────────────

  Widget _buildDataTable(List<TestCase> cases) {
    return Container(
      width: 1450,
      decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(navy),
        border: TableBorder.all(color: Colors.black12, width: 1),
        columnSpacing: 10,
        columns: [
          _col('Test ID'),
          _col('Test Case Name'),
          _col('Feature'),
          _col('Activity'),
          _col('Drivetrain'),
          _col('Water\nDepth'),
          _col('Tire Type'),
          _col('Tire Condition'),
          _col('Tire Pressure'),
          _col('Road Surface'),
          _col('Load'),
          _col('Test Description'),
          _col('Link'),
        ],
        rows: cases.map((tc) => DataRow(
          // Row tinted by road surface so a surface change is obvious while
          // scrolling the full, unfiltered sheet.
          color: WidgetStateProperty.all(_surfaceRowTint(tc.roadSurfaceType)),
          cells: [
            _cell(tc.testId, bold: true),
            _cell(tc.testCasesName),
            _featureCell(tc.feature),
            _activityCell(tc.activityType),
            _drivetrainCell(tc.drivetrain),
            _waterDepthCell(tc.waterDepth),
            _cell(tc.tireType),
            _cell(tc.tireCondition),
            _cell(tc.tirePressure),
            _surfaceCell(tc.roadSurface, tc.roadSurfaceType),
            _cell(tc.load),
            _cell(tc.testDescription, maxWidth: 240),
            _cell(tc.testCaseLink ?? '—'),
          ],
        )).toList(),
      ),
    );
  }

  DataColumn _col(String text) => DataColumn(
        label: Text(text,
            style: const TextStyle(
              fontFamily: 'Arial',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: gold,
            )),
      );

  DataCell _cell(String text, {bool bold = false, double? maxWidth}) {
    final style = TextStyle(
      fontFamily: 'Calibri',
      fontSize: 11,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: Colors.black87,
    );
    return DataCell(maxWidth != null
        ? SizedBox(width: maxWidth, child: Text(text, style: style, softWrap: true))
        : Text(text, style: style));
  }

  DataCell _featureCell(String feature) {
    final Map<String, Color> colors = {
      'AQD': const Color(0xFF0277BD),
      'DFE': const Color(0xFF2E7D32),
      'Leak Detection': const Color(0xFF6A1B9A),
    };
    final color = colors[feature] ?? Colors.grey;
    return DataCell(Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(feature,
          style: TextStyle(fontFamily: 'Arial', fontSize: 10,
              fontWeight: FontWeight.bold, color: color)),
    ));
  }

  DataCell _activityCell(String activity) {
    final isValidation = activity == 'Validation';
    final color = isValidation ? const Color(0xFF2E7D32) : const Color(0xFF7B1FA2);
    return DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(isValidation ? Icons.verified_outlined : Icons.tune, size: 12, color: color),
      const SizedBox(width: 4),
      Text(activity,
          style: TextStyle(fontFamily: 'Arial', fontSize: 10,
              fontWeight: FontWeight.bold, color: color)),
    ]));
  }

  DataCell _drivetrainCell(String drivetrain) {
    Color color;
    IconData icon;
    String label;
    if (drivetrain == 'EV') {
      color = evColor;
      icon = Icons.electric_bolt;
      label = 'EV';
    } else if (drivetrain == 'ICE') {
      color = iceColor;
      icon = Icons.local_fire_department;
      label = 'ICE';
    } else {
      color = Colors.blueGrey;
      icon = Icons.swap_horiz;
      label = 'Both';
    }
    return DataCell(Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontFamily: 'Arial', fontSize: 10,
                fontWeight: FontWeight.bold, color: color)),
      ]),
    ));
  }

  DataCell _waterDepthCell(String wd) {
    if (wd == 'N/A') {
      return DataCell(Text('—',
          style: const TextStyle(fontFamily: 'Calibri', fontSize: 11, color: Colors.black38)));
    }
    const color = Color(0xFF0288D1);
    return DataCell(Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.water_drop, size: 11, color: color),
        const SizedBox(width: 3),
        Text(wd,
            style: const TextStyle(fontFamily: 'Arial', fontSize: 10,
                fontWeight: FontWeight.bold, color: color)),
      ]),
    ));
  }

  DataCell _surfaceCell(String label, String type) {
    final color = _surfaceColor(type);
    final show = label.trim().isEmpty ? type : label;
    return DataCell(Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(show,
            style: TextStyle(
                fontFamily: 'Arial', fontSize: 10,
                fontWeight: FontWeight.bold, color: color)),
      ]),
    ));
  }

  Widget _buildEmptyState() {
    return Container(
      width: 1450,
      height: 200,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
        const SizedBox(height: 8),
        Text('No test cases match the selected filters.',
            style: TextStyle(fontFamily: 'Arial', fontSize: 13,
                color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text('Try selecting "All" in one or more filter options above.',
            style: TextStyle(fontFamily: 'Arial', fontSize: 11,
                color: Colors.grey.shade400)),
      ]),
    );
  }
}

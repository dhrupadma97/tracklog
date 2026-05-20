import '../../core/app_export.dart';
import './widgets/create_gate_sheet_widget.dart';
import './widgets/gate_card_widget.dart';

// TODO: Replace with Riverpod/Bloc for production
class GateManagementScreen extends StatefulWidget {
  const GateManagementScreen({super.key});

  @override
  State<GateManagementScreen> createState() => _GateManagementScreenState();
}

class _GateManagementScreenState extends State<GateManagementScreen> {
  String _searchQuery = '';
  bool _searchActive = false;

  // Map-first mock data
  static final List<Map<String, dynamic>> _gateMaps = [
    {
      'id': 'gate-001',
      'name': 'High Speed Track — Main Entry',
      'trackType': 'HST',
      'zone': 'Zone A',
      'lat': 22.5671,
      'lng': 75.6182,
      'radiusMeters': 500,
      'hourlyRateINR': 4200.0,
      'isActive': true,
      'lastUsed': '2026-05-20T08:15:00',
      'totalSessionsThisMonth': 3,
    },
    {
      'id': 'gate-002',
      'name': 'Dynamic Platform — Gate 2',
      'trackType': 'DYN',
      'zone': 'Zone B',
      'lat': 22.5648,
      'lng': 75.6155,
      'radiusMeters': 350,
      'hourlyRateINR': 4200.0,
      'isActive': true,
      'lastUsed': '2026-05-19T09:30:00',
      'totalSessionsThisMonth': 2,
    },
    {
      'id': 'gate-003',
      'name': 'Braking Track — North Entry',
      'trackType': 'BRK',
      'zone': 'Zone C',
      'lat': 22.5690,
      'lng': 75.6201,
      'radiusMeters': 250,
      'hourlyRateINR': 3800.0,
      'isActive': true,
      'lastUsed': '2026-05-19T14:00:00',
      'totalSessionsThisMonth': 2,
    },
    {
      'id': 'gate-004',
      'name': 'Handling Circuit — Pit Lane',
      'trackType': 'HC',
      'zone': 'Zone D',
      'lat': 22.5632,
      'lng': 75.6130,
      'radiusMeters': 400,
      'hourlyRateINR': 4500.0,
      'isActive': true,
      'lastUsed': '2026-05-17T07:45:00',
      'totalSessionsThisMonth': 2,
    },
    {
      'id': 'gate-005',
      'name': 'Wet Skid Pad — East Entry',
      'trackType': 'WSP',
      'zone': 'Zone E',
      'lat': 22.5658,
      'lng': 75.6175,
      'radiusMeters': 200,
      'hourlyRateINR': 3600.0,
      'isActive': false,
      'lastUsed': '2026-05-16T10:00:00',
      'totalSessionsThisMonth': 1,
    },
    {
      'id': 'gate-006',
      'name': 'NATRAX Main Gate — Perimeter',
      'trackType': 'GEN',
      'zone': 'Main',
      'lat': 22.5667,
      'lng': 75.6167,
      'radiusMeters': 2500,
      'hourlyRateINR': 0.0,
      'isActive': true,
      'lastUsed': '2026-05-20T08:10:00',
      'totalSessionsThisMonth': 10,
    },
  ];

  List<Map<String, dynamic>> get _filteredGates {
    if (_searchQuery.isEmpty) return _gateMaps;
    final q = _searchQuery.toLowerCase();
    return _gateMaps
        .where(
          (g) =>
              (g['name'] as String).toLowerCase().contains(q) ||
              (g['trackType'] as String).toLowerCase().contains(q) ||
              (g['zone'] as String).toLowerCase().contains(q),
        )
        .toList();
  }

  void _toggleGateActive(String id) {
    // TODO: Persist to local storage / backend
    setState(() {
      final idx = _gateMaps.indexWhere((g) => g['id'] == id);
      if (idx != -1) {
        _gateMaps[idx] = {
          ..._gateMaps[idx],
          'isActive': !(_gateMaps[idx]['isActive'] as bool),
        };
      }
    });
  }

  void _deleteGate(String id) {
    setState(() {
      _gateMaps.removeWhere((g) => g['id'] == id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Gate removed',
          style: TextStyle(fontFamily: 'Manrope'),
        ),
        backgroundColor: const Color(0xFF1A2236),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppTheme.primary,
          onPressed: () {
            // TODO: Implement undo with stored gate data
          },
        ),
      ),
    );
  }

  void _showCreateGateSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CreateGateSheetWidget(
        onGateCreated: (gate) {
          setState(() {
            _gateMaps.insert(0, gate);
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateGateSheet,
        icon: CustomIconWidget(
          iconName: 'add',
          color: const Color(0xFF001A10),
          size: 20,
        ),
        label: const Text(
          'New Gate',
          style: TextStyle(fontFamily: 'Manrope', fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: const Color(0xFF001A10),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(theme),
            const SizedBox(height: 8),
            _buildStatsStrip(theme),
            const SizedBox(height: 16),
            Expanded(
              child: isTablet
                  ? _buildTabletLayout(theme)
                  : _buildPhoneList(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _searchActive
            ? Row(
                key: const ValueKey('search'),
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2236),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(102),
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        autofocus: true,
                        style: const TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 14,
                          color: Color(0xFFE8EAF0),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search gates...',
                          hintStyle: TextStyle(
                            fontFamily: 'Manrope',
                            color: Color(0xFF6B7490),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: Color(0xFF6B7490),
                            size: 18,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => setState(() {
                      _searchActive = false;
                      _searchQuery = '';
                    }),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2236),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF3A4460),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: CustomIconWidget(
                          iconName: 'close',
                          color: const Color(0xFFA8B0C8),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                key: const ValueKey('header'),
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gate Management',
                          style: theme.textTheme.headlineMedium,
                        ),
                        Text(
                          'NATRAX track entry points',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _searchActive = true),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2236),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF3A4460),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: CustomIconWidget(
                          iconName: 'search',
                          color: const Color(0xFFA8B0C8),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatsStrip(ThemeData theme) {
    final activeCount = _gateMaps.where((g) => g['isActive'] as bool).length;
    final totalCount = _gateMaps.length;
    final totalSessions = _gateMaps.fold<int>(
      0,
      (s, g) => s + (g['totalSessionsThisMonth'] as int),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _StatChip(
            label: 'Active Gates',
            value: '$activeCount/$totalCount',
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Sessions This Month',
            value: '$totalSessions',
            color: AppTheme.secondary,
          ),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Tracks Covered',
            value: '${_gateMaps.map((g) => g['trackType']).toSet().length}',
            color: AppTheme.info,
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneList(ThemeData theme) {
    final gates = _filteredGates;
    if (gates.isEmpty) {
      return EmptyStateWidget(
        iconName: 'fence',
        title: 'No gates found',
        subtitle:
            'Create geofenced entry points for each NATRAX track you use. The app auto-starts your session when you enter.',
        ctaLabel: 'Create Gate',
        onCta: _showCreateGateSheet,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      itemCount: gates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final gate = gates[index];
        return GateCardWidget(
          gate: gate,
          index: index,
          onToggleActive: () => _toggleGateActive(gate['id'] as String),
          onDelete: () => _deleteGate(gate['id'] as String),
          onEdit: () => _showEditGateSheet(gate),
          onGeofenceUpdated: (lat, lng, radius) {
            setState(() {
              final idx = _gateMaps.indexWhere((g) => g['id'] == gate['id']);
              if (idx != -1) {
                _gateMaps[idx] = {
                  ..._gateMaps[idx],
                  'lat': lat,
                  'lng': lng,
                  'radiusMeters': radius,
                };
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Geofence boundary updated',
                  style: TextStyle(fontFamily: 'Manrope'),
                ),
                backgroundColor: const Color(0xFF1A2236),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTabletLayout(ThemeData theme) {
    final gates = _filteredGates;
    return Row(
      children: [
        Expanded(flex: 5, child: _buildPhoneList(theme)),
        Container(width: 1, color: const Color(0xFF252E45)),
        Expanded(flex: 4, child: _buildTabletDetailPanel(theme, gates)),
      ],
    );
  }

  Widget _buildTabletDetailPanel(
    ThemeData theme,
    List<Map<String, dynamic>> gates,
  ) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gate Overview', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text(
            '${gates.length} gates configured',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF131929),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF252E45), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NATRAX Center',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFE8EAF0),
                  ),
                ),
                const SizedBox(height: 8),
                _CoordRow(label: 'Latitude', value: '22.5667° N'),
                _CoordRow(label: 'Longitude', value: '75.6167° E'),
                _CoordRow(label: 'District', value: 'Pithampur, Dhar'),
                _CoordRow(label: 'State', value: 'Madhya Pradesh'),
                _CoordRow(label: 'Facility', value: '~3,000 acres'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditGateSheet(Map<String, dynamic> gate) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CreateGateSheetWidget(
        existingGate: gate,
        onGateCreated: (updated) {
          setState(() {
            final idx = _gateMaps.indexWhere((g) => g['id'] == gate['id']);
            if (idx != -1) _gateMaps[idx] = updated;
          });
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(51), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordRow extends StatelessWidget {
  final String label;
  final String value;
  const _CoordRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFFE8EAF0),
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

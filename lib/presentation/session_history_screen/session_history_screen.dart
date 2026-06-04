import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/project_manager.dart';
import './widgets/hero_metric_widget.dart';
import './widgets/monthly_summary_card_widget.dart';
import './widgets/session_chart_widget.dart';
import './widgets/session_list_widget.dart';

// TODO: Replace with Riverpod/Bloc for production
class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Completed', 'This Week', 'High Cost'];

  List<Map<String, dynamic>> _sessionMaps = [];
  bool _isLoading = true;
  String _activeProject = '';

  @override
  void initState() {
    super.initState();
    _activeProject = ProjectManager.instance.activeProject;
    ProjectManager.instance.addListener(_onProjectChanged);
    _loadSessions();
  }

  @override
  void dispose() {
    ProjectManager.instance.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted && _activeProject != ProjectManager.instance.activeProject) {
      setState(() => _activeProject = ProjectManager.instance.activeProject);
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await EngineerAuthService.instance.getMySessionHistory();
      final pm = ProjectManager.instance;
      final filtered = sessions.where((s) => pm.sessionBelongsToProject(s.projectName)).toList();
      final mapped = filtered
          .map(
            (s) => {
              'id': s.id,
              'gate': s.trackName,
              'trackType': s.trackCode,
              'engineer': '',
              'startTime': s.startedAt.toIso8601String(),
              'durationMinutes': s.durationMinutes ?? 0,
              'costINR': s.totalCost ?? 0.0,
              'hourlyRate': s.hourlyRate,
              'status': s.sessionStatus,
              'notes': s.notes ?? '',
            },
          )
          .toList();
      if (mounted) {
        setState(() {
          _sessionMaps = mapped;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    switch (_selectedFilter) {
      case 'Completed':
        return _sessionMaps.where((s) => s['status'] == 'completed').toList();
      case 'This Week':
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return _sessionMaps.where((s) {
          final start = DateTime.parse(s['startTime'] as String);
          return start.isAfter(weekStart);
        }).toList();
      case 'High Cost':
        return _sessionMaps
            .where((s) => (s['costINR'] as double) > 15000)
            .toList();
      default:
        return _sessionMaps;
    }
  }

  double get _totalMonthlyCost =>
      _sessionMaps.fold(0.0, (sum, s) => sum + (s['costINR'] as double));
  double get _totalHours => _sessionMaps.fold(
    0.0,
    (sum, s) => sum + (s['durationMinutes'] as int) / 60.0,
  );
  int get _sessionCount => _sessionMaps.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exporting $_sessionCount sessions...',
                style: const TextStyle(fontFamily: 'Space Grotesk'),
              ),
              backgroundColor: const Color(0xFF0A1025),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
        icon: CustomIconWidget(
          iconName: 'share',
          color: const Color(0xFF001A10),
          size: 18,
        ),
        label: const Text(
          'Export Report',
          style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: const Color(0xFF001A10),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Goodyear background image with dark overlay
            Positioned.fill(
              child: Image.asset(
                'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
                fit: BoxFit.cover,
                semanticLabel: 'Goodyear racing team wallpaper',
              ),
            ),
            Positioned.fill(
              child: Container(color: const Color(0xFF050811).withAlpha(220)),
            ),
            _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                    ),
                  )
                : (isTablet
                      ? _buildTabletLayout(theme)
                      : _buildPhoneLayout(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneLayout(ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(theme)),
        SliverToBoxAdapter(
          child: HeroMetricWidget(
            totalHours: _totalHours,
            totalCost: _totalMonthlyCost,
            sessionCount: _sessionCount,
          ),
        ),
        SliverToBoxAdapter(child: SessionChartWidget(sessions: _sessionMaps)),
        SliverToBoxAdapter(
          child: MonthlySummaryCardWidget(
            totalCost: _totalMonthlyCost,
            totalHours: _totalHours,
            sessionCount: _sessionCount,
            avgDurationMinutes: _sessionMaps.isEmpty
                ? 0
                : (_sessionMaps.fold<int>(
                        0,
                        (s, m) => s + (m['durationMinutes'] as int),
                      ) ~/
                      _sessionMaps.length),
          ),
        ),
        SliverToBoxAdapter(child: _buildFilterRow(theme)),
        SessionListWidget(sessions: _filteredSessions),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildTabletLayout(ThemeData theme) {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildPhoneLayout(theme)),
        Container(width: 1, color: const Color(0xFF3a494b)),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly Breakdown', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                MonthlySummaryCardWidget(
                  totalCost: _totalMonthlyCost,
                  totalHours: _totalHours,
                  sessionCount: _sessionCount,
                  avgDurationMinutes: _sessionMaps.isEmpty
                      ? 0
                      : (_sessionMaps.fold<int>(
                              0,
                              (s, m) => s + (m['durationMinutes'] as int),
                            ) ~/
                            _sessionMaps.length),
                  vertical: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back to projects (web only)
          if (kIsWeb)
            GestureDetector(
              onTap: () => context.go('/project-selection'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_ios_rounded,
                      color: Color(0xFF94A3B8), size: 14),
                  const SizedBox(width: 4),
                  Text('All Projects',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      )),
                ],
              ),
            ),
          if (kIsWeb) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session History', style: theme.textTheme.headlineMedium),
                    Row(children: [
                      Text(
                        'NATRAX Proving Ground · ',
                        style: theme.textTheme.bodySmall,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primary.withAlpha(80)),
                        ),
                        child: Text(
                          _activeProject,
                          style: TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: CustomIconWidget(
                  iconName: 'tune',
                  color: const Color(0xFFA8B0C8),
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Sessions',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFdfe2f0),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_filteredSessions.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) {
                final isSelected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withAlpha(38)
                            : const Color(0xFF0A1025),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary.withAlpha(128)
                              : const Color(0xFF849495),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFFA8B0C8),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

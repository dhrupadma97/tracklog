import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  List<Map<String, dynamic>> _sessionMaps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await EngineerAuthService.instance.getMySessionHistory();
      final mapped = sessions
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

  double get _totalMonthlyCost =>
      _sessionMaps.fold(0.0, (sum, s) => sum + (s['costINR'] as double));
  int get _sessionCount => _sessionMaps.length;
  double get _avgEfficiency => 70.2; // Placeholder for now
  int get _activeAlerts => 2; // Placeholder

  final _currencyFmt = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    return Scaffold(
      backgroundColor: const Color(0xFF050811), // Deep Space
      body: Stack(
        children: [
          // Background ambient glow
          Positioned(
            top: -200,
            left: -200,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF7000FF).withAlpha(15), // Stellar purple
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 32),
        _buildMetricsRow(),
        const SizedBox(height: 32),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 7,
                child: _buildTrackMapPanel(),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 3,
                child: _buildRecentSessionsPanel(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: double.infinity, child: _buildMetricCard('Total Revenue', _currencyFmt.format(_totalMonthlyCost))),
              SizedBox(width: double.infinity, child: _buildMetricCard('Avg. Efficiency', '${_avgEfficiency}%')),
              SizedBox(width: double.infinity, child: _buildMetricCard('Total Sessions', '$_sessionCount')),
              SizedBox(width: double.infinity, child: _buildMetricCard('Active Alerts', '$_activeAlerts', isAlert: true)),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 300,
            child: _buildTrackMapPanel(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverFillRemaining(
          hasScrollBody: true,
          child: _buildRecentSessionsPanel(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NATRAX TrackLog',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Proving Ground Telemetry & Operations',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: const Color(0xFFA8B0C8),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(60)),
          ),
          child: Row(
            children: [
              const CustomIconWidget(iconName: 'download', color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'EXPORT REPORT',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(child: _buildMetricCard('Total Revenue', _currencyFmt.format(_totalMonthlyCost))),
        const SizedBox(width: 24),
        Expanded(child: _buildMetricCard('Avg. Efficiency', '${_avgEfficiency}%')),
        const SizedBox(width: 24),
        Expanded(child: _buildMetricCard('Total Sessions', '$_sessionCount')),
        const SizedBox(width: 24),
        Expanded(child: _buildMetricCard('Active Alerts', '$_activeAlerts', isAlert: true)),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, {bool isAlert = false}) {
    final color = isAlert ? const Color(0xFFFF4D6A) : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFA8B0C8),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFdfe2f0),
            ),
          ),
          const SizedBox(height: 16),
          // Micro sparkline simulation
          Container(
            height: 2,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withAlpha(50),
                  color,
                  color.withAlpha(50),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTrackMapPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/track_layout.png',
              fit: BoxFit.cover,
            ),
          ),
          // Glassmorphism header overlay
          Positioned(
            top: 24,
            left: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF050811).withAlpha(200),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary,
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Live Track Status',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFdfe2f0),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessionsPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(150),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ACTIVE SESSIONS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFA8B0C8),
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'LIVE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _sessionMaps.isEmpty
                ? Center(
                    child: Text(
                      'No recent sessions',
                      style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _sessionMaps.take(6).length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 32,
                      color: Color(0xFF3a494b),
                    ),
                    itemBuilder: (context, index) {
                      final session = _sessionMaps[index];
                      final isOngoing = session['status'] == 'in_progress' || session['status'] == 'started';
                      
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isOngoing 
                                ? AppTheme.primary.withAlpha(20)
                                : const Color(0xFF181B25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isOngoing 
                                  ? AppTheme.primary.withAlpha(60)
                                  : const Color(0xFF3a494b),
                              ),
                            ),
                            child: Center(
                              child: CustomIconWidget(
                                iconName: 'directions_car',
                                color: isOngoing ? AppTheme.primary : const Color(0xFFA8B0C8),
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session['gate'] ?? 'Unknown Track',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFdfe2f0),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('dd MMM, HH:mm').format(DateTime.parse(session['startTime'])),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 12,
                                    color: const Color(0xFF6B7490),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOngoing 
                                ? AppTheme.primary.withAlpha(15) 
                                : const Color(0xFF3a494b).withAlpha(100),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isOngoing 
                                  ? AppTheme.primary.withAlpha(50) 
                                  : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              isOngoing ? 'Active' : 'Ended',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isOngoing ? AppTheme.primary : const Color(0xFFA8B0C8),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

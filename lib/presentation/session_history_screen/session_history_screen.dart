import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  double _totalExpenseBeforeGst = 0.0;
  double _totalExpenseInclGst = 0.0;
  double _usdExpense = 0.0;
  String _topTrackName = 'N/A';
  int _topTrackHours = 0;
  int _activeTestingDays = 0;
  int _sessionCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final uid = EngineerAuthService.instance.currentUser?.id;
      if (uid == null) return;

      final client = Supabase.instance.client;
      final sessionsRaw = await client
          .from('engineer_sessions')
          .select('id, track_name, track_code, started_at, ended_at, duration_minutes, total_cost, session_status')
          .eq('engineer_id', uid)
          .eq('session_status', 'completed');

      final sessionIds = (sessionsRaw as List).map((s) => s['id'] as String).toList();
      List<dynamic> servicesRaw = [];
      if (sessionIds.isNotEmpty) {
        servicesRaw = await client
            .from('session_additional_services')
            .select('session_id, total_cost')
            .inFilter('session_id', sessionIds);
      }

      final Map<String, double> trackHours = {};
      final Set<String> uniqueDays = {};
      double totalExpense = 0.0;

      final mapped = (sessionsRaw).map((s) {
        final id = s['id'] as String;
        final trackName = s['track_name'] as String? ?? 'Unknown';
        final trackCode = s['track_code'] as String? ?? '';
        final startedAtStr = s['started_at'] as String? ?? '';
        final durationMin = (s['duration_minutes'] as int?) ?? 0;
        final costINR = (s['total_cost'] as num?)?.toDouble() ?? 0.0;

        if (startedAtStr.isNotEmpty) {
          final dt = DateTime.tryParse(startedAtStr);
          if (dt != null) {
            uniqueDays.add(DateFormat('yyyy-MM-dd').format(dt));
          }
        }

        double durationHrs = durationMin / 60.0;
        trackHours[trackName] = (trackHours[trackName] ?? 0.0) + durationHrs;
        totalExpense += costINR;

        return {
          'id': id,
          'gate': trackName,
          'trackType': trackCode,
          'engineer': '',
          'startTime': startedAtStr,
          'durationMinutes': durationMin,
          'costINR': costINR,
          'status': s['session_status'],
        };
      }).toList();

      for (final svc in servicesRaw) {
        final cost = (svc['total_cost'] as num?)?.toDouble() ?? 0.0;
        totalExpense += cost;
      }

      String bestTrack = 'N/A';
      double maxHours = 0;
      trackHours.forEach((track, hrs) {
        if (hrs > maxHours) {
          maxHours = hrs;
          bestTrack = track;
        }
      });

      if (mounted) {
        setState(() {
          _sessionMaps = mapped;
          _sessionCount = mapped.length;
          _totalExpenseBeforeGst = totalExpense;
          _totalExpenseInclGst = totalExpense * 1.18;
          _usdExpense = _totalExpenseInclGst / 83.0; // Hardcoded USD conversion
          _topTrackName = bestTrack;
          _topTrackHours = maxHours.round();
          _activeTestingDays = uniqueDays.length;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  final _currencyFmt = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );
  
  final _currencyFmtFull = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  final _usdFmt = NumberFormat.compactCurrency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 1,
  );

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    return Scaffold(
      backgroundColor: const Color(0xFF050811), // Deep Space
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.6),
              colorBlendMode: BlendMode.darken,
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
              SizedBox(width: double.infinity, child: _buildMetricCard('Total Testing Expense', _currencyFmtFull.format(_totalExpenseInclGst), subtitle: 'Excl GST: ${_currencyFmtFull.format(_totalExpenseBeforeGst)}\nUSD: ${_usdFmt.format(_usdExpense)}')),
              SizedBox(width: double.infinity, child: _buildMetricCard('Most Utilized Track', _topTrackName, subtitle: '$_topTrackHours Hours')),
              SizedBox(width: double.infinity, child: _buildMetricCard('Total Sessions', '$_sessionCount')),
              SizedBox(width: double.infinity, child: _buildMetricCard('Active Testing Days', '$_activeTestingDays')),
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
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/goodyear-sightline-logo-single-black-1779279917234.png',
                height: 40,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 16),
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
        Expanded(child: _buildMetricCard('Total Testing Expense', _currencyFmtFull.format(_totalExpenseInclGst), subtitle: 'Excl GST: ${_currencyFmtFull.format(_totalExpenseBeforeGst)}\nUSD: ${_usdFmt.format(_usdExpense)}')),
        const SizedBox(width: 24),
        Expanded(child: _buildMetricCard('Most Utilized Track', _topTrackName, subtitle: '$_topTrackHours Hours')),
        const SizedBox(width: 24),
        Expanded(child: _buildMetricCard('Total Sessions', '$_sessionCount')),
        const SizedBox(width: 24),
        Expanded(child: _buildMetricCard('Active Testing Days', '$_activeTestingDays')),
      ],
    );
  }

   Widget _buildMetricCard(String title, String value, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withOpacity(0.85),
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
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: AppTheme.primary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              height: 2,
              width: 60,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withAlpha(100),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ],
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

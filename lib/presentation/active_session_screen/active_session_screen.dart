import 'dart:async';

import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/rental_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../widgets/track_map_widget.dart';
import './widgets/metric_chip_widget.dart';
import './widgets/pending_returns_card_widget.dart';
import './widgets/recent_gate_strip_widget.dart';
import './widgets/session_control_widget.dart';
import './widgets/session_cost_panel_widget.dart';
import './widgets/session_dial_widget.dart';
import './widgets/session_status_header_widget.dart';

// Tracks that have the 2-hour daily minimum billing rule
const _minBillingTracks = {'T1', 'T2', 'T3', 'T3D', 'T3W'};

// Additional service rates (₹ per unit)
const Map<String, double> _additionalServiceRates = {
  'Refreshment/Lunch': 125.0, // per nos
  'Universal EV Charger': 25.0, // per kWh
  'Unskilled Labour': 1100.0, // per day
  'Electricity Charges': 15.0, // per unit
  'Big Conference Hall': 11000.0, // per day
};

// Sand bag rate
const double _sandBagDailyRate = 150.0; // per bag per day

// Workshop is a continuous monthly cost (₹50,000/month for April billing)
const double _workshopMonthlyRate = 50000.0;

// GST rate applied on final invoice total
const double _gstRate = 0.18;

// TODO: Replace with Riverpod/Bloc for production — session state management
class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({super.key});

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen>
    with TickerProviderStateMixin {
  bool _sessionActive = false;
  bool _gpsLocked = true;
  Duration _elapsed = Duration.zero;
  Timer? _sessionTimer;
  Timer? _anomalyTimer;
  String _currentGate = 'High Speed Track';
  final String _currentTrackType = 'T1';
  String _currentEngineer = '';
  bool _isManagerRole = false;
  final double _hourlyRate = 25000.0;
  DateTime? _sessionStart;
  String? _activeSessionId;

  // Daily cumulative tracking for T1/T2/T3
  Duration _dailyCumulativeDuration = Duration.zero;
  DateTime? _lastDayTracked;

  // Additional services (standard qty-based)
  final Map<String, double> _additionalServicesQty = {
    'Refreshment/Lunch': 0,
    'Unskilled Labour': 0,
    'Electricity Charges': 0,
    'Big Conference Hall': 0,
  };

  // EV Charger — manual kWh input
  final TextEditingController _evKwhController = TextEditingController();
  double _evKwh = 0;

  // Sand bags — manual qty + date-based rental
  final TextEditingController _sandBagQtyController = TextEditingController();
  int _sandBagQty = 0;
  DateTime? _sandBagStartDate;
  DateTime? _sandBagEndDate;

  // Rental instruments
  final List<Map<String, dynamic>> _rentalInstruments = [];

  // Anomaly thresholds
  static const Duration _longSessionThreshold = Duration(hours: 4);
  bool _longSessionAlertSent = false;
  bool _gpsLostAlertSent = false;

  final NotificationService _notificationService = NotificationService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // TODO: Replace with GPS geofencing service (geolocator + geofence_service)
  bool _inGeofence = false;

  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
    _loadEngineerProfile();
    _schedulePendingReturnsNotification();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Set GPS lock after 2s but do NOT auto-start session
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _inGeofence = true;
          _gpsLocked = true;
        });
      }
    });
  }

  Future<void> _loadEngineerProfile() async {
    final profile = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted && profile != null) {
      setState(() {
        _currentEngineer = profile.engineerName;
        _isManagerRole = profile.isManager;
      });
    } else if (mounted) {
      final user = EngineerAuthService.instance.currentUser;
      if (user != null) {
        setState(() {
          _currentEngineer = user.email?.split('@').first ?? 'Engineer';
        });
      }
    }
  }

  /// Fetches pending returns and schedules the daily 7 PM push notification
  /// if there are any unreturned sand bags or rental instruments.
  Future<void> _schedulePendingReturnsNotification() async {
    try {
      final pending = await RentalService.instance.getPendingReturns();
      final sandBags = pending['sand_bags'] as List<SandBagRental>;
      final instruments = pending['instruments'] as List<RentalInstrument>;
      if (sandBags.isEmpty && instruments.isEmpty) return;

      double totalCost = 0;
      for (final s in sandBags) {
        totalCost += s.liveCost;
      }
      for (final i in instruments) {
        totalCost += i.liveCost;
      }

      // Schedule the daily evening reminder
      await _notificationService.scheduleDailyPendingReturnsReminder(
        sandBagCount: sandBags.length,
        instrumentCount: instruments.length,
        totalRunningCost: totalCost,
      );
    } catch (_) {}
  }

  void _startSession({bool autoTriggered = false}) {
    final now = DateTime.now();
    // Reset daily cumulative if it's a new day
    if (_lastDayTracked == null ||
        _lastDayTracked!.day != now.day ||
        _lastDayTracked!.month != now.month ||
        _lastDayTracked!.year != now.year) {
      _dailyCumulativeDuration = Duration.zero;
      _lastDayTracked = now;
    }

    setState(() {
      _sessionActive = true;
      _sessionStart = now;
      _elapsed = Duration.zero;
      _longSessionAlertSent = false;
    });

    // Fire gate-entry notification
    if (autoTriggered) {
      _notificationService.onGateEntry(
        gateName: _currentGate,
        engineerName: _currentEngineer,
      );
    }

    // Persist session start to Supabase
    EngineerAuthService.instance
        .startSession(
          trackCode: _currentTrackType,
          trackName: _currentGate,
          hourlyRate: _hourlyRate,
        )
        .then((sessionId) {
          if (mounted) setState(() => _activeSessionId = sessionId);
        })
        .catchError((_) {});

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = DateTime.now().difference(_sessionStart!);
        });
        _checkAnomalies();
      }
    });
  }

  void _showStartSessionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.primary.withAlpha(100),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withAlpha(40),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(25),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primary.withAlpha(100),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_circle_outline_rounded,
                    color: AppTheme.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Start Testing Session',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFdfe2f0),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'You are about to begin a track testing session.\nMake sure all equipment is ready before proceeding.',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: const Color(0xFF6B7490),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1025),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.primary,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _currentGate,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: const Color(0xFF849495).withAlpha(150),
                            ),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7490),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _startSession();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: const Color(0xFF001A10),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Start Now',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _stopSession({bool autoTriggered = false}) {
    _sessionTimer?.cancel();
    _anomalyTimer?.cancel();

    // Accumulate into daily total
    _dailyCumulativeDuration += _elapsed;
    _lastDayTracked = DateTime.now();

    // Fire gate-exit notification
    if (autoTriggered) {
      _notificationService.onGateExit(
        gateName: _currentGate,
        sessionDuration: _elapsed,
        cost: _estimatedCost,
      );
    }

    // Persist session end to Supabase
    if (_activeSessionId != null) {
      final durationMinutes = _elapsed.inMinutes;
      EngineerAuthService.instance
          .endSession(
            sessionId: _activeSessionId!,
            durationMinutes: durationMinutes,
            totalCost: _estimatedCost,
            status: durationMinutes > 240 ? 'warning' : 'completed',
          )
          .catchError((_) {});
      _activeSessionId = null;
    }

    setState(() {
      _sessionActive = false;
    });
    _showSessionSummarySheet();
  }

  /// Checks for anomalies every tick and fires alerts as needed.
  void _checkAnomalies() {
    // Long session alert (fires once when threshold exceeded)
    if (!_longSessionAlertSent && _elapsed >= _longSessionThreshold) {
      _longSessionAlertSent = true;
      _notificationService.alertLongSession(elapsed: _elapsed);
    }

    // GPS lost simulation — in production, hook into geolocator stream
    if (!_gpsLocked && !_gpsLostAlertSent) {
      _gpsLostAlertSent = true;
      _notificationService.alertGpsLost();
    } else if (_gpsLocked && _gpsLostAlertSent) {
      _gpsLostAlertSent = false;
      _notificationService.alertGpsRestored();
    }
  }

  /// Simulates an unexpected gate exit (engineer leaves geofence mid-session).
  void _handleUnexpectedGeofenceExit() {
    if (_sessionActive) {
      _notificationService.alertUnexpectedExit(gateName: _currentGate);
      setState(() => _inGeofence = false);
      _stopSession(autoTriggered: true);
    }
  }

  /// T1/T2/T3 billing: minimum 2 hours per day, cumulative across sessions.
  /// After 2 hours of daily utilisation, billed per hour.
  double get _estimatedCost {
    final isMinBillingTrack = _minBillingTracks.contains(_currentTrackType);
    if (isMinBillingTrack) {
      // Total daily duration including current session
      final totalDailyDuration = _dailyCumulativeDuration + _elapsed;
      final totalDailyHours = totalDailyDuration.inSeconds / 3600.0;
      const minHours = 2.0;

      if (totalDailyHours <= minHours) {
        // Still within minimum — charge minimum 2 hours
        return minHours * _hourlyRate;
      } else {
        // Beyond minimum — charge actual hours
        return totalDailyHours * _hourlyRate;
      }
    } else {
      final hours = _elapsed.inSeconds / 3600.0;
      return hours * _hourlyRate;
    }
  }

  double get _additionalServicesCost {
    double total = 0;
    _additionalServicesQty.forEach((service, qty) {
      total += qty * (_additionalServiceRates[service] ?? 0);
    });
    // EV charger
    total += _evKwh * (_additionalServiceRates['Universal EV Charger'] ?? 0);
    // Sand bags rental
    total += _sandBagRentalCost;
    // Rental instruments
    total += _rentalInstrumentsCost;
    return total;
  }

  double get _totalCostWithServices => _estimatedCost + _additionalServicesCost;

  /// Track + Services subtotal before workshop and GST
  double get _subtotalBeforeWorkshopGst => _totalCostWithServices;

  /// Final invoice = (track + services + workshop) * (1 + GST)
  double get _finalInvoiceWithGst {
    final subtotal = _subtotalBeforeWorkshopGst + _workshopMonthlyRate;
    return subtotal * (1 + _gstRate);
  }

  /// Builds a list of known NATRAX gates for the live map display.
  List<Map<String, dynamic>> _buildGateList() {
    return [
      {
        'name': 'High Speed Track',
        'lat': 22.5671,
        'lng': 75.6182,
        'radiusMeters': 500,
      },
      {
        'name': 'Dynamic Platform',
        'lat': 22.5648,
        'lng': 75.6155,
        'radiusMeters': 350,
      },
      {
        'name': 'Braking Track',
        'lat': 22.5690,
        'lng': 75.6201,
        'radiusMeters': 250,
      },
      {
        'name': 'Handling Circuit',
        'lat': 22.5632,
        'lng': 75.6130,
        'radiusMeters': 400,
      },
      {
        'name': 'Wet Skid Pad',
        'lat': 22.5658,
        'lng': 75.6175,
        'radiusMeters': 200,
      },
    ];
  }

  void _showSessionSummarySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SessionSummarySheet(
        duration: _elapsed,
        cost: _estimatedCost,
        gate: _currentGate,
        engineer: _currentEngineer,
        hourlyRate: _hourlyRate,
        startTime: _sessionStart ?? DateTime.now(),
        trackCode: _currentTrackType,
        dailyCumulativeDuration: _dailyCumulativeDuration,
        additionalServicesCost: _additionalServicesCost,
        additionalServicesQty: Map.from(_additionalServicesQty),
        workshopMonthlyCost: _workshopMonthlyRate,
        gstRate: _gstRate,
      ),
    );
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _anomalyTimer?.cancel();
    _pulseController.dispose();
    _evKwhController.dispose();
    _sandBagQtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Stack(
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
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF050811).withAlpha(230),
                    const Color(0xFF050811).withAlpha(210),
                    const Color(0xFF050811).withAlpha(240),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: isTablet
                ? _buildTabletLayout(theme)
                : _buildPhoneLayout(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneLayout(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        children: [
          // Manager read-only banner
          if (_isManagerRole)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF9C88FF).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF9C88FF).withAlpha(100),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: Color(0xFF9C88FF),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Manager View — Read Only. Session controls are disabled.',
                      style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF9C88FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SessionStatusHeaderWidget(
            sessionActive: _sessionActive,
            gpsLocked: _gpsLocked,
            inGeofence: _inGeofence,
            currentDate: DateTime.now(),
            engineerName: _currentEngineer,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                MetricChipWidget(
                  iconName: 'gps_fixed',
                  label: 'GPS Accuracy',
                  value: _gpsLocked ? '4.2 m' : 'Searching...',
                  isActive: _gpsLocked,
                ),
                const SizedBox(width: 10),
                MetricChipWidget(
                  iconName: 'currency_rupee',
                  label: 'Hourly Rate',
                  value: '₹${_hourlyRate.toStringAsFixed(0)}/hr',
                  isActive: true,
                ),
                const SizedBox(width: 10),
                MetricChipWidget(
                  iconName: 'map',
                  label: 'Track Type',
                  value: _currentTrackType,
                  isActive: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── Live Track Map ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F3FF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Live Track Map',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFdfe2f0),
                      ),
                    ),
                    const Spacer(),
                    if (_sessionActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F3FF).withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF00F3FF).withAlpha(80),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00F3FF),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Tracking',
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00F3FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TrackMapWidget(
                  gates: _buildGateList(),
                  showEngineerLocation: true,
                  height: 240,
                  mapType: MapType.hybrid,
                ),
              ],
            ),
          ),
          // ── End Live Track Map ──────────────────────────────────────────
          const SizedBox(height: 20),
          SessionDialWidget(
            sessionActive: _sessionActive,
            elapsed: _elapsed,
            pulseAnimation: _pulseAnimation,
            gateLabel: _currentGate,
          ),
          const SizedBox(height: 20),
          // T1/T2/T3 billing info banner
          if (_minBillingTracks.contains(_currentTrackType))
            _buildMinBillingBanner(theme),
          const SizedBox(height: 12),
          SessionCostPanelWidget(
            estimatedCost: _estimatedCost,
            elapsed: _elapsed,
            sessionActive: _sessionActive,
            hourlyRate: _hourlyRate,
            trackCode: _currentTrackType,
            dailyCumulativeDuration: _dailyCumulativeDuration,
          ),
          const SizedBox(height: 20),
          // ── Pending Returns ─────────────────────────────────────────────
          const PendingReturnsCardWidget(),
          const SizedBox(height: 16),
          // ── Additional Services ─────────────────────────────────────────
          _buildAdditionalServicesPanel(theme),
          const SizedBox(height: 20),
          if (!_isManagerRole)
            SessionControlWidget(
              sessionActive: _sessionActive,
              onStart: () => _showStartSessionDialog(),
              onStop: () => _stopSession(),
            ),
          if (_isManagerRole)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1025).withAlpha(180),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF849495).withAlpha(100),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: Color(0xFF4A5470),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Session controls restricted to engineers',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF4A5470),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // Anomaly test strip — visible only during active session
          if (_sessionActive) _buildAnomalyTestStrip(theme),
          const SizedBox(height: 24),
          RecentGateStripWidget(
            currentGate: _currentGate,
            onGateTap: (gate) {
              setState(() => _currentGate = gate);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMinBillingBanner(ThemeData theme) {
    final totalDailyHours =
        (_dailyCumulativeDuration + (_sessionActive ? _elapsed : Duration.zero))
            .inSeconds /
        3600.0;
    final isAtMinimum = totalDailyHours < 2.0;
    final remainingToMin = isAtMinimum ? (2.0 - totalDailyHours) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF00F3FF).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF00F3FF).withAlpha(80),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF00F3FF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'T1/T2/T3 — 2 Hour Daily Minimum',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF00F3FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAtMinimum
                        ? 'Daily usage: ${totalDailyHours.toStringAsFixed(2)}h · ${remainingToMin.toStringAsFixed(2)}h remaining to minimum'
                        : 'Daily usage: ${totalDailyHours.toStringAsFixed(2)}h · Billed per hour beyond 2h minimum',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFA8B0C8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalServicesPanel(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF3a494b), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withAlpha(38),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.miscellaneous_services_rounded,
                    color: Color(0xFF6C63FF),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Additional Services',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFFA8B0C8),
                  ),
                ),
                const Spacer(),
                if (_additionalServicesCost > 0)
                  Text(
                    '₹${_additionalServicesCost.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF6C63FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Standard qty-based services
            ..._additionalServicesQty.entries.map((entry) {
              final service = entry.key;
              final qty = entry.value;
              final rate = _additionalServiceRates[service] ?? 0;
              final unit = service == 'Refreshment/Lunch'
                  ? 'nos'
                  : service == 'Unskilled Labour'
                  ? 'day'
                  : service == 'Electricity Charges'
                  ? 'unit'
                  : 'day';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFdfe2f0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '₹${rate.toStringAsFixed(0)} / $unit',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        _ServiceQtyButton(
                          icon: Icons.remove_rounded,
                          onTap: () {
                            if (qty > 0) {
                              setState(() {
                                _additionalServicesQty[service] = qty - 1;
                              });
                            }
                          },
                        ),
                        Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Text(
                            qty.toStringAsFixed(0),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: qty > 0
                                  ? const Color(0xFF6C63FF)
                                  : const Color(0xFFA8B0C8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _ServiceQtyButton(
                          icon: Icons.add_rounded,
                          onTap: () {
                            setState(() {
                              _additionalServicesQty[service] = qty + 1;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 70,
                          child: Text(
                            qty > 0
                                ? '₹${(qty * rate).toStringAsFixed(0)}'
                                : '—',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: qty > 0
                                  ? const Color(0xFFdfe2f0)
                                  : const Color(0xFF849495),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),

            // ── EV Charger — manual kWh input ──────────────────────────
            _buildSectionDivider(theme, 'EV Charging'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Universal EV Charger',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFdfe2f0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('₹25 / kWh', style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _evKwhController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6C63FF),
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        color: const Color(0xFF849495),
                      ),
                      suffixText: 'kWh',
                      suffixStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: const Color(0xFF6B7490),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF3a494b),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _evKwh = double.tryParse(v) ?? 0;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Text(
                    _evKwh > 0 ? '₹${(_evKwh * 25).toStringAsFixed(0)}' : '—',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: _evKwh > 0
                          ? const Color(0xFFdfe2f0)
                          : const Color(0xFF849495),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            // ── Sand Bags — qty + date-based rental ────────────────────
            const SizedBox(height: 14),
            _buildSectionDivider(theme, 'Sand Bags Rental'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sand bags 20/50kg',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFdfe2f0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '₹150 / bag / day',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _sandBagQtyController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6C63FF),
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        color: const Color(0xFF849495),
                      ),
                      suffixText: 'bags',
                      suffixStyle: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: const Color(0xFF6B7490),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: const Color(0xFF3a494b),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _sandBagQty = int.tryParse(v) ?? 0;
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_sandBagQty > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildDatePickerField(
                      theme: theme,
                      label: 'Taken Date',
                      date: _sandBagStartDate,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _sandBagStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF6C63FF),
                                surface: Color(0xFF0A1025),
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setState(() => _sandBagStartDate = picked);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDatePickerField(
                      theme: theme,
                      label: 'Return Date',
                      date: _sandBagEndDate,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _sandBagEndDate ?? DateTime.now(),
                          firstDate: _sandBagStartDate ?? DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFF6C63FF),
                                surface: Color(0xFF0A1025),
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setState(() => _sandBagEndDate = picked);
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (_sandBagStartDate != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withAlpha(60),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      () {
                        final endDate = _sandBagEndDate ?? DateTime.now();
                        final days = endDate
                            .difference(_sandBagStartDate!)
                            .inDays;
                        return Text(
                          '$_sandBagQty bags × ${days > 0 ? days : 0} days × ₹150',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 11,
                            color: const Color(0xFFA8B0C8),
                          ),
                        );
                      }(),
                      Text(
                        _sandBagRentalCost > 0
                            ? '₹${_sandBagRentalCost.toStringAsFixed(0)}'
                            : '—',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF6C63FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            // ── Rental Instruments ─────────────────────────────────────
            const SizedBox(height: 14),
            _buildSectionDivider(theme, 'Rental Instruments'),
            const SizedBox(height: 10),
            ..._rentalInstruments.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return _RentalInstrumentRow(
                index: idx,
                item: item,
                theme: theme,
                onChanged: (updated) {
                  setState(() => _rentalInstruments[idx] = updated);
                },
                onRemove: () {
                  setState(() => _rentalInstruments.removeAt(idx));
                },
              );
            }),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _rentalInstruments.add({
                    'name': '',
                    'perDay': 0.0,
                    'days': 0,
                  });
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3a494b),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF849495),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF6C63FF),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Add Rental Instrument',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6C63FF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_rentalInstrumentsCost > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Rental Instruments Total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFA8B0C8),
                    ),
                  ),
                  Text(
                    '₹${_rentalInstrumentsCost.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF6C63FF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],

            if (_additionalServicesCost > 0) ...[
              const SizedBox(height: 10),
              Container(height: 1, color: const Color(0xFF3a494b)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total (Track + Services)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFdfe2f0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '₹${_totalCostWithServices.toStringAsFixed(0)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionDivider(ThemeData theme, String label) {
    return Row(
      children: [
        Container(height: 1, width: 20, color: const Color(0xFF3a494b)),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF6B7490),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: const Color(0xFF3a494b))),
      ],
    );
  }

  Widget _buildDatePickerField({
    required ThemeData theme,
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF3a494b),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: Color(0xFF6C63FF),
              size: 14,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: const Color(0xFF6B7490),
                    ),
                  ),
                  Text(
                    date != null
                        ? DateFormat('dd MMM yyyy').format(date)
                        : 'Select',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: date != null
                          ? const Color(0xFFdfe2f0)
                          : const Color(0xFF849495),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _sandBagRentalCost {
    if (_sandBagQty <= 0) return 0;
    if (_sandBagStartDate == null) return 0;
    final endDate = _sandBagEndDate ?? DateTime.now();
    final days = endDate.difference(_sandBagStartDate!).inDays;
    if (days <= 0) return 0;
    return _sandBagQty * days * _sandBagDailyRate;
  }

  double get _rentalInstrumentsCost {
    double total = 0;
    for (final item in _rentalInstruments) {
      final perDay = (item['perDay'] as double?) ?? 0;
      final days = (item['days'] as int?) ?? 0;
      total += perDay * days;
    }
    return total;
  }

  /// Debug/demo strip to manually trigger anomaly notifications.
  Widget _buildAnomalyTestStrip(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2235),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF849495), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFFFF6B35),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Notification Triggers',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFFF6B35),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AnomalyButton(
                    label: 'GPS Lost',
                    icon: Icons.gps_off_rounded,
                    color: const Color(0xFFFF6B35),
                    onTap: () {
                      setState(() => _gpsLocked = false);
                      _notificationService.alertGpsLost();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AnomalyButton(
                    label: 'GPS Back',
                    icon: Icons.gps_fixed_rounded,
                    color: const Color(0xFF00E676),
                    onTap: () {
                      setState(() => _gpsLocked = true);
                      _notificationService.alertGpsRestored();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AnomalyButton(
                    label: 'Gate Exit',
                    icon: Icons.logout_rounded,
                    color: const Color(0xFFFFB300),
                    onTap: _handleUnexpectedGeofenceExit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabletLayout(ThemeData theme) {
    return Row(
      children: [
        Expanded(flex: 6, child: _buildPhoneLayout(theme)),
        Container(width: 1, color: const Color(0xFF3a494b)),
        Expanded(flex: 4, child: _buildTabletSidebar(theme)),
      ],
    );
  }

  Widget _buildTabletSidebar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session Details', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _DetailRow(label: 'Engineer', value: _currentEngineer),
          _DetailRow(label: 'Gate', value: _currentGate),
          _DetailRow(label: 'Track Type', value: _currentTrackType),
          _DetailRow(
            label: 'Start Time',
            value: _sessionStart != null
                ? '${_sessionStart!.hour.toString().padLeft(2, '0')}:${_sessionStart!.minute.toString().padLeft(2, '0')}'
                : '--:--',
          ),
          _DetailRow(
            label: 'Hourly Rate',
            value: '₹${_hourlyRate.toStringAsFixed(0)}/hr',
          ),
          if (_minBillingTracks.contains(_currentTrackType))
            _DetailRow(
              label: 'Daily Usage',
              value:
                  '${((_dailyCumulativeDuration + _elapsed).inSeconds / 3600.0).toStringAsFixed(2)}h',
            ),
        ],
      ),
    );
  }
}

class _ServiceQtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ServiceQtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFF3a494b),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFFA8B0C8), size: 16),
      ),
    );
  }
}

class _AnomalyButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AnomalyButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(76), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: const Color(0xFFdfe2f0),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionSummarySheet extends StatelessWidget {
  final Duration duration;
  final double cost;
  final String gate;
  final String engineer;
  final double hourlyRate;
  final DateTime startTime;
  final String trackCode;
  final Duration dailyCumulativeDuration;
  final double additionalServicesCost;
  final Map<String, double> additionalServicesQty;
  final double workshopMonthlyCost;
  final double gstRate;

  const _SessionSummarySheet({
    required this.duration,
    required this.cost,
    required this.gate,
    required this.engineer,
    required this.hourlyRate,
    required this.startTime,
    required this.trackCode,
    required this.dailyCumulativeDuration,
    required this.additionalServicesCost,
    required this.additionalServicesQty,
    this.workshopMonthlyCost = 50000.0,
    this.gstRate = 0.18,
  });

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMinBillingTrack = _minBillingTracks.contains(trackCode);
    final totalDailyDuration = dailyCumulativeDuration + duration;
    final totalDailyHours = totalDailyDuration.inSeconds / 3600.0;
    final billedHours = isMinBillingTrack
        ? (totalDailyHours < 2.0 ? 2.0 : totalDailyHours)
        : (duration.inSeconds / 3600.0);
    final trackCost = billedHours * hourlyRate;
    final trackAndServicesCost = trackCost + additionalServicesCost;
    final subtotalExclGst = trackAndServicesCost + workshopMonthlyCost;
    final gstAmount = subtotalExclGst * gstRate;
    final totalInvoiceAmount = subtotalExclGst + gstAmount;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF849495), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(38),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'SESSION COMPLETE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7490)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Session Summary', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('$gate · $engineer', style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Duration',
                  value: _formatDuration(duration),
                  iconName: 'timer',
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: isMinBillingTrack ? 'Daily Total' : 'Billable Hrs',
                  value: '${billedHours.toStringAsFixed(2)}h',
                  iconName: 'access_time',
                  color: AppTheme.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Track Cost',
                  value: '₹${trackCost.toStringAsFixed(0)}',
                  iconName: 'currency_rupee',
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryCard(
                  label: 'Services',
                  value: additionalServicesCost > 0
                      ? '₹${additionalServicesCost.toStringAsFixed(0)}'
                      : '—',
                  iconName: 'miscellaneous_services',
                  color: const Color(0xFF6C63FF),
                ),
              ),
            ],
          ),
          if (isMinBillingTrack) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00F3FF).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00F3FF).withAlpha(60),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF00F3FF),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      totalDailyHours < 2.0
                          ? 'Minimum 2h daily charge applied for $trackCode track'
                          : 'Charged at actual daily usage (${totalDailyHours.toStringAsFixed(2)}h > 2h minimum)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF00F3FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // ── Invoice Breakdown ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF3a494b), width: 1),
            ),
            child: Column(
              children: [
                _InvoiceRow(
                  label: 'Track + Services',
                  value: '₹${trackAndServicesCost.toStringAsFixed(0)}',
                  color: const Color(0xFFA8B0C8),
                ),
                const SizedBox(height: 6),
                _InvoiceRow(
                  label: 'Workshop (Monthly)',
                  value: '₹${workshopMonthlyCost.toStringAsFixed(0)}',
                  color: const Color(0xFFA8B0C8),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Color(0xFF3a494b), height: 1),
                ),
                _InvoiceRow(
                  label: 'Subtotal (Excl. GST)',
                  value: '₹${subtotalExclGst.toStringAsFixed(0)}',
                  color: const Color(0xFFdfe2f0),
                  bold: true,
                ),
                const SizedBox(height: 6),
                _InvoiceRow(
                  label: 'GST @ ${(gstRate * 100).toStringAsFixed(0)}%',
                  value: '₹${gstAmount.toStringAsFixed(2)}',
                  color: const Color(0xFFA8B0C8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.secondary.withAlpha(60),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Invoice (incl. GST)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFdfe2f0),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '₹${totalInvoiceAmount.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text(
                'Done',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: const Color(0xFF001A10),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _InvoiceRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String iconName;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.iconName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(51), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomIconWidget(iconName: iconName, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _RentalInstrumentRow extends StatefulWidget {
  final int index;
  final Map<String, dynamic> item;
  final ThemeData theme;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;

  const _RentalInstrumentRow({
    required this.index,
    required this.item,
    required this.theme,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_RentalInstrumentRow> createState() => _RentalInstrumentRowState();
}

class _RentalInstrumentRowState extends State<_RentalInstrumentRow> {
  late TextEditingController _nameCtrl;
  late TextEditingController _perDayCtrl;
  late TextEditingController _daysCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.item['name'] as String? ?? '',
    );
    _perDayCtrl = TextEditingController(
      text:
          (widget.item['perDay'] as double?) != null &&
              (widget.item['perDay'] as double) > 0
          ? (widget.item['perDay'] as double).toStringAsFixed(0)
          : '',
    );
    _daysCtrl = TextEditingController(
      text:
          (widget.item['days'] as int?) != null &&
              (widget.item['days'] as int) > 0
          ? (widget.item['days'] as int).toString()
          : '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _perDayCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      'name': _nameCtrl.text,
      'perDay': double.tryParse(_perDayCtrl.text) ?? 0.0,
      'days': int.tryParse(_daysCtrl.text) ?? 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final perDay = double.tryParse(_perDayCtrl.text) ?? 0.0;
    final days = int.tryParse(_daysCtrl.text) ?? 0;
    final cost = perDay * days;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3a494b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF849495).withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: const Color(0xFFdfe2f0),
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Instrument name',
                    hintStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: const Color(0xFF849495),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0A1025),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => _notify(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4757).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFFF4757),
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _perDayCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: const Color(0xFFdfe2f0),
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: const Color(0xFF849495),
                    ),
                    prefixText: '₹ ',
                    prefixStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: const Color(0xFF6B7490),
                    ),
                    suffixText: '/day',
                    suffixStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: const Color(0xFF6B7490),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0A1025),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _notify();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _daysCtrl,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: const Color(0xFFdfe2f0),
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: const Color(0xFF849495),
                    ),
                    suffixText: 'days',
                    suffixStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: const Color(0xFF6B7490),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0A1025),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _notify();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Text(
                  cost > 0 ? '₹${cost.toStringAsFixed(0)}' : '—',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cost > 0
                        ? const Color(0xFF6C63FF)
                        : const Color(0xFF849495),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

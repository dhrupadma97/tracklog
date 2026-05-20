import 'dart:async';

import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/track_map_widget.dart';
import './widgets/metric_chip_widget.dart';
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
  'Universal EV Charger': 25.0, // per unit
  'Sand bags 20/50kg': 150.0, // per nos/day
  'Unskilled Labour': 1100.0, // per day
  'Electricity Charges': 15.0, // per unit
  'Big Conference Hall': 11000.0, // per day
};

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

  // Additional services
  final Map<String, double> _additionalServicesQty = {
    'Refreshment/Lunch': 0,
    'Universal EV Charger': 0,
    'Sand bags 20/50kg': 0,
    'Unskilled Labour': 0,
    'Electricity Charges': 0,
    'Big Conference Hall': 0,
  };

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

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Simulate GPS lock and auto-session start after 2s (gate entry)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _inGeofence = true;
          _gpsLocked = true;
        });
        // Don't auto-start for manager/read-only role
        if (!_isManagerRole) {
          _startSession(autoTriggered: true);
        }
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
                    const Color(0xFF0A0E1A).withAlpha(230),
                    const Color(0xFF0A0E1A).withAlpha(210),
                    const Color(0xFF0A0E1A).withAlpha(240),
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
                      style: GoogleFonts.manrope(
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
                        color: const Color(0xFF00C896),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Live Track Map',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EAF0),
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
                          color: const Color(0xFF00C896).withAlpha(30),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF00C896).withAlpha(80),
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
                                color: Color(0xFF00C896),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Tracking',
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF00C896),
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
          // ── Additional Services ─────────────────────────────────────────
          _buildAdditionalServicesPanel(theme),
          const SizedBox(height: 20),
          if (!_isManagerRole)
            SessionControlWidget(
              sessionActive: _sessionActive,
              onStart: () => _startSession(),
              onStop: () => _stopSession(),
            ),
          if (_isManagerRole)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2236).withAlpha(180),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF3A4460).withAlpha(100),
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
                    style: GoogleFonts.manrope(
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
          color: const Color(0xFFE8500A).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE8500A).withAlpha(80),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFE8500A),
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
                      color: const Color(0xFFE8500A),
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
          color: const Color(0xFF1A2236),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF252E45), width: 1),
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
            ..._additionalServicesQty.entries.map((entry) {
              final service = entry.key;
              final qty = entry.value;
              final rate = _additionalServiceRates[service] ?? 0;
              final unit = service == 'Refreshment/Lunch'
                  ? 'nos'
                  : service == 'Universal EV Charger'
                  ? 'unit'
                  : service == 'Sand bags 20/50kg'
                  ? 'nos/day'
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
                              color: const Color(0xFFE8EAF0),
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
                                  ? const Color(0xFFE8EAF0)
                                  : const Color(0xFF3A4460),
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
            if (_additionalServicesCost > 0) ...[
              Container(height: 1, color: const Color(0xFF252E45)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total (Track + Services)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFE8EAF0),
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

  /// Debug/demo strip to manually trigger anomaly notifications.
  Widget _buildAnomalyTestStrip(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2235),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A4460), width: 1),
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
        Container(width: 1, color: const Color(0xFF252E45)),
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
          color: const Color(0xFF252E45),
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
              color: const Color(0xFFE8EAF0),
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
        color: const Color(0xFF131929),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF3A4460), width: 1),
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
                color: const Color(0xFFE8500A).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFE8500A).withAlpha(60),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFE8500A),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      totalDailyHours < 2.0
                          ? 'Minimum 2h daily charge applied for $trackCode track'
                          : 'Charged at actual daily usage (${totalDailyHours.toStringAsFixed(2)}h > 2h minimum)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFE8500A),
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
              color: const Color(0xFF1A2236),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF252E45), width: 1),
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
                  child: Divider(color: Color(0xFF252E45), height: 1),
                ),
                _InvoiceRow(
                  label: 'Subtotal (Excl. GST)',
                  value: '₹${subtotalExclGst.toStringAsFixed(0)}',
                  color: const Color(0xFFE8EAF0),
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
                    color: const Color(0xFFE8EAF0),
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
                  fontFamily: 'Manrope',
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

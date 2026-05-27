import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/location_service.dart';

/// NATRAX proving ground centre coordinates
const LatLng kNatraxCenter = LatLng(22.5667, 75.6167);

// Platform channel to read BuildConfig values from native Android
const _diagnosticsChannel = MethodChannel('com.example.tracklog/diagnostics');

/// A live Google Map showing:
/// - NATRAX track area
/// - All gates with their geofence radius circles
/// - Real-time engineer GPS position (browser Geolocation on web, GPS on mobile)
/// - Optional: a single highlighted gate (for geofence setup mode)
class TrackMapWidget extends StatefulWidget {
  /// List of gate maps: each must have 'name', 'lat', 'lng', 'radiusMeters'
  final List<Map<String, dynamic>> gates;

  /// If set, this gate is highlighted (geofence setup mode)
  final Map<String, dynamic>? highlightedGate;

  /// If true, shows the engineer's real-time GPS dot
  final bool showEngineerLocation;

  /// Called when map is ready (optional)
  final void Function(GoogleMapController)? onMapCreated;

  /// Height of the map widget
  final double height;

  /// Map type (satellite shows the track clearly)
  final MapType mapType;

  const TrackMapWidget({
    super.key,
    this.gates = const [],
    this.highlightedGate,
    this.showEngineerLocation = true,
    this.onMapCreated,
    this.height = 280,
    this.mapType = MapType.hybrid,
  });

  @override
  State<TrackMapWidget> createState() => _TrackMapWidgetState();
}

class _TrackMapWidgetState extends State<TrackMapWidget> {
  GoogleMapController? _mapController;
  LatLng? _engineerPosition;
  StreamSubscription<({double lat, double lng})>? _positionStream;
  bool _locationPermissionGranted = false;
  bool _mapReady = false;

  // Diagnostic state
  String _keyDiagnostic = 'Checking...';
  bool _keyValid = false;
  bool _showDiagnostic = true; // Show for first 8 seconds then auto-hide

  final _locationService = LocationService();

  // Dark map style JSON for non-satellite mode
  static const String _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0a0e1a"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1a2236"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]}
]
''';

  @override
  void initState() {
    super.initState();
    _initLocation();
    if (!kIsWeb) {
      _checkMapsKeyDiagnostic();
    } else {
      setState(() {
        _keyDiagnostic = 'Web platform';
        _keyValid = true;
        _showDiagnostic = false;
      });
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Query native Android for the actual BuildConfig key value and log it
  Future<void> _checkMapsKeyDiagnostic() async {
    try {
      final result = await _diagnosticsChannel.invokeMapMethod<String, dynamic>(
        'getMapsKeyStatus',
      );
      if (result != null) {
        final keyLength = result['keyLength'] as int? ?? 0;
        final isEmpty = result['isEmpty'] as bool? ?? true;
        final prefix = result['prefix'] as String? ?? '';
        final isValid = result['isValid'] as bool? ?? false;

        debugPrint('=== MAPS KEY DIAGNOSTIC ===');
        debugPrint('Key length: $keyLength');
        debugPrint('Is empty: $isEmpty');
        debugPrint('Prefix: $prefix...');
        debugPrint('Is valid (>20 chars): $isValid');
        debugPrint('===========================');

        if (mounted) {
          setState(() {
            _keyValid = isValid;
            if (isEmpty) {
              _keyDiagnostic = 'KEY EMPTY — not injected at build time';
            } else if (!isValid) {
              _keyDiagnostic =
                  'KEY TOO SHORT ($keyLength chars) — may be truncated';
            } else {
              _keyDiagnostic = 'Key OK ($keyLength chars, prefix: $prefix...)';
            }
          });
        }

        // Auto-hide diagnostic after 8 seconds if key is valid
        if (isValid) {
          Future.delayed(const Duration(seconds: 8), () {
            if (mounted) setState(() => _showDiagnostic = false);
          });
        }
      }
    } catch (e) {
      debugPrint('Maps diagnostic channel error: $e');
      if (mounted) {
        setState(() {
          _keyDiagnostic = 'Diagnostic unavailable: $e';
          _keyValid = false;
        });
      }
    }
  }

  Future<void> _initLocation() async {
    if (!widget.showEngineerLocation) return;

    try {
      final granted = await _locationService.requestPermission();
      if (!granted) return;

      if (mounted) setState(() => _locationPermissionGranted = true);

      // Get initial position
      final pos = await _locationService.getCurrentPosition();
      if (mounted && pos != null) {
        setState(() => _engineerPosition = LatLng(pos.lat, pos.lng));
        _animateCameraToEngineer();
      } else if (mounted) {
        setState(() => _engineerPosition = kNatraxCenter);
      }

      // Stream position updates
      _positionStream = _locationService.positionStream().listen((pos) {
        if (mounted) {
          setState(() => _engineerPosition = LatLng(pos.lat, pos.lng));
        }
      });
    } catch (_) {
      // Location not available — map still shows without engineer dot
    }
  }

  void _animateCameraToEngineer() {
    if (_mapController == null || _engineerPosition == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(_engineerPosition!, 15.0),
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Gate markers
    for (int i = 0; i < widget.gates.length; i++) {
      final gate = widget.gates[i];
      final lat = gate['lat'] as double? ?? kNatraxCenter.latitude;
      final lng = gate['lng'] as double? ?? kNatraxCenter.longitude;
      final name = gate['name'] as String? ?? 'Gate ${i + 1}';
      final isHighlighted =
          widget.highlightedGate != null &&
          widget.highlightedGate!['name'] == name;

      markers.add(
        Marker(
          markerId: MarkerId('gate_$i'),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: name,
            snippet: '${gate['radiusMeters'] ?? 300}m radius',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isHighlighted
                ? BitmapDescriptor.hueGreen
                : BitmapDescriptor.hueOrange,
          ),
          zIndex: isHighlighted ? 2.0 : 1.0,
        ),
      );
    }

    // Engineer position marker
    if (_engineerPosition != null && widget.showEngineerLocation) {
      markers.add(
        Marker(
          markerId: const MarkerId('engineer'),
          position: _engineerPosition!,
          infoWindow: const InfoWindow(title: 'Your Position'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          zIndex: 3.0,
        ),
      );
    }

    return markers;
  }

  Set<Circle> _buildCircles() {
    final circles = <Circle>{};

    for (int i = 0; i < widget.gates.length; i++) {
      final gate = widget.gates[i];
      final lat = gate['lat'] as double? ?? kNatraxCenter.latitude;
      final lng = gate['lng'] as double? ?? kNatraxCenter.longitude;
      final radius = (gate['radiusMeters'] as int? ?? 300).toDouble();
      final name = gate['name'] as String? ?? 'Gate $i';
      final isHighlighted =
          widget.highlightedGate != null &&
          widget.highlightedGate!['name'] == name;

      circles.add(
        Circle(
          circleId: CircleId('geofence_$i'),
          center: LatLng(lat, lng),
          radius: radius,
          fillColor: isHighlighted
              ? const Color(0xFF00C896).withAlpha(50)
              : const Color(0xFFFF6B35).withAlpha(30),
          strokeColor: isHighlighted
              ? const Color(0xFF00C896)
              : const Color(0xFFFF6B35),
          strokeWidth: isHighlighted ? 2 : 1,
        ),
      );
    }

    // Highlighted gate (geofence setup mode — live preview)
    if (widget.highlightedGate != null) {
      final g = widget.highlightedGate!;
      final lat = g['lat'] as double? ?? kNatraxCenter.latitude;
      final lng = g['lng'] as double? ?? kNatraxCenter.longitude;
      final radius = (g['radiusMeters'] as int? ?? 300).toDouble();

      // Outer pulse ring
      circles.add(
        Circle(
          circleId: const CircleId('geofence_highlight_outer'),
          center: LatLng(lat, lng),
          radius: radius * 1.15,
          fillColor: Colors.transparent,
          strokeColor: const Color(0xFF00C896).withAlpha(60),
          strokeWidth: 1,
        ),
      );
    }

    return circles;
  }

  LatLng _computeInitialTarget() {
    if (widget.highlightedGate != null) {
      final g = widget.highlightedGate!;
      return LatLng(
        g['lat'] as double? ?? kNatraxCenter.latitude,
        g['lng'] as double? ?? kNatraxCenter.longitude,
      );
    }
    return kNatraxCenter;
  }

  double _computeInitialZoom() {
    if (widget.highlightedGate != null) {
      final radius = widget.highlightedGate!['radiusMeters'] as int? ?? 300;
      if (radius > 1000) return 13.5;
      if (radius > 500) return 14.5;
      return 15.5;
    }
    return 14.0;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                if (widget.mapType == MapType.normal) {
                  controller.setMapStyle(_darkMapStyle);
                }
                setState(() => _mapReady = true);
                widget.onMapCreated?.call(controller);
              },
              initialCameraPosition: CameraPosition(
                target: _computeInitialTarget(),
                zoom: _computeInitialZoom(),
                tilt: (!kIsWeb && widget.highlightedGate != null) ? 30 : 0,
              ),
              mapType: widget.mapType,
              markers: _buildMarkers(),
              circles: _buildCircles(),
              // myLocationEnabled not supported on web — use custom marker instead
              myLocationEnabled: _locationPermissionGranted && !kIsWeb,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: !kIsWeb, // tilt not supported on web
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
            ),
            // Map type toggle + locate button overlay
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapButton(
                    icon: Icons.my_location_rounded,
                    onTap: _animateCameraToEngineer,
                    tooltip: 'My Location',
                  ),
                  const SizedBox(height: 8),
                  _MapButton(
                    icon: Icons.center_focus_strong_rounded,
                    onTap: () {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          _computeInitialTarget(),
                          _computeInitialZoom(),
                        ),
                      );
                    },
                    tooltip: 'Center on Track',
                  ),
                ],
              ),
            ),
            // Loading overlay
            if (!_mapReady)
              Container(
                color: const Color(0xFF0A0E1A),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00C896),
                    strokeWidth: 2,
                  ),
                ),
              ),
            // NATRAX label badge
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1520).withAlpha(220),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00C896).withAlpha(100),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00C896),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'NATRAX · Live',
                      style: TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EAF0),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // API Key diagnostic overlay — shows on Android for 8 seconds
            if (!kIsWeb && _showDiagnostic)
              Positioned(
                left: 12,
                bottom: 12,
                right: 60,
                child: GestureDetector(
                  onTap: () => setState(() => _showDiagnostic = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _keyValid
                          ? const Color(0xFF0F3020).withAlpha(230)
                          : const Color(0xFF3A0A0A).withAlpha(230),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _keyValid
                            ? const Color(0xFF00C896).withAlpha(150)
                            : const Color(0xFFFF4444).withAlpha(150),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _keyValid
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: _keyValid
                              ? const Color(0xFF00C896)
                              : const Color(0xFFFF4444),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Maps Key: $_keyDiagnostic',
                            style: TextStyle(
                              fontSize: 9,
                              color: _keyValid
                                  ? const Color(0xFF00C896)
                                  : const Color(0xFFFF6666),
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _MapButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1520).withAlpha(230),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3A4460), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(60),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: const Color(0xFF00C896), size: 18),
        ),
      ),
    );
  }
}

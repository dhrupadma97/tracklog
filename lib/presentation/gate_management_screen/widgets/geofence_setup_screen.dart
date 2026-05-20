import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/app_export.dart';
import '../../../widgets/track_map_widget.dart';

/// Full-screen geofence setup — lets the user manually pin a gate centre
/// and drag a radius ring to define the entry/exit boundary.
class GeofenceSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? existingGate;
  final void Function(double lat, double lng, int radiusMeters) onSave;

  const GeofenceSetupScreen({
    super.key,
    this.existingGate,
    required this.onSave,
  });

  @override
  State<GeofenceSetupScreen> createState() => _GeofenceSetupScreenState();
}

class _GeofenceSetupScreenState extends State<GeofenceSetupScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────
  late double _lat;
  late double _lng;
  late int _radiusMeters;

  // Canvas pan/zoom
  double _scale = 1.0;
  Offset _panOffset = Offset.zero;
  Offset _focalPoint = Offset.zero;
  double _baseScale = 1.0;

  // Drag state
  bool _draggingCenter = false;
  bool _draggingRadius = false;

  // Coordinate input controllers
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;

  // Animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Map mode toggle
  bool _showLiveMap = true;
  GoogleMapController? _googleMapController;

  // NATRAX reference points (for the mini-map grid)
  static const double _natraxLat = 22.5667;
  static const double _natraxLng = 75.6167;

  // Pixels per degree at default scale (roughly 1° ≈ 111 km → 1 m ≈ 0.009 px at scale 1)
  static const double _pxPerDeg = 8000.0; // at scale=1

  @override
  void initState() {
    super.initState();
    final g = widget.existingGate;
    _lat = g != null ? (g['lat'] as double) : _natraxLat;
    _lng = g != null ? (g['lng'] as double) : _natraxLng;
    _radiusMeters = g != null ? (g['radiusMeters'] as int) : 300;

    _latCtrl = TextEditingController(text: _lat.toStringAsFixed(6));
    _lngCtrl = TextEditingController(text: _lng.toStringAsFixed(6));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  // ── Coordinate helpers ─────────────────────────────────────────────────

  /// Convert lat/lng to canvas pixel offset (relative to canvas centre).
  Offset _coordToCanvas(double lat, double lng, Size canvasSize) {
    final cx = canvasSize.width / 2;
    final cy = canvasSize.height / 2;
    final dx = (lng - _natraxLng) * _pxPerDeg * _scale + _panOffset.dx;
    final dy = -((lat - _natraxLat) * _pxPerDeg * _scale) + _panOffset.dy;
    return Offset(cx + dx, cy + dy);
  }

  /// Convert canvas pixel offset back to lat/lng.
  (double, double) _canvasToCoord(Offset pos, Size canvasSize) {
    final cx = canvasSize.width / 2;
    final cy = canvasSize.height / 2;
    final dx = pos.dx - cx - _panOffset.dx;
    final dy = pos.dy - cy - _panOffset.dy;
    final lat = _natraxLat - dy / (_pxPerDeg * _scale);
    final lng = _natraxLng + dx / (_pxPerDeg * _scale);
    return (lat, lng);
  }

  /// Radius in pixels on canvas.
  double _radiusPx(Size canvasSize) {
    // 1 degree lat ≈ 111,000 m
    return (_radiusMeters / 111000.0) * _pxPerDeg * _scale;
  }

  void _updateFromCanvas(Offset pos, Size canvasSize) {
    final (lat, lng) = _canvasToCoord(pos, canvasSize);
    setState(() {
      _lat = lat;
      _lng = lng;
      _latCtrl.text = lat.toStringAsFixed(6);
      _lngCtrl.text = lng.toStringAsFixed(6);
    });
    HapticFeedback.selectionClick();
    _animateGoogleMapToGate();
  }

  void _updateRadiusFromDrag(Offset handlePos, Offset centerPos) {
    final dist = (handlePos - centerPos).distance;
    // Convert px distance back to metres
    final metres = (dist / (_pxPerDeg * _scale)) * 111000.0;
    setState(() {
      _radiusMeters = metres.clamp(50, 5000).toInt();
    });
  }

  void _applyManualCoords() {
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    if (lat == null || lng == null) return;
    setState(() {
      _lat = lat;
      _lng = lng;
    });
    HapticFeedback.mediumImpact();
    _animateGoogleMapToGate();
  }

  void _animateGoogleMapToGate() {
    _googleMapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(_lat, _lng), 15.5),
    );
  }

  // ── Preset locations ───────────────────────────────────────────────────
  static const List<Map<String, dynamic>> _presets = [
    {'name': 'HST Main', 'lat': 22.5671, 'lng': 75.6182, 'radius': 500},
    {'name': 'Dynamic Plt', 'lat': 22.5648, 'lng': 75.6155, 'radius': 350},
    {'name': 'Braking Trk', 'lat': 22.5690, 'lng': 75.6201, 'radius': 250},
    {'name': 'Handling Cct', 'lat': 22.5632, 'lng': 75.6130, 'radius': 400},
    {'name': 'Wet Skid Pad', 'lat': 22.5658, 'lng': 75.6175, 'radius': 200},
    {'name': 'NATRAX Gate', 'lat': 22.5667, 'lng': 75.6167, 'radius': 2500},
  ];

  void _applyPreset(Map<String, dynamic> p) {
    setState(() {
      _lat = p['lat'] as double;
      _lng = p['lng'] as double;
      _radiusMeters = p['radius'] as int;
      _latCtrl.text = _lat.toStringAsFixed(6);
      _lngCtrl.text = _lng.toStringAsFixed(6);
    });
    HapticFeedback.mediumImpact();
    _animateGoogleMapToGate();
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: _showLiveMap ? _buildLiveMapView() : _buildMapCanvas(),
            ),
            _buildBottomPanel(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1520),
        border: Border(bottom: BorderSide(color: Color(0xFF252E45), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2236),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3A4460), width: 1),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFFE8EAF0),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set Geofence Boundary',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8EAF0),
                  ),
                ),
                Text(
                  _showLiveMap
                      ? 'Live map · tap presets to position'
                      : 'Drag pin to position · drag ring to resize',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: Color(0xFF6B7490),
                  ),
                ),
              ],
            ),
          ),
          // Map mode toggle
          GestureDetector(
            onTap: () => setState(() => _showLiveMap = !_showLiveMap),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2236),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3A4460), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showLiveMap ? Icons.grid_on_rounded : Icons.map_rounded,
                    color: const Color(0xFF00C896),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showLiveMap ? 'Grid' : 'Map',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00C896),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Save button
          GestureDetector(
            onTap: () {
              widget.onSave(_lat, _lng, _radiusMeters);
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF001A10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Live Google Map view for geofence setup
  Widget _buildLiveMapView() {
    final currentGate = {
      'name': widget.existingGate?['name'] ?? 'New Gate',
      'lat': _lat,
      'lng': _lng,
      'radiusMeters': _radiusMeters,
    };

    return Stack(
      children: [
        TrackMapWidget(
          gates: [currentGate],
          highlightedGate: currentGate,
          showEngineerLocation: true,
          height: double.infinity,
          mapType: MapType.hybrid,
          onMapCreated: (controller) {
            _googleMapController = controller;
          },
        ),
        // Preset strip overlay
        Positioned(
          left: 0,
          right: 0,
          top: 12,
          child: _PresetStrip(presets: _presets, onSelect: _applyPreset),
        ),
        // Coordinate display overlay
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1520).withAlpha(220),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3A4460), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE8EAF0),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Radius: ${_radiusMeters}m',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 10,
                    color: Color(0xFF00C896),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapCanvas() {
    return GestureDetector(
      onScaleStart: (d) {
        _focalPoint = d.localFocalPoint;
        _baseScale = _scale;
      },
      onScaleUpdate: (d) {
        setState(() {
          _scale = (_baseScale * d.scale).clamp(0.3, 8.0);
          if (d.pointerCount == 1) {
            _panOffset += d.focalPointDelta;
          }
        });
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final centerPx = _coordToCanvas(_lat, _lng, size);
          final rPx = _radiusPx(size);
          // Radius handle sits at 0° (right side of circle)
          final handlePx = centerPx + Offset(rPx, 0);

          return Stack(
            children: [
              // Grid background
              CustomPaint(
                size: size,
                painter: _GridPainter(
                  scale: _scale,
                  panOffset: _panOffset,
                  natraxCenter: _coordToCanvas(_natraxLat, _natraxLng, size),
                ),
              ),
              // Geofence ring + centre
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => CustomPaint(
                  size: size,
                  painter: _GeofencePainter(
                    center: centerPx,
                    radiusPx: rPx,
                    pulse: _pulseAnim.value,
                    draggingCenter: _draggingCenter,
                    draggingRadius: _draggingRadius,
                  ),
                ),
              ),
              // Centre drag handle
              Positioned(
                left: centerPx.dx - 22,
                top: centerPx.dy - 22,
                child: GestureDetector(
                  onPanStart: (_) => setState(() => _draggingCenter = true),
                  onPanUpdate: (d) {
                    _updateFromCanvas(centerPx + d.delta, size);
                  },
                  onPanEnd: (_) => setState(() => _draggingCenter = false),
                  child: _CenterPin(active: _draggingCenter),
                ),
              ),
              // Radius drag handle
              Positioned(
                left: handlePx.dx - 16,
                top: handlePx.dy - 16,
                child: GestureDetector(
                  onPanStart: (_) => setState(() => _draggingRadius = true),
                  onPanUpdate: (d) {
                    _updateRadiusFromDrag(handlePx + d.delta, centerPx);
                  },
                  onPanEnd: (_) => setState(() => _draggingRadius = false),
                  child: _RadiusHandle(active: _draggingRadius),
                ),
              ),
              // Radius label
              Positioned(
                left: (centerPx.dx + handlePx.dx) / 2 - 30,
                top: centerPx.dy - 22,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1520).withAlpha(204),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primary.withAlpha(77),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${_radiusMeters}m',
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00C896),
                      ),
                    ),
                  ),
                ),
              ),
              // Zoom controls
              Positioned(
                right: 16,
                top: 16,
                child: _ZoomControls(
                  onZoomIn: () =>
                      setState(() => _scale = (_scale * 1.4).clamp(0.3, 8.0)),
                  onZoomOut: () =>
                      setState(() => _scale = (_scale / 1.4).clamp(0.3, 8.0)),
                  onReset: () => setState(() {
                    _scale = 1.0;
                    _panOffset = Offset.zero;
                  }),
                ),
              ),
              // Preset chips
              Positioned(
                left: 0,
                right: 0,
                top: 12,
                child: _PresetStrip(presets: _presets, onSelect: _applyPreset),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1520),
        border: Border(top: BorderSide(color: Color(0xFF252E45), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Coordinate inputs row
          Row(
            children: [
              Expanded(
                child: _CoordField(
                  label: 'Latitude',
                  controller: _latCtrl,
                  onSubmit: _applyManualCoords,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CoordField(
                  label: 'Longitude',
                  controller: _lngCtrl,
                  onSubmit: _applyManualCoords,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _applyManualCoords,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(31),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withAlpha(102),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF00C896),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Radius slider
          Row(
            children: [
              const Text(
                'Radius',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA8B0C8),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primary,
                    inactiveTrackColor: const Color(0xFF252E45),
                    thumbColor: AppTheme.primary,
                    overlayColor: AppTheme.primary.withAlpha(31),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: _radiusMeters.toDouble(),
                    min: 50,
                    max: 5000,
                    divisions: 99,
                    onChanged: (v) => setState(() => _radiusMeters = v.toInt()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Text(
                  '${_radiusMeters}m',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00C896),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Info row
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: Color(0xFF6B7490),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Session auto-starts when GPS enters this boundary',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11,
                    color: Color(0xFF6B7490),
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

// ── Custom Painters ────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final double scale;
  final Offset panOffset;
  final Offset natraxCenter;

  _GridPainter({
    required this.scale,
    required this.panOffset,
    required this.natraxCenter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dark base
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0E1A),
    );

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1C2438)
      ..strokeWidth = 1;

    final spacing = 40.0 * scale;
    final cx = size.width / 2 + panOffset.dx;
    final cy = size.height / 2 + panOffset.dy;

    // Vertical lines
    for (double x = cx % spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    // Horizontal lines
    for (double y = cy % spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // NATRAX reference marker
    final refPaint = Paint()
      ..color = const Color(0xFF4A9EFF).withAlpha(51)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(natraxCenter, 6 * scale.clamp(0.5, 2.0), refPaint);

    final refBorderPaint = Paint()
      ..color = const Color(0xFF4A9EFF).withAlpha(128)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(natraxCenter, 6 * scale.clamp(0.5, 2.0), refBorderPaint);

    // NATRAX label
    final tp = TextPainter(
      text: const TextSpan(
        text: 'NATRAX',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 10,
          color: Color(0xFF4A9EFF),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, natraxCenter + const Offset(10, -6));
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.scale != scale ||
      old.panOffset != panOffset ||
      old.natraxCenter != natraxCenter;
}

class _GeofencePainter extends CustomPainter {
  final Offset center;
  final double radiusPx;
  final double pulse;
  final bool draggingCenter;
  final bool draggingRadius;

  _GeofencePainter({
    required this.center,
    required this.radiusPx,
    required this.pulse,
    required this.draggingCenter,
    required this.draggingRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Outer pulse ring
    final pulsePaint = Paint()
      ..color = const Color(0xFF00C896).withAlpha((30 * pulse).toInt())
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center,
      radiusPx * (1.0 + (1 - pulse) * 0.08),
      pulsePaint,
    );

    // Fill
    final fillPaint = Paint()
      ..color = const Color(0xFF00C896).withAlpha(draggingCenter ? 40 : 20)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radiusPx, fillPaint);

    // Border ring
    final borderPaint = Paint()
      ..color = draggingRadius
          ? const Color(0xFF00C896)
          : const Color(0xFF00C896).withAlpha(180)
      ..style = PaintingStyle.stroke
      ..strokeWidth = draggingRadius ? 2.5 : 1.8
      ..strokeCap = StrokeCap.round;

    // Dashed circle
    _drawDashedCircle(canvas, center, radiusPx, borderPaint);

    // Cross-hair lines
    final crossPaint = Paint()
      ..color = const Color(0xFF00C896).withAlpha(60)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - radiusPx * 1.15, center.dy),
      Offset(center.dx + radiusPx * 1.15, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radiusPx * 1.15),
      Offset(center.dx, center.dy + radiusPx * 1.15),
      crossPaint,
    );

    // Radius line to handle
    final linePaint = Paint()
      ..color = const Color(0xFF00C896).withAlpha(120)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center + Offset(radiusPx, 0), linePaint);
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    const dashCount = 48;
    const dashAngle = (2 * math.pi) / dashCount;
    const gapFraction = 0.35;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final sweepAngle = dashAngle * (1 - gapFraction);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GeofencePainter old) =>
      old.center != center ||
      old.radiusPx != radiusPx ||
      old.pulse != pulse ||
      old.draggingCenter != draggingCenter ||
      old.draggingRadius != draggingRadius;
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _CenterPin extends StatelessWidget {
  final bool active;
  const _CenterPin({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primary.withAlpha(51)
            : const Color(0xFF131929).withAlpha(230),
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? AppTheme.primary : AppTheme.primary.withAlpha(180),
          width: active ? 2.5 : 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppTheme.primary.withAlpha(80),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: const Icon(Icons.location_pin, color: Color(0xFF00C896), size: 22),
    );
  }
}

class _RadiusHandle extends StatelessWidget {
  final bool active;
  const _RadiusHandle({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primary
            : const Color(0xFF131929).withAlpha(230),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primary, width: active ? 0 : 2),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppTheme.primary.withAlpha(100),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Icon(
        Icons.open_with_rounded,
        color: active ? const Color(0xFF001A10) : AppTheme.primary,
        size: 16,
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1520).withAlpha(230),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252E45), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomBtn(icon: Icons.add_rounded, onTap: onZoomIn),
          Container(height: 1, color: const Color(0xFF252E45)),
          _ZoomBtn(icon: Icons.remove_rounded, onTap: onZoomOut),
          Container(height: 1, color: const Color(0xFF252E45)),
          _ZoomBtn(icon: Icons.center_focus_strong_rounded, onTap: onReset),
        ],
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Icon(icon, color: const Color(0xFFA8B0C8), size: 18),
      ),
    );
  }
}

class _PresetStrip extends StatelessWidget {
  final List<Map<String, dynamic>> presets;
  final void Function(Map<String, dynamic>) onSelect;

  const _PresetStrip({required this.presets, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final p = presets[i];
          return GestureDetector(
            onTap: () => onSelect(p),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1520).withAlpha(230),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF3A4460), width: 1),
              ),
              child: Text(
                p['name'] as String,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFCDD0E0),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CoordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _CoordField({
    required this.label,
    required this.controller,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7490),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF1A2236),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3A4460), width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE8EAF0),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
      ],
    );
  }
}

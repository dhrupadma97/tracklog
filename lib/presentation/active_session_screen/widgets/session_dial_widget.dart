import 'dart:math' as math;

import '../../../core/app_export.dart';

// Anatomy locked: circular arc gauge, elapsed time centered, device icons around arc
class SessionDialWidget extends StatelessWidget {
  final bool sessionActive;
  final Duration elapsed;
  final Animation<double> pulseAnimation;
  final String gateLabel;

  const SessionDialWidget({
    super.key,
    required this.sessionActive,
    required this.elapsed,
    required this.pulseAnimation,
    required this.gateLabel,
  });

  String _formatTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // Progress: 0.0 to 1.0 based on a max 8-hour session
  double get _progress {
    final maxSeconds = 8 * 3600.0;
    return (elapsed.inSeconds / maxSeconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialColor = sessionActive
        ? AppTheme.primary
        : const Color(0xFF849495);
    final glowColor = sessionActive
        ? AppTheme.primary.withAlpha(77)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: sessionActive
                ? AppTheme.primary.withAlpha(51)
                : const Color(0xFF3a494b),
            width: 1,
          ),
          boxShadow: sessionActive
              ? [BoxShadow(color: glowColor, blurRadius: 32, spreadRadius: 4)]
              : [],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            // Gate label
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181B25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF849495),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomIconWidget(
                        iconName: 'location_on',
                        color: AppTheme.secondary,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        gateLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFdfe2f0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Circular dial
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  if (sessionActive)
                    AnimatedBuilder(
                      animation: pulseAnimation,
                      builder: (_, __) => Transform.scale(
                        scale: pulseAnimation.value,
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(
                                0.15 * pulseAnimation.value,
                              ),
                              width: 8,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Arc painter
                  CustomPaint(
                    size: const Size(200, 200),
                    painter: _ArcPainter(
                      progress: _progress,
                      trackColor: const Color(0xFF3a494b),
                      progressColor: dialColor,
                      strokeWidth: 10,
                    ),
                  ),
                  // Center content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sessionActive)
                        AnimatedBuilder(
                          animation: pulseAnimation,
                          builder: (_, __) => Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primary.withOpacity(
                                pulseAnimation.value,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withAlpha(128),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 18),
                      Text(
                        _formatTime(elapsed),
                        style: const TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFdfe2f0),
                          fontFeatures: [FontFeature.tabularFigures()],
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sessionActive ? 'Session Running' : 'Session Idle',
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: sessionActive
                              ? AppTheme.primary
                              : const Color(0xFF6B7490),
                        ),
                      ),
                    ],
                  ),
                  // Icons around arc — top
                  Positioned(
                    top: 8,
                    child: CustomIconWidget(
                      iconName: 'speed',
                      color: const Color(0xFF4A9EFF).withAlpha(179),
                      size: 20,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 70,
                    child: CustomIconWidget(
                      iconName: 'map',
                      color: const Color(0xFF6B7490),
                      size: 18,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 70,
                    child: CustomIconWidget(
                      iconName: 'gps_fixed',
                      color: sessionActive
                          ? AppTheme.primary.withAlpha(179)
                          : const Color(0xFF6B7490),
                      size: 18,
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
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  const _ArcPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final startAngle = math.pi * 0.75;
    final sweepAngle = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Track arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * progress,
        false,
        progressPaint,
      );
    }

    // Thumb dot
    if (progress > 0) {
      final thumbAngle = startAngle + sweepAngle * progress;
      final thumbX = center.dx + radius * math.cos(thumbAngle);
      final thumbY = center.dy + radius * math.sin(thumbAngle);
      canvas.drawCircle(
        Offset(thumbX, thumbY),
        strokeWidth / 2 + 2,
        Paint()..color = progressColor,
      );
      canvas.drawCircle(
        Offset(thumbX, thumbY),
        strokeWidth / 2,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.progressColor != progressColor;
}

import 'package:flutter/material.dart';

enum SessionStatus { active, idle, completed, warning, paused }

class StatusBadgeWidget extends StatelessWidget {
  final SessionStatus status;
  final String? customLabel;
  final bool compact;

  const StatusBadgeWidget({
    super.key,
    required this.status,
    this.customLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _statusConfig[status]!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: config.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: config.dot,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            customLabel ?? config.label,
            style: TextStyle(
              fontFamily: 'Space Grotesk',
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: config.text,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  static final Map<SessionStatus, _BadgeConfig> _statusConfig = {
    SessionStatus.active: _BadgeConfig(
      label: 'ACTIVE',
      bg: const Color(0xFF00F3FF).withAlpha(38),
      border: const Color(0xFF00F3FF).withAlpha(102),
      dot: const Color(0xFF00F3FF),
      text: const Color(0xFF00F3FF),
    ),
    SessionStatus.idle: _BadgeConfig(
      label: 'IDLE',
      bg: const Color(0xFF6B7490).withAlpha(38),
      border: const Color(0xFF6B7490).withAlpha(102),
      dot: const Color(0xFF6B7490),
      text: const Color(0xFF6B7490),
    ),
    SessionStatus.completed: _BadgeConfig(
      label: 'COMPLETED',
      bg: const Color(0xFF4A9EFF).withAlpha(38),
      border: const Color(0xFF4A9EFF).withAlpha(102),
      dot: const Color(0xFF4A9EFF),
      text: const Color(0xFF4A9EFF),
    ),
    SessionStatus.warning: _BadgeConfig(
      label: 'OVERRUN',
      bg: const Color(0xFFFFB547).withAlpha(38),
      border: const Color(0xFFFFB547).withAlpha(102),
      dot: const Color(0xFFFFB547),
      text: const Color(0xFFFFB547),
    ),
    SessionStatus.paused: _BadgeConfig(
      label: 'PAUSED',
      bg: const Color(0xFF7000FF).withAlpha(38),
      border: const Color(0xFF7000FF).withAlpha(102),
      dot: const Color(0xFF7000FF),
      text: const Color(0xFF7000FF),
    ),
  };
}

class _BadgeConfig {
  final String label;
  final Color bg;
  final Color border;
  final Color dot;
  final Color text;
  const _BadgeConfig({
    required this.label,
    required this.bg,
    required this.border,
    required this.dot,
    required this.text,
  });
}

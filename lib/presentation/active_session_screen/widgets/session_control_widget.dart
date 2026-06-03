import '../../../core/app_export.dart';

class SessionControlWidget extends StatefulWidget {
  final bool sessionActive;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const SessionControlWidget({
    super.key,
    required this.sessionActive,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<SessionControlWidget> createState() => _SessionControlWidgetState();
}

class _SessionControlWidgetState extends State<SessionControlWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _scaleController.forward().then((_) {
      _scaleController.reverse();
    });
    if (widget.sessionActive) {
      widget.onStop();
    } else {
      widget.onStart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: GestureDetector(
                    onTap: _handleTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 56,
                      decoration: BoxDecoration(
                        color: widget.sessionActive
                            ? AppTheme.error.withAlpha(38)
                            : AppTheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: widget.sessionActive
                              ? AppTheme.error.withAlpha(102)
                              : AppTheme.primary,
                          width: 1,
                        ),
                        boxShadow: widget.sessionActive
                            ? []
                            : [
                                BoxShadow(
                                  color: AppTheme.primary.withAlpha(77),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomIconWidget(
                            iconName: widget.sessionActive
                                ? 'stop'
                                : 'play_arrow',
                            color: widget.sessionActive
                                ? AppTheme.error
                                : const Color(0xFF001A10),
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.sessionActive
                                ? 'Stop Session'
                                : 'Start Session',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: widget.sessionActive
                                  ? AppTheme.error
                                  : const Color(0xFF001A10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomIconWidget(
                iconName: 'info',
                color: const Color(0xFF6B7490),
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'GPS auto-starts session on track entry',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

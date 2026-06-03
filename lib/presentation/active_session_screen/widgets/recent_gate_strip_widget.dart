import '../../../core/app_export.dart';

class RecentGateStripWidget extends StatelessWidget {
  final String currentGate;
  final void Function(String gate) onGateTap;

  const RecentGateStripWidget({
    super.key,
    required this.currentGate,
    required this.onGateTap,
  });

  static const List<Map<String, String>> _gates = [
    {'name': 'High Speed Track', 'type': 'HST', 'floor': 'Zone A'},
    {'name': 'Dynamic Platform', 'type': 'DYN', 'floor': 'Zone B'},
    {'name': 'Braking Track', 'type': 'BRK', 'floor': 'Zone C'},
    {'name': 'Handling Circuit', 'type': 'HC', 'floor': 'Zone D'},
    {'name': 'Wet Skid Pad', 'type': 'WSP', 'floor': 'Zone E'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Text(
                'NATRAX Tracks',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFdfe2f0),
                ),
              ),
              const Spacer(),
              Text(
                'Switch Track',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _gates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final gate = _gates[i];
              final isSelected = gate['name'] == currentGate;
              return GestureDetector(
                onTap: () => onGateTap(gate['name']!),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 130,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withAlpha(26)
                        : const Color(0xFF0A1025),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary.withAlpha(128)
                          : const Color(0xFF849495),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CustomIconWidget(
                            iconName: 'location_on',
                            color: isSelected
                                ? AppTheme.primary
                                : const Color(0xFF6B7490),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            gate['floor']!,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        gate['name']!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFFdfe2f0),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3a494b),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          gate['type']!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

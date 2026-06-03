import 'package:flutter/services.dart';

import '../../../core/app_export.dart';
import './geofence_setup_screen.dart';

class CreateGateSheetWidget extends StatefulWidget {
  final Map<String, dynamic>? existingGate;
  final void Function(Map<String, dynamic> gate) onGateCreated;

  const CreateGateSheetWidget({
    super.key,
    this.existingGate,
    required this.onGateCreated,
  });

  @override
  State<CreateGateSheetWidget> createState() => _CreateGateSheetWidgetState();
}

class _CreateGateSheetWidgetState extends State<CreateGateSheetWidget> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late TextEditingController _rateController;
  String _selectedTrackType = 'HST';
  double _radiusMeters = 300;
  bool _isActive = true;

  static const List<Map<String, String>> _trackTypes = [
    {'code': 'HST', 'label': 'High Speed Track'},
    {'code': 'DYN', 'label': 'Dynamic Platform'},
    {'code': 'BRK', 'label': 'Braking Track'},
    {'code': 'HC', 'label': 'Handling Circuit'},
    {'code': 'WSP', 'label': 'Wet Skid Pad'},
    {'code': 'GEN', 'label': 'General / Perimeter'},
  ];

  @override
  void initState() {
    super.initState();
    final g = widget.existingGate;
    _nameController = TextEditingController(text: g?['name'] as String? ?? '');
    _latController = TextEditingController(
      text: g != null ? (g['lat'] as double).toStringAsFixed(4) : '22.5667',
    );
    _lngController = TextEditingController(
      text: g != null ? (g['lng'] as double).toStringAsFixed(4) : '75.6167',
    );
    _rateController = TextEditingController(
      text: g != null
          ? (g['hourlyRateINR'] as double).toStringAsFixed(0)
          : '4200',
    );
    if (g != null) {
      _selectedTrackType = g['trackType'] as String;
      _radiusMeters = (g['radiusMeters'] as int).toDouble();
      _isActive = g['isActive'] as bool;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _useCurrentLocation() {
    // TODO: Replace with actual GPS location from geolocator package
    setState(() {
      _latController.text = '22.5667';
      _lngController.text = '75.6167';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Using NATRAX center coordinates (GPS demo)',
          style: TextStyle(fontFamily: 'Space Grotesk'),
        ),
        backgroundColor: const Color(0xFF0A1025),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _openGeofenceSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GeofenceSetupScreen(
          existingGate: widget.existingGate != null
              ? {
                  'lat': double.tryParse(_latController.text) ?? 22.5667,
                  'lng': double.tryParse(_lngController.text) ?? 75.6167,
                  'radiusMeters': _radiusMeters.toInt(),
                }
              : null,
          onSave: (lat, lng, radius) {
            setState(() {
              _latController.text = lat.toStringAsFixed(6);
              _lngController.text = lng.toStringAsFixed(6);
              _radiusMeters = radius.toDouble();
            });
          },
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final isEdit = widget.existingGate != null;
    final gate = <String, dynamic>{
      'id': isEdit
          ? widget.existingGate!['id']
          : 'gate-${DateTime.now().millisecondsSinceEpoch}',
      'name': _nameController.text.trim(),
      'trackType': _selectedTrackType,
      'zone': _trackTypes.firstWhere(
        (t) => t['code'] == _selectedTrackType,
      )['label']!,
      'lat': double.tryParse(_latController.text) ?? 22.5667,
      'lng': double.tryParse(_lngController.text) ?? 75.6167,
      'radiusMeters': _radiusMeters.toInt(),
      'hourlyRateINR': double.tryParse(_rateController.text) ?? 4200.0,
      'isActive': _isActive,
      'lastUsed': DateTime.now().toIso8601String(),
      'totalSessionsThisMonth': isEdit
          ? widget.existingGate!['totalSessionsThisMonth']
          : 0,
    };
    widget.onGateCreated(gate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existingGate != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A1025),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: Color(0xFF849495), width: 1),
            left: BorderSide(color: Color(0xFF849495), width: 1),
            right: BorderSide(color: Color(0xFF849495), width: 1),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF849495),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text(
                    isEdit ? 'Edit Gate' : 'Create Gate',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF6B7490),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF3a494b), height: 24),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  children: [
                    // Section: Gate Identity
                    _SectionLabel(label: 'Gate Identity'),
                    const SizedBox(height: 10),
                    _GlassFormField(
                      controller: _nameController,
                      label: 'Gate Name',
                      hint: 'e.g. High Speed Track — Main Entry',
                      iconName: 'fence',
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Gate name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    // Track type selector
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Track Type',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFFA8B0C8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _trackTypes.map((t) {
                            final isSelected = _selectedTrackType == t['code'];
                            return GestureDetector(
                              onTap: () => setState(
                                () => _selectedTrackType = t['code']!,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primary.withAlpha(38)
                                      : const Color(0xFF0A1025),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary.withAlpha(128)
                                        : const Color(0xFF849495),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      t['code']!,
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? AppTheme.primary
                                            : const Color(0xFFdfe2f0),
                                      ),
                                    ),
                                    Text(
                                      t['label']!,
                                      style: TextStyle(
                                        fontFamily: 'Space Grotesk',
                                        fontSize: 10,
                                        color: isSelected
                                            ? AppTheme.primary.withAlpha(204)
                                            : const Color(0xFF6B7490),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Section: GPS Location
                    _SectionLabel(label: 'GPS Location'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _GlassFormField(
                            controller: _latController,
                            label: 'Latitude',
                            hint: '22.5667',
                            iconName: 'gps_fixed',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              final d = double.tryParse(v);
                              if (d == null || d < -90 || d > 90) {
                                return 'Invalid';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _GlassFormField(
                            controller: _lngController,
                            label: 'Longitude',
                            hint: '75.6167',
                            iconName: 'gps_fixed',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              final d = double.tryParse(v);
                              if (d == null || d < -180 || d > 180) {
                                return 'Invalid';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Use current location button
                    GestureDetector(
                      onTap: _useCurrentLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withAlpha(64),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CustomIconWidget(
                              iconName: 'my_location',
                              color: AppTheme.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Use Current Location',
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Set on Map button — opens GeofenceSetupScreen
                    GestureDetector(
                      onTap: _openGeofenceSetup,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9EFF).withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF4A9EFF).withAlpha(77),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.map_outlined,
                              color: Color(0xFF4A9EFF),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Set Boundary on Map',
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A9EFF),
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF4A9EFF),
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Section: Geofence Settings
                    _SectionLabel(label: 'Geofence Settings'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Geofence Radius',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFFA8B0C8),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(31),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_radiusMeters.toInt()} m',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.primary,
                        inactiveTrackColor: const Color(0xFF3a494b),
                        thumbColor: AppTheme.primary,
                        overlayColor: AppTheme.primary.withAlpha(26),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _radiusMeters,
                        min: 50,
                        max: 3000,
                        divisions: 59,
                        onChanged: (v) => setState(() => _radiusMeters = v),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('50 m', style: theme.textTheme.labelSmall),
                        Text('3,000 m', style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Section: Billing
                    _SectionLabel(label: 'Billing Rate'),
                    const SizedBox(height: 10),
                    _GlassFormField(
                      controller: _rateController,
                      label: 'Hourly Rate (INR)',
                      hint: 'e.g. 4200',
                      iconName: 'currency_rupee',
                      helperText: 'Enter rate from your NATRAX quote document',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Hourly rate is required';
                        }
                        final d = double.tryParse(v);
                        if (d == null || d < 0) {
                          return 'Enter a valid rate in INR';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    // Active toggle
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1025),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF849495),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CustomIconWidget(
                            iconName: _isActive ? 'toggle_on' : 'toggle_off',
                            color: _isActive
                                ? AppTheme.primary
                                : const Color(0xFF6B7490),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gate Active',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: const Color(0xFFdfe2f0),
                                  ),
                                ),
                                Text(
                                  _isActive
                                      ? 'GPS auto-session enabled'
                                      : 'Gate disabled — no auto-session',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isActive,
                            onChanged: (v) => setState(() => _isActive = v),
                            activeThumbColor: AppTheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: CustomIconWidget(
                          iconName: isEdit ? 'check' : 'add',
                          color: const Color(0xFF001A10),
                          size: 20,
                        ),
                        label: Text(
                          isEdit ? 'Save Changes' : 'Create Gate',
                          style: const TextStyle(
                            fontFamily: 'Space Grotesk',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: const Color(0xFF001A10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Space Grotesk',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7490),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: const Color(0xFF3a494b))),
      ],
    );
  }
}

// V5 Glassmorphism form field — LOCKED
class _GlassFormField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String iconName;
  final String? helperText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _GlassFormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.iconName,
    this.helperText,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  State<_GlassFormField> createState() => _GlassFormFieldState();
}

class _GlassFormFieldState extends State<_GlassFormField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: const Color(0xFFA8B0C8),
          ),
        ),
        const SizedBox(height: 6),
        Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? AppTheme.primary.withAlpha(153)
                    : const Color(0xFF849495),
                width: _focused ? 1.5 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withAlpha(20),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: TextFormField(
              controller: widget.controller,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              validator: widget.validator,
              style: const TextStyle(
                fontFamily: 'Space Grotesk',
                fontSize: 14,
                color: Color(0xFFdfe2f0),
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  color: Color(0xFF6B7490),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: CustomIconWidget(
                    iconName: widget.iconName,
                    color: _focused
                        ? AppTheme.primary
                        : const Color(0xFF6B7490),
                    size: 16,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                helperText: widget.helperText,
                helperStyle: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 11,
                  color: Color(0xFF6B7490),
                ),
                errorStyle: const TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 11,
                  color: Color(0xFFFF4D6A),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/offline_queue_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();
  final _durationHrsCtrl = TextEditingController();
  final _durationMinsCtrl = TextEditingController();
  final _costCtrl = TextEditingController();

  String _selectedTrackCode = 'T1';
  String _selectedTrackName = 'High Speed Track';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  TimeOfDay _endTime = TimeOfDay(
    hour: (TimeOfDay.now().hour + 1) % 24,
    minute: TimeOfDay.now().minute,
  );
  String _sessionStatus = 'completed';
  bool _isSaving = false;
  bool _isSyncing = false;

  // Offline queue state
  bool _isOnline = true;
  int _pendingCount = 0;
  StreamSubscription<List<QueuedEntry>>? _queueSub;

  // Recent manual entries
  List<Map<String, dynamic>> _recentEntries = [];
  bool _loadingEntries = true;

  static const List<Map<String, String>> _tracks = [
    {'code': 'T1', 'name': 'High Speed Track'},
    {'code': 'T2', 'name': 'Dynamic Platform Track'},
    {'code': 'T3D', 'name': 'Straight Dry Braking Track'},
    {'code': 'T3W', 'name': 'Straight Wet Braking Track'},
    {'code': 'T7', 'name': 'Handling Track 4W (1.6 Km)'},
    {'code': 'T8', 'name': 'Gradient Track'},
    {'code': 'T9', 'name': 'Noise Track'},
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
    _initOfflineQueue();
    _loadRecentEntries();
  }

  Future<void> _initOfflineQueue() async {
    await OfflineQueueService.instance.initialize();
    _isOnline = OfflineQueueService.instance.isOnline;
    _pendingCount = await OfflineQueueService.instance.getPendingCount();
    if (mounted) setState(() {});

    _queueSub = OfflineQueueService.instance.queueStream.listen((
      entries,
    ) async {
      if (mounted) {
        setState(() {
          _pendingCount = entries.length;
          _isOnline = OfflineQueueService.instance.isOnline;
        });
        // When queue drains to 0 after a sync, reload entries from Supabase
        if (entries.isEmpty) {
          _loadRecentEntries();
        }
      }
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _animController.dispose();
    _notesCtrl.dispose();
    _durationHrsCtrl.dispose();
    _durationMinsCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecentEntries() async {
    setState(() => _loadingEntries = true);
    try {
      final data = await SupabaseService.instance.client
          .from('engineer_sessions')
          .select()
          .eq('notes', 'Manual entry')
          .order('started_at', ascending: false)
          .limit(20);
      if (mounted) {
        setState(() {
          _recentEntries = List<Map<String, dynamic>>.from(data as List);
          _loadingEntries = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            surface: Color(0xFF0A1025),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            surface: Color(0xFF0A1025),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _recalcDuration();
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            surface: Color(0xFF0A1025),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _recalcDuration();
      });
    }
  }

  void _recalcDuration() {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    final diff = endMinutes - startMinutes;
    if (diff > 0) {
      _durationHrsCtrl.text = (diff ~/ 60).toString();
      _durationMinsCtrl.text = (diff % 60).toString();
      _recalcCost();
    }
  }

  void _recalcCost() {
    final hrs = int.tryParse(_durationHrsCtrl.text) ?? 0;
    final mins = int.tryParse(_durationMinsCtrl.text) ?? 0;
    final totalMins = hrs * 60 + mins;
    if (totalMins <= 0) {
      _costCtrl.text = '';
      return;
    }

    const double hourlyRate = 25000.0;
    final double hours = totalMins / 60.0;
    final isMinBillingTrack = const {'T1', 'T2', 'T3D', 'T3W'}.contains(_selectedTrackCode);

    double cost = 0.0;
    if (isMinBillingTrack) {
      if (hours < 2.0) {
        cost = 2.0 * hourlyRate;
      } else {
        cost = hours * hourlyRate;
      }
    } else {
      cost = hours * hourlyRate;
    }

    _costCtrl.text = cost.toStringAsFixed(0);
  }

  Future<void> _saveEntry() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final hrs = int.tryParse(_durationHrsCtrl.text) ?? 0;
    final mins = int.tryParse(_durationMinsCtrl.text) ?? 0;
    final totalMins = hrs * 60 + mins;
    if (totalMins <= 0) {
      _showSnack('Duration must be greater than 0 minutes.', isError: true);
      return;
    }

    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '')) ?? 0.0;

    setState(() => _isSaving = true);
    try {
      final user = EngineerAuthService.instance.currentUser;
      if (user == null) throw Exception('Not signed in');

      final startedAt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      final endedAt = startedAt.add(Duration(minutes: totalMins));

      final payload = {
        'engineer_id': user.id,
        'track_code': _selectedTrackCode,
        'track_name': _selectedTrackName,
        'vehicle_category': 'below_3_5t',
        'booking_type': 'standard',
        'session_status': _sessionStatus,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_minutes': totalMins,
        'hourly_rate': 25000.0,
        'total_cost': cost,
        'notes':
            'Manual entry${_notesCtrl.text.isNotEmpty ? ' — ${_notesCtrl.text}' : ''}',
      };

      // Check connectivity — queue if offline, insert directly if online
      _isOnline = OfflineQueueService.instance.isOnline;
      if (_isOnline) {
        await SupabaseService.instance.client
            .from('engineer_sessions')
            .insert(payload);
        _showSnack('Session entry saved successfully.');
        _loadRecentEntries();
      } else {
        await OfflineQueueService.instance.enqueue(payload);
        _pendingCount = await OfflineQueueService.instance.getPendingCount();
        if (mounted) setState(() {});
        _showSnack(
          'You\'re offline. Entry queued — will sync automatically when connected.',
          isError: false,
          isWarning: true,
        );
      }

      _resetForm();
    } catch (e) {
      _showSnack('Failed to save entry. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _manualSync() async {
    if (_isSyncing || !_isOnline) return;
    setState(() => _isSyncing = true);
    try {
      final result = await OfflineQueueService.instance.syncPendingEntries();
      _pendingCount = await OfflineQueueService.instance.getPendingCount();
      if (mounted) setState(() {});
      if (result.synced > 0) {
        _showSnack(
          '${result.synced} queued entr${result.synced == 1 ? 'y' : 'ies'} synced successfully.',
        );
        _loadRecentEntries();
      } else if (result.failed > 0) {
        _showSnack(
          'Sync failed for ${result.failed} entr${result.failed == 1 ? 'y' : 'ies'}. Will retry.',
          isError: true,
        );
      } else {
        _showSnack('No pending entries to sync.');
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _resetForm() {
    _notesCtrl.clear();
    _durationHrsCtrl.clear();
    _durationMinsCtrl.clear();
    _costCtrl.clear();
    setState(() {
      _selectedTrackCode = 'T1';
      _selectedTrackName = 'High Speed Track';
      _selectedDate = DateTime.now();
      _startTime = TimeOfDay.now();
      _endTime = TimeOfDay(
        hour: (TimeOfDay.now().hour + 1) % 24,
        minute: TimeOfDay.now().minute,
      );
      _sessionStatus = 'completed';
    });
  }

  void _showSnack(
    String message, {
    bool isError = false,
    bool isWarning = false,
  }) {
    if (!mounted) return;
    Color bg = AppTheme.success;
    if (isError) bg = AppTheme.error;
    if (isWarning) bg = const Color(0xFFFF9500);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildConnectivityBanner()),
              SliverToBoxAdapter(child: _buildInfoBanner()),
              SliverToBoxAdapter(child: _buildEntryForm()),
              SliverToBoxAdapter(child: _buildRecentEntriesSection()),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9500).withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFF9500).withAlpha(70)),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: Color(0xFFFF9500),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual Entry',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFdfe2f0),
                  ),
                ),
                Text(
                  'Correct or add track timing records',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7490),
                  ),
                ),
              ],
            ),
          ),
          // Connectivity indicator dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isOnline ? AppTheme.success : const Color(0xFFFF9500),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows offline warning or pending-sync banner
  Widget _buildConnectivityBanner() {
    if (_isOnline && _pendingCount == 0) return const SizedBox.shrink();

    if (!_isOnline) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFF3B30).withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF3B30).withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFFF3B30),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pendingCount > 0
                      ? 'Offline — $_pendingCount entr${_pendingCount == 1 ? 'y' : 'ies'} queued. Will sync automatically when connected.'
                      : 'You\'re offline. Entries will be queued and synced when connectivity returns.',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFF3B30),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Online but has pending entries — show sync prompt
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9500).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF9500).withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_upload_outlined,
              color: Color(0xFFFF9500),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_pendingCount queued entr${_pendingCount == 1 ? 'y' : 'ies'} ready to sync.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFFF9500),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSyncing ? null : _manualSync,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF9500).withAlpha(120),
                  ),
                ),
                child: _isSyncing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFFFF9500),
                        ),
                      )
                    : Text(
                        'Sync Now',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFF9500),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9500).withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF9500).withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFFFF9500),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Use this form to manually add or correct track session timings when the system fails to record automatically.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFFF9500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionLabel('Track Selection'),
                  const SizedBox(height: 10),
                  _buildTrackDropdown(),
                  const SizedBox(height: 16),
                  _buildSectionLabel('Date & Time'),
                  const SizedBox(height: 10),
                  _buildDateTimePickers(),
                  const SizedBox(height: 16),
                  _buildSectionLabel('Duration'),
                  const SizedBox(height: 10),
                  _buildDurationFields(),
                  const SizedBox(height: 16),
                  _buildSectionLabel('Cost (₹)'),
                  const SizedBox(height: 10),
                  _buildCostField(),
                  const SizedBox(height: 16),
                  _buildSectionLabel('Status'),
                  const SizedBox(height: 10),
                  _buildStatusSelector(),
                  const SizedBox(height: 16),
                  _buildSectionLabel('Notes (optional)'),
                  const SizedBox(height: 10),
                  _buildNotesField(),
                  const SizedBox(height: 20),
                  _buildSaveButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF6B7490),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTrackDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedTrackCode,
          isExpanded: true,
          dropdownColor: const Color(0xFF0A1025),
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFdfe2f0),
          ),
          items: _tracks.map((t) {
            return DropdownMenuItem<String>(
              value: t['code'],
              child: Text('${t['code']} — ${t['name']}'),
            );
          }).toList(),
          onChanged: (val) {
            if (val == null) return;
            final track = _tracks.firstWhere((t) => t['code'] == val);
            setState(() {
              _selectedTrackCode = val;
              _selectedTrackName = track['name']!;
              _recalcCost();
            });
          },
        ),
      ),
    );
  }

  Widget _buildDateTimePickers() {
    return Row(
      children: [
        Expanded(
          child: _buildPickerTile(
            icon: 'calendar_today',
            label: DateFormat('dd MMM yyyy').format(_selectedDate),
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildPickerTile(
            icon: 'schedule',
            label: 'Start: ${_startTime.format(context)}',
            onTap: _pickStartTime,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildPickerTile(
            icon: 'schedule',
            label: 'End: ${_endTime.format(context)}',
            onTap: _pickEndTime,
          ),
        ),
      ],
    );
  }

  Widget _buildPickerTile({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
        ),
        child: Column(
          children: [
            CustomIconWidget(iconName: icon, color: AppTheme.primary, size: 16),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFdfe2f0),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _durationHrsCtrl,
            keyboardType: TextInputType.number,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: const Color(0xFFdfe2f0),
            ),
            decoration: InputDecoration(
              labelText: 'Hours',
              suffixText: 'hrs',
              suffixStyle: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: const Color(0xFF6B7490),
              ),
            ),
            onChanged: (val) => _recalcCost(),
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              if (int.tryParse(v) == null) return 'Invalid';
              return null;
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _durationMinsCtrl,
            keyboardType: TextInputType.number,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: const Color(0xFFdfe2f0),
            ),
            decoration: InputDecoration(
              labelText: 'Minutes',
              suffixText: 'min',
              suffixStyle: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: const Color(0xFF6B7490),
              ),
            ),
            onChanged: (val) => _recalcCost(),
            validator: (v) {
              if (v == null || v.isEmpty) return null;
              final n = int.tryParse(v);
              if (n == null || n < 0 || n > 59) return 'Invalid';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCostField() {
    return TextFormField(
      controller: _costCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
      decoration: InputDecoration(
        labelText: 'Total Cost',
        prefixText: '₹ ',
        prefixStyle: GoogleFonts.spaceGrotesk(
          fontSize: 13,
          color: AppTheme.primary,
          fontWeight: FontWeight.w700,
        ),
        hintText: '0.00',
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Cost is required';
        if (double.tryParse(v.replaceAll(',', '')) == null) {
          return 'Enter a valid amount';
        }
        return null;
      },
    );
  }

  Widget _buildStatusSelector() {
    final statuses = [
      {'value': 'completed', 'label': 'Completed', 'color': AppTheme.success},
      {'value': 'warning', 'label': 'Warning', 'color': AppTheme.warning},
      {'value': 'active', 'label': 'Active', 'color': AppTheme.primary},
    ];
    return Row(
      children: statuses.map((s) {
        final isSelected = _sessionStatus == s['value'];
        final color = s['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _sessionStatus = s['value'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withAlpha(30)
                    : const Color(0xFF0A1025),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? color.withAlpha(150)
                      : const Color(0xFF849495).withAlpha(80),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                s['label'] as String,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? color : const Color(0xFF6B7490),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesCtrl,
      maxLines: 2,
      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
      decoration: const InputDecoration(
        labelText: 'Notes',
        hintText: 'e.g. System failure, GPS lost, manual correction...',
      ),
    );
  }

  Widget _buildSaveButton() {
    final isOffline = !_isOnline;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveEntry,
        icon: _isSaving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF001A10),
                ),
              )
            : Icon(
                isOffline ? Icons.cloud_off_rounded : Icons.save_rounded,
                size: 18,
              ),
        label: Text(
          _isSaving
              ? 'Saving...'
              : isOffline
              ? 'Queue Entry (Offline)'
              : 'Save Entry',
          style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isOffline
              ? const Color(0xFFFF9500)
              : const Color(0xFFFF9500),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildRecentEntriesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(190),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF849495).withAlpha(100)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: Row(
                    children: [
                      CustomIconWidget(
                        iconName: 'history',
                        color: const Color(0xFFFF9500),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recent Manual Entries',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFdfe2f0),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _loadRecentEntries,
                        child: const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF6B7490),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  color: Color(0xFF3a494b),
                  height: 1,
                  thickness: 1,
                ),
                _loadingEntries
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    : _recentEntries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No manual entries yet.\nUse the form above to add records.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              color: const Color(0xFF6B7490),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentEntries.length,
                        separatorBuilder: (_, __) => const Divider(
                          color: Color(0xFF3a494b),
                          height: 1,
                          thickness: 1,
                          indent: 18,
                          endIndent: 18,
                        ),
                        itemBuilder: (context, index) {
                          final entry = _recentEntries[index];
                          final startedAt = DateTime.tryParse(
                            entry['started_at'] as String? ?? '',
                          );
                          final durationMins =
                              entry['duration_minutes'] as int? ?? 0;
                          final cost =
                              (entry['total_cost'] as num?)?.toDouble() ?? 0.0;
                          final trackCode =
                              entry['track_code'] as String? ?? '';
                          final trackName =
                              entry['track_name'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFF9500,
                                    ).withAlpha(25),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      trackCode,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFFFF9500),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trackName,
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFdfe2f0),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        startedAt != null
                                            ? DateFormat(
                                                'dd MMM yyyy',
                                              ).format(startedAt)
                                            : '—',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          color: const Color(0xFF6B7490),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${cost.toStringAsFixed(0)}',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                    Text(
                                      '${durationMins ~/ 60}h ${durationMins % 60}m',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 11,
                                        color: const Color(0xFF6B7490),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/offline_queue_service.dart';
import '../../services/project_manager.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';

// ─── NATRAX Other Service model ───────────────────────────────────────────────

enum ServiceInputType {
  perDay,    // in/out date → days × rate
  perQty,    // simple quantity field
  evCharger, // kWh input → kWh × rate
  deadWeight // in/out date + weight (tons) + bags count
}

class _NatraxService {
  final String code;
  final String name;
  final String unit;
  final double rate;
  final ServiceInputType inputType;
  const _NatraxService(this.code, this.name, this.unit, this.rate, this.inputType);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key});
  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen>
    with TickerProviderStateMixin {
  // Tab: 0 = Track Session, 1 = Other Services
  int _activeTab = 0;

  // ── Track Session fields ─────────────────────────────────────────────────
  final _formKey    = GlobalKey<FormState>();
  final _notesCtrl  = TextEditingController();
  final _hrsCtrl    = TextEditingController();
  final _minsCtrl   = TextEditingController();
  final _costCtrl   = TextEditingController();
  String _trackCode = 'T3W';
  String _trackName = 'T3 Wet Braking Track';
  DateTime _date    = DateTime.now();
  TimeOfDay _start  = TimeOfDay.now();
  TimeOfDay _end    = TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: TimeOfDay.now().minute);
  String _status    = 'completed';
  bool _savingTrack = false;

  // ── Other Services fields ────────────────────────────────────────────────
  final Map<String, int>      _svcQty     = {}; // perQty → count/units
  final Map<String, DateTime> _svcInDate  = {}; // perDay → in date
  final Map<String, DateTime> _svcOutDate = {}; // perDay → out date
  final Map<String, double>   _svcKwh     = {}; // evCharger → kWh
  final Map<String, double>   _svcTons    = {}; // deadWeight → tons
  final Map<String, int>      _svcBags    = {}; // deadWeight → no. of bags
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _kwhControllers = {};
  final Map<String, TextEditingController> _tonsControllers = {};
  final Map<String, TextEditingController> _bagsControllers = {};
  DateTime _svcDate = DateTime.now();
  String _svcProject = 'Mahindra EV PoC';
  bool _savingSvc = false;

  // ── Offline / connectivity ────────────────────────────────────────────────
  bool _isOnline = true;
  int _pendingCount = 0;
  StreamSubscription<List<QueuedEntry>>? _queueSub;

  // ── Recent entries ────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _recentEntries = [];
  bool _loadingEntries = true;

  // ── NATRAX tracks ─────────────────────────────────────────────────────────
  static const _tracks = [
    {'code': 'T3W',  'name': 'T3 Wet Braking Track',     'rate': 21000.0, 'minHrs': 2.0},
    {'code': 'T3D',  'name': 'T3 Dry Braking Track',     'rate': 19000.0, 'minHrs': 2.0},
    {'code': 'T1',   'name': 'High Speed Track',          'rate': 25000.0, 'minHrs': 2.0},
    {'code': 'T2',   'name': 'Dynamic Platform Track',    'rate': 25000.0, 'minHrs': 2.0},
    {'code': 'T7',   'name': 'Handling Track 4W (1.6km)', 'rate': 18000.0, 'minHrs': 2.0},
    {'code': 'T8',   'name': 'Gradient Track',            'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T9',   'name': 'Noise Track',               'rate': 20000.0, 'minHrs': 1.0},
    {'code': 'T10',  'name': 'Wet Skid Pad',              'rate': 18000.0, 'minHrs': 1.0},
    {'code': 'T11',  'name': 'Comfort Track',             'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T12',  'name': 'Fatigue Track',             'rate': 20000.0, 'minHrs': 2.0},
    {'code': 'T13',  'name': 'Gravel & Off-Road Track',   'rate': 15000.0, 'minHrs': 1.0},
  ];

  // ── NATRAX Other Services (from rate card) ────────────────────────────────
  static const _services = [
    _NatraxService('WORKSHOP', 'Continuous Workshop Flat Rate', 'Per Day',     5000,  ServiceInputType.perDay),
    _NatraxService('S01',  'Weigh Bridge',                      'Per Test',    1100,  ServiceInputType.perQty),
    _NatraxService('S02',  'Weighing Pads',                     'Per Test',     600,  ServiceInputType.perQty),
    _NatraxService('S03',  'Small Workshop 2-9',                'Per Day',     9000,  ServiceInputType.perDay),
    _NatraxService('S04',  'FAT.3 Workshop',                    'Per Day',     6000,  ServiceInputType.perDay),
    _NatraxService('S05',  'Dust Tunnel Test DTT-001',          'Per Test',   26000,  ServiceInputType.perQty),
    _NatraxService('S06',  'Big Conference Hall',               'Per Day',    11000,  ServiceInputType.perDay),
    _NatraxService('S07',  'Unskilled Labour',                  'Per Day',     1100,  ServiceInputType.perDay),
    _NatraxService('S08',  'Refreshment / Lunch',               'Per Nos',      125,  ServiceInputType.perQty),
    _NatraxService('S09',  'Electricity Charges',               'Per Unit',      15,  ServiceInputType.perQty),
    _NatraxService('S10',  'Universal EV Charger',              'Per kWh',       25,  ServiceInputType.evCharger),
    _NatraxService('S11',  'Dead Weight',                       'Per Ton/Day',  200,  ServiceInputType.deadWeight),
    _NatraxService('S12',  'JCB Hiring',                        'Per Hour',    1200,  ServiceInputType.perQty),
    _NatraxService('S13',  'Sand Bags 20/50kg',                 'Per Nos/Day',  150,  ServiceInputType.perDay),
    _NatraxService('S14',  'Vbox Battery Hiring',               'Per Day',     1000,  ServiceInputType.perDay),
    _NatraxService('S15',  'Vbox 3i Hiring',                    'Per Day',    27000,  ServiceInputType.perDay),
  ];

  final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _svcProject = ProjectManager.instance.activeProject;
    _initOffline();
    _loadRecentEntries();
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _notesCtrl.dispose(); _hrsCtrl.dispose();
    _minsCtrl.dispose();  _costCtrl.dispose();
    for (final c in _qtyControllers.values)  c.dispose();
    for (final c in _kwhControllers.values)  c.dispose();
    for (final c in _tonsControllers.values) c.dispose();
    for (final c in _bagsControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _initOffline() async {
    await OfflineQueueService.instance.initialize();
    _isOnline     = OfflineQueueService.instance.isOnline;
    _pendingCount = await OfflineQueueService.instance.getPendingCount();
    if (mounted) setState(() {});
    _queueSub = OfflineQueueService.instance.queueStream.listen((entries) async {
      if (mounted) {
        setState(() {
          _pendingCount = entries.length;
          _isOnline = OfflineQueueService.instance.isOnline;
        });
        if (entries.isEmpty) _loadRecentEntries();
      }
    });
  }

  Future<void> _loadRecentEntries() async {
    setState(() => _loadingEntries = true);
    try {
      final data = await SupabaseService.instance.client
          .from('engineer_sessions')
          .select()
          .ilike('notes', 'Manual entry%')
          .order('started_at', ascending: false)
          .limit(10);
      if (mounted) setState(() {
        _recentEntries = List<Map<String, dynamic>>.from(data as List);
        _loadingEntries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  // ── Track session helpers ─────────────────────────────────────────────────

  void _recalcCost() {
    final hrs  = int.tryParse(_hrsCtrl.text)  ?? 0;
    final mins = int.tryParse(_minsCtrl.text) ?? 0;
    final totalMins = hrs * 60 + mins;
    if (totalMins <= 0) { _costCtrl.text = ''; return; }

    final track  = _tracks.firstWhere((t) => t['code'] == _trackCode, orElse: () => _tracks.first);
    final rate   = (track['rate'] as double);
    final minHrs = (track['minHrs'] as double);
    double hours = totalMins / 60.0;
    if (hours < minHrs) hours = minHrs;
    _costCtrl.text = (hours * rate).toStringAsFixed(0);
  }

  void _recalcFromTime() {
    final s = _start.hour * 60 + _start.minute;
    final e = _end.hour   * 60 + _end.minute;
    final diff = e - s;
    if (diff > 0) {
      _hrsCtrl.text  = (diff ~/ 60).toString();
      _minsCtrl.text = (diff % 60).toString();
    }
    _recalcCost();
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context, initialDate: _date,
      firstDate: DateTime(2020), lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9500), surface: Color(0xFF0A1025))),
        child: child!,
      ),
    );
    if (p != null) setState(() => _date = p);
  }

  Future<void> _pickSvcDate() async {
    final p = await showDatePicker(
      context: context, initialDate: _svcDate,
      firstDate: DateTime(2020), lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9500), surface: Color(0xFF0A1025))),
        child: child!,
      ),
    );
    if (p != null) setState(() => _svcDate = p);
  }

  Future<void> _pickTime(bool isStart) async {
    final p = await showTimePicker(
      context: context, initialTime: isStart ? _start : _end,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9500), surface: Color(0xFF0A1025))),
        child: child!,
      ),
    );
    if (p != null) setState(() { if (isStart) _start = p; else _end = p; _recalcFromTime(); });
  }

  Future<void> _saveTrackEntry() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final hrs  = int.tryParse(_hrsCtrl.text)  ?? 0;
    final mins = int.tryParse(_minsCtrl.text) ?? 0;
    final totalMins = hrs * 60 + mins;
    if (totalMins <= 0) { _snack('Duration must be > 0', error: true); return; }
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '')) ?? 0.0;
    setState(() => _savingTrack = true);
    try {
      final user = EngineerAuthService.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      final startedAt = DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);
      final endedAt   = startedAt.add(Duration(minutes: totalMins));
      final track     = _tracks.firstWhere((t) => t['code'] == _trackCode);
      final payload = {
        'engineer_id':    user.id,
        'track_code':     _trackCode,
        'track_name':     _trackName,
        'vehicle_category':'below_3_5t',
        'booking_type':   'standard',
        'session_status': _status,
        'started_at':     startedAt.toIso8601String(),
        'ended_at':       endedAt.toIso8601String(),
        'duration_minutes': totalMins,
        'hourly_rate':    (track['rate'] as double),
        'total_cost':     cost,
        'project_name':   ProjectManager.instance.activeProject,
        'notes': 'Manual entry${_notesCtrl.text.isNotEmpty ? ' — ${_notesCtrl.text}' : ''}',
      };
      if (_isOnline) {
        await SupabaseService.instance.client.from('engineer_sessions').insert(payload);
        _snack('Track session saved ✓');
        _loadRecentEntries();
        _resetTrackForm();
      } else {
        await OfflineQueueService.instance.enqueue(payload);
        _pendingCount = await OfflineQueueService.instance.getPendingCount();
        setState(() {});
        _snack('Queued — will sync when online', warning: true);
      }
    } catch (_) {
      _snack('Failed to save. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _savingTrack = false);
    }
  }

  void _resetTrackForm() {
    _notesCtrl.clear(); _hrsCtrl.clear(); _minsCtrl.clear(); _costCtrl.clear();
    setState(() {
      _trackCode = 'T3W'; _trackName = 'T3 Wet Braking Track';
      _date = DateTime.now(); _status = 'completed';
      _start = TimeOfDay.now();
      _end   = TimeOfDay(hour: (TimeOfDay.now().hour + 1) % 24, minute: TimeOfDay.now().minute);
    });
  }

  // ── Other Services save ───────────────────────────────────────────────────

  double _calcServiceTotal(_NatraxService s) {
    switch (s.inputType) {
      case ServiceInputType.perQty:
        return (_svcQty[s.code] ?? 0) * s.rate;
      case ServiceInputType.perDay:
        final inD  = _svcInDate[s.code];
        final outD = _svcOutDate[s.code];
        if (inD == null || outD == null) return 0;
        final days = outD.difference(inD).inDays + 1;
        if (days <= 0) return 0;
        // For sand bags: qty (nos) × days × rate
        if (s.code == 'S13') {
          return (_svcQty[s.code] ?? 1) * days * s.rate;
        }
        return days * s.rate;
      case ServiceInputType.evCharger:
        return (_svcKwh[s.code] ?? 0) * s.rate;
      case ServiceInputType.deadWeight:
        final inD  = _svcInDate[s.code];
        final outD = _svcOutDate[s.code];
        if (inD == null || outD == null) return 0;
        final days = outD.difference(inD).inDays + 1;
        final tons = _svcTons[s.code] ?? 0;
        return tons * days * s.rate;
    }
  }

  bool _isServiceSelected(_NatraxService s) {
    switch (s.inputType) {
      case ServiceInputType.perQty:   return (_svcQty[s.code] ?? 0) > 0;
      case ServiceInputType.perDay:   return _svcInDate[s.code] != null && _svcOutDate[s.code] != null;
      case ServiceInputType.evCharger: return (_svcKwh[s.code] ?? 0) > 0;
      case ServiceInputType.deadWeight: return _svcInDate[s.code] != null && _svcOutDate[s.code] != null && (_svcTons[s.code] ?? 0) > 0;
    }
  }

  double get _svcGrandTotal => _services.fold(0.0, (sum, s) => sum + _calcServiceTotal(s));

  List<_NatraxService> get _selectedServices =>
      _services.where((s) => _isServiceSelected(s)).toList();

  Future<void> _saveServices() async {
    if (_selectedServices.isEmpty) { _snack('Select at least one service', error: true); return; }
    setState(() => _savingSvc = true);
    try {
      final user = EngineerAuthService.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      // Create a container session for these services
      final startedAt = DateTime(_svcDate.year, _svcDate.month, _svcDate.day, 8, 0);
      final sessionResp = await SupabaseService.instance.client
          .from('engineer_sessions')
          .insert({
            'engineer_id':     user.id,
            'track_code':      'MISC',
            'track_name':      'Other Services',
            'vehicle_category':'below_3_5t',
            'booking_type':    'standard',
            'session_status':  'completed',
            'started_at':      startedAt.toIso8601String(),
            'ended_at':        startedAt.toIso8601String(),
            'duration_minutes': 0,
            'hourly_rate':     0.0,
            'total_cost':      0.0,
            'project_name':    _svcProject,
            'notes':           'Other Services Log — Manual Entry',
          })
          .select('id')
          .single();
      final sessionId = sessionResp['id'] as String;
      // Insert each selected service with correct quantity & notes
      final svcRows = _selectedServices.map((s) {
        final total = _calcServiceTotal(s);
        double qty = 0;
        String notes = '';
        switch (s.inputType) {
          case ServiceInputType.perQty:
            qty = (_svcQty[s.code] ?? 0).toDouble();
            break;
          case ServiceInputType.perDay:
            final inD = _svcInDate[s.code]!;
            final outD = _svcOutDate[s.code]!;
            qty = (outD.difference(inD).inDays + 1).toDouble();
            notes = '${DateFormat('dd MMM').format(inD)} – ${DateFormat('dd MMM yyyy').format(outD)}';
            if (s.code == 'S13') { // Sand bags: store nos as qty2
              notes = '${_svcQty[s.code] ?? 1} bags/day · $notes';
            }
            break;
          case ServiceInputType.evCharger:
            qty = _svcKwh[s.code] ?? 0;
            notes = '${qty.toStringAsFixed(1)} kWh × ₹${s.rate.toStringAsFixed(0)}/unit';
            break;
          case ServiceInputType.deadWeight:
            final inD = _svcInDate[s.code]!;
            final outD = _svcOutDate[s.code]!;
            final days = outD.difference(inD).inDays + 1;
            final tons = _svcTons[s.code] ?? 0;
            qty = tons * days;
            final bags = _svcBags[s.code] ?? 0;
            notes = '${tons.toStringAsFixed(1)} tons × $days days${bags > 0 ? ' · $bags bags' : ''}';
            break;
        }
        return {
          'session_id':   sessionId,
          'service_name': s.name,
          'quantity':     qty,
          'unit_rate':    s.rate,
          'total_cost':   total,
          'notes':        notes,
        };
      }).toList();
      await SupabaseService.instance.client
          .from('session_additional_services')
          .insert(svcRows);
      _snack('${_selectedServices.length} services saved ✓ · ${_inr.format(_svcGrandTotal)}');
      setState(() {
        _svcQty.clear(); _svcInDate.clear(); _svcOutDate.clear();
        _svcKwh.clear(); _svcTons.clear(); _svcBags.clear();
        for (final c in _kwhControllers.values)  c.clear();
        for (final c in _tonsControllers.values) c.clear();
        for (final c in _bagsControllers.values) c.clear();
      });
    } catch (e) {
      _snack('Failed: ${e.toString()}', error: true);
    } finally {
      if (mounted) setState(() => _savingSvc = false);
    }
  }

  void _snack(String msg, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    Color bg = AppTheme.success;
    if (error)   bg = AppTheme.error;
    if (warning) bg = const Color(0xFFFF9500);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.spaceGrotesk(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  Color _getTrackColor(String code) {
    if (code.startsWith('T1') && code == 'T1') return const Color(0xFF00F3FF); // Cyan
    if (code.startsWith('T2')) return const Color(0xFFFFB547); // Amber
    if (code.startsWith('T3')) return const Color(0xFFFF4D6A); // Crimson
    if (code.startsWith('T7')) return const Color(0xFFA855F7); // Purple
    if (code.startsWith('T8')) return const Color(0xFF10B981); // Emerald
    if (code.startsWith('T10')) return const Color(0xFF3B82F6); // Blue
    return const Color(0xFFFF9500); // Default orange
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background ambient glows for added color appeal
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 480,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFB547).withOpacity(0.12), // Amber glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: Container(
              width: 400,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00F3FF).withOpacity(0.12), // Cyan glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 250,
            right: -100,
            child: Container(
              width: 350,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFA855F7).withOpacity(0.10), // Purple glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(children: [
              _buildTopBar(),
              _buildTabSwitcher(),
              _buildConnBanner(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1000;
                    return _activeTab == 0
                        ? _buildTrackTab(isWide)
                        : _buildServicesTab(isWide);
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFF9500).withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF9500).withAlpha(70)),
          ),
          child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFF9500), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Manual Entry', style: GoogleFonts.spaceGrotesk(
              fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFFdfe2f0))),
          Text('Log track sessions & NATRAX services',
              style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF6B7490))),
        ])),
        Image.asset(
          'assets/images/goodyear_sightline_logo.png',
          height: 18,
          color: Colors.white70,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 12),
        // Connectivity dot
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isOnline ? AppTheme.success : const Color(0xFFFF9500),
          ),
        ),
      ]),
    );
  }

  // ── Tab switcher ───────────────────────────────────────────────────────────

  Widget _buildTabSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(200),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF849495).withAlpha(80)),
        ),
        child: Row(children: [
          _tabBtn(0, Icons.timer_outlined, 'Track Session'),
          _tabBtn(1, Icons.miscellaneous_services_rounded, 'Other Services'),
        ]),
      ),
    );
  }

  Widget _tabBtn(int idx, IconData icon, String label) {
    final active = _activeTab == idx;

    // Choose distinct premium gradients for active tabs
    final activeGradient = idx == 0
        ? const LinearGradient(
            colors: [Color(0xFF00F3FF), Color(0xFF08B5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [Color(0xFFFFB547), Color(0xFFFF9500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            gradient: active ? activeGradient : null,
            color: active ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: (idx == 0 ? const Color(0xFF00F3FF) : const Color(0xFFFF9500)).withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15,
                color: active ? Colors.black : const Color(0xFF6B7490)),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.spaceGrotesk(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: active ? Colors.black : const Color(0xFF6B7490))),
          ]),
        ),
      ),
    );
  }

  // ── Connectivity banner ───────────────────────────────────────────────────

  Widget _buildConnBanner() {
    if (_isOnline && _pendingCount == 0) return const SizedBox.shrink();
    final color = _isOnline ? const Color(0xFFFF9500) : const Color(0xFFFF3B30);
    final msg   = !_isOnline
        ? 'Offline — entries will be queued'
        : '$_pendingCount entr${_pendingCount == 1 ? 'y' : 'ies'} pending sync';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(20), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(children: [
          Icon(!_isOnline ? Icons.wifi_off_rounded : Icons.cloud_upload_outlined,
              color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(msg,
              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: color))),
        ]),
      ),
    );
  }

  // ── Track Session tab ─────────────────────────────────────────────────────

  double get _trackBaseCost => double.tryParse(_costCtrl.text.replaceAll(',', '')) ?? 0.0;

  Widget _buildTrackTab(bool isWide) {
    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTrackSelectionCard(),
                      const SizedBox(height: 12),
                      _buildDateTimeCard(),
                      const SizedBox(height: 12),
                      _buildDurationCostCard(),
                      const SizedBox(height: 12),
                      _buildStatusNotesCard(),
                      if (!_loadingEntries && _recentEntries.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildRecentEntriesCard(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 380,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildTrackCheckoutCard(),
              ),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 650),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTrackSelectionCard(),
                  const SizedBox(height: 12),
                  _buildDateTimeCard(),
                  const SizedBox(height: 12),
                  _buildDurationCostCard(),
                  const SizedBox(height: 12),
                  _buildStatusNotesCard(),
                  const SizedBox(height: 16),
                  _buildTrackSaveButton(),
                  if (!_loadingEntries && _recentEntries.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildRecentEntriesCard(),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildServicesTab(bool isWide) {
    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _buildServicesHeaderCard(false),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 40),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _services.length,
                      itemBuilder: (_, i) => _buildServiceRow(_services[i]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 380,
              child: _buildServicesCheckoutCard(),
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(children: [
            _buildServicesHeaderCard(true),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                physics: const BouncingScrollPhysics(),
                itemCount: _services.length,
                itemBuilder: (_, i) => _buildServiceRow(_services[i]),
              ),
            ),
            _buildServicesSubmitButton(inCard: false),
          ]),
        ),
      );
    }
  }

  Widget _buildServiceRow(_NatraxService s) {
    final selected = _isServiceSelected(s);
    final total    = _calcServiceTotal(s);
    final accent   = s.inputType == ServiceInputType.evCharger
        ? const Color(0xFF4CAF50)
        : s.inputType == ServiceInputType.deadWeight
            ? const Color(0xFFA855F7)
            : const Color(0xFFFF9500);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(15) : const Color(0xFF0A1025).withAlpha(180),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent.withAlpha(120) : Colors.white.withAlpha(10),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row: name + rate + total
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.white70)),
              Row(children: [
                Text('₹${s.rate.toStringAsFixed(0)}',
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: accent)),
                Text(' · ${s.unit}',
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF6B7490))),
              ]),
            ])),
            if (selected && total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4CAF50).withAlpha(60)),
                ),
                child: Text(_inr.format(total),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, fontWeight: FontWeight.w800,
                        color: const Color(0xFF4CAF50))),
              ),
          ]),

          const SizedBox(height: 12),

          // Input area based on type
          switch (s.inputType) {
            ServiceInputType.perQty    => _buildQtyInput(s, accent),
            ServiceInputType.perDay    => _buildDateRangeInput(s, accent),
            ServiceInputType.evCharger => _buildEvChargerInput(s),
            ServiceInputType.deadWeight=> _buildDeadWeightInput(s),
          },
        ]),
      ),
    );
  }

  // ── Per-Qty input (stepper + text field) ─────────────────────────────────

  Widget _buildQtyInput(_NatraxService s, Color accent) {
    final qty = _svcQty[s.code] ?? 0;
    return Row(children: [
      _stepBtn(Icons.remove_rounded, qty > 0 ? () => setState(() {
        if (qty > 1) _svcQty[s.code] = qty - 1; else _svcQty.remove(s.code);
      }) : null),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('$qty', style: GoogleFonts.spaceGrotesk(
            fontSize: 18, fontWeight: FontWeight.w800,
            color: qty > 0 ? accent : const Color(0xFF4A5470))),
      ),
      _stepBtn(Icons.add_rounded, () => setState(() {
        _svcQty[s.code] = qty + 1;
      }), isPrimary: true, accent: accent),
      const SizedBox(width: 10),
      Text(s.unit, style: GoogleFonts.spaceGrotesk(
          fontSize: 11, color: const Color(0xFF6B7490))),
    ]);
  }

  // ── Per-Day input (in/out date) ────────────────────────────────────────────

  Widget _buildDateRangeInput(_NatraxService s, Color accent) {
    final inD  = _svcInDate[s.code];
    final outD = _svcOutDate[s.code];
    int days = 0;
    if (inD != null && outD != null) {
      days = outD.difference(inD).inDays + 1;
    }
    final showNos = s.code == 'S13'; // Sand Bags: also ask for Nos/Day
    final nos = _svcQty[s.code] ?? 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _dateTap(
          label: inD != null ? 'In: ${DateFormat('dd MMM').format(inD)}' : 'In Date',
          icon: Icons.login_rounded,
          onTap: () async {
            final p = await _pickSvcDate2();
            if (p != null) setState(() => _svcInDate[s.code] = p);
          },
          selected: inD != null,
        )),
        const SizedBox(width: 8),
        Expanded(child: _dateTap(
          label: outD != null ? 'Out: ${DateFormat('dd MMM').format(outD)}' : 'Out Date',
          icon: Icons.logout_rounded,
          onTap: () async {
            final p = await _pickSvcDate2(first: inD);
            if (p != null) setState(() => _svcOutDate[s.code] = p);
          },
          selected: outD != null,
        )),
        if (days > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$days day${days == 1 ? '' : 's'}',
                style: GoogleFonts.spaceGrotesk(fontSize: 11,
                    fontWeight: FontWeight.w700, color: accent)),
          ),
        ],
      ]),
      if (showNos) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF6B7490)),
          const SizedBox(width: 6),
          Text('Bags per day:', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490))),
          const SizedBox(width: 10),
          _stepBtn(Icons.remove_rounded, nos > 1 ? () => setState(() => _svcQty[s.code] = nos - 1) : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('$nos', style: GoogleFonts.spaceGrotesk(
                fontSize: 15, fontWeight: FontWeight.w800, color: accent)),
          ),
          _stepBtn(Icons.add_rounded, () => setState(() => _svcQty[s.code] = nos + 1),
              isPrimary: true, accent: accent),
        ]),
      ],
    ]);
  }

  // ── EV Charger input (kWh) ────────────────────────────────────────────────

  Widget _buildEvChargerInput(_NatraxService s) {
    _kwhControllers.putIfAbsent(s.code, () => TextEditingController());
    final ctrl = _kwhControllers[s.code]!;
    return Row(children: [
      const Icon(Icons.electric_bolt_rounded, color: Color(0xFF4CAF50), size: 16),
      const SizedBox(width: 8),
      SizedBox(
        width: 120,
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700,
              color: const Color(0xFF4CAF50)),
          decoration: InputDecoration(
            hintText: '0.0',
            hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 13),
            suffixText: 'kWh',
            suffixStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 11),
            filled: true, fillColor: Colors.white.withAlpha(5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(15))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(15))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5)),
          ),
          onChanged: (v) => setState(() {
            final d = double.tryParse(v) ?? 0;
            if (d > 0) _svcKwh[s.code] = d; else _svcKwh.remove(s.code);
          }),
        ),
      ),
      const SizedBox(width: 10),
      Text('× ₹${s.rate.toStringAsFixed(0)}/kWh',
          style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490))),
    ]);
  }

  // ── Dead Weight input ─────────────────────────────────────────────────────

  Widget _buildDeadWeightInput(_NatraxService s) {
    _tonsControllers.putIfAbsent(s.code, () => TextEditingController());
    _bagsControllers.putIfAbsent(s.code, () => TextEditingController());
    final inD  = _svcInDate[s.code];
    final outD = _svcOutDate[s.code];
    int days = 0;
    if (inD != null && outD != null) days = outD.difference(inD).inDays + 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // In/Out dates
      Row(children: [
        Expanded(child: _dateTap(
          label: inD != null ? 'In: ${DateFormat('dd MMM').format(inD)}' : 'In Date',
          icon: Icons.login_rounded,
          onTap: () async {
            final p = await _pickSvcDate2();
            if (p != null) setState(() => _svcInDate[s.code] = p);
          },
          selected: inD != null,
        )),
        const SizedBox(width: 8),
        Expanded(child: _dateTap(
          label: outD != null ? 'Out: ${DateFormat('dd MMM').format(outD)}' : 'Out Date',
          icon: Icons.logout_rounded,
          onTap: () async {
            final p = await _pickSvcDate2(first: inD);
            if (p != null) setState(() => _svcOutDate[s.code] = p);
          },
          selected: outD != null,
        )),
        if (days > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFA855F7).withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$days day${days == 1 ? '' : 's'}',
                style: GoogleFonts.spaceGrotesk(fontSize: 11,
                    fontWeight: FontWeight.w700, color: const Color(0xFFA855F7))),
          ),
        ],
      ]),
      const SizedBox(height: 8),
      // Weight + Bags
      Row(children: [
        // Tons input
        SizedBox(
          width: 120,
          child: TextField(
            controller: _tonsControllers[s.code],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFA855F7)),
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 12),
              suffixText: 'Tons',
              suffixStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 10),
              filled: true, fillColor: Colors.white.withAlpha(5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withAlpha(15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withAlpha(15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFA855F7), width: 1.5)),
            ),
            onChanged: (v) => setState(() {
              final d = double.tryParse(v) ?? 0;
              if (d > 0) _svcTons[s.code] = d; else _svcTons.remove(s.code);
            }),
          ),
        ),
        const SizedBox(width: 12),
        // Bags input
        SizedBox(
          width: 130,
          child: TextField(
            controller: _bagsControllers[s.code],
            keyboardType: TextInputType.number,
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFF94A3B8)),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 12),
              suffixText: 'Bags',
              suffixStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 10),
              labelText: 'No. of Bags',
              labelStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 10),
              filled: true, fillColor: Colors.white.withAlpha(5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withAlpha(15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withAlpha(15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withAlpha(20), width: 1)),
            ),
            onChanged: (v) => setState(() {
              final n = int.tryParse(v) ?? 0;
              if (n > 0) _svcBags[s.code] = n; else _svcBags.remove(s.code);
            }),
          ),
        ),
      ]),
    ]);
  }

  // ── Date picker helper ────────────────────────────────────────────────────

  Future<DateTime?> _pickSvcDate2({DateTime? first}) async {
    return showDatePicker(
      context: context,
      initialDate: first ?? _svcDate,
      firstDate: first ?? DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF9500), surface: Color(0xFF0A1025))),
        child: child!,
      ),
    );
  }

  Widget _dateTap({required String label, required IconData icon,
      required VoidCallback onTap, bool selected = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF9500).withAlpha(18) : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFFF9500).withAlpha(100) : Colors.white.withAlpha(12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13,
              color: selected ? const Color(0xFFFF9500) : const Color(0xFF6B7490)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: GoogleFonts.spaceGrotesk(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF6B7490)),
              overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap,
      {bool isPrimary = false, Color? accent}) {
    final c = accent ?? const Color(0xFFFF9500);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.3 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: isPrimary ? c.withAlpha(30) : Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isPrimary ? c.withAlpha(80) : Colors.white.withAlpha(20)),
          ),
          child: Icon(icon, size: 16, color: isPrimary ? c : Colors.white54),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _card({required Widget child, EdgeInsets? margin, Color? accentColor}) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accentColor != null 
                    ? accentColor.withOpacity(0.35) 
                    : const Color(0xFF849495).withAlpha(80),
                width: accentColor != null ? 1.2 : 1.0,
              ),
              boxShadow: accentColor != null
                  ? [
                      BoxShadow(
                        color: accentColor.withOpacity(0.04),
                        blurRadius: 12,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: accentColor == null
                ? child
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accent line at the very top of the card
                      Container(
                        height: 2.5,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accentColor, accentColor.withOpacity(0.08)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                      child,
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _cardTitle(IconData icon, String title, Color color) {
    return Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withAlpha(25), borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
      const SizedBox(width: 10),
      Text(title, style: GoogleFonts.spaceGrotesk(
          fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFFdfe2f0))),
    ]);
  }

  Widget _timeTile(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(15)),
        ),
        child: Column(children: [
          Icon(icon, color: AppTheme.primary, size: 16),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.spaceGrotesk(
              fontSize: 9, fontWeight: FontWeight.w600, color: const Color(0xFFdfe2f0)),
              textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label, String suffix, void Function(String) onChange) {
    return TextFormField(
      controller: ctrl, keyboardType: TextInputType.number,
      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
      onChanged: onChange,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 12),
        suffixText: suffix,
        suffixStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 11),
        filled: true, fillColor: Colors.white.withAlpha(5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(15))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(15))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _statusChip(String val, String label, Color color) {
    final sel = _status == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _status = val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? color.withAlpha(35) : Colors.white.withAlpha(5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? color : Colors.white.withAlpha(12),
                width: sel ? 1.5 : 1),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: sel ? color : const Color(0xFF6B7490))),
        ),
      ),
    );
  }

  // ── Modular card components ───────────────────────────────────────────────

  Widget _buildTrackSelectionCard() {
    return _card(
      accentColor: const Color(0xFFFF9500),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.location_on_rounded, 'Track Selection', const Color(0xFFFF9500)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8,
          children: _tracks.map((t) {
            final sel = _trackCode == t['code'];
            final trackColor = _getTrackColor(t['code'] as String);
            return GestureDetector(
              onTap: () => setState(() {
                _trackCode = t['code'] as String;
                _trackName = t['name'] as String;
                _recalcCost();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? trackColor.withAlpha(35) : Colors.white.withAlpha(5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: sel ? trackColor : Colors.white.withAlpha(15),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['code'] as String, style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: sel ? trackColor : Colors.white70)),
                  Text(t['name'] as String, style: GoogleFonts.spaceGrotesk(
                      fontSize: 9, color: sel ? trackColor.withOpacity(0.8) : const Color(0xFF6B7490))),
                  Text('₹${(t['rate'] as double).toStringAsFixed(0)}/hr',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9, color: sel ? Colors.white70 : const Color(0xFF4A5470))),
                ]),
              ),
            );
          }).toList(),
        ),
      ]));
  }

  Widget _buildDateTimeCard() {
    return _card(
      accentColor: const Color(0xFF00F3FF),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.calendar_today_rounded, 'Date & Time', const Color(0xFF00F3FF)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _timeTile(Icons.calendar_month_outlined,
              DateFormat('dd MMM yyyy').format(_date), _pickDate)),
          const SizedBox(width: 8),
          Expanded(child: _timeTile(Icons.play_arrow_rounded,
              'Start: ${_start.format(context)}', () => _pickTime(true))),
          const SizedBox(width: 8),
          Expanded(child: _timeTile(Icons.stop_rounded,
              'End: ${_end.format(context)}', () => _pickTime(false))),
        ]),
      ]));
  }

  Widget _buildDurationCostCard() {
    return _card(
      accentColor: const Color(0xFF4CAF50),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.timer_rounded, 'Duration & Cost', const Color(0xFF4CAF50)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _numField(_hrsCtrl, 'Hours', 'hrs', (_) => _recalcCost())),
          const SizedBox(width: 10),
          Expanded(child: _numField(_minsCtrl, 'Minutes', 'min', (_) => _recalcCost())),
        ]),
        const SizedBox(height: 10),
        TextFormField(
          controller: _costCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700,
              color: const Color(0xFF4CAF50)),
          decoration: InputDecoration(
            labelText: 'Total Cost (excl. GST)',
            prefixText: '₹ ',
            prefixStyle: GoogleFonts.spaceGrotesk(
                fontSize: 14, color: const Color(0xFF4CAF50), fontWeight: FontWeight.w700),
            hintText: 'Auto-calculated',
            filled: true, fillColor: Colors.white.withAlpha(5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(15))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(15))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
        ),
      ]));
  }

  Widget _buildStatusNotesCard() {
    return _card(
      accentColor: const Color(0xFF4A9EFF),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.flag_rounded, 'Status & Notes', const Color(0xFF4A9EFF)),
        const SizedBox(height: 12),
        Row(children: [
          _statusChip('completed', 'Completed', const Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          _statusChip('warning',   'Warning',   const Color(0xFFFFB547)),
          const SizedBox(width: 8),
          _statusChip('active',    'Active',    const Color(0xFF00F3FF)),
        ]),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesCtrl, maxLines: 2,
          style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
          decoration: InputDecoration(
            hintText: 'e.g. System failure, GPS lost, correction reason...',
            hintStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF4A5470), fontSize: 12),
            filled: true, fillColor: Colors.white.withAlpha(5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(15))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(15))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF00F3FF), width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ]));
  }

  Widget _buildRecentEntriesCard() {
    return _card(
      accentColor: const Color(0xFF6B7490),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.history_rounded, 'Recent Manual Entries', const Color(0xFF6B7490)),
        const SizedBox(height: 12),
      ..._recentEntries.take(5).map((e) {
        final dt   = DateTime.tryParse(e['started_at'] as String? ?? '');
        final mins = e['duration_minutes'] as int? ?? 0;
        final cost = (e['total_cost'] as num?)?.toDouble() ?? 0.0;
        final code = e['track_code'] as String? ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(code,
                  style: GoogleFonts.spaceGrotesk(fontSize: 10,
                      fontWeight: FontWeight.w800, color: const Color(0xFFFF9500)))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['track_name'] as String? ?? '',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600,
                      color: Colors.white), overflow: TextOverflow.ellipsis),
              Text(dt != null ? DateFormat('dd MMM yyyy').format(dt) : '—',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${cost.toStringAsFixed(0)}',
                  style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
              Text('${mins ~/ 60}h ${mins % 60}m',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490))),
            ]),
          ]),
        );
      }),
    ]));
  }

  Widget _buildTrackCheckoutCard() {
    final track = _tracks.firstWhere((t) => t['code'] == _trackCode, orElse: () => _tracks.first);
    final rate = track['rate'] as double;
    final minHrs = track['minHrs'] as double;
    
    final hrs = int.tryParse(_hrsCtrl.text) ?? 0;
    final mins = int.tryParse(_minsCtrl.text) ?? 0;
    final durationHrs = hrs + (mins / 60.0);
    final isMinHrsEnforced = durationHrs > 0 && durationHrs < minHrs;
    
    final baseCost = _trackBaseCost;
    final gst = baseCost * 0.18;
    final totalCost = baseCost * 1.18;

    return _card(
      accentColor: const Color(0xFFFF9500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  'BOOKING SUMMARY',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: const Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NATRAX Estimate',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: const Color(0xFF6B7490),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          
          _receiptRow('Track', _trackCode, valueBold: true),
          const SizedBox(height: 8),
          _receiptRow('Track Name', _trackName, valueStyle: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 8),
          _receiptRow('Date', DateFormat('dd MMM yyyy').format(_date)),
          const SizedBox(height: 8),
          _receiptRow('Time Slot', '${_start.format(context)} - ${_end.format(context)}'),
          const SizedBox(height: 8),
          _receiptRow('Duration Entered', '${hrs}h ${mins}m'),
          const SizedBox(height: 8),
          _receiptRow('Hourly Rate', '₹${rate.toStringAsFixed(0)}/hr'),
          
          if (isMinHrsEnforced) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFF9500).withAlpha(40)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFFF9500), size: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Min booking of ${minHrs.toStringAsFixed(1)} hrs enforced.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFFFF9500), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          
          _receiptRow('Subtotal (Excl. GST)', _inr.format(baseCost)),
          const SizedBox(height: 8),
          _receiptRow('GST (18%)', _inr.format(gst)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF042D2A),
                  Color(0xFF021E20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00F3FF).withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F3FF).withOpacity(0.06),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Grand Total',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF00F3FF),
                  ),
                ),
                Text(
                  _inr.format(totalCost),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF00F3FF),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Text(
                'Status: ',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(_status).withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _status.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _statusColor(_status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildTrackSaveButton(),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '* Database saves Subtotal (Excl. GST)',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: const Color(0xFF4A5470),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed': return const Color(0xFF4CAF50);
      case 'warning': return const Color(0xFFFFB547);
      default: return AppTheme.primary;
    }
  }

  Widget _buildTrackSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _savingTrack ? null : _saveTrackEntry,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF9500),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: _savingTrack
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : const Icon(Icons.save_rounded, size: 18),
        label: Text(
          _savingTrack ? 'Saving...' : 'Save Track Session',
          style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool valueBold = false, TextStyle? valueStyle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            color: const Color(0xFF6B7490),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            style: valueStyle ?? GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildServicesHeaderCard(bool showSelectedSummary) {
    return _card(
      accentColor: const Color(0xFFFF9500),
      margin: showSelectedSummary ? const EdgeInsets.fromLTRB(16, 4, 16, 0) : EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.receipt_long_rounded, 'NATRAX Other Services', const Color(0xFFFF9500)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: _pickSvcDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_month_outlined, color: Color(0xFFFF9500), size: 15),
                const SizedBox(width: 8),
                Text(DateFormat('dd MMM yyyy').format(_svcDate),
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: Colors.white70)),
              ]),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _svcProject,
              isExpanded: true,
              dropdownColor: const Color(0xFF0A1025),
              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white70),
              items: ['Mahindra EV PoC', 'Mahindra ICE PoC', 'Hyundai PoC']
                  .map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) { if (v != null) setState(() => _svcProject = v); },
            )),
          )),
        ]),
        if (showSelectedSummary && _selectedServices.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4CAF50).withAlpha(60)),
            ),
            child: Row(children: [
              Text('${_selectedServices.length} services selected',
                  style: GoogleFonts.spaceGrotesk(color: const Color(0xFF4CAF50), fontSize: 11)),
              const Spacer(),
              Text(_inr.format(_svcGrandTotal),
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF4CAF50), fontSize: 14, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildServicesCheckoutCard() {
    final grandTotal = _svcGrandTotal;
    final gst = grandTotal * 0.18;
    final totalCost = grandTotal * 1.18;
    final selected = _selectedServices;

    return _card(
      accentColor: const Color(0xFFFF9500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  'SERVICES INVOICE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: const Color(0xFFFF9500),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NATRAX Estimate',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: const Color(0xFF6B7490),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          
          _receiptRow('Project', _svcProject, valueBold: true),
          const SizedBox(height: 6),
          _receiptRow('Date', DateFormat('dd MMM yyyy').format(_svcDate)),
          const SizedBox(height: 12),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          
          Text(
            'SELECTED ITEMS',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFFF9500),
            ),
          ),
          const SizedBox(height: 8),
          
          if (selected.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No services selected.\nSelect items from the left list.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    color: const Color(0xFF4A5470),
                  ),
                ),
              ),
            ),
          ] else ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: selected.length,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, idx) {
                  final s = selected[idx];
                  final total = _calcServiceTotal(s);
                  String qtyDesc = '';
                  switch (s.inputType) {
                    case ServiceInputType.perQty:
                      qtyDesc = 'Qty: ${_svcQty[s.code]}';
                      break;
                    case ServiceInputType.perDay:
                      final inD = _svcInDate[s.code]!;
                      final outD = _svcOutDate[s.code]!;
                      final days = outD.difference(inD).inDays + 1;
                      qtyDesc = '$days Days';
                      if (s.code == 'S13') {
                        qtyDesc = '${_svcQty[s.code] ?? 1} bags × $days days';
                      }
                      break;
                    case ServiceInputType.evCharger:
                      qtyDesc = '${_svcKwh[s.code]?.toStringAsFixed(1)} kWh';
                      break;
                    case ServiceInputType.deadWeight:
                      final inD = _svcInDate[s.code]!;
                      final outD = _svcOutDate[s.code]!;
                      final days = outD.difference(inD).inDays + 1;
                      qtyDesc = '${_svcTons[s.code]}T × $days days';
                      break;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                qtyDesc,
                                style: GoogleFonts.spaceGrotesk(fontSize: 9, color: const Color(0xFF6B7490)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _inr.format(total),
                          style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          
          const SizedBox(height: 12),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          
          _receiptRow('Subtotal (Excl. GST)', _inr.format(grandTotal)),
          const SizedBox(height: 8),
          _receiptRow('GST (18%)', _inr.format(gst)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF042D2A),
                  Color(0xFF021E20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00F3FF).withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00F3FF).withOpacity(0.06),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Grand Total',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF00F3FF),
                  ),
                ),
                Text(
                  _inr.format(totalCost),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF00F3FF),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          const DottedLine(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          
          _buildServicesSubmitButton(inCard: true),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '* Database saves Subtotal (Excl. GST)',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: const Color(0xFF4A5470),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesSubmitButton({bool inCard = false}) {
    final btn = ElevatedButton.icon(
      onPressed: (_savingSvc || _selectedServices.isEmpty) ? null : _saveServices,
      style: ElevatedButton.styleFrom(
        backgroundColor: _selectedServices.isEmpty
            ? Colors.white.withAlpha(15) : const Color(0xFFFF9500),
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      icon: _savingSvc
          ? const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : const Icon(Icons.save_rounded, size: 18),
      label: Text(
        _savingSvc
            ? 'Saving...'
            : _selectedServices.isEmpty
                ? 'Select services above'
                : 'Save ${_selectedServices.length} Service${_selectedServices.length == 1 ? '' : 's'} · ${_inr.format(_svcGrandTotal)}',
        style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );

    if (inCard) {
      return SizedBox(width: double.infinity, child: btn);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF050811).withAlpha(230),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(10))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: btn,
      ),
    );
  }
}

// ─── Dotted Line widget for receipt layout ───────────────────────────────────

class DottedLine extends StatelessWidget {
  final Color color;
  final double height;
  const DottedLine({super.key, this.color = Colors.white24, this.height = 1});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
              ),
            );
          }),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/excel_backup_downloader.dart';
import '../../services/offline_queue_service.dart';
import '../../services/project_catalog.dart';
import '../../services/project_manager.dart';
import '../../services/supabase_service.dart';
import '../../services/track_venue_catalog.dart';
import '../../services/venue_manager.dart';
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

  /// Already-booked minutes on the same track + date in the DB.
  /// Used to apply the minimum booking charge correctly across multiple entries.
  int _sameDayMinutes = 0;

  /// Already-booked cost (excl. GST) on the same track + date in the DB.
  /// Used to compute the incremental cost of a new entry.
  double _sameDayCost = 0.0;

  /// Whole billable hours already taken on the OTHER surface of the same
  /// track on this date - see [_minGroups]. Each surface rounds up on its
  /// own; this is the part of the day's minimum they have already covered
  /// between them, so it is counted in hours, not minutes.
  double _siblingCeilHours = 0.0;

  /// True while fetching the same-day total from Supabase.
  bool _loadingDayTotal = false;

  /// The programme this track session bills to.
  ///
  /// It used to be read straight off ProjectManager at save time with nothing
  /// on screen to say so, which meant an entry could be booked to whichever
  /// project happened to be selected elsewhere without the person entering it
  /// ever seeing which. It is now shown, and can be changed here.
  String _trackProject = 'Mahindra EV PoC';

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

  // ── Today's entries (all sessions on the selected date) ───────────────────
  /// All sessions saved for the current _date, shown in the sidebar so the
  /// user can see exactly what's been logged while making a new entry.
  List<Map<String, dynamic>> _todayEntries = [];
  bool _loadingTodayEntries = false;

  // ── NATRAX tracks ─────────────────────────────────────────────────────────
  // Which proving ground the entry is for. Defaults to NATRAX, where every
  // session logged so far ran.
  String _venueKey = TrackVenueCatalog.defaultVenueKey;

  TrackVenue get _venue => TrackVenueCatalog.resolve(_venueKey);

  /// Layouts for the selected venue.
  List<Map<String, dynamic>> get _tracks =>
      _venueKey == 'coastt' ? _coasttTracks : _natraxTracks;

  /// NATRAX rate card, reconciled line by line against real invoices:
  /// INV/26-27/205 (April 2026) and INV/26-27/388 (18-25 May 2026), both of
  /// which tie out to the rupee against BillingBaseline.
  ///
  /// Five rates here were wrong and are corrected below:
  ///
  ///   T2  Dynamic Platform   25,000 -> 20,000   (April and May invoices)
  ///   T7  4W Handling        18,000 -> 15,000   (April invoice)
  ///   T16 General Road       absent -> 9,000    (May invoice; was not listed)
  ///   T8  Comfort Track      15,000 -> 10,500   (May invoice, 23 May)
  ///   T11 Wet Skid Pad Track 10,500 -> 15,000   (May invoice, 19 and 20 May)
  ///
  /// T8 and T11 carried each other's rate AND each other's name. An earlier
  /// pass read the right rupee values off the May invoice - a 10,500 Comfort
  /// line and a 15,000 Wet Skid Pad line - but attached them to the wrong
  /// codes, because every imported March-May session was labelled at 25,000
  /// and could not be tied back to an invoice line. The workbook's Daily
  /// Track Billing sheet settles it, and `track_rates` in Supabase has said
  /// the same since the table was seeded:
  ///
  ///   23 May  T8   35 min  -> 1 Hr at 10,500   Comfort Track
  ///   19 May  T11  60 min  -> 1 Hr at 15,000   Wet Skid Pad Track
  ///   20 May  T11  30 min  -> 1 Hr at 15,000   Wet Skid Pad Track
  ///
  /// Those three lines are part of May's 1,73,500 of track charges, which
  /// ties to INV/26-27/388 exactly. T10 is renamed to match `track_rates`
  /// only so it stops colliding with T11 in the picker; its rate has never
  /// appeared on an invoice and is left alone.
  ///
  /// T3W 21,000, T3D 19,000 and T1 25,000 were already right. T3W billed
  /// 19,000 in March because March fell in FY 2025-26; the card below runs
  /// 1 April 2026 to 31 March 2027, so a March figure will not reconcile
  /// against it.
  ///
  /// T9, T12 and T13 have not appeared on any invoice yet, so their rates
  /// are still unverified and are left as they were.
  ///
  /// A day's usage on a track is summed, rounded UP to the whole hour, and
  /// then floored at `minHrs`. T1, T2, T3W and T3D carry a two-hour minimum;
  /// every other track bills from one hour.
  ///
  /// The split is read off the invoices, not assumed:
  ///
  ///   T3W  two-hour  - May bills 41 min and 60 min on separate days as 4 Hrs
  ///   T2   two-hour  - April bills 35 min on 9 Apr within a 5 Hrs total
  ///   T3D  two-hour  - per the programme owner; both braking tracks are
  ///                    two-hour bookings
  ///   T7   one-hour  - April bills a 30 min day as 1 Hr
  ///   T8   one-hour  - May bills a 35 min day as 1 Hr
  ///   T11  one-hour  - May bills a 30 min day as 1 Hr
  ///
  /// April's T3D days argue for one hour: 36, 49 and 50 minutes invoiced as
  /// 3 Hrs, where a two-hour minimum gives 6. That is still NOT adopted. The
  /// programme owner's position is that both braking tracks are booked on
  /// two-hour terms, and booking terms win over arithmetic. Reaffirmed
  /// 15 Sep 2026, with the T8/T11 mislabelling above now fixed - so this is a
  /// deliberate choice against clean data, no longer a doubt about the data.
  ///
  /// T9, T12 and T13 have not appeared on an invoice, so their minimums come
  /// from the programme owner rather than from arithmetic: T9 and T13 bill
  /// from one hour, T12 from two.
  static const _natraxTracks = [
    {'code': 'T3W',  'name': 'T3 Wet Braking Track',     'rate': 21000.0, 'minHrs': 2.0},
    {'code': 'T3D',  'name': 'T3 Dry Braking Track',     'rate': 19000.0, 'minHrs': 2.0},
    {'code': 'T1',   'name': 'High Speed Track',          'rate': 25000.0, 'minHrs': 2.0},
    {'code': 'T2',   'name': 'Dynamic Platform Track',    'rate': 20000.0, 'minHrs': 2.0},
    {'code': 'T7',   'name': 'Handling Track 4W (1.6km)', 'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T16',  'name': 'General Road Track',        'rate':  9000.0, 'minHrs': 1.0},
    {'code': 'T8',   'name': 'Comfort Track',             'rate': 10500.0, 'minHrs': 1.0},
    {'code': 'T9',   'name': 'Noise Track',               'rate': 20000.0, 'minHrs': 1.0},
    {'code': 'T10',  'name': 'Sustainability Track',      'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T11',  'name': 'Wet Skid Pad Track',        'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T12',  'name': 'Fatigue Track',             'rate': 20000.0, 'minHrs': 2.0},
    {'code': 'T13',  'name': 'Gravel & Off-Road Track',   'rate': 15000.0, 'minHrs': 1.0},
  ];

  /// Tracks that share ONE minimum between them on a given day.
  ///
  /// T3 Wet and T3 Dry are two surfaces of the same braking track, and NATRAX
  /// applies the two-hour minimum to the track once a day rather than to each
  /// surface. Invoice INV/26-27/205 settles it. April has exactly three dry
  /// days -- 7, 8 and 9 April, running 49, 36 and 50 minutes -- and wet ran on
  /// all three. The invoice bills:
  ///
  ///   Braking Track Testing - WET   34 Hrs at 21,000 = 7,14,000
  ///   Braking Track Testing - DRY    3 Hrs at 19,000 =   57,000
  ///
  /// Three dry days at 3 Hrs is one hour each: the ceiling of each day's own
  /// time, with no minimum of its own, because wet had already met the day's
  /// two hours. Charging each surface its own two-hour minimum gives 6 Hrs
  /// and Rs 1,14,000 -- double what was invoiced.
  ///
  /// Dry running ALONE still bills two hours; nothing in the data shows such
  /// a day, and the booking terms are unchanged.
  static const _minGroups = <String, List<String>>{
    'T3W': ['T3W', 'T3D'],
    'T3D': ['T3W', 'T3D'],
  };

  /// Every track code sharing this entry's day minimum, itself included.
  List<String> get _minGroupCodes => _minGroups[_trackCode] ?? [_trackCode];

  // CoASTT Coimbatore. Specs come from the CoASTT deck; rates are 0 because
  // that deck states none, and the summary reads "not recorded" rather than
  // printing the zero as though it were a price.
  static const _coasttTracks = [
    {'code': 'CO-INT', 'name': 'International Circuit',  'rate': 0.0, 'minHrs': 1.0},
    {'code': 'CO-NAT', 'name': 'National Circuit',       'rate': 0.0, 'minHrs': 1.0},
    {'code': 'CO-HND', 'name': 'Handling Circuit',       'rate': 0.0, 'minHrs': 1.0},
    {'code': 'CO-EV',  'name': 'EV Testing Track',       'rate': 0.0, 'minHrs': 1.0},
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
    _trackProject = ProjectManager.instance.activeProject;
    _initOffline();
    _loadRecentEntries();
    // Seed the day total for today + default track so the cost field is
    // correct from the moment the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSameDayMinutes());
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

  /// Loads every track session saved for [_date], regardless of track or
  /// whether it was a manual entry. Shown in the "Today's Entries" panel
  /// so the user can see the full picture at a glance while at the track.
  /// Remove a logged session, after confirming.
  ///
  /// Deleting changes what the rest of that day costs — the day's minutes drop,
  /// so it may round down to fewer billable hours and the remaining sessions
  /// are then over-charged between them. The app cannot silently rewrite rows
  /// the user did not ask it to touch, so this says plainly what is left and
  /// what it now ought to cost, and the user re-enters to settle it.
  Future<void> _confirmDeleteEntry(Map<String, dynamic> entry) async {
    final id = entry['id'] as String?;
    if (id == null) return;
    final code = entry['track_code'] as String? ?? '';
    final mins = entry['duration_minutes'] as int? ?? 0;
    final cost = (entry['total_cost'] as num? ?? 0).toDouble();
    final started = DateTime.tryParse(entry['started_at'] as String? ?? '');
    final slot = started == null ? '' : DateFormat('HH:mm').format(started);

    // What the day looks like once this one is gone.
    final track = _tracks.firstWhere((t) => t['code'] == code,
        orElse: () => _tracks.first);
    final rate = track['rate'] as double;
    final remainingMins = _sameDayMinutes - mins;
    final remainingDue = _ceilHours(remainingMins) * rate;
    final remainingBilled = _sameDayCost - cost;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1025),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete this session?',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$code  ·  $slot  ·  ${mins ~/ 60}h ${mins % 60}m  ·  '
              '${_inr.format(cost)}',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 12),
          if (remainingMins > 0)
            Text(
                '${_todayEntries.length - 1} session'
                '${_todayEntries.length - 1 == 1 ? '' : 's'} left on $code that '
                'day: ${remainingMins ~/ 60}h ${remainingMins % 60}m, which '
                'bills ${_ceilHours(remainingMins).toStringAsFixed(0)} hr at '
                '${_inr.format(remainingDue)}.'
                '${(remainingBilled - remainingDue).abs() < 1 ? '' : ' They '
                    'currently carry ${_inr.format(remainingBilled)} between '
                    'them, so re-enter them to settle the difference.'}',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFFFFB547), fontSize: 11, height: 1.4))
          else
            Text('Nothing else is logged on $code that day.',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490), fontSize: 11)),
          const SizedBox(height: 8),
          Text('This cannot be undone.',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490), fontSize: 10)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await SupabaseService.instance.client
          .from('engineer_sessions')
          .delete()
          .eq('id', id);
      _snack('Session deleted');
      // Refetch the day so the next entry's cost is computed against what is
      // actually left, not against the row just removed.
      await _fetchSameDayMinutes();
      _backUpAfterEntry();
    } catch (e) {
      _snack('Could not delete: $e', error: true);
    }
  }

  Future<void> _loadTodayEntries() async {
    setState(() => _loadingTodayEntries = true);
    try {
      final dayStart = DateTime(_date.year, _date.month, _date.day);
      final dayEnd   = dayStart.add(const Duration(days: 1));
      final data = await SupabaseService.instance.client
          .from('engineer_sessions')
          .select()
          .gte('started_at', dayStart.toIso8601String())
          .lt('started_at',  dayEnd.toIso8601String())
          .neq('track_code', 'MISC')   // exclude Other Services containers
          .order('started_at', ascending: true);
      if (mounted) setState(() {
        _todayEntries = List<Map<String, dynamic>>.from(data as List);
        _loadingTodayEntries = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTodayEntries = false);
    }
  }

  // ── Track session helpers ─────────────────────────────────────────────────

  /// Fetches already-booked minutes and cost on this track + date and then
  /// recomputes the cost for the current entry. Called whenever _date or
  /// _trackCode changes so the minimum-hours rule is applied per day, not
  /// per individual entry.
  Future<void> _fetchSameDayMinutes() async {
    setState(() => _loadingDayTotal = true);
    try {
      final dayStart = DateTime(_date.year, _date.month, _date.day);
      final dayEnd   = dayStart.add(const Duration(days: 1));
      final rows = await SupabaseService.instance.client
          .from('engineer_sessions')
          .select('track_code, duration_minutes, total_cost, project_name, venue')
          .inFilter('track_code', _minGroupCodes)
          .gte('started_at', dayStart.toIso8601String())
          .lt('started_at', dayEnd.toIso8601String());
      final list = List<Map<String, dynamic>>.from(rows as List);
      int totalMins  = 0;
      double totalCost = 0.0;
      // Minutes on the OTHER surface of the same track, kept per code so each
      // rounds up on its own before the day's shared minimum is tested.
      final siblingMins = <String, int>{};
      for (final r in list) {
        // The minimum is charged once per programme per track per day, not
        // once per track. Each PoC is invoiced separately, so letting one
        // programme's session satisfy another's minimum would make one
        // invoice quietly subsidise the other and neither would reconcile.
        if (!ProjectManager.sessionBelongsTo(
            r['project_name'] as String?, _trackProject)) {
          continue;
        }
        // track_code is unique per venue, not globally, so an unscoped match
        // would let a CoASTT layout sharing a code count towards a NATRAX day.
        final venue = (r['venue'] as String? ?? '').trim();
        if (venue.isNotEmpty && venue != _venue.dbValue) continue;
        final code = (r['track_code'] as String? ?? '').trim();
        final mins = (r['duration_minutes'] as int? ?? 0);
        if (code == _trackCode) {
          totalMins += mins;
          totalCost += (r['total_cost'] as num? ?? 0).toDouble();
        } else {
          siblingMins[code] = (siblingMins[code] ?? 0) + mins;
        }
      }
      final siblingHours =
          siblingMins.values.fold<double>(0.0, (s, m) => s + _ceilHours(m));
      if (mounted) {
        setState(() {
          _sameDayMinutes   = totalMins;
          _sameDayCost      = totalCost;
          _siblingCeilHours = siblingHours;
          _loadingDayTotal  = false;
        });
        _recalcCost();
        // Refresh the Today's Entries panel at the same time.
        _loadTodayEntries();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDayTotal = false);
    }
  }

  /// Computes the incremental cost for THIS entry, respecting the per-day
  /// minimum-hours rule across all sessions already saved for the same track
  /// and date.
  ///
  /// Logic:
  ///   dayTotal = _sameDayMinutes + thisEntryMins
  ///   billableDay = max(dayTotal, minHrs × 60)
  ///   thisCost = billableDay × rate/60 − _sameDayCost
  ///
  /// This ensures the minimum is only charged once per track per day.
  void _recalcCost() {
    final hrs  = int.tryParse(_hrsCtrl.text)  ?? 0;
    final mins = int.tryParse(_minsCtrl.text) ?? 0;
    final entryMins = hrs * 60 + mins;
    if (entryMins <= 0) { _costCtrl.text = ''; return; }

    final track   = _tracks.firstWhere((t) => t['code'] == _trackCode, orElse: () => _tracks.first);
    final rate    = (track['rate'] as double);
    final minHrs  = (track['minHrs'] as double);

    // NATRAX bills WHOLE HOURS, rounded up, per track per day. Verified
    // against invoice INV/26-27/205 (April 2026): 30.75 h of wet braking
    // across nine days invoiced as 34 Hrs, the sum of each day rounded up.
    //
    // Billing the fraction under-charged every part-hour day - 2.35 h was
    // quoted as Rs 49,350 where NATRAX will invoice 3 Hrs at Rs 63,000.
    //
    // The MINIMUM belongs to the group, not to this surface (see [_minGroups]).
    // Each surface rounds up on its own, and only the shortfall the group has
    // not already covered between them is added here. For a track with no
    // sibling this reduces to max(ceil(day), minHrs) - unchanged behaviour.
    //
    // Order caveat: if the sibling surface is entered AFTER this one, this
    // entry has already absorbed the shortfall and the day can come out an
    // hour long. The day total is what NATRAX invoices, so on a wet+dry day
    // enter whichever surface ran first, first.
    final dayTotalMins  = _sameDayMinutes + entryMins;
    final thisCeil      = _ceilHours(dayTotalMins);
    final groupCeil     = thisCeil + _siblingCeilHours;
    final shortfall     = math.max(0.0, minHrs - groupCeil);
    final billableHours = thisCeil + shortfall;

    // Incremental: what the whole day now costs, less what is already billed
    // for it. So the first entry of a day carries the rounding up and a later
    // one adds nothing until the day crosses into the next whole hour.
    final cost = billableHours * rate - _sameDayCost;
    _costCtrl.text = cost.clamp(0, double.infinity).toStringAsFixed(0);
  }

  /// Minutes to whole billable hours, always rounding up.
  ///
  /// Zero stays zero: a day with nothing logged has nothing to bill. One
  /// minute is an hour, which is the floor NATRAX charges.
  double _ceilHours(int minutes) =>
      minutes <= 0 ? 0 : (minutes / 60.0).ceilToDouble();

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
    if (p != null) {
      setState(() => _date = p);
      _fetchSameDayMinutes();
    }
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
        'venue':          _venue.dbValue,
        'vehicle_category':'below_3_5t',
        'booking_type':   'standard',
        'session_status': _status,
        'started_at':     startedAt.toIso8601String(),
        'ended_at':       endedAt.toIso8601String(),
        'duration_minutes': totalMins,
        'hourly_rate':    (track['rate'] as double),
        'total_cost':     cost,
        'project_name':   _trackProject,
        'notes': 'Manual entry${_notesCtrl.text.isNotEmpty ? ' — ${_notesCtrl.text}' : ''}',
      };
      if (_isOnline) {
        await SupabaseService.instance.client.from('engineer_sessions').insert(payload);
        _snack('Track session saved to $_trackProject ✓');
        _backUpAfterEntry();
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
    // Re-fetch the day total so the next entry already accounts for what was
    // just saved — the cost calculation must reflect the updated DB state.
    _fetchSameDayMinutes();
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

  /// Refresh the Excel backup as soon as an entry is saved.
  ///
  /// A manual entry is often the only record that the work happened, and the
  /// backup previously only moved when somebody remembered to open Settings —
  /// so the spreadsheet was routinely older than the entries it was supposed
  /// to protect.
  ///
  /// Deliberately not awaited by the save, and its failure is reported
  /// separately: the entry is already committed by the time this runs, and a
  /// failed download must never make a saved entry look unsaved.
  ///
  /// Web only. The download path hands bytes to the browser, which has no
  /// meaning on mobile; there the entry saves exactly as before.
  Future<void> _backUpAfterEntry() async {
    if (!kIsWeb) return;
    try {
      final name = await ExcelBackupDownloader.runAndSave();
      if (mounted) _snack('Backed up to $name');
    } catch (e) {
      if (mounted) {
        _snack('Entry saved. The backup did not download: $e', error: true);
      }
    }
  }

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
            'venue':           _venue.dbValue,
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
        double qty = 0;
        String notes = '';
        switch (s.inputType) {
          case ServiceInputType.perQty:
            qty = (_svcQty[s.code] ?? 0).toDouble();
            break;
          case ServiceInputType.perDay:
            final inD = _svcInDate[s.code]!;
            final outD = _svcOutDate[s.code]!;
            final days = outD.difference(inD).inDays + 1;
            qty = days.toDouble();
            notes = '${DateFormat('dd MMM').format(inD)} – ${DateFormat('dd MMM yyyy').format(outD)}';
            if (s.code == 'S13') {
              // NATRAX bills sand bags as BAG-DAYS, not days. INV/26-27/205
              // reads "Sand Bag Charges (Per Day), 75 Nos at 150" for the
              // 36 and 39 bags logged on 6 and 16 April. quantity must carry
              // that product, because total_cost is generated as
              // quantity * rate: leaving qty as the day count would have
              // billed 2 days x 150 = 300 where NATRAX charged 11,250.
              qty = ((_svcQty[s.code] ?? 1) * days).toDouble();
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
        // total_cost is NOT sent. It is a GENERATED column --
        // `GENERATED ALWAYS AS (quantity * rate) STORED` -- and Postgres
        // rejects any insert that names it: 428C9, "cannot insert a
        // non-DEFAULT value into column total_cost". That killed every
        // service line at the last step, after the rate/unit_rate fix had
        // already got it past PGRST204.
        //
        // Because the database multiplies, `quantity` has to be the full
        // billable quantity for every service, not a day count with the
        // real measure hidden in notes. Sand bags were the one case that
        // broke that rule; see the S13 branch above.
        return {
          'session_id':   sessionId,
          'service_name': s.name,
          'quantity':     qty,
          'rate':         s.rate,
          'notes':        notes,
        };
      }).toList();
      // The container session is created BEFORE the lines that give it
      // meaning, so a failed insert leaves an empty MISC session behind. It
      // then counts as a session on History for ever, at zero cost, with
      // nothing hanging off it. That is how Mahindra EV PoC came to show 47
      // sessions for 46 days of testing: one service save failed earlier
      // today and left its container.
      //
      // Deleted here rather than hidden on the screens. A MISC row that DOES
      // carry service lines is the only record of that accessory spend, and
      // both History and the PO Tracker read their costs through it -- filter
      // MISC out of those and the money disappears with it.
      try {
        await SupabaseService.instance.client
            .from('session_additional_services')
            .insert(svcRows);
      } catch (_) {
        try {
          await SupabaseService.instance.client
              .from('engineer_sessions')
              .delete()
              .eq('id', sessionId);
        } catch (_) {
          // Swallowed: the outer catch reports the failure that matters, and
          // a stray empty container is better than masking it.
        }
        rethrow;
      }
      _snack('${_selectedServices.length} services saved ✓ · ${_inr.format(_svcGrandTotal)}');
      _backUpAfterEntry();
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
                      _buildBookedToCard(),
                      const SizedBox(height: 12),
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
                child: Column(
                  children: [
                    _buildTrackCheckoutCard(),
                    const SizedBox(height: 12),
                    _buildTodayEntriesCard(),
                  ],
                ),
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
                  _buildBookedToCard(),
                  const SizedBox(height: 12),
                  _buildTrackSelectionCard(),
                  const SizedBox(height: 12),
                  _buildDateTimeCard(),
                  const SizedBox(height: 12),
                  _buildDurationCostCard(),
                  const SizedBox(height: 12),
                  _buildStatusNotesCard(),
                  const SizedBox(height: 16),
                  _buildTrackSaveButton(),
                  const SizedBox(height: 20),
                  _buildTodayEntriesCard(),
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

  /// Which programme this entry bills to.
  ///
  /// Deliberately the first card on the form. Track time is charged to a PoC,
  /// and an entry filed against the wrong one is only ever found later, in a
  /// reconciliation — so the answer is stated up front rather than inherited
  /// silently from whatever was last selected on another screen.
  Widget _buildBookedToCard() {
    const accent = Color(0xFF9C88FF);
    final programme = ProjectCatalog.byKey(_trackProject);
    final globalProject = ProjectManager.instance.activeProject;
    final differsFromGlobal = _trackProject != globalProject;

    return _card(
      accentColor: accent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.science_rounded, 'Booked To', accent),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withAlpha(90)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _trackProject,
              isExpanded: true,
              dropdownColor: const Color(0xFF0A1025),
              icon: const Icon(Icons.expand_more_rounded, color: accent, size: 18),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              items: ProjectCatalog.displayNames
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) {
                // The day total is now scoped to the programme, so changing
                // the programme changes which sessions count towards the
                // minimum — the cost has to be recomputed, not just relabelled.
                if (v != null) {
                  setState(() => _trackProject = v);
                  _fetchSameDayMinutes();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(
            programme?.powertrain.isIce ?? false
                ? Icons.local_fire_department_rounded
                : Icons.electric_bolt_rounded,
            size: 13,
            color: const Color(0xFF6B7490),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              programme == null
                  ? 'This session will be filed under $_trackProject.'
                  : 'This session will be filed under ${programme.displayName} '
                      '— ${programme.vehicle}.',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10.5, color: const Color(0xFF6B7490), height: 1.4),
            ),
          ),
        ]),
        if (differsFromGlobal) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB547).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFB547).withAlpha(70)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: Color(0xFFFFB547)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Not the project you have open ($globalProject). '
                  'The entry follows this card, not the open project.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: const Color(0xFFFFB547),
                      height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildTrackSelectionCard() {
    return _card(
      accentColor: const Color(0xFFFF9500),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.location_on_rounded, 'Track Selection', const Color(0xFFFF9500)),
        const SizedBox(height: 12),

        // Venue first: the track list depends on it, so choosing a track
        // before a venue would offer layouts from the wrong proving ground.
        Wrap(spacing: 8, runSpacing: 8,
          children: TrackVenueCatalog.bookable.map((v) {
            final sel = _venueKey == v.key;
            return GestureDetector(
              onTap: sel
                  ? null
                  : () {
                      setState(() {
                        _venueKey = v.key;
                        VenueManager.instance.setVenue(v.key);
                        // The old code belongs to the old venue, so reset to
                        // this one's first layout rather than leaving a
                        // NATRAX code selected under CoASTT.
                        final first = _tracks.first;
                        _trackCode = first['code'] as String;
                        _trackName = first['name'] as String;
                      });
                      _fetchSameDayMinutes();
                    },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFFFF9500).withAlpha(32)
                        : Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel
                          ? const Color(0xFFFF9500).withAlpha(160)
                          : Colors.white.withAlpha(28),
                      width: sel ? 1.4 : 1,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.place_outlined,
                        size: 13,
                        color: sel
                            ? const Color(0xFFFF9500)
                            : Colors.white54),
                    const SizedBox(width: 6),
                    Text(v.shortName,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: sel
                                ? const Color(0xFFFF9500)
                                : Colors.white70)),
                    if (v.ratesPending) ...[
                      const SizedBox(width: 6),
                      Text('rates pending',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white38)),
                    ],
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Text('${_venue.displayName} · ${_venue.location}',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10.5, color: Colors.white38)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8,
          children: _tracks.map((t) {
            final sel = _trackCode == t['code'];
            final trackColor = _getTrackColor(t['code'] as String);
            return GestureDetector(
              onTap: () {
                setState(() {
                  _trackCode = t['code'] as String;
                  _trackName = t['name'] as String;
                });
                _fetchSameDayMinutes();
              },
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
              // Which programme it went to. Without this the list cannot answer
              // the one question worth asking of a past entry — whether it was
              // booked to the right project.
              Text(
                  '${dt != null ? DateFormat('dd MMM yyyy').format(dt) : '—'}'
                  ' · ${ProjectCatalog.displayName(e['project_name'] as String?)}',
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF6B7490)),
                  overflow: TextOverflow.ellipsis),
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

  Widget _buildTodayEntriesCard() {
    final dateLabel = DateFormat('dd MMM yyyy').format(_date);
    final isToday = _date.year == DateTime.now().year &&
        _date.month == DateTime.now().month &&
        _date.day == DateTime.now().day;
    final title = isToday ? "Today's Entries" : 'Entries on $dateLabel';

    // Running totals across all sessions that day.
    int totalMins  = 0;
    double totalCost = 0.0;
    for (final e in _todayEntries) {
      totalMins  += (e['duration_minutes'] as int?  ?? 0);
      totalCost  += (e['total_cost']       as num? ?? 0).toDouble();
    }

    return _card(
      accentColor: const Color(0xFF00F3FF),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row with refresh button
        Row(children: [
          Icon(Icons.list_alt_rounded, color: const Color(0xFF00F3FF), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: const Color(0xFF00F3FF))),
          ),
          if (_loadingTodayEntries)
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFF00F3FF)),
            )
          else
            GestureDetector(
              onTap: _loadTodayEntries,
              child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF00F3FF), size: 16),
            ),
        ]),
        const SizedBox(height: 10),

        if (_loadingTodayEntries && _todayEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('Loading…',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: const Color(0xFF6B7490))),
            ),
          )
        else if (_todayEntries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Column(children: [
                Icon(Icons.inbox_rounded,
                    color: const Color(0xFF4A5470), size: 28),
                const SizedBox(height: 6),
                Text('No sessions logged for this date',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11, color: const Color(0xFF4A5470))),
              ]),
            ),
          )
        else ...[
          // One row per session
          ..._todayEntries.map((e) {
            final code     = e['track_code']  as String? ?? '';
            final name     = e['track_name']  as String? ?? '';
            final mins     = e['duration_minutes'] as int? ?? 0;
            final cost     = (e['total_cost'] as num? ?? 0).toDouble();
            final project  = e['project_name'] as String? ?? '';
            final startedAt = DateTime.tryParse(e['started_at'] as String? ?? '');
            final endedAt   = DateTime.tryParse(e['ended_at']   as String? ?? '');
            final timeSlot  = (startedAt != null && endedAt != null)
                ? '${DateFormat('HH:mm').format(startedAt)} – ${DateFormat('HH:mm').format(endedAt)}'
                : '—';
            final trackColor = _getTrackColor(code);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: trackColor.withAlpha(60)),
                ),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: trackColor.withAlpha(28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(code,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9, fontWeight: FontWeight.w900,
                              color: trackColor)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                      Text('$timeSlot  ·  ${mins ~/ 60}h ${mins % 60}m',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 10, color: const Color(0xFF6B7490))),
                      if (project.isNotEmpty)
                        Text(ProjectCatalog.displayName(project),
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 9, color: const Color(0xFF4A5470)),
                            overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹${cost.toStringAsFixed(0)}',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 12, fontWeight: FontWeight.w800,
                            color: const Color(0xFF00F3FF))),
                    Text('excl. GST',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 8, color: const Color(0xFF4A5470))),
                  ]),
                  // Delete, so a wrong entry can be removed and logged again.
                  // There is no edit: changing one session's duration changes
                  // how the whole day rounds, and therefore what every other
                  // session that day should carry. Deleting and re-entering
                  // makes the app recompute all of them from scratch, which
                  // an in-place edit would have to do by hand and could get
                  // subtly wrong.
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _confirmDeleteEntry(e),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 16, color: Colors.white.withAlpha(90)),
                    ),
                  ),
                ]),
              ),
            );
          }),

          // Day running total
          const DottedLine(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              'Day total  ${totalMins ~/ 60}h ${totalMins % 60}m · ${_todayEntries.length} session${_todayEntries.length == 1 ? '' : 's'}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: const Color(0xFF6B7490)),
            ),
            Text(
              '₹${totalCost.toStringAsFixed(0)}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w900,
                  color: const Color(0xFF00F3FF)),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _buildTrackCheckoutCard() {
    final track = _tracks.firstWhere((t) => t['code'] == _trackCode, orElse: () => _tracks.first);
    final rate = track['rate'] as double;

    final hrs = int.tryParse(_hrsCtrl.text) ?? 0;
    final mins = int.tryParse(_minsCtrl.text) ?? 0;
    final entryMins = hrs * 60 + mins;
    final dayTotalMins = _sameDayMinutes + entryMins;

    // Rounding is applied to the day total, not per entry. 'Already satisfied'
    // now means the day has whole hours banked that this entry can use before
    // it costs anything; 'enforced' means the day is being rounded up.
    final dayAlreadySatisfied = _sameDayMinutes > 0;
    final isMinHrsEnforced =
        entryMins > 0 && dayTotalMins % 60 != 0 && _sameDayMinutes == 0;

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
          
          _receiptRow('Project', _trackProject, valueBold: true),
          const SizedBox(height: 8),
          _receiptRow('Venue', _venue.shortName, valueBold: true),
          const SizedBox(height: 8),
          _receiptRow('Track', _trackCode, valueBold: true),
          const SizedBox(height: 8),
          _receiptRow('Track Name', _trackName, valueStyle: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 8),
          _receiptRow('Date', DateFormat('dd MMM yyyy').format(_date)),
          const SizedBox(height: 8),
          _receiptRow('Time Slot', '${_start.format(context)} - ${_end.format(context)}'),
          const SizedBox(height: 8),
          _receiptRow('Duration Entered', '${hrs}h ${mins}m'),

          // Show how much has already been logged today on this track.
          if (_sameDayMinutes > 0) ...[
            const SizedBox(height: 8),
            _receiptRow(
              'Day logged so far',
              _loadingDayTotal
                  ? '…'
                  : '${_sameDayMinutes ~/ 60}h ${_sameDayMinutes % 60}m on $_trackCode',
              valueStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: dayAlreadySatisfied
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFFFB547)),
            ),
          ],

          const SizedBox(height: 8),
          _receiptRow(
              'Hourly Rate',
              _venue.ratesPending
                  ? '— not recorded'
                  : '₹${rate.toStringAsFixed(0)}/hr'),

          // A venue with no rate card would otherwise price every session at
          // zero, which reads as billed rather than unpriced.
          if (_venue.ratesPending) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(24),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFFF59E0B).withAlpha(90)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFF59E0B), size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${_venue.shortName} has no rate card loaded. This '
                      'session saves with zero cost and will not appear in '
                      'billing totals until rates are entered.',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9.5,
                          height: 1.4,
                          color: const Color(0xFFF59E0B))),
                ),
              ]),
            ),
          ],

          // Minimum-hours notice — context-aware:
          //   • Green: minimum already met by earlier sessions today.
          //   • Amber: this entry (alone) triggers the minimum.
          if (entryMins > 0) ...[
            const SizedBox(height: 8),
            if (dayAlreadySatisfied)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF4CAF50).withAlpha(40)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF4CAF50), size: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Day already billed at ${_ceilHours(_sameDayMinutes).toStringAsFixed(0)} hr on $_trackCode — this entry adds only what crosses into the next whole hour.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF4CAF50), fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              )
            else if (isMinHrsEnforced)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500).withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFF9500).withAlpha(40)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFFF9500), size: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Day total ${dayTotalMins ~/ 60}h ${dayTotalMins % 60}m rounds up to ${_ceilHours(dayTotalMins).toStringAsFixed(0)} billable hrs — NATRAX bills whole hours.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFFFF9500), fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
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
              items: ProjectCatalog.displayNames
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

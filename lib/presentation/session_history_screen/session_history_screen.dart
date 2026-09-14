import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/day_note_service.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/muster_service.dart';
import '../../services/project_manager.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import './widgets/hero_metric_widget.dart';
import './widgets/monthly_summary_card_widget.dart';
import './widgets/session_chart_widget.dart';
import './widgets/session_list_widget.dart';

/// What a full-history row records. Track time and the two muster kinds are
/// funded and counted differently, so they stay distinguishable rather than
/// being flattened into one "entry".
enum _HistoryKind { track, manpower, workshop }

class _HistoryEntry {
  final DateTime date;
  final _HistoryKind kind;
  final String title;
  final String detail;

  /// Null where this screen cannot price the row honestly — a manpower day is
  /// worth its PO's day rate, which is not loaded here. Shown as an em dash
  /// rather than as zero, which would read as free.
  final double? amount;

  const _HistoryEntry({
    required this.date,
    required this.kind,
    required this.title,
    required this.detail,
    this.amount,
  });
}

// TODO: Replace with Riverpod/Bloc for production
class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Completed', 'This Week', 'High Cost'];

  List<Map<String, dynamic>> _sessionMaps = [];
  bool _isLoading = true;
  String _activeProject = '';

  /// Widen the register to every programme. Off by default — the screen is
  /// normally read one programme at a time — but without it there was no way
  /// to see the whole history at once, or to compare a gap in one programme
  /// against another without leaving the screen.
  bool _allProjects = false;

  /// Muster days in the current scope, for the full-history timeline.
  List<MusterDay> _musterDays = [];

  /// Why a day carries muster but no track session, keyed
  /// 'YYYY-MM-DD|project'. Empty until the day_notes migration is applied.
  Map<String, DayNote> _dayNotes = {};

  int _selectedPeriod = 0; // 0 = This Month, 1 = Last Month

  @override
  void initState() {
    super.initState();
    _activeProject = ProjectManager.instance.activeProject;
    ProjectManager.instance.addListener(_onProjectChanged);
    _loadSessions();
  }

  @override
  void dispose() {
    ProjectManager.instance.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted && _activeProject != ProjectManager.instance.activeProject) {
      setState(() => _activeProject = ProjectManager.instance.activeProject);
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final client = SupabaseService.instance.client;
      final sessions = await EngineerAuthService.instance.getMySessionHistory();
      final pm = ProjectManager.instance;
      final filtered = _allProjects
          ? sessions
          : sessions.where((s) => pm.sessionBelongsToProject(s.projectName)).toList();

      final sessionIds = filtered.map((s) => s.id).toList();
      List<dynamic> svcsRaw = [];
      if (sessionIds.isNotEmpty) {
        svcsRaw = await client
            .from('session_additional_services')
            .select('session_id, total_cost')
            .inFilter('session_id', sessionIds);
      }

      final Map<String, double> svcMap = {};
      for (final svc in svcsRaw) {
        final sid = svc['session_id'] as String;
        final c = (svc['total_cost'] as num?)?.toDouble() ?? 0.0;
        svcMap[sid] = (svcMap[sid] ?? 0) + c;
      }

      // The muster for the same scope, so the full history below can show
      // track time, manpower and workshop as one chronology. The sessions
      // list above stays month-pinned; this does not touch it.
      try {
        final days = await MusterService.instance.list();
        final musterDays = _allProjects
            ? days
            : days
                .where((d) => ProjectManager.sessionBelongsTo(
                    d.projectName, _activeProject))
                .toList();
        if (mounted) _musterDays = musterDays;
      } catch (_) {
        // An unreadable muster must not take the session history down.
        if (mounted) _musterDays = [];
      }
      // Returns empty rather than throwing if the table is not there yet.
      final notes = await DayNoteService.instance.byDay();
      if (mounted) _dayNotes = notes;

      final mapped = filtered
          .map(
            (s) => {
              'id': s.id,
              'gate': s.trackName,
              'trackType': s.trackCode,
              'engineer': '',
              'startTime': s.startedAt.toIso8601String(),
              'durationMinutes': s.durationMinutes ?? 0,
              'costINR': (s.totalCost ?? 0.0) + (svcMap[s.id] ?? 0.0),
              'hourlyRate': s.hourlyRate,
              'status': s.sessionStatus,
              'notes': s.notes ?? '',
            },
          )
          .toList();
      if (mounted) {
        setState(() {
          _sessionMaps = mapped;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    switch (_selectedFilter) {
      case 'Completed':
        return _sessionMaps.where((s) => s['status'] == 'completed').toList();
      case 'This Week':
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return _sessionMaps.where((s) {
          final start = DateTime.parse(s['startTime'] as String);
          return start.isAfter(weekStart);
        }).toList();
      case 'High Cost':
        return _sessionMaps
            .where((s) => (s['costINR'] as double) > 15000)
            .toList();
      default:
        return _sessionMaps;
    }
  }

  List<Map<String, dynamic>> get _currentPeriodSessions =>
      _getSessionsForPeriod(_selectedPeriod);

  /// The month a period refers to, counted back from today.
  ///
  /// This was pinned to May and April 2026, so 'This Month' meant May whatever
  /// the date actually was. From June onwards the screen showed a fixed
  /// four-month-old window and labelled it as current — a programme that
  /// started in September could only ever read as empty.
  DateTime monthFor(int period) {
    final now = DateTime.now();
    // Year/month arithmetic rather than subtracting days, so stepping back
    // from the 31st cannot land in the wrong month.
    return DateTime(now.year, now.month - period);
  }

  List<Map<String, dynamic>> _getSessionsForPeriod(int period) {
    final target = monthFor(period);
    return _sessionMaps.where((s) {
      final dt = DateTime.tryParse(s['startTime'] as String? ?? '');
      if (dt == null) return false;
      return dt.month == target.month && dt.year == target.year;
    }).toList();
  }

  double get _currentHours => _currentPeriodSessions.fold(
        0.0,
        (sum, s) => sum + (s['durationMinutes'] as int) / 60.0,
      );

  /// Summed from the sessions on screen, for every programme.
  ///
  /// Mahindra EV PoC used to return two hardcoded figures — 377739 and
  /// 1152375 — the exact ex-GST subtotals for May and April 2026. Correct the
  /// day they were typed and wrong every month after: the screen reported
  /// those two numbers whatever period was selected and whatever the sessions
  /// beneath them said, so a new session could never move it. Pinned
  /// invoice-reconciled figures belong in BillingBaseline, which the Analyser
  /// reads, not in a getter the rest of this screen treats as live.
  double get _currentCost => _currentPeriodSessions.fold(
        0.0,
        (sum, s) => sum + (s['costINR'] as double),
      );

  int get _currentSessionCount => _currentPeriodSessions.length;

  int get _currentAvgDuration {
    if (_currentPeriodSessions.isEmpty) return 0;
    final totalMinutes = _currentPeriodSessions.fold<int>(
      0,
      (sum, s) => sum + (s['durationMinutes'] as int),
    );
    return totalMinutes ~/ _currentPeriodSessions.length;
  }

  List<Map<String, dynamic>> get _displaySessions {
    final target = monthFor(_selectedPeriod);
    return _filteredSessions.where((s) {
      final dt = DateTime.tryParse(s['startTime'] as String? ?? '');
      if (dt == null) return false;
      return dt.month == target.month && dt.year == target.year;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exporting $_currentSessionCount sessions...',
                style: const TextStyle(fontFamily: 'Space Grotesk'),
              ),
              backgroundColor: const Color(0xFF0A1025),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        },
        icon: CustomIconWidget(
          iconName: 'share',
          color: const Color(0xFF001A10),
          size: 18,
        ),
        label: const Text(
          'Export Report',
          style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: const Color(0xFF001A10),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Goodyear background image with dark overlay
            Positioned.fill(
              child: Image.asset(
                'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
                fit: BoxFit.cover,
                semanticLabel: 'Goodyear racing team wallpaper',
              ),
            ),
            Positioned.fill(
              child: Container(color: const Color(0xFF050811).withAlpha(220)),
            ),
            _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                    ),
                  )
                : (isTablet
                      ? _buildTabletLayout(theme)
                      : _buildPhoneLayout(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneLayout(ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(theme)),
        SliverToBoxAdapter(
          child: HeroMetricWidget(
            totalHours: _currentHours,
            totalCost: _currentCost,
            sessionCount: _currentSessionCount,
            isLastMonth: _selectedPeriod == 1,
          ),
        ),
        SliverToBoxAdapter(
          child: SessionChartWidget(
            sessions: _currentPeriodSessions,
            selectedPeriod: _selectedPeriod,
            onPeriodChanged: (p) => setState(() => _selectedPeriod = p),
          ),
        ),
        SliverToBoxAdapter(
          child: MonthlySummaryCardWidget(
            totalCost: _currentCost,
            totalHours: _currentHours,
            sessionCount: _currentSessionCount,
            avgDurationMinutes: _currentAvgDuration,
            isLastMonth: _selectedPeriod == 1,
          ),
        ),
        SliverToBoxAdapter(child: _buildFilterRow(theme)),
        SessionListWidget(sessions: _displaySessions),
        SliverToBoxAdapter(child: _buildGapPrompt()),
        SliverToBoxAdapter(child: _buildFullHistory()),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  /// Everything logged for the current scope, across every month.
  ///
  /// Track time, manpower and workshop in one chronology. The Sessions list
  /// above is deliberately pinned to a single month and shows track only, so
  /// there was no way to see a programme's whole life — or to notice that a
  /// day carries muster but no track session, which is exactly how weeks of
  /// work went unbilled.
  Widget _buildFullHistory() {
    final entries = <_HistoryEntry>[];
    for (final s in _sessionMaps) {
      final dt = DateTime.tryParse(s['startTime'] as String? ?? '');
      if (dt == null) continue;
      entries.add(_HistoryEntry(
        date: dt,
        kind: _HistoryKind.track,
        title: (s['gate'] ?? '').toString(),
        detail: '${s['trackType']} · ${s['durationMinutes']} min'
            '${(s['status'] ?? '') == 'completed' ? '' : ' · ${s['status']}'}',
        amount: (s['costINR'] as num?)?.toDouble() ?? 0,
      ));
    }
    for (final d in _musterDays) {
      final workshop = d.kind == MusterKind.workshop;
      entries.add(_HistoryEntry(
        date: d.date,
        kind: workshop ? _HistoryKind.workshop : _HistoryKind.manpower,
        title: workshop ? 'Workshop' : 'Manpower',
        detail: workshop
            ? 'PO ${d.poNumber}'
            : '${d.headCount} on site · PO ${d.poNumber}',
        // Workshop is a flat daily rental. Manpower is priced off its PO's
        // day rate, which this screen does not hold, so it shows the days
        // rather than inventing a rupee figure.
        amount: workshop ? kWorkshopRatePerDay : null,
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    entries.sort((a, b) => b.date.compareTo(a.date));

    final byMonth = <String, List<_HistoryEntry>>{};
    for (final e in entries) {
      byMonth
          .putIfAbsent(DateFormat('yyyy-MM').format(e.date), () => [])
          .add(e);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history_rounded,
              color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          Text('Full History',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(
              '${entries.length} entries · '
              '${_allProjects ? 'all programmes' : _activeProject}',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490), fontSize: 10)),
        ]),
        const SizedBox(height: 4),
        Text(
            'Track, manpower and workshop together, every month. '
            'Workshop is accrued at the full daily rental as a worst case — '
            'the invoice is often lower, or absent.',
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF6B7490), fontSize: 10, height: 1.4)),
        const SizedBox(height: 10),
        ...months.map((m) {
          final rows = byMonth[m]!;
          final track = rows.where((e) => e.kind == _HistoryKind.track);
          final manpower =
              rows.where((e) => e.kind == _HistoryKind.manpower).length;
          final shop =
              rows.where((e) => e.kind == _HistoryKind.workshop).length;
          final tally = [
            if (track.isNotEmpty) '${track.length} session'
                '${track.length == 1 ? '' : 's'}',
            if (manpower > 0) '$manpower manpower',
            if (shop > 0) '$shop workshop',
          ].join('  ·  ');
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
                  child: Row(children: [
                    Text(
                        DateFormat('MMMM yyyy')
                            .format(DateTime.parse('$m-01')),
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Flexible(
                      child: Text(tally,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                              color: const Color(0xFF6B7490), fontSize: 10)),
                    ),
                  ]),
                ),
                ...rows.map(_historyTile),
              ]);
        }),
      ]),
    );
  }

  /// Days carrying muster but no track session, newest first.
  ///
  /// Somebody was on site and the workshop accrued, yet no track time was
  /// logged. Four different things could explain that — the vehicle was down,
  /// the track was booked out, no testing was planned, or the entry was simply
  /// missed — and only the last means billable time is still owed. Nothing
  /// recorded which, so months later it cannot be told apart.
  List<({DateTime date, String project, bool musterMissing})> get _gapDays {
    final sessionDays = <String>{};
    for (final s in _sessionMaps) {
      final dt = DateTime.tryParse(s['startTime'] as String? ?? '');
      if (dt != null) {
        sessionDays.add(DateFormat('yyyy-MM-dd').format(dt));
      }
    }
    final musterKeys = {for (final d in _musterDays) d.dateKey};

    final seen = <String>{};
    final out = <({DateTime date, String project, bool musterMissing})>[];

    // Muster but no track session: people on site, no track time logged.
    for (final d in _musterDays) {
      if (sessionDays.contains(d.dateKey)) continue;
      final project = (d.projectName ?? '').trim().isEmpty
          ? 'Mahindra EV PoC'
          : d.projectName!.trim();
      if (!seen.add('${d.dateKey}|${project.toLowerCase()}')) continue;
      out.add((date: d.date, project: project, musterMissing: false));
    }

    // The reverse: a session ran with nobody recorded on site. If testing
    // happened somebody was there, and an unrecorded man-day is a day that
    // never draws down the MOICARS PO and is therefore never invoiced — the
    // same loss as an unlogged session, pointing the other way.
    for (final s in _sessionMaps) {
      final dt = DateTime.tryParse(s['startTime'] as String? ?? '');
      if (dt == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(dt);
      if (musterKeys.contains(key)) continue;
      final project = _allProjects ? _activeProject : _activeProject;
      if (!seen.add('$key|${project.toLowerCase()}|rev')) continue;
      out.add((date: dt, project: project, musterMissing: true));
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  String _noteKey(DateTime date, String project) =>
      '${DateFormat('yyyy-MM-dd').format(date)}|${project.toLowerCase().trim()}';

  Widget _buildGapPrompt() {
    final gaps = _gapDays;
    if (gaps.isEmpty) return const SizedBox.shrink();
    final unanswered =
        gaps.where((g) => !_dayNotes.containsKey(_noteKey(g.date, g.project)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(200),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFFFFB547)
                  .withAlpha(unanswered.isEmpty ? 50 : 130)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                unanswered.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.help_outline_rounded,
                color: const Color(0xFFFFB547),
                size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  unanswered.isEmpty
                      ? 'All ${gaps.length} days without track time are explained'
                      : '${unanswered.length} day'
                          '${unanswered.length == 1 ? '' : 's'} with no track '
                          'session — add a reason',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              'Days where the register only half adds up — muster with no track '
              'session, or a session with nobody recorded on site. Either way a '
              'day may be going unbilled. Say why, so a quiet day can be told '
              'apart from a missed entry.',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490), fontSize: 10, height: 1.4)),
          const SizedBox(height: 10),
          ...gaps.take(30).map((g) {
            final note = _dayNotes[_noteKey(g.date, g.project)];
            return InkWell(
              onTap: () => _askReason(g.date, g.project, existing: note),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withAlpha(110),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: note == null
                          ? const Color(0xFFFFB547).withAlpha(70)
                          : Colors.transparent),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('EEE, d MMM yyyy').format(g.date),
                              style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          Text(
                              note == null
                                  ? '${g.project} · '
                                      '${g.musterMissing ? 'no muster — man-day not claimed' : 'reason not recorded'}'
                                  : '${note.reason.label}'
                                      '${(note.comment ?? '').isEmpty ? '' : ' — ${note.comment}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                  color: note == null
                                      ? const Color(0xFFFFB547)
                                      : const Color(0xFF6B7490),
                                  fontSize: 10)),
                        ]),
                  ),
                  Icon(note == null ? Icons.add_comment_outlined : Icons.edit,
                      size: 14, color: const Color(0xFF6B7490)),
                ]),
              ),
            );
          }),
          if (gaps.length > 30)
            Text('and ${gaps.length - 30} more',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490), fontSize: 10)),
        ]),
      ),
    );
  }

  Future<void> _askReason(DateTime date, String project,
      {DayNote? existing}) async {
    var reason = existing?.reason ?? DayNoteReason.noTestingPlanned;
    final comment = TextEditingController(text: existing?.comment ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('No track session — ${DateFormat('d MMM yyyy').format(date)}',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(project,
                    style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490), fontSize: 11)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: DayNoteReason.values.map((r) {
                  final on = r == reason;
                  return GestureDetector(
                    onTap: () => setSheet(() => reason = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: on
                            ? AppTheme.primary.withAlpha(38)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: on
                                ? AppTheme.primary.withAlpha(140)
                                : const Color(0xFF849495).withAlpha(70)),
                      ),
                      child: Text(r.label,
                          style: GoogleFonts.spaceGrotesk(
                              color: on
                                  ? AppTheme.primary
                                  : const Color(0xFF94A3B8),
                              fontSize: 11,
                              fontWeight:
                                  on ? FontWeight.w700 : FontWeight.w500)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: comment,
                maxLines: 3,
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Comment (optional)',
                  hintStyle: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF6B7490), fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF1E293B).withAlpha(120),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF6B7490))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Save',
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (saved != true) {
      comment.dispose();
      return;
    }
    try {
      await DayNoteService.instance.save(DayNote(
        id: existing?.id,
        date: date,
        projectName: project,
        reason: reason,
        comment: comment.text,
      ));
      if (mounted) _loadSessions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save the reason: $e',
              style: GoogleFonts.spaceGrotesk(color: Colors.white)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
    comment.dispose();
  }

  Widget _historyTile(_HistoryEntry e) {
    final colour = switch (e.kind) {
      _HistoryKind.track => AppTheme.primary,
      _HistoryKind.manpower => const Color(0xFFB794F6),
      _HistoryKind.workshop => const Color(0xFFFFB547),
    };
    final icon = switch (e.kind) {
      _HistoryKind.track => Icons.speed_rounded,
      _HistoryKind.manpower => Icons.groups_rounded,
      _HistoryKind.workshop => Icons.home_repair_service_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(170),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withAlpha(45)),
      ),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: colour.withAlpha(28),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: colour, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            Text('${DateFormat('EEE, d MMM').format(e.date)} · ${e.detail}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490), fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
            e.amount == null
                ? '—'
                : NumberFormat.currency(
                        locale: 'en_IN', symbol: '₹', decimalDigits: 0)
                    .format(e.amount),
            style: GoogleFonts.spaceGrotesk(
                color: e.amount == null ? const Color(0xFF6B7490) : colour,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildTabletLayout(ThemeData theme) {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildPhoneLayout(theme)),
        Container(width: 1, color: const Color(0xFF3a494b)),
        Expanded(
          flex: 4,
          child: _RightPanel(
            totalCost: _currentCost,
            totalHours: _currentHours,
            sessionCount: _currentSessionCount,
            avgDurationMinutes: _currentAvgDuration,
            // Null means every programme — the charges panel then totals the
            // whole muster rather than one project's slice.
            activeProject: _allProjects ? null : _activeProject,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back to projects (web only)
          if (kIsWeb)
            GestureDetector(
              onTap: () => context.go('/project-selection'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_ios_rounded,
                      color: Color(0xFF94A3B8), size: 14),
                  const SizedBox(width: 4),
                  Text('All Projects',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                      )),
                ],
              ),
            ),
          if (kIsWeb) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session History', style: theme.textTheme.headlineMedium),
                    Row(children: [
                      Text(
                        'NATRAX Proving Ground · ',
                        style: theme.textTheme.bodySmall,
                      ),
                      // Tap to widen the register to every programme and back.
                      // The 'All Projects' link above this navigates away to
                      // the selection screen, which is not the same thing —
                      // there was no way to read the whole history at once,
                      // and a gap in one programme could not be compared
                      // against another without leaving the screen.
                      GestureDetector(
                        onTap: () {
                          setState(() => _allProjects = !_allProjects);
                          _loadSessions();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppTheme.primary.withAlpha(80)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              _allProjects ? 'All programmes' : _activeProject,
                              style: TextStyle(
                                fontFamily: 'Space Grotesk',
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                                _allProjects
                                    ? Icons.unfold_less_rounded
                                    : Icons.unfold_more_rounded,
                                size: 11,
                                color: AppTheme.primary),
                          ]),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: CustomIconWidget(
                  iconName: 'tune',
                  color: const Color(0xFFA8B0C8),
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Sessions',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFdfe2f0),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_filteredSessions.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) {
                final isSelected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withAlpha(38)
                            : const Color(0xFF0A1025),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary.withAlpha(128)
                              : const Color(0xFF849495),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          fontFamily: 'Space Grotesk',
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFFA8B0C8),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Right Panel: KPIs + Live Project Updates ─────────────────────────────────

class _RightPanel extends StatefulWidget {
  final double totalCost;
  final double totalHours;
  final int sessionCount;
  final int avgDurationMinutes;
  /// Null means every programme.
  final String? activeProject;

  const _RightPanel({
    required this.totalCost,
    required this.totalHours,
    required this.sessionCount,
    required this.avgDurationMinutes,
    required this.activeProject,
  });

  @override
  State<_RightPanel> createState() => _RightPanelState();
}

class _RightPanelState extends State<_RightPanel> {
  List<Map<String, dynamic>> _updates = [];
  bool _loadingUpdates = true;

  // Project-wise charges: track time from the sessions this screen already
  // loaded, manpower and workshop from the muster.
  ProjectCharges? _charges;
  bool _loadingCharges = true;

  final _compact = NumberFormat.compactCurrency(
      locale: 'en_IN', symbol: '₹', decimalDigits: 1);
  final _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    // Marking a muster day changes manpower and workshop here, so this panel
    // follows the register rather than holding whatever it read on open.
    MusterService.instance.addListener(_onMusterChanged);
    _fetchUpdates();
    _fetchCharges();
  }

  @override
  void dispose() {
    MusterService.instance.removeListener(_onMusterChanged);
    super.dispose();
  }

  void _onMusterChanged() {
    if (mounted) _fetchCharges();
  }

  Future<void> _fetchCharges() async {
    setState(() => _loadingCharges = true);
    try {
      final c =
          await MusterService.instance.chargesForProject(widget.activeProject);
      if (!mounted) return;
      setState(() {
        _charges = c;
        _loadingCharges = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCharges = false);
    }
  }

  @override
  void didUpdateWidget(_RightPanel old) {
    super.didUpdateWidget(old);
    if (old.activeProject != widget.activeProject) {
      _fetchUpdates();
      _fetchCharges();
    }
  }

  Future<void> _fetchUpdates() async {
    setState(() => _loadingUpdates = true);
    try {
      // Showing every programme means the updates are not scoped either,
      // rather than scoped to a project name that is deliberately absent.
      final project = widget.activeProject;
      var query = SupabaseService.instance.client
          .from('project_updates')
          .select('id, title, body, type, author_name, created_at');
      if (project != null && project.isNotEmpty) {
        query = query.eq('project_name', project);
      }
      final data =
          await query.order('created_at', ascending: false).limit(10);
      if (mounted) {
        setState(() {
          _updates = (data as List).cast<Map<String, dynamic>>();
          _loadingUpdates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUpdates = false);
    }
  }

  Color _typeColor(String? t) => switch (t) {
        'milestone' => const Color(0xFF00F3FF),
        'alert'     => const Color(0xFFFFB547),
        'attachment'=> const Color(0xFFA855F7),
        _           => const Color(0xFF4A9EFF),
      };

  IconData _typeIcon(String? t) => switch (t) {
        'milestone' => Icons.flag_rounded,
        'alert'     => Icons.warning_amber_rounded,
        'attachment'=> Icons.attach_file_rounded,
        _           => Icons.update_rounded,
      };

  String _ago(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('d MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final hrs = widget.totalHours.toStringAsFixed(1);
    final avgH = (widget.avgDurationMinutes ~/ 60).toString().padLeft(1, '0');
    final avgM = (widget.avgDurationMinutes % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Compact KPI row ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            _kpi('TOTAL COST', _compact.format(widget.totalCost),
                AppTheme.primary, Icons.currency_rupee_rounded),
            const SizedBox(width: 8),
            _kpi('TRACK HRS', '${hrs}h', const Color(0xFF4A9EFF),
                Icons.timer_rounded),
            const SizedBox(width: 8),
            _kpi('AVG/SESSION', '${avgH}h ${avgM}m',
                const Color(0xFFFFB547), Icons.speed_rounded),
          ]),
        ),

        const SizedBox(height: 16),
        Container(height: 1, color: const Color(0xFF3a494b)),

        _chargesCard(),

        Container(height: 1, color: const Color(0xFF3a494b)),

        // ── Updates header ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            const Icon(Icons.campaign_rounded,
                color: AppTheme.primary, size: 16),
            const SizedBox(width: 8),
            Text('Project Updates',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: _fetchUpdates,
              child: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF6B7490), size: 16),
            ),
          ]),
        ),

        // ── Updates list ───────────────────────────────────────────────
        Expanded(
          child: _loadingUpdates
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 1.5))
              : _updates.isEmpty
                  ? _emptyUpdates()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: _updates.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) => _updateCard(_updates[i]),
                    ),
        ),
      ],
    );
  }

  /// Project-wise charges: the three things NATRAX bills for, side by side.
  ///
  /// Track comes from the sessions this screen has already totalled; manpower
  /// and workshop come from the muster via [MusterService.chargesForProject],
  /// the same call the Analyser makes, so the two screens cannot quote
  /// different figures for one project.
  Widget _chargesCard() {
    final c = _charges;
    final track = widget.totalCost;
    final manpower = c?.manpowerCost ?? 0;
    final workshop = c?.workshopCost ?? 0;
    final total = track + manpower + workshop;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long_rounded,
              color: AppTheme.primary, size: 16),
          const SizedBox(width: 8),
          Text('Project Charges',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          if (_loadingCharges)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    color: AppTheme.primary, strokeWidth: 1.5)),
        ]),
        const SizedBox(height: 4),
        Text(widget.activeProject ?? 'All programmes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF6B7490), fontSize: 10)),
        const SizedBox(height: 12),
        _chargeRow('Track + Accessories', track, total, AppTheme.primary,
            '${widget.sessionCount} session'
            '${widget.sessionCount == 1 ? '' : 's'}'),
        _chargeRow('Manpower', manpower, total, const Color(0xFFB794F6),
            c == null
                ? ''
                : '${c.manDays} man-day${c.manDays == 1 ? '' : 's'}'),
        // Labelled 'accrued' on purpose. Every operational day is booked here
        // at the full daily rental as a worst case, but the workshop is used
        // on a shared basis and NATRAX has omitted it from some months
        // altogether — so this is a ceiling, not a prediction of the invoice.
        // Presenting it unqualified invites it to be read as money owed.
        _chargeRow('Workshop (accrued)', workshop, total,
            const Color(0xFFFFB547),
            c == null
                ? ''
                : '${c.workshopDays} day${c.workshopDays == 1 ? '' : 's'}'
                    ' @ ${_inr.format(kWorkshopRatePerDay)} · worst case'),
        const SizedBox(height: 8),
        Container(height: 1, color: const Color(0xFF3a494b)),
        const SizedBox(height: 8),
        Row(children: [
          Text('Total (excl. GST)',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(_inr.format(total),
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
        ]),
        // Days worked on a PO that carries no rate yet. They are real and
        // billable; showing them as ₹0 without comment is how unbilled work
        // stays invisible.
        if (c != null && c.manpowerUnpricedDays > 0) ...[
          const SizedBox(height: 8),
          Text(
              '${c.manpowerUnpricedDays} man-day'
              '${c.manpowerUnpricedDays == 1 ? '' : 's'} not priced — '
              'their PO has no day rate recorded yet.',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFFFFB547), fontSize: 10, height: 1.4)),
        ],
      ]),
    );
  }

  Widget _chargeRow(
      String label, double value, double total, Color colour, String sub) {
    // Share of the project, so the three read as a composition rather than
    // three unrelated numbers. Guarded because a project with nothing logged
    // has a zero total and no shares to speak of.
    final share = total > 0 ? value / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: colour, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          Text(_inr.format(value),
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 4,
            backgroundColor: const Color(0xFF1E293B),
            valueColor: AlwaysStoppedAnimation(colour),
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('$sub  ·  ${(share * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490), fontSize: 9)),
        ],
      ]),
    );
  }

  Widget _kpi(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(50)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(height: 6),
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: color.withAlpha(180),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _updateCard(Map<String, dynamic> u) {
    final type = u['type'] as String?;
    final color = _typeColor(type);
    final icon = _typeIcon(type);
    final title = u['title'] as String? ?? '';
    final body = u['body'] as String? ?? '';
    final author = u['author_name'] as String? ?? 'Team';
    final ago = _ago(u['created_at'] as String?);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1025).withAlpha(200),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(50)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // Type + time
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: color, size: 10),
                  const SizedBox(width: 4),
                  Text((type ?? 'update').toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                          color: color,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                ]),
              ),
              const Spacer(),
              Text(ago,
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF4A5470), fontSize: 9)),
            ]),
            const SizedBox(height: 6),
            // Title
            Text(title,
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            // Body
            Text(body,
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490),
                    fontSize: 11,
                    height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            // Author
            Row(children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    author.isNotEmpty ? author[0].toUpperCase() : 'T',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.primary,
                        fontSize: 8,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(author,
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF4A5470), fontSize: 9)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _emptyUpdates() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.campaign_outlined,
            color: Colors.white.withAlpha(25), size: 36),
        const SizedBox(height: 8),
        Text('No updates yet',
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF4A5470), fontSize: 12)),
        const SizedBox(height: 4),
        Text('Go to Updates tab to post',
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF3A4060), fontSize: 10)),
      ]),
    );
  }
}

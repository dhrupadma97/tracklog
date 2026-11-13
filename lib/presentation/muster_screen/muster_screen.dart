import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/invoice_service.dart';
import '../../services/muster_service.dart';
import '../../services/project_catalog.dart';
import '../../services/project_manager.dart';
import '../../routes/app_routes.dart';

/// Daily manpower muster — headcount per day against a manpower PO.
///
/// Contract manpower bills in man-days, so the headcount recorded here is what
/// draws the PO down. Kept as an interim register until a permanent technician
/// is in place.
class MusterScreen extends StatefulWidget {
  const MusterScreen({super.key});

  @override
  State<MusterScreen> createState() => _MusterScreenState();
}

class _MusterScreenState extends State<MusterScreen> {
  bool _loading = true;
  bool _readOnly = true;
  String? _error;

  List<MusterDay> _days = [];

  /// "Other" daily entries, from public.muster_entries — the office, the
  /// conference hall, food coupons. Kept apart from [_days] because nothing
  /// that counts man-days or workshop days may ever see them.
  List<MusterDay> _entries = [];

  /// Both, newest first: what the register shows.
  List<MusterDay> get _all =>
      [..._days, ..._entries]..sort((a, b) => b.date.compareTo(a.date));

  List<ManpowerPosition> _positions = [];
  List<Map<String, dynamic>> _pos = [];
  // Workshop is billed on the NATRAX track PO, a different pool from the
  // MOICARS manpower POs, so the sheet offers a different list per kind.
  List<Map<String, dynamic>> _workshopPos = [];
  List<WorkshopPosition> _workshopPositions = [];

  /// Which kinds the register is showing. Null means both, which is the point
  /// of the view — manpower and workshop in one chronology. The filter narrows
  /// it for a question about one of them, it does not define the default.
  MusterKind? _kindFilter;

  static const _teal = AppTheme.primary;
  static const _amber = Color(0xFFFFB547);
  static const _red = Color(0xFFFF6B6B);
  static const _green = Color(0xFF4CAF50);
  static const _muted = Color(0xFF6B7490);
  static const _deadColour = Color(0xFFB794F6);
  static const _otherColour = Color(0xFF4D9FFF);

  final _inr = NumberFormat.currency(
      locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    // A day recorded anywhere — this screen, or any future caller of the
    // service — reloads the register and the PO positions that hang off it,
    // so what is on screen is never behind what is in the table.
    MusterService.instance.addListener(_onMusterChanged);
    _load();
  }

  @override
  void dispose() {
    MusterService.instance.removeListener(_onMusterChanged);
    super.dispose();
  }

  void _onMusterChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await EngineerAuthService.instance.getCurrentProfile();

      // Invoiced-per-PO is read here and handed to the service, so the muster
      // and the PO tracker cannot disagree about what has been billed.
      final invoicedExcl = <String, double>{};
      try {
        for (final i in await InvoiceService.instance.list()) {
          final po = (i.poNumber ?? '').trim();
          if (po.isEmpty) continue;
          invoicedExcl[po] = (invoicedExcl[po] ?? 0) + i.amountExclGst;
        }
      } catch (_) {
        // An unreadable invoice list must not take the muster down with it.
      }

      final days = await MusterService.instance.list();
      final entries = await MusterService.instance.listEntries();
      final positions = await MusterService.instance
          .positions(invoicedExclGstByPo: invoicedExcl);
      final pos = await MusterService.instance.activeManpowerPos();
      final wPos = await MusterService.instance.workshopPos();
      final wPositions = await MusterService.instance
          .workshopPositions(invoicedExclGstByPo: invoicedExcl);

      if (!mounted) return;
      setState(() {
        _readOnly = profile?.isReadOnly ?? true;
        _days = days;
        _entries = entries;
        _positions = positions;
        _pos = pos;
        _workshopPos = wPos;
        _workshopPositions = wPositions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String get _defaultPo => _defaultPoFor(MusterKind.manpower);

  List<Map<String, dynamic>> _posFor(MusterKind kind) =>
      kind == MusterKind.workshop ? _workshopPos : _pos;

  String _defaultPoFor(MusterKind kind) {
    final list = _posFor(kind);
    if (list.isEmpty) return '';
    if (kind == MusterKind.manpower) {
      // Roll onto the next PO once the one in use is out of days, rather than
      // defaulting to whichever active PO happens to come first. Booking past
      // a PO's contracted days is an overrun with no budget behind it.
      final next = MusterService.instance.nextManpowerPo(_positions);
      if (next != null && next.isNotEmpty) {
        final stillOffered = list.any(
            (p) => (p['po_number'] as String? ?? '').trim() == next);
        if (stillOffered) return next;
      }
    }
    final active = list.firstWhere(
      (p) => (p['po_status'] as String? ?? '') == 'active',
      orElse: () => list.first,
    );
    return (active['po_number'] as String? ?? '').trim();
  }

  /// The position for a PO number, when it is a manpower one.
  ManpowerPosition? _positionFor(String po) {
    for (final p in _positions) {
      if (p.poNumber == po) return p;
    }
    return null;
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      // Shown even with no manpower PO loaded: an "other" entry needs none.
      floatingActionButton: _readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _entrySheet(),
              backgroundColor: _teal,
              icon: const Icon(Icons.how_to_reg, color: Colors.white, size: 18),
              label: Text('Mark a day',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
      body: Stack(children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/GYRacing_DesktopTeamsWallpaper_5-1779284234231.png',
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
            child: Container(color: const Color(0xFF050811).withAlpha(215))),
        SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : _error != null
                  ? _errorView()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _teal,
                      backgroundColor: const Color(0xFF0A1025),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                        children: [
                          _header(),
                          const SizedBox(height: 16),
                          // PO balances moved to the PO Tracker (13 Nov 2026):
                          // the muster is the day record, the tracker is the
                          // money. One line here says where they went and
                          // which PO the next manpower day draws.
                          _poLink(),
                          if (MusterService.instance.entriesTableMissing)
                            _entriesMissingNote(),
                          const SizedBox(height: 8),
                          _register(),
                        ],
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _errorView() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 44),
          const SizedBox(height: 10),
          Text('Could not load the muster',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
          ),
          TextButton(
              onPressed: _load,
              child:
                  Text('Retry', style: GoogleFonts.spaceGrotesk(color: _teal))),
        ]),
      );

  Widget _header() => Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _teal.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _teal.withAlpha(77)),
          ),
          child: const Icon(Icons.how_to_reg, color: _teal, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Muster',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(
                'Attendance, workshop, dead weight and other daily entries',
                style: GoogleFonts.spaceGrotesk(
                    color: _muted, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ),
        GestureDetector(
          onTap: _load,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(180),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
            ),
            child: const Icon(Icons.refresh, color: _muted, size: 18),
          ),
        ),
      ]);

  // ─── Position ──────────────────────────────────────────────────────────────

  /// Where the PO balances went, and which PO the next manpower day draws.
  ///
  /// The days-left and money-left cards lived here until 13 Nov 2026. They
  /// answer a money question, so they moved to the PO Tracker, split into
  /// manpower and track & workshop POs; the muster keeps only the day record.
  Widget _poLink() {
    final next = MusterService.instance.nextManpowerPo(_positions);
    ManpowerPosition? pos;
    for (final p in _positions) {
      if (p.poNumber == next) pos = p;
    }
    final lowOnDays = pos != null && pos.isComplete && pos.daysLeft <= 10;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(200),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (lowOnDays ? _amber : _teal).withAlpha(70)),
      ),
      child: Row(children: [
        Icon(Icons.receipt_long, color: lowOnDays ? _amber : _teal, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                pos == null
                    ? 'No manpower PO with days left'
                    : pos.isComplete
                        ? 'Next manpower day draws PO ${pos.poNumber} · '
                            '${pos.daysLeft.toStringAsFixed(0)} day'
                            '${pos.daysLeft == 1 ? '' : 's'} left'
                        : 'Next manpower day draws PO ${pos.poNumber} · '
                            'days not set on the PO',
                style: GoogleFonts.spaceGrotesk(
                    color: lowOnDays ? _amber : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                'Days left and money left on every PO are in the PO Tracker.',
                style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
          ]),
        ),
        TextButton(
          onPressed: () => context.go(AppRoutes.poTracker),
          child: Text('Open PO Tracker →',
              style: GoogleFonts.spaceGrotesk(
                  color: _teal, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  /// The "other" entries table has not been created yet.
  Widget _entriesMissingNote() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _amber.withAlpha(18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _amber.withAlpha(80)),
        ),
        child: Text(
            'Other entries need one setup step: paste '
            '20261113090000_muster_entries.sql into the Supabase SQL editor '
            'and run it. Manpower, workshop and dead weight work as before.',
            style: GoogleFonts.spaceGrotesk(
                color: _amber, fontSize: 11.5, height: 1.4)),
      );

  Widget _stat(String label, String value, String unit, Color colour) =>
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6)),
          const SizedBox(height: 3),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: GoogleFonts.spaceGrotesk(
                        color: colour,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                Text(unit,
                    style:
                        GoogleFonts.spaceGrotesk(color: _muted, fontSize: 10)),
              ]),
        ]),
      );

  // ─── Register ──────────────────────────────────────────────────────────────

  Widget _register() {
    final all = _all;
    if (all.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(160),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF849495).withAlpha(60)),
        ),
        child: Column(children: [
          const Icon(Icons.event_busy, color: _muted, size: 32),
          const SizedBox(height: 10),
          Text('No days recorded yet',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              'Mark a day to start the register.',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
        ]),
      );
    }

    final shown = _kindFilter == null
        ? all
        : all.where((d) => d.kind == _kindFilter).toList();

    // Grouped by month, newest first — the register is read by month.
    final byMonth = <String, List<MusterDay>>{};
    for (final d in shown) {
      byMonth.putIfAbsent(d.monthKey, () => []).add(d);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _registerSummary(),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                  'No ${(_kindFilter?.label ?? 'manpower').toLowerCase()} '
                  'entries in the register yet.',
                  style:
                      GoogleFonts.spaceGrotesk(color: _muted, fontSize: 12)),
            ),
          ),
        ...months.map((m) {
          final rows = byMonth[m]!;
          // Counted apart because they ARE apart: man-days are a sum of heads
          // and draw down a MOICARS PO contracted in days; workshop days are a
          // count of rows accruing rupees on the NATRAX track PO. The header
          // used to read '$manDays man-days · ${rows.length} days', where the
          // second figure silently mixed workshop rows into what reads as a
          // manpower total.
          final manDays = rows
              .where((d) => d.kind == MusterKind.manpower)
              .fold<int>(0, (s, d) => s + d.headCount);
          final manRows =
              rows.where((d) => d.kind == MusterKind.manpower).length;
          final shopDays =
              rows.where((d) => d.kind == MusterKind.workshop).length;
          final others = rows.where((d) => d.kind == MusterKind.other).length;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(children: [
              Text(_monthLabel(m),
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_monthTally(manDays, manRows, shopDays, others),
                  style:
                      GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
            ]),
          ),
          ...rows.map(_dayTile),
        ]);
        }),
      ],
    );
  }

  /// Month header tally. Only states a figure that exists — a month of pure
  /// manpower should not read '0 workshop days', which invites the reader to
  /// wonder what happened to the workshop that month.
  String _monthTally(int manDays, int manRows, int shopDays, [int others = 0]) {
    final parts = <String>[];
    if (manRows > 0) {
      parts.add('$manDays man-day${manDays == 1 ? '' : 's'}'
          ' over $manRows day${manRows == 1 ? '' : 's'}');
    }
    if (shopDays > 0) {
      parts.add('$shopDays workshop day${shopDays == 1 ? '' : 's'}');
    }
    if (others > 0) {
      parts.add('$others other entr${others == 1 ? 'y' : 'ies'}');
    }
    return parts.join('  ·  ');
  }

  /// The whole register at a glance: both kinds, every month, and the span
  /// they cover — so the totals can be read without scrolling the history,
  /// and the filter that narrows the history sits with them.
  Widget _registerSummary() {
    final manDays = _days
        .where((d) => d.kind == MusterKind.manpower)
        .fold<int>(0, (s, d) => s + d.headCount);
    final manRows = _days.where((d) => d.kind == MusterKind.manpower).length;
    final shopDays = _days.where((d) => d.kind == MusterKind.workshop).length;
    final deadRows =
        _days.where((d) => d.kind == MusterKind.deadweight).length;
    final otherRows = _entries.length;
    final all = _all;

    // _all is ordered newest first.
    final newest = all.first.date;
    final oldest = all.last.date;
    final fmt = DateFormat('d MMM yyyy');

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(200),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF849495).withAlpha(60)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, color: _muted, size: 16),
          const SizedBox(width: 8),
          Text('Full register',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Flexible(
            child: Text('${fmt.format(oldest)} — ${fmt.format(newest)}',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 14),
        // _stat already returns an Expanded, so these are not wrapped again —
        // an Expanded inside an Expanded is not a Flex child and throws.
        Row(children: [
          _stat('MAN-DAYS', '$manDays',
              'in $manRows day${manRows == 1 ? '' : 's'}', _teal),
          _stat('WORKSHOP', '$shopDays', shopDays == 1 ? 'day' : 'days',
              _amber),
          _stat('DEAD WT', '$deadRows', deadRows == 1 ? 'day' : 'days',
              _deadColour),
          _stat('OTHER', '$otherRows',
              otherRows == 1 ? 'entry' : 'entries', _otherColour),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _kindChip('All', null, all.length),
          _kindChip('Manpower', MusterKind.manpower, manRows),
          _kindChip('Workshop', MusterKind.workshop, shopDays),
          _kindChip('Dead wt', MusterKind.deadweight, deadRows),
          _kindChip('Other', MusterKind.other, otherRows),
        ]),
      ]),
    );
  }

  Widget _kindChip(String label, MusterKind? kind, int count) {
    final on = _kindFilter == kind;
    final accent = switch (kind) {
      MusterKind.workshop => _amber,
      MusterKind.deadweight => _deadColour,
      MusterKind.other => _otherColour,
      _ => _teal,
    };
    return GestureDetector(
      onTap: () => setState(() => _kindFilter = kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? accent.withAlpha(38) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: on
                  ? accent.withAlpha(130)
                  : const Color(0xFF849495).withAlpha(70)),
        ),
        child: Text('$label  $count',
            style: GoogleFonts.spaceGrotesk(
                color: on ? accent : _muted,
                fontSize: 11,
                fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
      ),
    );
  }

  String _qty(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _dayTile(MusterDay d) {
    final isWorkshop = d.kind == MusterKind.workshop;
    final isDead = d.kind == MusterKind.deadweight;
    final isOther = d.kind == MusterKind.other;
    // Amber zero means "day checked, nobody on site". Workshop, dead weight
    // and other entries legitimately carry head_count 0, so they must not
    // borrow that colour or they read as an empty manpower day.
    final emptyManpowerDay =
        d.kind == MusterKind.manpower && d.headCount == 0;
    final accent = isWorkshop
        ? _amber
        : isDead
            ? _deadColour
            : isOther
                ? _otherColour
                : (emptyManpowerDay ? _amber : _teal);
    final what = switch (d.kind) {
      MusterKind.workshop => 'Workshop · PO ${d.poNumber}',
      MusterKind.deadweight => 'Dead weight 250 kg · PO ${d.poNumber}',
      MusterKind.other => '${d.item}'
          '${d.quantity == 1 ? '' : ' × ${_qty(d.quantity)}'}'
          '${d.amount == null ? '' : ' · ${_inr.format(d.amount)}'}'
          '${d.poNumber.isEmpty ? '' : ' · PO ${d.poNumber}'}',
      _ => '${d.headCount} on site · PO ${d.poNumber}',
    };
    return GestureDetector(
      onTap: _readOnly ? null : () => _entrySheet(existing: d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(170),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: d.kind != MusterKind.manpower || emptyManpowerDay
                  ? accent.withAlpha(60)
                  : const Color(0xFF849495).withAlpha(60)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: d.kind != MusterKind.manpower
                ? Icon(
                    isWorkshop
                        ? Icons.home_repair_service
                        : isDead
                            ? Icons.fitness_center
                            : Icons.playlist_add_check,
                    color: accent,
                    size: 17)
                : Text('${d.headCount}',
                    style: GoogleFonts.spaceGrotesk(
                        color: accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEE, d MMM yyyy').format(d.date),
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              Text(
                  '$what'
                  ' · ${ProjectCatalog.displayName(d.projectName)}'
                  '${(d.notes ?? '').isEmpty ? '' : ' · ${d.notes}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
            ]),
          ),
          if (!_readOnly)
            const Icon(Icons.chevron_right, color: _muted, size: 18),
        ]),
      ),
    );
  }

  String _monthLabel(String yyyyMm) {
    final p = yyyyMm.split('-');
    if (p.length != 2) return yyyyMm;
    final m = int.tryParse(p[1]);
    if (m == null || m < 1 || m > 12) return yyyyMm;
    return '${DateFormat('MMMM').format(DateTime(2000, m))} ${p[0]}';
  }

  // ─── Entry ─────────────────────────────────────────────────────────────────

  Future<void> _entrySheet({MusterDay? existing}) async {
    var date = existing?.date ?? DateTime.now();
    // Null means a single day. Manpower is booked in stretches, so the
    // sheet takes a range and writes one row per day in it.
    DateTime? endDate;
    // An open stretch: a start date with no known end, filled up to today.
    // Never into the future - a day nobody has worked yet cannot be
    // recorded as worked, and testing pauses between vehicles anyway, so
    // the gap is filled by re-saving rather than run on automatically.
    var stillRunning = false;
    // Saturdays in the range that were actually worked, as date keys.
    // Sunday is never offered - a one-off Sunday is saved as a single date.
    var saturdaysWorked = <String>{};
    /// The days actually ticked, and whether anybody has touched them.
    ///
    /// Until [daysTouched], the calendar is re-seeded from the rule whenever
    /// the range or the kind changes, so it always opens on the sensible
    /// answer. After the first tap it is the user's list and is left alone.
    final chosenDays = <String>{};
    var daysTouched = false;
    var count = existing?.headCount ?? 1;
    var kind = existing?.kind ?? MusterKind.manpower;
    var po = existing?.poNumber ?? _defaultPo;
    // Which programme the day is worked against. Recorded on the row already,
    // but previously taken silently from whatever project was open elsewhere —
    // so a day could be attributed without the person marking it ever seeing
    // to what. Shown and editable, like the track entry form.
    var project = existing?.projectName ?? ProjectManager.instance.activeProject;
    final notes = TextEditingController(text: existing?.notes ?? '');
    // "Other" entries: what, how many, and at what rate if known.
    final item = TextEditingController(text: existing?.item ?? '');
    final qty = TextEditingController(
        text: existing == null ? '1' : _qty(existing.quantity));
    final rate = TextEditingController(
        text: existing?.rate == null ? '' : _qty(existing!.rate!));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A1025),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        // The sheet grew past the screen: on a laptop the Save button sat
        // below the fold with nothing to scroll, so a day could be filled in
        // and never recorded. A bottom sheet does not scroll on its own -
        // isScrollControlled only lets it exceed half the screen.
        //
        // Capped at 92% so the sheet never covers the whole screen, and the
        // keyboard inset stays inside the scroll view so the focused field
        // is reachable when the keyboard is up.
        builder: (ctx, setSheet) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.92,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(existing == null ? 'Mark a day' : 'Edit day',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),

            // What is being recorded. Manpower is per head per day and
            // draws a MOICARS PO; workshop is flat per day and is billed
            // on the NATRAX track PO. Locked once a day is recorded -
            // switching kind would move the row to a different PO pool.
            if (existing == null)
              Row(children: [
                Expanded(
                  child: _kindTab(
                    label: 'MANPOWER',
                    icon: Icons.groups,
                    selected: kind == MusterKind.manpower,
                    onTap: () => setSheet(() {
                      kind = MusterKind.manpower;
                      po = _defaultPoFor(kind);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _kindTab(
                    label: 'WORKSHOP',
                    icon: Icons.home_repair_service,
                    selected: kind == MusterKind.workshop,
                    onTap: () => setSheet(() {
                      kind = MusterKind.workshop;
                      po = _defaultPoFor(kind);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                // Hired by the day from MOICARS alongside the assistant, and
                // billed on their invoice — but it is not a man-day, so it
                // gets its own kind rather than being folded into the head
                // count the way MOI/TV-2331 folded it.
                Expanded(
                  child: _kindTab(
                    label: 'DEAD WT',
                    icon: Icons.fitness_center,
                    selected: kind == MusterKind.deadweight,
                    onTap: () => setSheet(() {
                      kind = MusterKind.deadweight;
                      po = _defaultPoFor(kind);
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                // Anything else worth a line on the day: the office, the
                // conference hall, food coupons. Drawn on no PO.
                Expanded(
                  child: _kindTab(
                    label: 'OTHER',
                    icon: Icons.playlist_add,
                    selected: kind == MusterKind.other,
                    onTap: () => setSheet(() {
                      kind = MusterKind.other;
                      po = '';
                    }),
                  ),
                ),
              ]),
            if (existing == null) const SizedBox(height: 14),

            // What is already on the books for this kind and PO.
            if (existing == null)
              ..._runBanner(
                kind: kind,
                po: po,
                onExtend: (runStart) => setSheet(() {
                  date = runStart;
                  stillRunning = true;
                  endDate = null;
                }),
              ),

            // Date
            GestureDetector(
              onTap: existing != null
                  // The date is what identifies a recorded day, so an
                  // edit corrects the headcount, not which day it was.
                  ? null
                  : () async {
                      // An open stretch has no end to pick, so offering a
                      // range picker would take an end date and then ignore
                      // it. Ask for the start only.
                      if (stillRunning) {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2026, 1, 1),
                          lastDate: _today,
                          helpText: 'Started on',
                        );
                        if (picked == null) return;
                        setSheet(() => date = picked);
                        return;
                      }
                      final picked = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(2026, 1, 1),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        initialDateRange: DateTimeRange(
                            start: date, end: endDate ?? date),
                        helpText: 'Days worked',
                        saveText: 'Done',
                      );
                      if (picked == null) return;
                      setSheet(() {
                        date = picked.start;
                        endDate = picked.end.difference(picked.start).inDays < 1
                            ? null
                            : picked.end;
                      });
                    },
              child: _field(
                  stillRunning
                      ? Icons.play_circle_outline
                      : (endDate == null
                          ? Icons.calendar_today
                          : Icons.date_range),
                  stillRunning
                      ? _openStretchLabel(date, saturdaysWorked, kind)
                      : _dateLabel(date, endDate, saturdaysWorked, kind),
                  enabled: existing == null),
            ),
            if (existing == null) ...[
              const SizedBox(height: 10),
              _sheetToggle(
                icon: Icons.all_inclusive,
                label: 'Still running',
                hint: 'Open-ended - records up to today',
                value: stillRunning,
                onChanged: (v) => setSheet(() {
                  stillRunning = v;
                  // An end date and an open stretch are contradictory.
                  if (v) endDate = null;
                }),
              ),
              ..._dayPickers(
                from: date,
                to: stillRunning ? _today : endDate,
                selected: _seedDays(
                    from: date,
                    to: stillRunning ? _today : endDate,
                    kind: kind,
                    chosen: chosenDays,
                    touched: daysTouched),
                onChange: (next) => setSheet(() {
                  chosenDays
                    ..clear()
                    ..addAll(next);
                  // Once anything is ticked by hand the selection stands on
                  // its own. Re-seeding from the rule after that would undo
                  // the edit the moment the range or kind changed.
                  daysTouched = true;
                }),
                kind: kind,
              ),
            ],
            const SizedBox(height: 12),

            // Other: what it was, how many, and the rate if known.
            if (kind == MusterKind.other)
              ..._otherFields(item, qty, rate, setSheet)
            // Headcount - manpower only. Workshop rental is flat per
            // operational day whoever is in it, so a head count on a
            // workshop day would be a number that bills nothing.
            else if (!kind.isHeadCounted)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF050811).withAlpha(160),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFF849495).withAlpha(90)),
                ),
                child: Row(children: [
                  const Icon(Icons.currency_rupee, color: _muted, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        kind == MusterKind.deadweight
                            ? 'Flat ${_inr.format(kDeadWeightRatePerDay)} per day of hire  ·  250 kg'
                            : 'Flat ${_inr.format(kWorkshopRatePerDay)} per operational day',
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white70, fontSize: 13)),
                  ),
                ]),
              )
            else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF050811).withAlpha(160),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF849495).withAlpha(90)),
              ),
              child: Row(children: [
                const Icon(Icons.groups, color: _muted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('People on site',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white70, fontSize: 13)),
                ),
                _stepBtn(Icons.remove,
                    () => setSheet(() => count = count > 0 ? count - 1 : 0)),
                Container(
                  width: 44,
                  alignment: Alignment.center,
                  child: Text('$count',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                ),
                _stepBtn(Icons.add,
                    () => setSheet(() => count = count < 50 ? count + 1 : 50)),
              ]),
            ),
            if (endDate != null || stillRunning) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    // Counts the days actually ticked, not what the rule would
                    // have picked. The two differ the moment a day is
                    // unticked, and this line is the one people read back
                    // before saving.
                    'Recorded against each of the '
                    '${_seedDays(from: date, to: stillRunning ? _today : endDate, kind: kind, chosen: chosenDays, touched: daysTouched).length} '
                    'day(s) ticked above.',
                    style: GoogleFonts.spaceGrotesk(
                        color: _muted, fontSize: 11)),
              ),
            ],
            const SizedBox(height: 12),

            // PO — not for an "other" entry, which draws on none.
            if (kind != MusterKind.other) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF050811).withAlpha(160),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF849495).withAlpha(90)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: po.isEmpty ? null : po,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0A1025),
                  hint: Text('${kind.label} PO',
                      style: GoogleFonts.spaceGrotesk(
                          color: _muted, fontSize: 13)),
                  icon: const Icon(Icons.arrow_drop_down, color: _muted),
                  items: _posFor(kind).map((p) {
                    final n = (p['po_number'] as String? ?? '').trim();
                    final st = (p['po_status'] as String? ?? '');
                    return DropdownMenuItem(
                      value: n,
                      child: Text('PO $n${st == 'active' ? '' : ' ($st)'}',
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white, fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (v) => setSheet(() => po = v ?? ''),
                ),
              ),
            ),
            _destinationHint(kind, po),
            _poCapacityBar(kind, po),
            const SizedBox(height: 12),
            ],

            // Project the day is booked to
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF050811).withAlpha(160),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF849495).withAlpha(90)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: ProjectCatalog.displayNames.contains(project)
                      ? project
                      : null,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF0A1025),
                  hint: Text('Project',
                      style: GoogleFonts.spaceGrotesk(
                          color: _muted, fontSize: 13)),
                  icon: const Icon(Icons.arrow_drop_down, color: _muted),
                  items: ProjectCatalog.displayNames
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p,
                                style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white, fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) => setSheet(() => project = v ?? project),
                ),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: notes,
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Note (optional)',
                hintStyle:
                    GoogleFonts.spaceGrotesk(color: _muted, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF050811).withAlpha(160),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF849495).withAlpha(90))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: const Color(0xFF849495).withAlpha(90))),
              ),
            ),
            const SizedBox(height: 18),

            Row(children: [
              if (existing?.id != null) ...[
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _delete(existing!);
                    },
                    child: Text('Delete',
                        style: GoogleFonts.spaceGrotesk(
                            color: _red, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (kind == MusterKind.other
                          ? item.text.trim().isEmpty
                          : po.isEmpty)
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final note = notes.text.trim().isEmpty
                              ? null
                              : notes.text.trim();
                          final rangeEnd =
                              stillRunning ? _today : endDate;
                          if (kind == MusterKind.other) {
                            final entry = MusterDay(
                              id: existing?.id,
                              date: DateTime(date.year, date.month, date.day),
                              headCount: 0,
                              poNumber: '',
                              projectName: project,
                              notes: note,
                              kind: MusterKind.other,
                              item: item.text.trim(),
                              quantity: double.tryParse(qty.text.trim()) ?? 1,
                              rate: double.tryParse(
                                  rate.text.trim().replaceAll(',', '')),
                            );
                            await _saveOther(
                              entry,
                              rangeEnd == null
                                  ? null
                                  : _seedDays(
                                      from: date,
                                      to: rangeEnd,
                                      kind: kind,
                                      chosen: chosenDays,
                                      touched: daysTouched),
                            );
                            return;
                          }
                          if (rangeEnd == null) {
                            await _save(MusterDay(
                              id: existing?.id,
                              date:
                                  DateTime(date.year, date.month, date.day),
                              headCount: count,
                              poNumber: po,
                              projectName: project,
                              notes: note,
                              kind: kind,
                            ));
                          } else {
                            await _saveRange(
                              from: date,
                              to: rangeEnd,
                              headCount: count,
                              poNumber: po,
                              projectName: project,
                              notes: note,
                              kind: kind,
                              saturdaysWorked: saturdaysWorked,
                              onlyDays: _seedDays(
                                  from: date,
                                  to: rangeEnd,
                                  kind: kind,
                                  chosen: chosenDays,
                                  touched: daysTouched),
                            );
                          }
                        },
                  child: Text('Save',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ]),
        ),
        ),
      ),
    );
  }

  Widget _field(IconData icon, String text, {bool enabled = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF050811).withAlpha(160),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF849495).withAlpha(90)),
        ),
        child: Row(children: [
          Icon(icon, color: _muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.spaceGrotesk(
                    color: enabled ? Colors.white : Colors.white54,
                    fontSize: 13)),
          ),
          if (enabled) const Icon(Icons.edit, color: _muted, size: 15),
        ]),
      );

  Widget _kindTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? _teal.withAlpha(30)
                  : const Color(0xFF050811).withAlpha(160),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _teal.withAlpha(150)
                    : const Color(0xFF849495).withAlpha(90),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: selected ? _teal : _muted),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: selected ? _teal : _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ]),
          ),
        ),
      );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _teal.withAlpha(26),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _teal.withAlpha(70)),
          ),
          child: Icon(icon, color: _teal, size: 17),
        ),
      );

  /// One chip per Saturday inside the chosen range.
  ///
  /// Saturday is worked some weeks and not others, so neither "always" nor
  /// "never" is right and a single switch cannot express it. Each Saturday in
  /// the range is listed and ticked individually. Sunday is not offered at all.
  /// What the calendar should show before anybody edits it.
  ///
  /// The rule for the kind — Mon-Fri for manpower, every day for a hire —
  /// so the common case needs no clicks. Once [chosen] has been touched it is
  /// returned untouched, because re-deriving it would wipe the correction the
  /// user came here to make.
  Set<String> _seedDays({
    required DateTime from,
    required DateTime? to,
    required MusterKind kind,
    required Set<String> chosen,
    bool touched = false,
  }) {
    if (touched || to == null) return chosen;
    if (chosen.isNotEmpty) return chosen;
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final out = <String>{};
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (MusterService.booksADay(d, kind, const {})) {
        out.add(d.toIso8601String().split('T').first);
      }
    }
    return out;
  }

  /// Every day in the stretch, as a calendar you tick.
  ///
  /// The Saturday chips could only answer "was Saturday worked". The
  /// assistant is not on site every working day — leave, a day off, a week
  /// with no testing — and a range plus a weekday rule has no way to say "not
  /// that Tuesday". October was recorded as a clean 1–15 run for exactly this
  /// reason and then stopped, leaving ten days MOICARS had billed and the
  /// register had not.
  ///
  /// Seeded from the rule rather than left blank: the common case is still
  /// Mon–Fri for manpower and every day for a hire, so the calendar opens on
  /// the right answer and is corrected rather than filled in.
  List<Widget> _dayPickers({
    required DateTime from,
    required DateTime? to,
    required Set<String> selected,
    required void Function(Set<String> next) onChange,
    required MusterKind kind,
  }) {
    if (to == null) return const [];
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return const [];

    final days = <DateTime>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(d);
    }
    // A very long stretch is a scrolling wall of boxes with no way to see a
    // month at a time; the rule still covers it and the register can be
    // corrected per day afterwards.
    if (days.length > 70) return const [];

    String k(DateTime d) => d.toIso8601String().split('T').first;
    final accent = switch (kind) {
      MusterKind.workshop => _amber,
      MusterKind.deadweight => _deadColour,
      MusterKind.other => _otherColour,
      _ => _teal,
    };

    // Grouped by month so a stretch crossing a month boundary reads as two
    // calendars rather than one run-on strip.
    final months = <String, List<DateTime>>{};
    for (final d in days) {
      months.putIfAbsent(DateFormat('MMMM yyyy').format(d), () => []).add(d);
    }

    return [
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: Text('Which days?',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        _miniBtn('All', () {
          onChange({for (final d in days) k(d)});
        }),
        const SizedBox(width: 6),
        _miniBtn('Weekdays', () {
          onChange({
            for (final d in days)
              if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday)
                k(d)
          });
        }),
        const SizedBox(width: 6),
        _miniBtn('None', () => onChange(<String>{})),
      ]),
      const SizedBox(height: 2),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
            '${selected.length} day${selected.length == 1 ? '' : 's'} selected'
            '  ·  tap to add or remove',
            style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 10)),
      ),
      const SizedBox(height: 10),
      for (final entry in months.entries) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(entry.key.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2)),
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: entry.value.map((d) {
            final key = k(d);
            final on = selected.contains(key);
            final weekend = d.weekday == DateTime.saturday ||
                d.weekday == DateTime.sunday;
            return GestureDetector(
              onTap: () {
                final next = Set<String>.from(selected);
                on ? next.remove(key) : next.add(key);
                onChange(next);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 42,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: on
                        ? accent.withAlpha(38)
                        : const Color(0xFF050811).withAlpha(160),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: on
                            ? accent.withAlpha(150)
                            : const Color(0xFF849495).withAlpha(60)),
                  ),
                  child: Column(children: [
                    Text(DateFormat('E').format(d).substring(0, 2),
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            // Weekends stay legible but read as the exception,
                            // so an unticked Saturday does not look like a bug.
                            color: on
                                ? accent
                                : (weekend ? _amber.withAlpha(140) : _muted))),
                    Text('${d.day}',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: on ? Colors.white : _muted)),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _miniBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFF849495).withAlpha(80)),
            ),
            child: Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70)),
          ),
        ),
      );

  List<Widget> _saturdayPickers({
    required DateTime from,
    required DateTime? to,
    required Set<String> selected,
    required void Function(String key) onToggle,
    MusterKind kind = MusterKind.manpower,
  }) {
    if (to == null) return const [];
    // Workshop books all seven days, so there is nothing to opt into and the
    // "Sundays are never counted" line beneath it was simply untrue there.
    if (kind == MusterKind.workshop) return const [];
    final sats = <DateTime>[];
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (d.weekday == DateTime.saturday) sats.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    if (sats.isEmpty) return const [];

    return [
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
            sats.length == 1
                ? 'Was this Saturday worked?'
                : 'Which Saturdays were worked?',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 2),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('Sundays are never counted.',
            style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 10)),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: sats.map((s) {
          final key = s.toIso8601String().split('T').first;
          final on = selected.contains(key);
          return GestureDetector(
            onTap: () => onToggle(key),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: on
                      ? _teal.withAlpha(30)
                      : const Color(0xFF050811).withAlpha(160),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: on
                          ? _teal.withAlpha(140)
                          : const Color(0xFF849495).withAlpha(90)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(on ? Icons.check_circle : Icons.circle_outlined,
                      size: 13, color: on ? _teal : _muted),
                  const SizedBox(width: 6),
                  Text(DateFormat('d MMM').format(s),
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white : Colors.white60)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    ];
  }

  Widget _sheetToggle({
    required IconData icon,
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      GestureDetector(
        onTap: () => onChanged(!value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: value
                  ? _teal.withAlpha(22)
                  : const Color(0xFF050811).withAlpha(160),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: value
                      ? _teal.withAlpha(120)
                      : const Color(0xFF849495).withAlpha(90)),
            ),
            child: Row(children: [
              Icon(icon, size: 17, color: value ? _teal : _muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: GoogleFonts.spaceGrotesk(
                              color: value ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(hint,
                          style: GoogleFonts.spaceGrotesk(
                              color: _muted, fontSize: 10)),
                    ]),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: _teal,
              ),
            ]),
          ),
        ),
      );

  /// Days in an inclusive range that will actually be recorded.
  ///
  /// Mirrors the rule in [MusterService.saveRange] rather than restating it:
  /// manpower keeps the Mon-Fri week with named Saturdays, workshop books
  /// every calendar day because the bay is rented continuously and is payable
  /// whether or not anybody is in it.
  ///
  /// The weekday rule used to be applied to both. The save was right and only
  /// the screen was wrong, which is the worst way round — a workshop sheet
  /// read "22 working days" and then wrote 31 rows, and offered a Saturday
  /// picker that changed nothing.
  int _workingDays(DateTime from, DateTime to, Set<String> saturdays,
      [MusterKind kind = MusterKind.manpower]) {
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(d)) return 0;
    var n = 0;
    while (!d.isAfter(end)) {
      if (MusterService.booksADay(d, kind, saturdays)) n++;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return n;
  }

  /// Today, as the end of an open stretch.
  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _openStretchLabel(DateTime from, Set<String> saturdays,
      [MusterKind kind = MusterKind.manpower]) {
    final n = _workingDays(from, _today, saturdays, kind);
    final left = DateFormat('d MMM yyyy').format(from);
    if (_today.isBefore(from)) return '$left  -  still running';
    // "working days" would be a lie on a workshop stretch, where weekends
    // count too.
    final unit = kind == MusterKind.workshop ? 'days' : 'working days';
    return '$left  -  today   ·   $n $unit so far';
  }

  /// The most recent unbroken run of recorded days for one kind and PO.
  ///
  /// There is no stored "this stretch is open" flag - the rows are the record,
  /// so the run is derived from them. Weekends are stepped over rather than
  /// treated as breaks, since Mon-Fri work leaves a two-day hole every week
  /// that is not a pause in the stretch.
  ///
  /// Returns null when nothing is recorded for that kind and PO.
  ({DateTime from, DateTime to, int days})? _currentRun(
      MusterKind kind, String po) {
    final keys = _days
        .where((d) => d.kind == kind && d.poNumber == po)
        .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
        .toSet()
        .toList()
      ..sort();
    if (keys.isEmpty) return null;

    final last = keys.last;
    var start = last;
    var count = 1;
    // Walk backwards while the previous recorded day is the previous working
    // day. Anything further back is a separate stretch.
    //
    // A workshop stretch has no weekend hole to step over, so a missing
    // Saturday there is a real break in the hire and must not be bridged.
    for (var i = keys.length - 2; i >= 0; i--) {
      var probe = DateTime(start.year, start.month, start.day - 1);
      while (kind != MusterKind.workshop &&
          (probe.weekday == DateTime.saturday ||
              probe.weekday == DateTime.sunday)) {
        probe = DateTime(probe.year, probe.month, probe.day - 1);
      }
      if (keys[i] == probe || keys[i] == DateTime(start.year, start.month, start.day - 1)) {
        start = keys[i];
        count++;
      } else {
        break;
      }
    }
    return (from: start, to: last, days: count);
  }

  /// Days between the end of a run and today that are still unrecorded.
  ///
  /// Counted on the same rule the save uses, so the banner cannot promise a
  /// smaller catch-up than "Extend to today" will actually write.
  int _gapToToday(DateTime lastRecorded,
      [MusterKind kind = MusterKind.manpower]) {
    var d = DateTime(lastRecorded.year, lastRecorded.month, lastRecorded.day + 1);
    var n = 0;
    while (d.isBefore(_today) || d.isAtSameMomentAs(_today)) {
      if (kind == MusterKind.workshop ||
          (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday)) {
        n++;
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return n;
  }

  /// Shows what is already recorded for the selected kind and PO, so opening
  /// the sheet tells you where the stretch stands instead of presenting a
  /// blank form. "Still running" only ever affected writing - it filled rows up
  /// to that day and left nothing behind saying a run was open, which is why
  /// a reopened sheet looked empty.
  List<Widget> _runBanner({
    required MusterKind kind,
    required String po,
    required void Function(DateTime from) onExtend,
  }) {
    if (po.isEmpty) return const [];
    final run = _currentRun(kind, po);
    if (run == null) return const [];

    final gap = _gapToToday(run.to, kind);
    final upToDate = gap == 0;
    final colour = upToDate ? _green : _amber;
    final label = kind == MusterKind.workshop ? 'Workshop' : 'Manpower';

    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colour.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colour.withAlpha(90)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(upToDate ? Icons.check_circle : Icons.pending_actions,
                size: 15, color: colour),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '$label recorded '
                  '${DateFormat('d MMM').format(run.from)} - '
                  '${DateFormat('d MMM').format(run.to)}'
                  '   ${run.days} day${run.days == 1 ? '' : 's'}',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              upToDate
                  ? 'Up to date. Nothing further to record for this stretch.'
                  : '$gap ${kind == MusterKind.workshop ? 'day' : 'working day'}'
                      '${gap == 1 ? '' : 's'} since, not yet '
                      'recorded. Extend if the stretch ran on; leave it if it '
                      'stopped on ${DateFormat('d MMM').format(run.to)}.',
              style: GoogleFonts.spaceGrotesk(
                  color: _muted, fontSize: 10.5, height: 1.4)),
          if (!upToDate) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onExtend(run.from),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colour.withAlpha(140)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.fast_forward_rounded, size: 15, color: colour),
                label: Text('Extend to today',
                    style: GoogleFonts.spaceGrotesk(
                        color: colour,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Names the card this entry will land on, and what is already sitting
  /// there.
  ///
  /// Cards are grouped by PO number alone, so the PO picked above is the
  /// whole answer to where a saved day turns up. The two drift apart easily:
  /// workshop defaults to the current track PO while the historical one is
  /// usually the card on screen, so a day saved against 8242390552 looks like
  /// it went nowhere when the 8242348442 card is the one being watched.
  ///
  /// Unlike [_runBanner] this shows even when nothing is recorded yet - a PO
  /// with no days is exactly the case that needs telling where to look.
  /// How full the destination PO is, live, as the day is being booked.
  ///
  /// Manpower POs are contracted in days, so they can genuinely run out — and
  /// 8242356330 did, at exactly its 38 days, while the sheet was still
  /// defaulting to it. Nothing said so: days kept being accepted against a PO
  /// with no budget left, and the overrun would only have surfaced when
  /// somebody tried to invoice it.
  ///
  /// Workshop draws a lumpsum track PO billed on actuals, which has no
  /// contracted day count to exhaust, so it gets no bar rather than an
  /// invented one.
  Widget _poCapacityBar(MusterKind kind, String po) {
    if (kind != MusterKind.manpower || po.isEmpty) {
      return const SizedBox.shrink();
    }
    final p = _positionFor(po);
    if (p == null || p.daysContracted <= 0) return const SizedBox.shrink();

    final left = p.daysLeft;
    final over = p.isOverrun;
    final colour = over || p.isExhausted
        ? _red
        : (p.isNearlyExhausted ? _amber : _green);
    final next = MusterService.instance.nextManpowerPo(_positions);
    final rollover = (p.isExhausted || over) && next != null && next != po;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              over || p.isExhausted
                  ? Icons.error_outline
                  : (p.isNearlyExhausted
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline),
              size: 13,
              color: colour),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                over
                    ? 'PO $po is over by ${(-left).toStringAsFixed(0)} day'
                        '${-left == 1 ? '' : 's'}'
                    : p.isExhausted
                        ? 'PO $po has no days left'
                        : '${left.toStringAsFixed(0)} of '
                            '${p.daysContracted.toStringAsFixed(0)} days left '
                            'on PO $po',
                style: GoogleFonts.spaceGrotesk(
                    color: colour,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: p.fractionUsed,
            minHeight: 5,
            backgroundColor: const Color(0xFF1E293B),
            valueColor: AlwaysStoppedAnimation(colour),
          ),
        ),
        if (rollover) ...[
          const SizedBox(height: 6),
          Text(
              'New days should go to PO $next — it is the next one in force '
              'with days remaining.',
              style: GoogleFonts.spaceGrotesk(
                  color: _amber, fontSize: 10, height: 1.4)),
        ],
        if (p.isNearlyExhausted && !rollover) ...[
          const SizedBox(height: 6),
          Text(
              'Booking a stretch longer than ${left.toStringAsFixed(0)} day'
              '${left == 1 ? '' : 's'} will overrun this PO.',
              style: GoogleFonts.spaceGrotesk(
                  color: _amber, fontSize: 10, height: 1.4)),
        ],
      ]),
    );
  }

  Widget _destinationHint(MusterKind kind, String po) {
    if (po.isEmpty) return const SizedBox.shrink();
    final isWorkshop = kind == MusterKind.workshop;
    final colour = isWorkshop ? _amber : _teal;
    // Matches the card headings verbatim, so the hint names something the
    // eye can actually find on the page behind the sheet.
    final title = isWorkshop ? 'Workshop · PO $po' : 'PO $po';

    // Read off the same position lists the cards are built from, so this
    // cannot disagree with the number the card shows.
    String standing = 'Nothing recorded there yet — this starts its count.';
    if (isWorkshop) {
      for (final w in _workshopPositions) {
        if (w.poNumber != po) continue;
        if (w.daysRecorded > 0) {
          standing = '${w.daysRecorded} day'
              '${w.daysRecorded == 1 ? '' : 's'} already recorded there.';
        }
        break;
      }
    } else {
      for (final m in _positions) {
        if (m.poNumber != po) continue;
        if (m.manDaysUsed > 0) {
          standing = '${m.manDaysUsed.toStringAsFixed(0)} man-days '
              'already used there.';
        }
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withAlpha(16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colour.withAlpha(70)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.subdirectory_arrow_right_rounded, size: 15, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Goes on the "$title" card',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(standing,
                style: GoogleFonts.spaceGrotesk(
                    color: _muted, fontSize: 10.5, height: 1.4)),
          ]),
        ),
      ]),
    );
  }

  /// Days in an inclusive range - 19th to 19th is one day, not zero.
  int _daysInclusive(DateTime from, DateTime to) =>
      DateTime(to.year, to.month, to.day)
          .difference(DateTime(from.year, from.month, from.day))
          .inDays +
      1;

  String _dateLabel(DateTime from, DateTime? to,
      [Set<String> saturdays = const {},
      MusterKind kind = MusterKind.manpower]) {
    if (to == null) return DateFormat('EEE, d MMM yyyy').format(from);
    final n = _workingDays(from, to, saturdays, kind);
    final span = _daysInclusive(from, to);
    final sameYear = from.year == to.year;
    final left = DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(from);
    final right = DateFormat('d MMM yyyy').format(to);
    // Show both when a weekend is being skipped, so the difference between
    // the range dragged and the days actually booked is visible up front.
    final tail = (n != span)
        ? '$n working days (of $span)'
        : '$n days';
    return '$left  -  $right   ·   $tail';
  }

  Future<void> _saveRange({
    required DateTime from,
    required DateTime to,
    required int headCount,
    required String poNumber,
    String? projectName,
    String? notes,
    MusterKind kind = MusterKind.manpower,
    Set<String> saturdaysWorked = const {},
    Set<String>? onlyDays,
  }) async {
    try {
      final n = await MusterService.instance.saveRange(
        from: from,
        to: to,
        headCount: headCount,
        poNumber: poNumber,
        projectName: projectName,
        notes: notes,
        kind: kind,
        saturdaysWorked: saturdaysWorked,
        onlyDays: onlyDays,
      );
      // Zero is a real outcome, and now usually means the calendar was
      // cleared rather than that the range fell on a weekend.
      if (n == 0) {
        _snack('Nothing recorded - no days are ticked. '
            'Pick the days on the calendar, then save.');
        return;
      }
      _snack('$n ${n == 1 ? 'day' : 'days'} recorded');
      // No _load() here, or anywhere below: the service notified on write and
      // _onMusterChanged is already reloading. Calling it again just fetches
      // the same rows twice.
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  Future<void> _save(MusterDay day) async {
    try {
      await MusterService.instance.save(day);
      _snack('Day recorded');
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  Future<void> _delete(MusterDay day) async {
    if (day.id == null) return;
    try {
      if (day.kind == MusterKind.other) {
        await MusterService.instance.deleteEntry(day.id!);
        _snack('Entry removed');
      } else {
        await MusterService.instance.delete(day.id!);
        _snack('Day removed');
      }
    } catch (e) {
      _snack('Could not remove: $e', error: true);
    }
  }

  /// Saves an "other" entry — one row, or one per ticked day of a range.
  Future<void> _saveOther(MusterDay entry, Set<String>? days) async {
    try {
      if (days == null || entry.id != null) {
        await MusterService.instance.saveEntry(entry);
        _snack('${entry.item} recorded');
      } else {
        final n = await MusterService.instance.saveEntries(entry, days);
        _snack(n == 0
            ? 'Nothing recorded - no days are ticked.'
            : '${entry.item} recorded on $n day${n == 1 ? '' : 's'}');
      }
    } catch (e) {
      final msg = e.toString();
      _snack(
          msg.contains('PGRST205') || msg.contains('does not exist')
              ? 'Other entries need the setup step first: run '
                  '20261113090000_muster_entries.sql in Supabase.'
              : 'Could not save: $e',
          error: true);
    }
  }

  /// Item, quantity and rate for an "other" entry, with the usual items one
  /// tap away.
  List<Widget> _otherFields(
    TextEditingController item,
    TextEditingController qty,
    TextEditingController rate,
    void Function(void Function()) setSheet,
  ) {
    const suggestions = [
      'Office / porta cabin',
      'Conference hall',
      'Food coupons',
      'Bisleri water 20L',
      'Weigh bridge',
      'Visitor',
      'Fuel',
    ];
    InputDecoration deco(String hint, {String? prefix}) => InputDecoration(
          hintText: hint,
          prefixText: prefix,
          prefixStyle: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 13),
          hintStyle: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 13),
          filled: true,
          isDense: true,
          fillColor: const Color(0xFF050811).withAlpha(160),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: const Color(0xFF849495).withAlpha(90))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: const Color(0xFF849495).withAlpha(90))),
        );
    final style = GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 13);
    final q = double.tryParse(qty.text.trim()) ?? 0;
    final r = double.tryParse(rate.text.trim().replaceAll(',', ''));
    return [
      TextField(
        controller: item,
        style: style,
        decoration: deco('What was it? e.g. Conference hall'),
        onChanged: (_) => setSheet(() {}),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in suggestions)
            GestureDetector(
              onTap: () => setSheet(() => item.text = s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: item.text == s
                      ? _otherColour.withAlpha(40)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: item.text == s
                          ? _otherColour
                          : const Color(0xFF849495).withAlpha(70)),
                ),
                child: Text(s,
                    style: GoogleFonts.spaceGrotesk(
                        color: item.text == s ? _otherColour : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: qty,
            style: style,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco('Quantity', prefix: 'Qty  '),
            onChanged: (_) => setSheet(() {}),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: rate,
            style: style,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: deco('Rate (optional)', prefix: '₹  '),
            onChanged: (_) => setSheet(() {}),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
            r == null
                ? 'A record of the day. Not added to any programme cost — '
                    'NATRAX charges go in Manual Entry → Other Services.'
                : '${_qty(q)} × ${_inr.format(r)} = ${_inr.format(q * r)} per day. '
                    'A record only; not added to programme cost.',
            style: GoogleFonts.spaceGrotesk(
                color: _muted, fontSize: 11, height: 1.4)),
      ),
    ];
  }
}

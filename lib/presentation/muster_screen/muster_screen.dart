import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/invoice_service.dart';
import '../../services/muster_service.dart';
import '../../services/project_catalog.dart';
import '../../services/project_manager.dart';

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
  List<ManpowerPosition> _positions = [];
  List<Map<String, dynamic>> _pos = [];
  // Workshop is billed on the NATRAX track PO, a different pool from the
  // MOICARS manpower POs, so the sheet offers a different list per kind.
  List<Map<String, dynamic>> _workshopPos = [];
  List<WorkshopPosition> _workshopPositions = [];

  static const _teal = AppTheme.primary;
  static const _amber = Color(0xFFFFB547);
  static const _red = Color(0xFFFF6B6B);
  static const _green = Color(0xFF4CAF50);
  static const _muted = Color(0xFF6B7490);

  final _inr = NumberFormat.currency(
      locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
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
      final positions = await MusterService.instance
          .positions(invoicedExclGstByPo: invoicedExcl);
      final pos = await MusterService.instance.activeManpowerPos();
      final wPos = await MusterService.instance.workshopPos();
      final wPositions = await MusterService.instance.workshopPositions();

      if (!mounted) return;
      setState(() {
        _readOnly = profile?.isReadOnly ?? true;
        _days = days;
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
    final active = list.firstWhere(
      (p) => (p['po_status'] as String? ?? '') == 'active',
      orElse: () => list.first,
    );
    return (active['po_number'] as String? ?? '').trim();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      floatingActionButton: _readOnly || _pos.isEmpty
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
                          ..._positions.map(_positionCard),
                          ..._workshopPositions.map(_workshopCard),
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
            Text('Manpower Muster',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(
                'Headcount per day — ${ProjectManager.instance.activeProject}',
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

  /// Workshop position: days recorded and what they accrue.
  ///
  /// Deliberately has no "days left" bar. The track PO workshop is billed on is
  /// a lumpsum on actuals, not a contracted number of days, so there is no
  /// remaining-days figure to show and inventing one would be worse than
  /// leaving it out.
  Widget _workshopCard(WorkshopPosition p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(200),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _amber.withAlpha(60)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.home_repair_service, color: _amber, size: 15),
          const SizedBox(width: 8),
          Text('Workshop · PO ${p.poNumber}',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          if (p.isClosed) ...[
            const Spacer(),
            Text('closed',
                style: GoogleFonts.spaceGrotesk(
                    color: _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _stat('Days recorded', '${p.daysRecorded}', 'days', Colors.white),
          _stat('Rate', _inr.format(p.ratePerDay), 'per day', Colors.white),
          _stat('Accrued', _inr.format(p.accruedExclGst), 'excl GST', _amber),
        ]),
        const SizedBox(height: 10),
        Text(
            p.isClosed
                ? 'This PO is closed. The days on it are historical and no '
                    'new ones can be booked against it.'
                : p.daysRecorded == 0
                    ? 'No workshop days recorded yet. Mark a day and pick '
                        'WORKSHOP to start the count.'
                    : 'Billed on actuals against a lumpsum PO, so this '
                        'accrues rather than drawing a contracted day '
                        'count down.',
            style: GoogleFonts.spaceGrotesk(
                color: _muted, fontSize: 11, height: 1.5)),
      ]),
    );
  }

  Widget _positionCard(ManpowerPosition p) {
    final incomplete = !p.isComplete;
    final pct = p.daysContracted <= 0
        ? 0.0
        : (p.manDaysUsed / p.daysContracted).clamp(0.0, 1.0);
    final barColour =
        p.isOverrun ? _red : (pct > 0.85 ? _amber : _teal);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1025).withAlpha(200),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withAlpha(50)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('PO ${p.poNumber}',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          if (incomplete)
            Text('value / days pending',
                style: GoogleFonts.spaceGrotesk(
                    color: _amber, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        if (incomplete)
          Text(
              'This PO has no value or day count recorded, so days remaining '
              'cannot be worked out. The muster below still counts against it.',
              style: GoogleFonts.spaceGrotesk(
                  color: _muted, fontSize: 11, height: 1.5))
        else ...[
          Row(children: [
            _stat('Used', p.manDaysUsed.toStringAsFixed(0), 'man-days',
                p.isOverrun ? _red : Colors.white),
            _stat('Contracted', p.daysContracted.toStringAsFixed(0), 'days',
                Colors.white),
            _stat(
                'Left',
                p.daysLeft.toStringAsFixed(0),
                'days',
                p.daysLeft <= 0
                    ? _red
                    : (p.daysLeft <= 10 ? _amber : _green)),
          ]),
          if (p.manDaysOpening > 0) ...[
            const SizedBox(height: 8),
            Text(
                '${p.manDaysOpening.toStringAsFixed(0)} of those were worked '
                'before the muster started and are carried on the PO; '
                '${p.manDaysMustered} recorded here by date.',
                style: GoogleFonts.spaceGrotesk(
                    color: _muted, fontSize: 11, height: 1.4)),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation(barColour),
            ),
          ),
          const SizedBox(height: 10),
          Text(
              '${p.manDaysInvoiced.toStringAsFixed(0)} man-days invoiced '
              'at ${_inr.format(p.ratePerDay)}/day',
              style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
          if (p.daysUnbilled > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _amber.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _amber.withAlpha(70)),
              ),
              child: Text(
                  '${p.daysUnbilled.toStringAsFixed(0)} man-days worked but not '
                  'yet invoiced — ${_inr.format(p.valueUnbilled)} ex-GST '
                  'outside PO drawdown.',
                  style: GoogleFonts.spaceGrotesk(
                      color: _amber, fontSize: 11, height: 1.4)),
            ),
          ],
          if (p.isOverrun) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _red.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red.withAlpha(70)),
              ),
              child: Text(
                  'Mustered days exceed the PO by '
                  '${(p.manDaysMustered - p.daysContracted).toStringAsFixed(0)}. '
                  'A follow-on PO is needed before further manpower is booked.',
                  style: GoogleFonts.spaceGrotesk(
                      color: _red, fontSize: 11, height: 1.4)),
            ),
          ],
        ],
      ]),
    );
  }

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
    if (_days.isEmpty) {
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
              _pos.isEmpty
                  ? 'No manpower PO is loaded, so there is nothing to book a '
                      'day against yet.'
                  : 'Mark a day to start the register.',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
        ]),
      );
    }

    // Grouped by month, newest first — the register is read by month.
    final byMonth = <String, List<MusterDay>>{};
    for (final d in _days) {
      byMonth.putIfAbsent(d.monthKey, () => []).add(d);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: months.map((m) {
        final rows = byMonth[m]!;
        final manDays = rows
            .where((d) => d.kind == MusterKind.manpower)
            .fold<int>(0, (s, d) => s + d.headCount);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(children: [
              Text(_monthLabel(m),
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('$manDays man-days · ${rows.length} days',
                  style:
                      GoogleFonts.spaceGrotesk(color: _muted, fontSize: 11)),
            ]),
          ),
          ...rows.map(_dayTile),
        ]);
      }).toList(),
    );
  }

  Widget _dayTile(MusterDay d) {
    final isWorkshop = d.kind == MusterKind.workshop;
    // Amber zero means "day checked, nobody on site". A workshop day
    // legitimately carries head_count 0, so it must not borrow that
    // colour or it reads as an empty manpower day.
    final emptyManpowerDay = !isWorkshop && d.headCount == 0;
    final accent =
        isWorkshop ? _amber : (emptyManpowerDay ? _amber : _teal);
    return GestureDetector(
      onTap: _readOnly ? null : () => _entrySheet(existing: d),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1025).withAlpha(170),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: emptyManpowerDay || isWorkshop
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
            child: isWorkshop
                ? Icon(Icons.home_repair_service, color: accent, size: 17)
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
                  '${isWorkshop ? 'Workshop' : '${d.headCount} on site'}'
                  ' · PO ${d.poNumber}'
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
    var count = existing?.headCount ?? 1;
    var kind = existing?.kind ?? MusterKind.manpower;
    var po = existing?.poNumber ?? _defaultPo;
    // Which programme the day is worked against. Recorded on the row already,
    // but previously taken silently from whatever project was open elsewhere —
    // so a day could be attributed without the person marking it ever seeing
    // to what. Shown and editable, like the track entry form.
    var project = existing?.projectName ?? ProjectManager.instance.activeProject;
    final notes = TextEditingController(text: existing?.notes ?? '');

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A1025),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
              ]),
            if (existing == null) const SizedBox(height: 14),

            // Date
            GestureDetector(
              onTap: existing != null
                  // The date is what identifies a recorded day, so an
                  // edit corrects the headcount, not which day it was.
                  ? null
                  : () async {
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
                  endDate == null ? Icons.calendar_today : Icons.date_range,
                  _dateLabel(date, endDate),
                  enabled: existing == null),
            ),
            const SizedBox(height: 12),

            // Headcount - manpower only. Workshop rental is flat per
            // operational day whoever is in it, so a head count on a
            // workshop day would be a number that bills nothing.
            if (kind == MusterKind.workshop)
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
                        'Flat ${_inr.format(kWorkshopRatePerDay)} per operational day',
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
            if (endDate != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Recorded against each of the '
                    '${_daysInclusive(date, endDate!)} days.',
                    style: GoogleFonts.spaceGrotesk(
                        color: _muted, fontSize: 11)),
              ),
            ],
            const SizedBox(height: 12),

            // PO
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
            const SizedBox(height: 12),

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
                  onPressed: po.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final note = notes.text.trim().isEmpty
                              ? null
                              : notes.text.trim();
                          if (endDate == null) {
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
                              to: endDate!,
                              headCount: count,
                              poNumber: po,
                              projectName: project,
                              notes: note,
                              kind: kind,
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

  /// Days in an inclusive range - 19th to 19th is one day, not zero.
  int _daysInclusive(DateTime from, DateTime to) =>
      DateTime(to.year, to.month, to.day)
          .difference(DateTime(from.year, from.month, from.day))
          .inDays +
      1;

  String _dateLabel(DateTime from, DateTime? to) {
    if (to == null) return DateFormat('EEE, d MMM yyyy').format(from);
    final n = _daysInclusive(from, to);
    final sameYear = from.year == to.year;
    final left = DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(from);
    return '$left  -  ${DateFormat('d MMM yyyy').format(to)}   ·   $n days';
  }

  Future<void> _saveRange({
    required DateTime from,
    required DateTime to,
    required int headCount,
    required String poNumber,
    String? projectName,
    String? notes,
    MusterKind kind = MusterKind.manpower,
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
      );
      _snack('$n ${n == 1 ? 'day' : 'days'} recorded');
      await _load();
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  Future<void> _save(MusterDay day) async {
    try {
      await MusterService.instance.save(day);
      _snack('Day recorded');
      await _load();
    } catch (e) {
      _snack('Could not save: $e', error: true);
    }
  }

  Future<void> _delete(MusterDay day) async {
    if (day.id == null) return;
    try {
      await MusterService.instance.delete(day.id!);
      _snack('Day removed');
      await _load();
    } catch (e) {
      _snack('Could not remove: $e', error: true);
    }
  }
}

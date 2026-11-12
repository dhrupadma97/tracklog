import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/day_entries_service.dart';
import '../../services/natrax_rate_card.dart';
import '../../services/project_catalog.dart';
import '../../theme/app_theme.dart';

const _card = Color(0xFF0D1520);
const _line = Color(0xFF1E293B);
const _muted = Color(0xFF6B7490);
const _teal = AppTheme.primary;
const _amber = Color(0xFFFFB547);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFFF6B6B);

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = Colors.white, double? h}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c, height: h);

/// One day's track runs, opened from the Analyser's month-by-date table:
/// each run with its in/out time, and its comment to edit, the run to
/// change, or the run to delete. EV charging that day is listed too.
///
/// Every change prices the programme's day again — see [DayEntriesService] —
/// and says what the day cost before and after.
class DayEntriesDialog extends StatefulWidget {
  final DateTime day;
  final Set<String> projects;
  const DayEntriesDialog({super.key, required this.day, required this.projects});

  /// True if anything was changed, so the caller reloads.
  static Future<bool?> show(BuildContext context,
          {required DateTime day, required Set<String> projects}) =>
      showDialog<bool>(
        context: context,
        builder: (_) => DayEntriesDialog(day: day, projects: projects),
      );

  @override
  State<DayEntriesDialog> createState() => _DayEntriesDialogState();
}

class _DayEntriesDialogState extends State<DayEntriesDialog> {
  bool _loading = true;
  String? _error;
  List<DayEntry> _runs = [];
  List<({String project, String name, double units, double cost})> _ev = [];
  bool _changed = false;
  String? _status;
  bool _statusError = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([
        DayEntriesService.load(widget.day, widget.projects),
        DayEntriesService.loadEv(widget.day, widget.projects),
      ]);
      _runs = r[0] as List<DayEntry>;
      _ev = r[1] as List<({String project, String name, double units, double cost})>;
      _error = null;
    } catch (e) {
      _error = 'Could not load the day: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _say(String text, {bool error = false}) =>
      setState(() {
        _status = text;
        _statusError = error;
      });

  String _moved(({double before, double after}) r) {
    final day = DateFormat('d MMM').format(widget.day);
    return (r.before - r.after).abs() < 1
        ? '$day still costs ${_inr.format(r.after)}.'
        : '$day was ${_inr.format(r.before)}, now ${_inr.format(r.after)}.';
  }

  Future<void> _editComment(DayEntry e) async {
    final c = TextEditingController(text: e.comment);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: Text('Comment · ${e.code} ${e.timeLabel}', style: _t(15, w: FontWeight.w800)),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            style: _t(13),
            decoration: _field('e.g. NATRAX sheet shows 2 h, agreed'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: _t(13, c: _muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text('Save', style: _t(13, w: FontWeight.w700, c: _teal))),
        ],
      ),
    );
    if (text == null) return;
    setState(() => _busyId = e.id);
    try {
      await DayEntriesService.setComment(e, text);
      _changed = true;
      _say(text.trim().isEmpty ? 'Comment removed.' : 'Comment saved.');
      await _load();
    } catch (err) {
      _say('Could not save the comment: $err', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _change(DayEntry e) async {
    final result = await showDialog<_Edit>(
      context: context,
      builder: (_) => _EditRunDialog(entry: e),
    );
    if (result == null) return;
    setState(() => _busyId = e.id);
    try {
      final r = await DayEntriesService.update(e,
          code: result.code,
          startMin: result.startMin,
          minutes: result.minutes,
          project: result.project,
          comment: result.comment);
      _changed = true;
      _say('Run changed. ${_moved(r)}');
      await _load();
    } catch (err) {
      _say('Could not change the run: $err', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(DayEntry e) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: Text('Delete this run?', style: _t(15, w: FontWeight.w800)),
        content: Text(
            '${e.code} ${e.name}\n${DateFormat('d MMM').format(widget.day)}, '
            '${e.timeLabel} (${e.minutes} min) · ${e.project}\n\n'
            'This cannot be undone. The rest of the day is priced again.',
            style: _t(12.5, c: Colors.white70, h: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: _t(13, c: _muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: _t(13, w: FontWeight.w700, c: _red))),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _busyId = e.id);
    try {
      final r = await DayEntriesService.delete(e);
      _changed = true;
      _say('Run deleted. ${_moved(r)}');
      await _load();
    } catch (err) {
      _say('Could not delete: $err', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceDark,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _teal.withAlpha(60))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 6),
            child: Row(children: [
              const Icon(Icons.event_note_outlined, color: _teal, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(DateFormat('EEEE d MMMM yyyy').format(widget.day),
                    style: _t(16, w: FontWeight.w800)),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context, _changed),
                icon: const Icon(Icons.close, color: _muted),
              ),
            ]),
          ),
          if (_status != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_statusError ? _red : _green).withAlpha(24),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (_statusError ? _red : _green).withAlpha(100)),
              ),
              child: Text(_status!,
                  style: _t(12, w: FontWeight.w600, c: _statusError ? _red : _green)),
            ),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: _teal)))
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, style: _t(12.5, c: _amber)))
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                        children: [
                          _summary(),
                          const SizedBox(height: 14),
                          if (_runs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('No track runs this day.',
                                  style: _t(12.5, c: _muted)),
                            ),
                          for (final e in _runs) _runCard(e),
                          if (_ev.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _evCard(),
                          ],
                        ],
                      ),
          ),
        ]),
      ),
    );
  }

  /// Per track: runs, minutes, billable hours and rupees, per programme,
  /// worked out the way NATRAX bill — so two tracks on one day each show
  /// their own utilisation.
  Widget _summary() {
    final byProject = <String, List<DayEntry>>{};
    for (final e in _runs) {
      byProject.putIfAbsent(e.project, () => []).add(e);
    }
    final rows = <TableRow>[];
    Widget c(String s, {bool head = false, bool right = true, Color? col, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Text(s,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: head
                  ? _t(9, w: FontWeight.w800, c: _muted).copyWith(letterSpacing: 0.8)
                  : _t(12, w: bold ? FontWeight.w800 : FontWeight.w600, c: col ?? Colors.white)),
        );
    rows.add(TableRow(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
      children: [
        c('TRACK', head: true, right: false),
        c('PROGRAMME', head: true, right: false),
        c('RUNS', head: true),
        c('MINUTES', head: true),
        c('BILLABLE H', head: true),
        c('COST', head: true),
      ],
    ));
    var totMin = 0, totRuns = 0;
    var totBill = 0.0, totCost = 0.0;
    byProject.forEach((project, list) {
      final mins = <String, int>{};
      final runs = <String, int>{};
      final cost = <String, double>{};
      for (final e in list) {
        mins[e.code] = (mins[e.code] ?? 0) + e.minutes;
        runs[e.code] = (runs[e.code] ?? 0) + 1;
        cost[e.code] = (cost[e.code] ?? 0) + e.cost;
      }
      final standard = {
        for (final k in mins.keys)
          if (!NatraxRateCard.isExclusive(k)) k: mins[k]!,
      };
      final bill = NatraxRateCard.billableForDay(standard);
      final codes = mins.keys.toList()..sort((a, b) => mins[b]!.compareTo(mins[a]!));
      for (final k in codes) {
        final b = NatraxRateCard.isExclusive(k)
            ? (mins[k]! / 60.0 / NatraxRateCard.blockHoursFor(k)).ceil() *
                NatraxRateCard.blockHoursFor(k)
            : (bill[k] ?? 0);
        totMin += mins[k]!;
        totRuns += runs[k]!;
        totBill += b;
        totCost += cost[k]!;
        rows.add(TableRow(children: [
          c('$k  ${NatraxRateCard.nameFor(k)}', right: false, bold: true),
          c(project, right: false, col: _muted),
          c('${runs[k]}', col: const Color(0xFF94A3B8)),
          c('${mins[k]}'),
          c(b == b.roundToDouble() ? b.toStringAsFixed(0) : b.toStringAsFixed(1), col: _teal, bold: true),
          c(_inr.format(cost[k])),
        ]));
      }
    });
    rows.add(TableRow(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
      children: [
        c('Day', right: false, bold: true),
        c('', right: false),
        c('$totRuns', bold: true, col: const Color(0xFF94A3B8)),
        c('$totMin', bold: true),
        c(totBill.toStringAsFixed(0), bold: true, col: _teal),
        c(_inr.format(totCost), bold: true),
      ],
    ));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.6),
          1: FlexColumnWidth(2.0),
          2: FlexColumnWidth(0.8),
          3: FlexColumnWidth(1.0),
          4: FlexColumnWidth(1.1),
          5: FlexColumnWidth(1.4),
        },
        children: rows,
      ),
    );
  }

  Widget _runCard(DayEntry e) {
    final busy = _busyId == e.id;
    final comment = e.comment;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: comment.isEmpty ? _line : _amber.withAlpha(70)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 104,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.timeLabel, style: _t(13, w: FontWeight.w800)),
            Text('${e.minutes} min', style: _t(11, c: _muted)),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.code}  ${e.name.isEmpty ? NatraxRateCard.nameFor(e.code) : e.name}',
                style: _t(13, w: FontWeight.w700)),
            Text('${e.project}${e.venue == 'NATRAX' ? '' : ' · ${e.venue}'} · ${_inr.format(e.cost)}',
                style: _t(11, c: _muted)),
            const SizedBox(height: 4),
            Text(comment.isEmpty ? 'No comment' : comment,
                style: _t(11.5,
                    c: comment.isEmpty ? const Color(0xFF3A4560) : const Color(0xFFE2C18C),
                    h: 1.35)),
          ]),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _teal)),
          )
        else ...[
          _action(Icons.chat_bubble_outline, 'Comment', () => _editComment(e)),
          _action(Icons.edit_outlined, 'Change', () => _change(e)),
          _action(Icons.delete_outline, 'Delete', () => _delete(e), colour: _red),
        ],
      ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {Color colour = _teal}) =>
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton.icon(
          onPressed: _busyId == null ? onTap : null,
          style: TextButton.styleFrom(
            foregroundColor: colour,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
          ),
          icon: Icon(icon, size: 14),
          label: Text(label, style: _t(11, w: FontWeight.w700, c: colour)),
        ),
      );

  Widget _evCard() {
    final units = _ev.fold<double>(0, (s, l) => s + l.units);
    final cost = _ev.fold<double>(0, (s, l) => s + l.cost);
    String u(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _green.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withAlpha(80)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.ev_station_outlined, color: _green, size: 17),
          const SizedBox(width: 8),
          Expanded(
              child: Text('EV CHARGING',
                  style: _t(11, w: FontWeight.w800, c: _green).copyWith(letterSpacing: 1.2))),
          Text('${u(units)} units · ${_inr.format(cost)}',
              style: _t(12.5, w: FontWeight.w800, c: _green)),
        ]),
        const SizedBox(height: 8),
        for (final l in _ev)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              Expanded(child: Text('${l.name} · ${l.project}', style: _t(11.5, c: Colors.white70))),
              Text('${u(l.units)} units', style: _t(11.5, w: FontWeight.w700)),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: Text(_inr.format(l.cost),
                    textAlign: TextAlign.right, style: _t(11.5, c: _muted)),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        Text('EV charging is edited in Manual Entry → Other Services.',
            style: _t(10.5, c: _muted)),
      ]),
    );
  }
}

InputDecoration _field(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: _t(12, c: const Color(0xFF4A5470)),
      isDense: true,
      filled: true,
      fillColor: AppTheme.backgroundDark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _teal.withAlpha(140))),
    );

class _Edit {
  final String code;
  final int startMin;
  final int minutes;
  final String project;
  final String comment;
  const _Edit(this.code, this.startMin, this.minutes, this.project, this.comment);
}

/// Change one run: its track, in and out times, programme and comment.
class _EditRunDialog extends StatefulWidget {
  final DayEntry entry;
  const _EditRunDialog({required this.entry});

  @override
  State<_EditRunDialog> createState() => _EditRunDialogState();
}

class _EditRunDialogState extends State<_EditRunDialog> {
  late String _code = widget.entry.code;
  late int _start = widget.entry.startMin;
  late int _end = widget.entry.endMin;
  late String _project = widget.entry.project;
  late final _comment = TextEditingController(text: widget.entry.comment);

  int get _minutes {
    final m = _end - _start;
    return m <= 0 ? m + 24 * 60 : m;
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final v = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: v ~/ 60, minute: v % 60),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() => start ? _start = t.hour * 60 + t.minute : _end = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final codes = [
      for (final t in NatraxRateCard.tracks) t['code'] as String,
      if (!NatraxRateCard.knows(_code)) _code,
    ];
    final projects = [
      ...ProjectCatalog.displayNames,
      if (!ProjectCatalog.displayNames.contains(_project)) _project,
    ];
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 5, top: 12),
          child: Text(s, style: _t(10.5, w: FontWeight.w700, c: _muted)),
        );
    Widget timeBox(String l, int v, bool start) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label(l),
            InkWell(
              onTap: () => _pick(start),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _line),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule, size: 15, color: _teal),
                  const SizedBox(width: 8),
                  Text(DayEntry.clock(v), style: _t(14, w: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
        );
    return AlertDialog(
      backgroundColor: AppTheme.surfaceDark,
      title: Text('Change run · ${DateFormat('d MMM').format(widget.entry.start)}',
          style: _t(15, w: FontWeight.w800)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            label('TRACK'),
            DropdownButtonFormField<String>(
              initialValue: _code,
              dropdownColor: AppTheme.surfaceDark,
              isExpanded: true,
              decoration: _field(''),
              style: _t(13),
              items: [
                for (final c in codes)
                  DropdownMenuItem(value: c, child: Text('$c  ${NatraxRateCard.nameFor(c)}')),
              ],
              onChanged: (v) => setState(() => _code = v ?? _code),
            ),
            Row(children: [
              timeBox('IN', _start, true),
              const SizedBox(width: 12),
              timeBox('OUT', _end, false),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('$_minutes min${_end <= _start ? ' — runs past midnight' : ''}',
                  style: _t(11, c: _end <= _start ? _amber : _muted)),
            ),
            label('PROGRAMME'),
            DropdownButtonFormField<String>(
              initialValue: _project,
              dropdownColor: AppTheme.surfaceDark,
              isExpanded: true,
              decoration: _field(''),
              style: _t(13),
              items: [
                for (final p in projects) DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _project = v ?? _project),
            ),
            label('COMMENT'),
            TextField(
              controller: _comment,
              maxLines: 3,
              minLines: 1,
              style: _t(13),
              decoration: _field('Optional'),
            ),
            const SizedBox(height: 10),
            Text('Saving prices the whole day again with NATRAX\'s rules — whole '
                'hours per track, the day minimum, T3 Wet and Dry sharing one.',
                style: _t(10.5, c: _muted, h: 1.4)),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: _t(13, c: _muted))),
        TextButton(
            onPressed: () => Navigator.pop(
                context, _Edit(_code, _start, _minutes, _project, _comment.text)),
            child: Text('Save', style: _t(13, w: FontWeight.w700, c: _teal))),
      ],
    );
  }
}

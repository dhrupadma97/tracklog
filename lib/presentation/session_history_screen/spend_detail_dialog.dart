import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/spend_breakdown_service.dart';

const _bg = Color(0xFF0A1025);
const _card = Color(0xFF0D1520);
const _line = Color(0xFF1E293B);
const _muted = Color(0xFF6B7490);
const _teal = Color(0xFF00F3FF);
const _amber = Color(0xFFFFB547);
const _red = Color(0xFFE8002D);

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = Colors.white, double? h}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: w, color: c, height: h);

/// The headline spend on the Projects screen, opened up: every programme by
/// kind of cost, before GST, and what each figure is made of.
class SpendDetailDialog extends StatefulWidget {
  final SpendBreakdown spend;
  const SpendDetailDialog({super.key, required this.spend});

  static Future<void> show(BuildContext context, SpendBreakdown spend) =>
      showDialog<void>(
        context: context,
        builder: (_) => SpendDetailDialog(spend: spend),
      );

  @override
  State<SpendDetailDialog> createState() => _SpendDetailDialogState();
}

class _SpendDetailDialogState extends State<SpendDetailDialog> {
  final _open = <String>{};

  String _q(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final b = widget.spend;
    final rows = b.rows.where((r) => r.total > 0).toList()
      ..sort((a, x) => x.total.compareTo(a.total));
    final idle = b.rows.where((r) => r.total <= 0).map((r) => r.project).toList();
    final manpowerAll = b.sum((r) => r.manpower) + b.unassignedManpower;

    return Dialog(
      backgroundColor: _bg,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _teal.withAlpha(60))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.currency_rupee_rounded, color: _red, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Spend in detail', style: _t(18, w: FontWeight.w800)),
                  Text('Every programme, before GST, from what TrackLog has recorded',
                      style: _t(12, c: _muted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_inr.format(b.total), style: _t(24, w: FontWeight.w800)),
                Text('total, before GST', style: _t(11, c: _muted)),
              ]),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: _muted),
              ),
            ]),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                _table(b, rows),
                const SizedBox(height: 6),
                Text('Click a programme to see what its figures are made of.',
                    style: _t(10.5, c: _muted)),
                for (final r in rows)
                  if (_open.contains(r.project)) _detail(r),
                const SizedBox(height: 16),
                _notes(b, manpowerAll, idle),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _table(SpendBreakdown b, List<SpendRow> rows) {
    Widget c(String s,
            {bool head = false, bool left = false, Color? col, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
          child: Text(s,
              textAlign: left ? TextAlign.left : TextAlign.right,
              style: head
                  ? _t(9.5, w: FontWeight.w800, c: _muted).copyWith(letterSpacing: 0.8)
                  : _t(12, w: bold ? FontWeight.w800 : FontWeight.w600, c: col ?? Colors.white)),
        );
    String m(double v) => v.abs() < 0.5 ? '—' : _inr.format(v);
    TableRow row(SpendRow r) {
      final open = _open.contains(r.project);
      Widget tap(Widget w) => TableRowInkWell(
            onTap: () => setState(() => open ? _open.remove(r.project) : _open.add(r.project)),
            child: w,
          );
      return TableRow(
        decoration: open ? BoxDecoration(color: _teal.withAlpha(14)) : null,
        children: [
          tap(Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            child: Row(children: [
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: _muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(r.project,
                    style: _t(12.5, w: FontWeight.w700), overflow: TextOverflow.ellipsis),
              ),
              if (r.pinned) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Pinned to its NATRAX invoices',
                  child: Icon(Icons.push_pin_outlined, size: 12, color: _amber.withAlpha(200)),
                ),
              ],
            ]),
          )),
          tap(c(m(r.track))),
          tap(c(m(r.services))),
          tap(c(r.pinned ? 'in services' : m(r.ev), col: r.pinned ? _muted : null)),
          tap(c(m(r.workshop))),
          tap(c(m(r.manpower))),
          tap(c(m(r.deadWeight))),
          tap(c(_inr.format(r.total), bold: true, col: _teal)),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.4),
          1: FlexColumnWidth(1.3),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.1),
          4: FlexColumnWidth(1.2),
          5: FlexColumnWidth(1.2),
          6: FlexColumnWidth(1.1),
          7: FlexColumnWidth(1.4),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
            children: [
              c('PROGRAMME', head: true, left: true),
              c('TRACK', head: true),
              c('SERVICES', head: true),
              c('EV CHARGING', head: true),
              c('WORKSHOP', head: true),
              c('MANPOWER', head: true),
              c('DEAD WT', head: true),
              c('TOTAL', head: true),
            ],
          ),
          for (final r in rows) row(r),
          if (b.unassignedManpower > 0)
            TableRow(children: [
              c('Manpower before the muster (no programme)', left: true, col: Colors.white70),
              c('—'), c('—'), c('—'), c('—'),
              c(_inr.format(b.unassignedManpower)),
              c('—'),
              c(_inr.format(b.unassignedManpower), bold: true, col: _teal),
            ]),
          TableRow(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
            children: [
              c('Total', left: true, bold: true),
              c(m(b.sum((r) => r.track)), bold: true),
              c(m(b.sum((r) => r.services)), bold: true),
              c(m(b.sum((r) => r.ev)), bold: true),
              c(m(b.sum((r) => r.workshop)), bold: true),
              c(m(b.sum((r) => r.manpower) + b.unassignedManpower), bold: true),
              c(m(b.sum((r) => r.deadWeight)), bold: true),
              c(_inr.format(b.total), bold: true, col: _teal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(SpendRow r) {
    final lines = r.serviceLines.entries.toList()
      ..sort((a, b) => b.value.cost.compareTo(a.value.cost));
    Widget fact(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: _t(12, c: Colors.white70))),
            Text(v, style: _t(12, w: FontWeight.w700)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _teal.withAlpha(50)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.project.toUpperCase(),
            style: _t(11, w: FontWeight.w800, c: _teal).copyWith(letterSpacing: 1.2)),
        const SizedBox(height: 10),
        fact('Track time', '${_inr.format(r.track)} · ${r.sessions} run${r.sessions == 1 ? '' : 's'}'),
        if (r.workshop > 0)
          fact(
              r.pinned ? 'Workshop (as invoiced, Mar–May)' : 'Workshop / office',
              '${_inr.format(r.workshop)} · ${r.workshopDays} day${r.workshopDays == 1 ? '' : 's'}'),
        if (r.manpower > 0)
          fact('Manpower (muster)', '${_inr.format(r.manpower)} · ${r.manDays} man-day${r.manDays == 1 ? '' : 's'}'),
        if (r.deadWeight > 0)
          fact('Dead weight 250 kg', '${_inr.format(r.deadWeight)} · ${r.deadWeightDays} day${r.deadWeightDays == 1 ? '' : 's'}'),
        if (r.pinned)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
                'Services, EV charging and workshop for March–May are taken as '
                'invoiced (${_inr.format(r.services)} and ${_inr.format(r.workshop)}), '
                'so they are not split line by line.',
                style: _t(11, c: _amber, h: 1.4)),
          ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('SERVICE LINES${r.pinned ? ' (months after the invoices)' : ''}',
              style: _t(9.5, w: FontWeight.w800, c: _muted).copyWith(letterSpacing: 0.8)),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                Expanded(child: Text(l.key, style: _t(11.5, c: Colors.white70))),
                SizedBox(
                  width: 90,
                  child: Text(l.value.quantity > 0 ? '× ${_q(l.value.quantity)}' : '',
                      textAlign: TextAlign.right, style: _t(11.5, c: _muted)),
                ),
                SizedBox(
                  width: 110,
                  child: Text(_inr.format(l.value.cost),
                      textAlign: TextAlign.right, style: _t(11.5, w: FontWeight.w700)),
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _notes(SpendBreakdown b, double manpowerAll, List<String> idle) {
    Widget note(IconData i, String s, {Color c = Colors.white70}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(i, size: 14, color: _muted)),
            const SizedBox(width: 8),
            Expanded(child: Text(s, style: _t(11.5, c: c, h: 1.45))),
          ]),
        );
    final outside = b.outside.fold<double>(0, (s, x) => s + x.exclGst);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      note(Icons.receipt_long_outlined,
          'GST: NATRAX bill this SEZ unit without GST, so their figures are what is paid. '
          'MOICARS manpower invoices add 18% IGST — about ${_inr.format(manpowerAll * 0.18)} '
          'on the manpower shown here.'),
      note(Icons.event_note_outlined,
          'Workshop and manpower come from the muster (₹5,000 a workshop day; each PO\'s day '
          'rate for manpower). Workshop logged as a service line is not counted again from the muster.'),
      if (b.outside.isNotEmpty)
        note(Icons.info_outline,
            'Not in the total — Mahindra EV costs outside the NATRAX invoices, '
            '${_inr.format(outside)}: '
            '${b.outside.map((x) => '${x.label} ${_inr.format(x.exclGst)}').join('; ')}.',
            c: _amber),
      if (idle.isNotEmpty)
        note(Icons.hourglass_empty, 'Nothing recorded yet: ${idle.join(', ')}.'),
    ]);
  }
}

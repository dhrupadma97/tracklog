import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/billing_baseline.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/excel_backup_downloader.dart';
import '../../services/invoice_service.dart';
import '../../services/natrax_reconciler.dart';
import '../../services/natrax_utilisation_sheet.dart';
import '../../services/project_manager.dart';
import '../../services/reconciliation_service.dart';
import '../../services/session_log_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/invoice_upload_flow.dart';

// ── Palette ─────────────────────────────────────────────────────────────────
const _bg = Color(0xFF0D1520);
const _line = Color(0xFF1E293B);
const _muted = Color(0xFF6B7490);
const _green = Color(0xFF22C55E);
const _amber = Color(0xFFFFB547);
const _red = Color(0xFFFF6B6B);
const _purple = Color(0xFFB794F6);
const _teal = AppTheme.primary;

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String _h(num? v) => v == null
    ? '—'
    : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
String _monthLabel(String key) =>
    DateFormat('MMMM yyyy').format(DateFormat('yyyy-MM').parse(key));

TextStyle _t(double size,
        {FontWeight weight = FontWeight.w500, Color color = Colors.white, double? height}) =>
    GoogleFonts.spaceGrotesk(
        fontSize: size, fontWeight: weight, color: color, height: height);

/// Which way a line leans, as a colour and a few words.
({Color colour, String label, IconData icon}) _stanceLook(ReconStance s) =>
    switch (s) {
      ReconStance.matched =>
        (colour: _green, label: 'Agrees', icon: Icons.check_circle_outline),
      ReconStance.inFavour =>
        (colour: _teal, label: 'NATRAX less', icon: Icons.south_east),
      ReconStance.theirsMore =>
        (colour: _amber, label: 'NATRAX more', icon: Icons.north_east),
      ReconStance.theirsOnly =>
        (colour: _amber, label: 'Only on NATRAX', icon: Icons.add_circle_outline),
      ReconStance.oursOnly =>
        (colour: _teal, label: 'Only ours', icon: Icons.remove_circle_outline),
      ReconStance.overcharge =>
        (colour: _red, label: 'Above their gate log', icon: Icons.gpp_maybe_outlined),
      ReconStance.undercharge =>
        (colour: _green, label: 'Below their gate log', icon: Icons.savings_outlined),
      ReconStance.unknown =>
        (colour: _purple, label: 'Needs a decision', icon: Icons.help_outline),
      ReconStance.notOurs =>
        (colour: _red, label: 'Not ours', icon: Icons.block),
    };

/// One month of NATRAX, from utilisation sheet to settled.
///
/// Upload NATRAX's sheet; say whose each vehicle is; answer only what does
/// not agree — anything in our favour settles in one click with its own
/// note; then set the invoice against what was agreed, and settle. The
/// judging is all in NatraxReconciler, which is pure and tested; this screen
/// asks and records.
class ReconcileScreen extends StatefulWidget {
  const ReconcileScreen({super.key, this.service, this.initialMonth});

  /// Only tests pass these; the app uses the shared service and last month.
  final ReconciliationService? service;
  final String? initialMonth;

  @override
  State<ReconcileScreen> createState() => _ReconcileScreenState();
}

class _ReconcileScreenState extends State<ReconcileScreen> {
  late final _svc = widget.service ?? ReconciliationService.instance;

  late String _month;
  List<String> _monthChoices = [];
  Set<String> _settledMonths = {};

  bool _loading = true;
  String? _error;
  ReconMonthState? _state;
  OurMonth _ours = const OurMonth();
  Map<String, VehicleDecision> _vehicles = {};
  ReconOutcome? _outcome;
  List<ReconItem> _invoiceItems = [];
  List<NatraxInvoice> _invoiceChoices = [];

  String _filter = 'ask';
  final _comments = <String, TextEditingController>{};
  final _expanded = <String>{};
  final _busy = <String>{};
  final _noteCtrl = TextEditingController();
  bool _working = false;

  /// Every decision made on the month, newest first, with its comment.
  List<ReconHistoryEntry> _history = [];

  /// Lines answered while this month is open on screen. They stay where
  /// they are, shown as chosen, instead of vanishing from "Needs a
  /// decision" the moment an option is picked — which read as the choice
  /// not having been taken.
  final _justAnswered = <String>{};

  /// The option clicked on a line whose save has not come back yet, so it
  /// shows as selected at once.
  final _pending = <String, String>{};

  /// Why a line's last save failed, shown on the line itself.
  final _itemErrors = <String, String>{};

  // Anchors for "go to" links: the stage strip, the next-step bar and the
  // settle checklist all jump to the card that needs doing.
  final _kSheet = GlobalKey();
  final _kVehicles = GlobalKey();
  final _kQuestions = GlobalKey();
  final _kInvoice = GlobalKey();
  final _kSettle = GlobalKey();
  final _kSummary = GlobalKey();

  void _goTo(GlobalKey k) {
    final c = k.currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(c,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.02);
  }

  @override
  void initState() {
    super.initState();
    // Last month by default: the utilisation sheet always arrives after the
    // month it covers.
    final now = DateTime.now();
    _month = widget.initialMonth ??
        DateFormat('yyyy-MM').format(DateTime(now.year, now.month - 1));
    SessionLogService.instance.addListener(_onSessionsChanged);
    _loadMonths();
    _load();
  }

  @override
  void dispose() {
    SessionLogService.instance.removeListener(_onSessionsChanged);
    for (final c in _comments.values) {
      c.dispose();
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  /// A session added elsewhere — Manual Entry, or the "add runs" button
  /// here — changes our side of the month.
  void _onSessionsChanged() {
    if (mounted && _state?.sheet != null) _load(quiet: true);
  }

  Future<void> _loadMonths() async {
    final now = DateTime.now();
    final recent = [
      for (var i = 0; i < 6; i++)
        DateFormat('yyyy-MM').format(DateTime(now.year, now.month - i))
    ];
    try {
      final stored = await _svc.months();
      _settledMonths = {for (final m in stored) if (m.settled) m.month};
      final all = {...recent, ...stored.map((m) => m.month)}.toList()
        ..sort((a, b) => b.compareTo(a));
      if (mounted) setState(() => _monthChoices = all);
    } catch (_) {
      if (mounted) setState(() => _monthChoices = recent);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.load(_month),
        _svc.vehicles(),
        _svc.ourMonth(_month),
        _svc.invoicesFor(_month),
      ]);
      _state = results[0] as ReconMonthState;
      _vehicles = results[1] as Map<String, VehicleDecision>;
      _ours = results[2] as OurMonth;
      _invoiceChoices = results[3] as List<NatraxInvoice>;
      _error = null;
      // On its own: a history that cannot be read costs the history, not
      // the month.
      try {
        _history = await _svc.history(_month);
      } catch (_) {
        _history = [];
      }
      _recompute();
    } catch (e) {
      final msg = e.toString();
      _error = msg.contains('recon_') &&
              (msg.contains('does not exist') || msg.contains('PGRST205'))
          ? 'The reconciliation tables are not set up yet. Paste '
              '20261112120000_natrax_reconciliation.sql into the Supabase SQL '
              'editor and run it, then reload.'
          : 'Could not load $_month: $msg';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _recompute() {
    final s = _state;
    if (s?.sheet == null) {
      _outcome = null;
      _invoiceItems = [];
      return;
    }
    _outcome = NatraxReconciler.run(
      sheet: s!.sheet!,
      ours: _ours,
      vehicles: _vehicles,
      answers: s.answers,
    );
    _invoiceItems = s.invoice == null
        ? []
        : NatraxReconciler.tally(
            outcome: _outcome!, invoice: s.invoice!, answers: s.answers);
  }

  bool get _settled => _state?.settled ?? false;

  bool get _narrow => MediaQuery.of(context).size.width < 700;

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontFamily: 'Space Grotesk')),
      backgroundColor: error ? const Color(0xFF5A1A1A) : AppTheme.surfaceDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// Runs a write, says how it went, and reloads what it touched.
  Future<void> _do(String key, Future<void> Function() action,
      {String? done}) async {
    setState(() => _busy.add(key));
    try {
      await action();
      if (done != null) _say(done);
      await _load(quiet: true);
    } catch (e) {
      _say('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  TextEditingController _commentFor(ReconItem i) => _comments.putIfAbsent(
      i.key, () => TextEditingController(text: i.answer?.comment ?? ''));

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _uploadSheet() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() => _working = true);
    try {
      final sheet = NatraxUtilisationSheet.fromXlsx(file!.bytes!);
      if (!mounted) return;
      if (sheet.company.isNotEmpty &&
          !sheet.company.toLowerCase().contains('goodyear')) {
        final go = await _confirm(
          'Addressed to someone else?',
          'This sheet is made out to "${sheet.company}". Use it anyway?',
          'Use it',
        );
        if (go != true) return;
      }
      if (sheet.monthKey != _month) {
        final go = await _confirm(
          'This sheet is for ${_monthLabel(sheet.monthKey)}',
          'You are looking at ${_monthLabel(_month)}. Switch to '
              '${_monthLabel(sheet.monthKey)} and load it there?',
          'Switch',
        );
        if (go != true) return;
        _month = sheet.monthKey;
      }
      if (_state?.sheet != null) {
        final go = await _confirm(
          'Replace the sheet?',
          '${_monthLabel(_month)} already has a sheet. Answers stay where '
              'the lines still match; any whose figures move will be asked '
              'again.',
          'Replace',
        );
        if (go != true) return;
      }
      await _svc.saveSheet(sheet, file.name);
      _say('${sheet.reference.isEmpty ? 'Sheet' : sheet.reference} read: '
          '${sheet.blocks.length} track lines, ${_h(sheet.chargedHours)} h.');
      await _loadMonths();
      await _load();
    } on FormatException catch (e) {
      _say('That file could not be read as a NATRAX sheet: ${e.message}',
          error: true);
    } catch (e) {
      _say('Could not read or save the sheet: $e', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _answer(ReconItem i, ReconOption o) async {
    final ctrl = _commentFor(i);
    if (ctrl.text.trim().isEmpty && i.autoComment.isNotEmpty) {
      ctrl.text = i.autoComment;
    }
    // A difference on the invoice must say why; that is what the month's
    // record is for.
    if (i.kind == ReconKind.invoice && ctrl.text.trim().isEmpty) {
      setState(() => _itemErrors[i.key] =
          'Write why in the comment box, then pick the option again.');
      return;
    }
    setState(() {
      _pending[i.key] = o.id;
      _justAnswered.add(i.key);
      _itemErrors.remove(i.key);
      _busy.add(i.key);
    });
    try {
      await _svc.answer(_month, i, o.id, ctrl.text);
      await _load(quiet: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _justAnswered.remove(i.key);
          _itemErrors[i.key] = 'Not saved: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _pending.remove(i.key);
          _busy.remove(i.key);
        });
      }
    }
  }

  /// Enter in a comment box: saves the comment with the option already
  /// chosen, or with the suggested one; otherwise says what is missing
  /// rather than doing nothing.
  void _submitComment(ReconItem i) {
    final c = i.stale ? null : i.chosen;
    if (c != null) {
      _answer(i, c);
      return;
    }
    for (final o in i.options) {
      if (o.id == i.suggested) {
        _answer(i, o);
        return;
      }
    }
    setState(() => _itemErrors[i.key] =
        'Pick one of the options above — the comment is saved with it.');
  }

  Future<void> _setVehicle(ReconItem v, ReconOption o) async {
    final key = v.key.substring('veh|'.length);
    final notOurs = o.id == 'not_ours';
    await _do(
      v.key,
      () => _svc.setVehicle(key, v.title,
          project: notOurs ? null : o.id.substring('prog:'.length),
          notOurs: notOurs,
          month: _month),
      done: notOurs
          ? '${v.title} marked not ours — everything on it is disputed.'
          : '${v.title} → ${o.label}. Remembered for later months.',
    );
  }

  Future<void> _acceptAllInFavour() async {
    final o = _outcome;
    if (o == null) return;
    final items = [...o.items, ..._invoiceItems];
    await _do('bulk', () async {
      final n = await _svc.acceptInFavour(_month, items);
      _say('$n line${n == 1 ? '' : 's'} settled at NATRAX\'s lower figure, '
          'each with its own note.');
    });
  }

  Future<void> _addRuns(ReconItem i) async {
    final runs = ReconciliationService.missingRuns(i);
    if (runs.isEmpty) return;
    final go = await _confirm(
      'Add ${runs.length} run${runs.length == 1 ? '' : 's'} to TrackLog?',
      '${DateFormat('d MMM').format(i.date!)} · ${i.code} · ${i.project}\n\n'
          '${runs.map((r) => '${r.label}  (${r.minutes} min)').join('\n')}\n\n'
          'Priced exactly as Manual Entry would price them, against what the '
          'day already carries. They can be deleted from Manual Entry like any '
          'other entry.',
      'Add',
    );
    if (go != true) return;
    await _do(i.key, () async {
      final r = await _svc.addRuns(i, runs, _state?.sheet?.reference ?? '');
      _say('Added ${r.count} run${r.count == 1 ? '' : 's'}, '
          '${_inr.format(r.cost)}.');
    });
  }

  Future<void> _useInvoice(NatraxInvoice inv) async {
    await _do('invoice', () async {
      final parsed = await _svc.readInvoice(inv);
      if (parsed == null || parsed.lines.isEmpty) {
        throw StateError('${inv.invoiceNumber}\'s PDF could not be read line '
            'by line, so it cannot be tallied here.');
      }
      await _svc.setInvoice(_month, inv, parsed);
    }, done: '${inv.invoiceNumber} set against ${_monthLabel(_month)}.');
  }

  Future<void> _uploadInvoice() async {
    try {
      final pos = await SupabaseService.instance.client
          .from('po_trackers')
          .select()
          .order('created_at');
      if (!mounted) return;
      final created = await InvoiceUploadFlow.start(
        context,
        poOptions: (pos as List).cast<Map<String, dynamic>>(),
        knownMonths: [
          _month,
          ...BillingBaseline.forProject(ProjectManager.instance.activeProject)
              .map((m) => m.month),
        ],
        uploadedBy: EngineerAuthService.instance.currentUser?.email,
        onMessage: (m, {bool error = false}) => _say(m, error: error),
      );
      if (created == null) return;
      await _load(quiet: true);
      if (created.periodMonth == _month) await _useInvoice(created);
    } catch (e) {
      _say('Could not upload: $e', error: true);
    }
  }

  /// The month's money in one place, so the money card, the list to raise,
  /// the summary and the export cannot disagree.
  ///
  /// Once the invoice is set it is the figure of record: what is to be
  /// raised is then the invoice lines disputed, and what is to be paid is
  /// the invoice less those. Before it, the sheet's disputes stand in.
  ({
    double sheet,
    double ours,
    double agreed,
    double? invoiceExcl,
    double? invoiceGst,
    double? invoiceTotal,
    List<ReconItem> raise,
    double toRaise,
    double? toPay,
  }) get _figures {
    final o = _outcome!;
    final inv = _state?.invoice;
    double? excl, gst, total;
    if (inv != null) {
      excl = inv.amountExclGst ??
          inv.lines.fold<double>(0, (s, l) => s + l.amount);
      gst = inv.gstAmount ?? 0;
      total = inv.totalAmount ?? (excl + gst);
    }
    final raise = inv == null
        ? o.disputes
        : NatraxReconciler.invoiceDisputes(_invoiceItems);
    final toRaise = raise.fold<double>(
        0,
        (s, d) => s +
            (d.kind == ReconKind.notOurs
                ? d.theirsMoney
                : d.theirsMoney - d.agreedMoney));
    return (
      sheet: o.natraxMoney,
      ours: o.oursMoney,
      agreed: o.agreedMoney,
      invoiceExcl: excl,
      invoiceGst: gst,
      invoiceTotal: total,
      raise: raise,
      toRaise: toRaise,
      toPay: excl == null ? null : excl - toRaise,
    );
  }

  /// Every answered line that carries a comment: the month's remarks.
  List<ReconItem> get _remarks => [
        for (final i in [...?_outcome?.items, ..._invoiceItems])
          if (i.answer != null && (i.answer!.comment).trim().isNotEmpty) i,
      ];

  Map<String, dynamic> _summary() {
    final o = _outcome!;
    final s = _state!;
    final f = _figures;
    return {
      'natrax': o.natraxMoney,
      'ours': o.oursMoney,
      'agreed': o.agreedMoney,
      'disputed': f.toRaise,
      'not_ours': o.notOursMoney,
      'invoice': s.invoiceNumber,
      'invoice_excl': f.invoiceExcl,
      'invoice_gst': f.invoiceGst,
      'invoice_total': f.invoiceTotal,
      'to_raise': f.toRaise,
      'to_pay': f.toPay,
      'remarks': [
        for (final r in _remarks)
          {
            'line': r.title,
            'decision': r.chosen?.label ?? r.answer!.choice,
            'comment': r.answer!.comment,
            'by': r.answer!.by,
          },
      ],
      'sheet': s.sheet?.reference,
      'lines': [
        for (final l in o.trackLines)
          {
            'code': l.code,
            'natrax': l.natrax,
            'ours': l.ours,
            'agreed': l.agreed,
            'agreed_money': l.agreedMoney,
          },
      ],
    };
  }

  Future<void> _settle() async {
    final go = await _confirm(
      'Settle ${_monthLabel(_month)}?',
      'The agreed and disputed figures are frozen as they stand. It can be '
          'reopened later, with a reason.',
      'Settle',
    );
    if (go != true) return;
    await _do('settle', () => _svc.settle(_month, _summary()),
        done: '${_monthLabel(_month)} settled.');
    await _loadMonths();
  }

  Future<void> _reopen() async {
    final reason = await _ask('Reopen ${_monthLabel(_month)}',
        'Why is it being reopened?');
    if (reason == null || reason.trim().isEmpty) return;
    await _do('settle', () => _svc.reopen(_month, reason),
        done: '${_monthLabel(_month)} reopened.');
    await _loadMonths();
  }

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    await _do('note', () => _svc.addNote(_month, text));
    _noteCtrl.clear();
  }

  String _disputeText() {
    final s = _state!;
    final f = _figures;
    final b = StringBuffer()
      ..writeln(s.invoice != null
          ? 'Invoice ${s.invoiceNumber ?? ''} — ${_monthLabel(_month)}'
          : 'Utilisation sheet ${s.sheet?.reference ?? ''} — ${_monthLabel(_month)}')
      ..writeln();
    for (final d in f.raise) {
      if (d.kind == ReconKind.notOurs) {
        b.writeln('• ${d.title}${d.subtitle.isEmpty ? '' : ' (${d.subtitle})'}: '
            '${_h(d.theirs)} h and services, ${_inr.format(d.theirsMoney)}');
        for (final h in d.hints) {
          b.writeln('    $h');
        }
      } else {
        final c = d.chosen;
        b.writeln('• ${d.title}${d.project == null ? '' : ' — ${d.project}'}: '
            'charged ${_h(d.theirs)} ${d.unit}, we make it ${_h(c?.agreed)} '
            '${d.unit} (${_inr.format(d.theirsMoney - d.agreedMoney)})'
            '${(d.answer?.comment ?? '').isEmpty ? '' : '. ${d.answer!.comment}'}');
      }
    }
    b
      ..writeln()
      ..writeln('Total in question: ${_inr.format(f.toRaise)}');
    if (f.toPay != null) {
      b.writeln('Invoice ${_inr.format(f.invoiceExcl)} less this: '
          '${_inr.format(f.toPay)} to pay');
    }
    return b.toString();
  }

  Future<void> _export() async {
    final o = _outcome;
    final s = _state;
    if (o == null || s == null) return;
    final book = Excel.createExcel();
    void sheet(String name, List<String> head, List<List<Object?>> rows) {
      final t = book[name];
      t.appendRow([for (final h in head) TextCellValue(h)]);
      for (final r in rows) {
        t.appendRow([
          for (final v in r)
            v == null
                ? TextCellValue('')
                : (v is num ? DoubleCellValue(v.toDouble()) : TextCellValue('$v')),
        ]);
      }
    }

    sheet('Summary', ['Item', 'Value'], [
      ['Month', _monthLabel(_month)],
      ['NATRAX sheet', s.sheet?.reference],
      ['NATRAX (our vehicles)', o.natraxMoney],
      ['Our record', o.oursMoney],
      ['Agreed', o.agreedMoney],
      ['Not ours', o.notOursMoney],
      ['Invoice', s.invoiceNumber],
      ['Invoice, before GST', _figures.invoiceExcl],
      ['Invoice GST', _figures.invoiceGst],
      ['Invoice total', _figures.invoiceTotal],
      ['To raise with NATRAX', _figures.toRaise],
      ['To pay, before GST', _figures.toPay],
      ['Settled', s.settledAt == null ? 'No' : DateFormat('d MMM yyyy').format(s.settledAt!)],
    ]);
    sheet('Remarks', ['Line', 'Stage', 'Decision', 'Comment', 'By', 'When'], [
      for (final r in _remarks)
        [
          r.title,
          r.kind == ReconKind.invoice ? 'Invoice' : 'Sheet',
          r.chosen?.label ?? r.answer!.choice,
          r.answer!.comment,
          r.answer!.by ?? '',
          r.answer!.at == null ? '' : DateFormat('dd-MMM-yyyy HH:mm').format(r.answer!.at!.toLocal()),
        ],
    ]);
    sheet('History', ['When', 'Action', 'Line', 'Decision', 'Comment', 'NATRAX ₹', 'Agreed ₹', 'By'], [
      for (final h in _history)
        [
          DateFormat('dd-MMM-yyyy HH:mm').format(h.at.toLocal()),
          h.action,
          h.title ?? '',
          h.choiceLabel ?? h.choice ?? '',
          h.comment ?? '',
          h.natraxAmount,
          h.agreedAmount,
          h.by ?? '',
        ],
    ]);
    sheet('Tracks', ['Track', 'Name', 'NATRAX h', 'Ours h', 'Agreed h', 'Rate', 'Agreed ₹', 'Disputed ₹'], [
      for (final l in o.trackLines)
        [l.code, l.name, l.natrax, l.ours, l.agreed, l.rate, l.agreedMoney, l.disputedMoney],
    ]);
    sheet('Lines', [
      'Date', 'Programme', 'Line', 'Leans', 'NATRAX', 'Ours', 'Gate log', 'NATRAX min',
      'Our min', 'NATRAX runs', 'Our runs', 'Decision', 'Agreed', 'Comment', 'By', 'When'
    ], [
      for (final i in [...o.items, ..._invoiceItems])
        if (i.kind != ReconKind.vehicle)
          [
            i.date == null ? '' : DateFormat('dd-MMM-yyyy').format(i.date!),
            i.project ?? '',
            i.title,
            _stanceLook(i.stance).label,
            i.theirs,
            i.ours,
            i.rule,
            i.theirsMinutes,
            i.oursMinutes,
            i.theirRuns.map((r) => r.label).join(', '),
            i.ourRuns.map((r) => r.label).join(', '),
            i.chosen?.label ?? (i.needsAnswer ? 'Open' : ''),
            i.agreed,
            i.answer?.comment ?? '',
            i.answer?.by ?? '',
            i.answer?.at == null ? '' : DateFormat('dd-MMM-yyyy HH:mm').format(i.answer!.at!.toLocal()),
          ],
    ]);
    sheet('Disputes', ['Line', 'Programme', 'NATRAX', 'Agreed', '₹ in question', 'Comment'], [
      for (final d in o.disputes)
        [d.title, d.project ?? d.subtitle, d.theirs, d.kind == ReconKind.notOurs ? 0 : d.chosen?.agreed,
          d.kind == ReconKind.notOurs ? d.theirsMoney : d.theirsMoney - d.agreedMoney, d.answer?.comment ?? ''],
    ]);
    sheet('To do', ['Fix in TrackLog'], [for (final t in o.todos) [t]]);
    sheet('Notes', ['When', 'Kind', 'Note', 'By'], [
      for (final n in s.notes)
        [DateFormat('dd-MMM-yyyy HH:mm').format(n.createdAt.toLocal()), n.kind, n.note, n.createdBy ?? ''],
    ]);
    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');
    final bytes = book.encode();
    if (bytes == null) return;
    final name = 'NATRAX_Reconciliation_${DateFormat('MMM-yyyy').format(DateFormat('yyyy-MM').parse(_month))}.xlsx';
    ExcelBackupDownloader.save(Uint8List.fromList(bytes), name);
    _say('Downloaded $name');
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  Future<bool?> _confirm(String title, String body, String yes) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          title: Text(title, style: _t(15, weight: FontWeight.w800)),
          content: Text(body, style: _t(12.5, color: Colors.white70, height: 1.45)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: _t(13, color: _muted))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(yes, style: _t(13, weight: FontWeight.w700, color: _teal))),
          ],
        ),
      );

  Future<String?> _ask(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: Text(title, style: _t(15, weight: FontWeight.w800)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          style: _t(13),
          decoration: _fieldDecoration(hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: _t(13, color: _muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text('OK', style: _t(13, weight: FontWeight.w700, color: _teal))),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: _t(12, color: const Color(0xFF4A5470)),
        isDense: true,
        filled: true,
        fillColor: AppTheme.backgroundDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _teal.withAlpha(140))),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1100;
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(children: [
          _header(),
          if (_loading)
            const Expanded(
                child: Center(child: CircularProgressIndicator(color: _teal)))
          else if (_error != null)
            Expanded(child: Center(child: _errorCard(_error!)))
          else
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        flex: 7,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 10, 40),
                          children: _mainCards(),
                        ),
                      ),
                      SizedBox(
                        width: 380,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(10, 4, 20, 40),
                          children: _sideCards(),
                        ),
                      ),
                    ])
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 60),
                      children: [..._mainCards(), ..._sideCards()],
                    ),
            ),
        ]),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fact_check_outlined, color: _teal, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NATRAX RECONCILIATION',
                  style: _t(11, weight: FontWeight.w800, color: _teal)
                      .copyWith(letterSpacing: 1.6)),
              Text('Utilisation sheet → questions → invoice → settled',
                  style: _t(12, color: _muted)),
            ]),
          ),
          // Icons only on a phone, where the words would squeeze the title.
          if (_outcome != null) ...[
            _smallButton(Icons.download_rounded, _narrow ? '' : 'Export', _export),
            const SizedBox(width: 8),
          ],
          _smallButton(Icons.refresh, _narrow ? '' : 'Reload', () => _load()),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final m in (_monthChoices.isEmpty ? [_month] : _monthChoices))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _monthChip(m),
              ),
          ]),
        ),
        if (!_loading && _error == null) ...[
          const SizedBox(height: 12),
          _stageStrip(),
          _nextStepBar(),
        ],
      ]),
    );
  }

  Widget _monthChip(String m) {
    final on = m == _month;
    final settled = _settledMonths.contains(m);
    return GestureDetector(
      onTap: on
          ? null
          : () {
              setState(() {
                _month = m;
                _comments.clear();
                _justAnswered.clear();
                _pending.clear();
                _itemErrors.clear();
                _expanded.clear();
              });
              _load();
            },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: on ? _teal.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? _teal.withAlpha(160) : _line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (settled) ...[
              const Icon(Icons.verified, size: 13, color: _green),
              const SizedBox(width: 5),
            ],
            Text(_monthLabel(m),
                style: _t(12,
                    weight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? _teal : Colors.white70)),
          ]),
        ),
      ),
    );
  }

  /// Where the month stands, and what is left, with a jump to each.
  ///
  /// "I came here and nothing to go forward" (17 Nov 2026): the strip said
  /// step 2 while the screen was scrolled to the invoice, and nothing said
  /// what was holding the month up. Now every step can be clicked, and the
  /// bar under it names the next thing to do and goes there.
  List<({String text, GlobalKey target, String? filter})> _nextSteps() {
    final s = _state;
    final o = _outcome;
    final out = <({String text, GlobalKey target, String? filter})>[];
    if (s?.sheet == null) {
      out.add((text: "Upload NATRAX's utilisation sheet", target: _kSheet, filter: null));
      return out;
    }
    if (o == null) return out;
    final vehicles = o.items
        .where((i) => i.kind == ReconKind.vehicle && i.isOpen)
        .map((i) => i.title)
        .toList();
    if (vehicles.isNotEmpty) {
      out.add((
        text: 'Place ${vehicles.length} vehicle${vehicles.length == 1 ? '' : 's'}: '
            '${vehicles.join(', ')}',
        target: _kVehicles,
        filter: null,
      ));
    }
    final ask = o.items
        .where((i) => i.kind != ReconKind.vehicle && i.isOpen && !i.bulkOk)
        .length;
    if (ask > 0) {
      out.add((
        text: 'Decide $ask line${ask == 1 ? '' : 's'} where NATRAX bill more',
        target: _kQuestions,
        filter: 'ask',
      ));
    }
    final favour = o.items.where((i) => i.isOpen && i.bulkOk).length;
    if (favour > 0) {
      out.add((
        text: 'Accept $favour line${favour == 1 ? '' : 's'} in your favour — one click',
        target: _kQuestions,
        filter: 'favour',
      ));
    }
    if (s!.invoice == null) {
      out.add((text: 'Set the final invoice against the month', target: _kInvoice, filter: null));
    } else {
      final inv = _invoiceItems.where((i) => i.isOpen).length;
      if (inv > 0) {
        out.add((
          text: 'Explain $inv invoice difference${inv == 1 ? '' : 's'} (comment + choice)',
          target: _kInvoice,
          filter: null,
        ));
      }
    }
    if (out.isEmpty && !_settled) {
      out.add((text: 'Everything is answered — settle the month', target: _kSettle, filter: null));
    }
    return out;
  }

  void _follow(({String text, GlobalKey target, String? filter}) step) {
    if (step.filter != null && step.filter != _filter) {
      setState(() {
        _filter = step.filter!;
        _justAnswered.clear();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(step.target));
  }

  Widget _nextStepBar() {
    final steps = _nextSteps();
    if (_settled) {
      return _bar(
        colour: _green,
        icon: Icons.verified,
        text: '${_monthLabel(_month)} is settled'
            '${_state?.settledAt == null ? '' : ' on ${DateFormat('d MMM yyyy').format(_state!.settledAt!.toLocal())}'}'
            '. The summary, remarks and history are at the bottom.',
        action: 'See summary',
        onTap: () => _goTo(_kSummary),
      );
    }
    if (steps.isEmpty) return const SizedBox.shrink();
    final next = steps.first;
    final more = steps.length - 1;
    return _bar(
      colour: _teal,
      icon: Icons.arrow_circle_right_outlined,
      text: 'Next: ${next.text}'
          '${more > 0 ? '   ·   then $more more: ${steps.skip(1).map((x) => x.text).join(' · ')}' : ''}',
      action: 'Go there',
      onTap: () => _follow(next),
    );
  }

  Widget _bar({
    required Color colour,
    required IconData icon,
    required String text,
    required String action,
    required VoidCallback onTap,
  }) =>
      Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: colour.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colour.withAlpha(110)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _t(12.5, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 8),
          _smallButton(Icons.south, action, onTap, colour: colour),
        ]),
      );

  Widget _stageStrip() {
    final s = _state;
    final o = _outcome;
    final hasSheet = s?.sheet != null;
    final vehiclesDone = o != null && o.unknownVehicles == 0;
    final questionsDone = o != null && o.cleared;
    final invoiceDone = s?.invoice != null &&
        _invoiceItems.every((i) => !i.isOpen);
    final steps = [
      ('Sheet', hasSheet, _kSheet),
      ('Vehicles', vehiclesDone, _kVehicles),
      ('Questions', questionsDone, _kQuestions),
      ('Invoice', invoiceDone, _kInvoice),
      ('Settled', _settled, _kSettle),
    ];
    final current = steps.indexWhere((x) => !x.$2);
    // On a phone only the current step keeps its name; the rest shrink to a
    // tick or a number so none of them is cut to "1....".
    Widget compact(int i) => Center(
          child: steps[i].$2
              ? const Icon(Icons.check_circle, size: 15, color: _green)
              : Text('${i + 1}', style: _t(12, weight: FontWeight.w800, color: _muted)),
        );
    Widget box(int i) => _narrow && i != current
        ? Container(
            height: 34,
            decoration: BoxDecoration(
              color: steps[i].$2 ? _green.withAlpha(22) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: steps[i].$2 ? _green.withAlpha(110) : _line),
            ),
            child: compact(i),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: steps[i].$2
                  ? _green.withAlpha(22)
                  : (i == current ? _teal.withAlpha(22) : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: steps[i].$2
                      ? _green.withAlpha(110)
                      : (i == current ? _teal.withAlpha(140) : _line)),
            ),
            child: Row(children: [
              Icon(
                  steps[i].$2
                      ? Icons.check_circle
                      : (i == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                  size: 15,
                  color: steps[i].$2
                      ? _green
                      : (i == current ? _teal : _muted)),
              const SizedBox(width: 7),
              Flexible(
                child: Text('${i + 1}. ${steps[i].$1}',
                    overflow: TextOverflow.ellipsis,
                    style: _t(11.5,
                        weight: FontWeight.w700,
                        color: steps[i].$2
                            ? _green
                            : (i == current ? _teal : _muted))),
              ),
            ]),
          );
    return Row(children: [
      for (var i = 0; i < steps.length; i++) ...[
        Expanded(
          flex: _narrow && i == current ? 4 : 1,
          child: Tooltip(
            message: 'Go to ${steps[i].$1.toLowerCase()}',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _goTo(steps[i].$3),
                child: box(i),
              ),
            ),
          ),
        ),
        if (i < steps.length - 1) const SizedBox(width: 6),
      ],
    ]);
  }

  List<Widget> _mainCards() {
    final s = _state!;
    if (s.sheet == null) {
      return [KeyedSubtree(key: _kSheet, child: _sheetCard())];
    }
    return [
      KeyedSubtree(key: _kSheet, child: _sheetCard()),
      KeyedSubtree(key: _kVehicles, child: _vehiclesCard()),
      KeyedSubtree(key: _kQuestions, child: _questionsCard()),
      _agreedCard(),
      KeyedSubtree(key: _kInvoice, child: _invoiceCard()),
      KeyedSubtree(key: _kSettle, child: _settleCard()),
      KeyedSubtree(key: _kSummary, child: _summaryCard()),
    ];
  }

  List<Widget> _sideCards() {
    if (_outcome == null) return [_notesCard()];
    return [_moneyCard(), _todoCard(), _disputesCard(), _notesCard()];
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _card({
    required String title,
    required IconData icon,
    Widget? trailing,
    required List<Widget> children,
    Color accent = _teal,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _bg.withAlpha(235),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withAlpha(50)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: accent, size: 17),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(title,
                  style: _t(11.5, weight: FontWeight.w800, color: const Color(0xFF94A3B8))
                      .copyWith(letterSpacing: 1.3)),
            ),
            // Capped so a long status never pushes the title off a phone.
            if (trailing != null)
              Flexible(
                flex: 2,
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _smallButton(IconData icon, String label, VoidCallback? onTap,
          {Color colour = _teal, bool busy = false}) =>
      GestureDetector(
        onTap: busy ? null : onTap,
        child: MouseRegion(
          cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: Opacity(
            opacity: onTap == null ? 0.4 : 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: colour.withAlpha(24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colour.withAlpha(120)),
              ),
              // One rich text rather than a Row, so a long label wraps on a
              // phone instead of overflowing, wherever the button is placed.
              child: Text.rich(TextSpan(children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: busy
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6, color: colour))
                      : Icon(icon, size: 13, color: colour),
                ),
                if (label.isNotEmpty) ...[
                  const WidgetSpan(child: SizedBox(width: 6)),
                  TextSpan(text: label, style: _t(11, weight: FontWeight.w700, color: colour)),
                ],
              ])),
            ),
          ),
        ),
      );

  Widget _errorCard(String text) => Container(
        margin: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _amber.withAlpha(120)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.info_outline, color: _amber),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: _t(13, color: Colors.white70, height: 1.5)),
        ]),
      );

  Widget _sheetCard() {
    final s = _state!;
    final sheet = s.sheet;
    if (sheet == null) {
      return _card(
        title: 'STEP 1 · NATRAX UTILISATION SHEET',
        icon: Icons.upload_file,
        children: [
          Text(
              'Upload the Service Utilization Sheet NATRAX sent for '
              '${_monthLabel(_month)}. Every day, track and in/out time on it is '
              'set against TrackLog, and only what does not agree is asked.',
              style: _t(12.5, color: Colors.white70, height: 1.5)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _working ? null : _uploadSheet,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: _teal.withAlpha(14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _teal.withAlpha(110)),
                ),
                child: Column(children: [
                  _working
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: _teal))
                      : const Icon(Icons.cloud_upload_outlined, color: _teal, size: 30),
                  const SizedBox(height: 10),
                  Text(_working ? 'Reading the sheet…' : 'Choose the .xlsx file',
                      style: _t(14, weight: FontWeight.w700, color: _teal)),
                  const SizedBox(height: 4),
                  Text('e.g. "Goodyear Oct-26.xlsx"', style: _t(11, color: _muted)),
                ]),
              ),
            ),
          ),
        ],
      );
    }
    final byCode = <String, double>{};
    for (final b in sheet.blocks) {
      final k = b.code.isEmpty ? '?' : b.code;
      byCode[k] = (byCode[k] ?? 0) + (b.charged ?? 0);
    }
    return _card(
      title: 'STEP 1 · NATRAX UTILISATION SHEET',
      icon: Icons.description_outlined,
      accent: _green,
      trailing: _settled
          ? null
          : _smallButton(Icons.swap_horiz, 'Replace', _uploadSheet, busy: _working),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (sheet.reference.isNotEmpty) _chip(sheet.reference),
          if (sheet.issuedOn != null)
            _chip('Issued ${DateFormat('d MMM yyyy').format(sheet.issuedOn!)}'),
          _chip('${sheet.blocks.length} track lines · ${sheet.runCount} runs'),
          _chip('${_h(sheet.chargedHours)} h charged', colour: _teal),
          if (s.sheetFile != null) _chip(s.sheetFile!, colour: _muted),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in (byCode.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
            _chip('${e.key} ${_h(e.value)} h', colour: _muted),
        ]),
        if (sheet.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final w in sheet.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: _amber),
                const SizedBox(width: 6),
                Expanded(child: Text(w, style: _t(11.5, color: _amber, height: 1.4))),
              ]),
            ),
        ],
      ],
    );
  }

  Widget _chip(String text, {Color colour = Colors.white70}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line),
          color: AppTheme.backgroundDark.withAlpha(140),
        ),
        child: Text(text, style: _t(11, weight: FontWeight.w600, color: colour)),
      );

  Widget _vehiclesCard() {
    final vs = _outcome!.items.where((i) => i.kind == ReconKind.vehicle).toList();
    final open = vs.where((v) => v.isOpen).length;
    return _card(
      title: 'STEP 2 · WHOSE VEHICLES',
      icon: Icons.directions_car_outlined,
      accent: open == 0 ? _green : _purple,
      trailing: Text(open == 0 ? 'All placed' : '$open to place',
          style: _t(11, weight: FontWeight.w700, color: open == 0 ? _green : _purple)),
      children: [
        if (open > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                'Each vehicle on the sheet belongs to a programme or is not ours. '
                'Decided once, remembered every month after. A vehicle that is '
                'not ours is disputed whole — its track time and its services.',
                style: _t(11.5, color: _muted, height: 1.45)),
          ),
        for (final v in vs) _vehicleRow(v),
      ],
    );
  }

  Widget _vehicleRow(ReconItem v) {
    final busy = _busy.contains(v.key);
    final current = v.answer?.choice;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: v.isOpen ? _purple.withAlpha(120) : _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(v.title, style: _t(13.5, weight: FontWeight.w800)),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
                width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: _teal)),
        ]),
        if (v.subtitle.isNotEmpty)
          Text(v.subtitle, style: _t(11, color: _muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in v.options)
            _optionButton(
              label: o.label,
              selected: current == o.id,
              suggested: current == null && v.suggested == o.id,
              colour: o.dispute ? _red : _teal,
              onTap: (_settled || busy) ? null : () => _setVehicle(v, o),
            ),
        ]),
      ]),
    );
  }

  Widget _optionButton({
    required String label,
    required bool selected,
    required bool suggested,
    required Color colour,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? colour.withAlpha(40) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: selected
                      ? colour
                      : (suggested ? colour.withAlpha(150) : _line),
                  width: selected ? 1.4 : 1),
            ),
            child: Text.rich(TextSpan(children: [
              if (selected) ...[
                WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.check, size: 13, color: colour)),
                const WidgetSpan(child: SizedBox(width: 5)),
              ],
              TextSpan(
                  text: label,
                  style: _t(11.5,
                      weight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? colour : Colors.white)),
              if (suggested) ...[
                const WidgetSpan(child: SizedBox(width: 6)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: colour.withAlpha(36), borderRadius: BorderRadius.circular(5)),
                    child: Text('suggested', style: _t(8.5, weight: FontWeight.w800, color: colour)),
                  ),
                ),
              ],
            ])),
          ),
        ),
      );

  Widget _questionsCard() {
    final o = _outcome!;
    final items = o.items.where((i) => i.kind != ReconKind.vehicle).toList();
    // A line answered while on screen stays in the view it was answered in,
    // shown as chosen, until the month or the view changes.
    bool inFilter(ReconItem i) => switch (_filter) {
          'ask' => (i.isOpen && !i.bulkOk) ||
              (_justAnswered.contains(i.key) && !i.bulkOk && i.needsAnswer),
          'favour' => (i.isOpen && i.bulkOk) ||
              (_justAnswered.contains(i.key) && i.bulkOk),
          'answered' => i.needsAnswer && !i.isOpen,
          'info' => !i.needsAnswer,
          _ => true,
        };
    final counts = {
      'ask': items.where((i) => i.isOpen && !i.bulkOk).length,
      'favour': items.where((i) => i.isOpen && i.bulkOk).length,
      'answered': items.where((i) => i.needsAnswer && !i.isOpen).length,
      'info': items.where((i) => !i.needsAnswer).length,
      'all': items.length,
    };
    final shown = items.where(inFilter).toList();
    final total = counts['ask']! + counts['favour']! + counts['answered']!;
    final progress = total == 0 ? 1.0 : counts['answered']! / total;
    return _card(
      title: 'STEP 3 · WHAT DOES NOT AGREE',
      icon: Icons.question_answer_outlined,
      accent: o.cleared ? _green : _amber,
      trailing: Text('${counts['answered']} of $total settled',
          style: _t(11, weight: FontWeight.w700, color: o.cleared ? _green : _amber)),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: _line,
            color: o.cleared ? _green : _teal,
          ),
        ),
        const SizedBox(height: 12),
        if (o.unknownVehicles > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                'Some lines are waiting on step 2 — they appear once their vehicle is placed.',
                style: _t(11.5, color: _purple)),
          ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in const [
            ('ask', 'Needs a decision'),
            ('favour', 'In your favour'),
            ('answered', 'Settled'),
            ('info', 'Agrees / for info'),
            ('all', 'All'),
          ])
            _optionButton(
              label: '${f.$2}  ${counts[f.$1]}',
              selected: _filter == f.$1,
              suggested: false,
              colour: f.$1 == 'ask' ? _amber : (f.$1 == 'favour' ? _teal : _green),
              onTap: () => setState(() {
                _filter = f.$1;
                _justAnswered.clear();
              }),
            ),
        ]),
        if (counts['favour']! > 0 && !_settled) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _teal.withAlpha(16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _teal.withAlpha(80)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                    '${counts['favour']} line${counts['favour'] == 1 ? '' : 's'} where NATRAX bill less '
                    'than our record. Settle them at NATRAX\'s figure, each with '
                    'its own note.',
                    style: _t(12, color: Colors.white70, height: 1.4)),
              ),
              const SizedBox(width: 10),
              _smallButton(Icons.done_all, 'Accept all', _acceptAllInFavour,
                  busy: _busy.contains('bulk')),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: Text(
                    _filter == 'ask' ? 'Nothing needs a decision here.' : 'Nothing in this view.',
                    style: _t(12.5, color: _muted))),
          ),
        for (final i in shown) _itemCard(i),
      ],
    );
  }

  Widget _itemCard(ReconItem i) {
    final look = _stanceLook(i.stance);
    final busy = _busy.contains(i.key);
    final open = _expanded.contains(i.key);
    final diff = i.theirsMoney - i.oursMoney;
    // The option just clicked shows as chosen before its save returns.
    final pendingId = _pending[i.key];
    ReconOption? chosen = i.stale ? null : i.chosen;
    if (pendingId != null) {
      for (final o in i.options) {
        if (o.id == pendingId) chosen = o;
      }
    }
    final itemError = _itemErrors[i.key];
    final missing = ReconciliationService.missingRuns(i);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark.withAlpha(150),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: i.isOpen ? look.colour.withAlpha(120) : _line,
            width: i.isOpen ? 1.2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(look.icon, color: look.colour, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, style: _t(13.5, weight: FontWeight.w800)),
              if (i.subtitle.isNotEmpty) Text(i.subtitle, style: _t(11, color: _muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _pill(look.label, look.colour),
                if (i.kind != ReconKind.rule &&
                    i.kind != ReconKind.notOurs &&
                    diff.abs() >= 1)
                  _pill('NATRAX ${diff > 0 ? '+' : '−'}${_inr.format(diff.abs())}',
                      diff > 0 ? _amber : _teal),
              ]),
            ]),
          ),
          if (busy) ...[
            const SizedBox(width: 8),
            const SizedBox(
                width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6, color: _teal)),
          ],
        ]),
        if (i.kind != ReconKind.notOurs && (i.theirs != null || i.ours != null)) ...[
          const SizedBox(height: 10),
          Row(children: [
            // On an invoice line the left side is what the sheet settled
            // at, not our own record.
            Expanded(
                child: _side(i.kind == ReconKind.invoice ? 'AGREED' : 'OURS', i.ours,
                    i.unit, i.oursMinutes, i.ourRuns.length, i.oursMoney, _teal)),
            const SizedBox(width: 8),
            Expanded(
              child: _side(i.kind == ReconKind.invoice ? 'INVOICE' : 'NATRAX', i.theirs,
                  i.unit, i.theirsMinutes, i.theirRuns.length,
                  i.theirsMoney, _amber,
                  note: (i.rule != null && i.rule != i.theirs)
                      ? 'gate log supports ${_h(i.rule)} h'
                      : null),
            ),
          ]),
        ],
        if (i.ourRuns.isNotEmpty || i.theirRuns.isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => open ? _expanded.remove(i.key) : _expanded.add(i.key)),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(children: [
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 16, color: _muted),
                Text(open ? 'Hide in/out times' : 'Show in/out times',
                    style: _t(11, weight: FontWeight.w600, color: _muted)),
              ]),
            ),
          ),
          if (open) _runsTable(i),
        ],
        if (i.hints.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final h in i.hints)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.lightbulb_outline, size: 13, color: _amber),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(h, style: _t(11.5, color: const Color(0xFFE2C18C), height: 1.4))),
              ]),
            ),
        ],
        if (i.needsAnswer) ...[
          const SizedBox(height: 10),
          if (i.stale)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  'The figures have changed since this was answered — please look again.',
                  style: _t(11.5, weight: FontWeight.w600, color: _amber)),
            ),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in i.options)
              _optionButton(
                label: o.label,
                selected: chosen?.id == o.id,
                suggested: chosen == null && i.suggested == o.id,
                colour: o.dispute ? _red : (i.stance == ReconStance.inFavour ? _teal : _green),
                onTap: (_settled || busy) ? null : () => _answer(i, o),
              ),
          ]),
          if (chosen?.detail.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(chosen!.detail, style: _t(11, color: _muted)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentFor(i),
            enabled: !_settled,
            maxLines: 2,
            minLines: 1,
            style: _t(12),
            decoration: _fieldDecoration(i.autoComment.isNotEmpty
                ? 'Comment — "${i.autoComment.length > 70 ? '${i.autoComment.substring(0, 70)}…' : i.autoComment}" is used if left blank'
                : (i.kind == ReconKind.invoice
                    ? 'Comment — required: why does the invoice differ?'
                    : 'Comment (optional)')),
            onSubmitted: (_) => _submitComment(i),
          ),
          if (itemError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, size: 14, color: _red),
                const SizedBox(width: 6),
                Expanded(child: Text(itemError, style: _t(11.5, weight: FontWeight.w600, color: _red))),
              ]),
            ),
          if (i.answer != null && !i.stale)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.check_circle, size: 14, color: _green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Saved: ${i.chosen?.label ?? i.answer!.choice}'
                      '${i.answer!.by == null ? '' : ' · ${i.answer!.by}'}'
                      '${i.answer!.at == null ? '' : ', ${DateFormat('d MMM, HH:mm').format(i.answer!.at!.toLocal())}'}',
                      overflow: TextOverflow.ellipsis,
                      style: _t(10.5, weight: FontWeight.w600, color: _green)),
                ),
                if (!_settled)
                  GestureDetector(
                    onTap: () => _answer(i, i.chosen!),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('Save comment', style: _t(10.5, weight: FontWeight.w700, color: _teal)),
                    ),
                  ),
                if (!_settled) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _do(i.key, () => _svc.clearAnswer(_month, i.key, item: i)),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('Undo', style: _t(10.5, weight: FontWeight.w700, color: _muted)),
                    ),
                  ),
                ],
              ]),
            ),
        ],
        if (missing.isNotEmpty && !_settled && i.kind == ReconKind.track &&
            (i.stance == ReconStance.theirsOnly || i.stance == ReconStance.theirsMore)) ...[
          const SizedBox(height: 10),
          _smallButton(
            Icons.playlist_add,
            'Add NATRAX\'s ${missing.length} missing run${missing.length == 1 ? '' : 's'} to TrackLog',
            () => _addRuns(i),
            colour: _green,
            busy: busy,
          ),
        ],
      ]),
    );
  }

  Widget _pill(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withAlpha(110)),
        ),
        child: Text(text, style: _t(10, weight: FontWeight.w800, color: c)),
      );

  Widget _side(String label, double? qty, String unit, int? minutes, int runs,
      double money, Color c,
      {String? note}) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withAlpha(60)),
          color: c.withAlpha(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _t(9.5, weight: FontWeight.w800, color: c).copyWith(letterSpacing: 1.2)),
          const SizedBox(height: 3),
          Text.rich(TextSpan(children: [
            TextSpan(text: _h(qty), style: _t(20, weight: FontWeight.w800)),
            TextSpan(text: '  $unit', style: _t(11, color: _muted)),
          ])),
          Text(_inr.format(money),
              style: _t(12, weight: FontWeight.w700, color: Colors.white70)),
          if (minutes != null && minutes > 0)
            Text('$minutes min${runs > 0 ? ' · $runs run${runs == 1 ? '' : 's'}' : ''}',
                style: _t(10.5, color: _muted)),
          if (note != null) Text(note, style: _t(10.5, weight: FontWeight.w700, color: _amber)),
        ]),
      );

  Widget _runsTable(ReconItem i) {
    final rows = <({String who, int start, String label, int minutes})>[
      for (final r in i.ourRuns) (who: 'Ours', start: r.startMin, label: r.label, minutes: r.minutes),
      for (final r in i.theirRuns) (who: 'NATRAX', start: r.inMin, label: r.label, minutes: r.minutes),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8), border: Border.all(color: _line)),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: Text(r.who,
                    style: _t(10.5, weight: FontWeight.w700, color: r.who == 'Ours' ? _teal : _amber)),
              ),
              Expanded(child: Text(r.label, style: _t(11.5))),
              Text('${r.minutes} min', style: _t(11, color: _muted)),
            ]),
          ),
      ]),
    );
  }

  Widget _agreedCard() {
    final o = _outcome!;
    final services = o.items
        .where((i) => i.kind == ReconKind.service || i.kind == ReconKind.ev)
        .toList();
    Widget cell(String t, {bool head = false, TextAlign align = TextAlign.right, Color? colour}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Text(t,
              textAlign: align,
              style: head
                  ? _t(9.5, weight: FontWeight.w800, color: _muted).copyWith(letterSpacing: 0.8)
                  : _t(11.5, weight: FontWeight.w600, color: colour ?? Colors.white)),
        );
    return _card(
      title: 'WHAT IS AGREED',
      icon: Icons.table_chart_outlined,
      trailing: o.cleared
          ? _pill('final', _green)
          : _pill('provisional — questions open', _amber),
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2.6),
            1: FlexColumnWidth(1.1),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(1.1),
            4: FlexColumnWidth(1.7),
            5: FlexColumnWidth(1.7),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
              children: [
                cell('TRACK', head: true, align: TextAlign.left),
                cell('NATRAX', head: true),
                cell('OURS', head: true),
                cell('AGREED', head: true),
                cell('AGREED ₹', head: true),
                cell('DISPUTED ₹', head: true),
              ],
            ),
            for (final l in o.trackLines)
              TableRow(children: [
                cell('${l.code}  ${l.name}', align: TextAlign.left),
                cell('${_h(l.natrax)} h', colour: _amber),
                cell('${_h(l.ours)} h', colour: _teal),
                cell('${_h(l.agreed)} h'),
                cell(_inr.format(l.agreedMoney)),
                cell(l.disputedMoney.abs() < 1 ? '—' : _inr.format(l.disputedMoney),
                    colour: l.disputedMoney >= 1 ? _red : _muted),
              ]),
            for (final s in services)
              TableRow(children: [
                cell(s.title, align: TextAlign.left),
                cell('${_h(s.theirs)} ${s.unit}', colour: _amber),
                cell('${_h(s.ours)} ${s.unit}', colour: _teal),
                cell('${_h(s.agreed)} ${s.unit}'),
                cell(_inr.format(s.agreedMoney)),
                cell((s.theirsMoney - s.agreedMoney).abs() < 1
                    ? '—'
                    : _inr.format(s.theirsMoney - s.agreedMoney),
                    colour: (s.theirsMoney - s.agreedMoney) >= 1 ? _red : _muted),
              ]),
            TableRow(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
              children: [
                cell('Total, our vehicles', align: TextAlign.left),
                cell(_inr.format(o.natraxMoney), colour: _amber),
                cell(_inr.format(o.oursMoney), colour: _teal),
                cell(''),
                cell(_inr.format(o.agreedMoney), colour: _green),
                cell(_inr.format((o.natraxMoney - o.agreedMoney).clamp(0, double.infinity)),
                    colour: _red),
              ],
            ),
          ],
        ),
        if (o.notOursMoney > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'Plus ${_inr.format(o.notOursMoney)} billed against vehicles that are '
                'not ours — disputed in full.',
                style: _t(11.5, weight: FontWeight.w700, color: _red)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              'Exclusive blocks are estimated at the quoted block price. NATRAX\'s '
              'invoice is the figure of record.',
              style: _t(10.5, color: _muted)),
        ),
      ],
    );
  }

  Widget _invoiceCard() {
    final s = _state!;
    final inv = s.invoice;
    final open = _invoiceItems.where((i) => i.isOpen).length;
    return _card(
      title: 'STEP 4 · THE FINAL INVOICE',
      icon: Icons.receipt_long_outlined,
      accent: inv == null ? _muted : (open == 0 ? _green : _amber),
      trailing: inv == null
          ? null
          : Text(open == 0 ? 'Tallied' : '$open to answer',
              style: _t(11, weight: FontWeight.w700, color: open == 0 ? _green : _amber)),
      children: [
        if (inv == null) ...[
          Text(
              _outcome!.cleared
                  ? 'Set NATRAX\'s invoice for ${_monthLabel(_month)} against what was '
                      'agreed. Every line that differs needs a comment, kept with the month.'
                  : 'Once the questions above are answered, set the invoice against '
                      'what was agreed. It can be done now too — the agreed figures '
                      'are provisional until then.',
              style: _t(12, color: Colors.white70, height: 1.45)),
          const SizedBox(height: 12),
          if (_invoiceChoices.isNotEmpty) ...[
            Text('Already uploaded for this month:', style: _t(11, color: _muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _invoiceChoices)
                _smallButton(
                  Icons.link,
                  '${c.invoiceNumber} · ${_inr.format(c.amountExclGst)}',
                  _settled ? null : () => _useInvoice(c),
                  busy: _busy.contains('invoice'),
                ),
            ]),
            const SizedBox(height: 10),
          ],
          _smallButton(Icons.upload_file, 'Upload the invoice', _settled ? null : _uploadInvoice),
          const SizedBox(height: 6),
          Text('Uploads once — it is recorded in the PO Tracker as well.',
              style: _t(10.5, color: _muted)),
        ] else ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(s.invoiceNumber ?? inv.invoiceNumber ?? 'Invoice'),
            _chip('Taxable ${_inr2.format(inv.amountExclGst ?? 0)}', colour: _teal),
            _chip('GST ${_inr2.format(inv.gstAmount ?? 0)}'),
            _chip('${inv.lines.length} lines', colour: _muted),
          ]),
          const SizedBox(height: 12),
          for (final i in _invoiceItems)
            i.needsAnswer ? _itemCard(i) : _tallyRow(i),
          if (!_settled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _smallButton(Icons.swap_horiz, 'Use a different invoice', () async {
                await _do('invoice',
                    () => _svc.clearInvoice(_month, s.invoiceNumber));
              }, colour: _muted),
            ),
        ],
      ],
    );
  }

  Widget _tallyRow(ReconItem i) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, size: 15, color: _green),
          const SizedBox(width: 8),
          Expanded(child: Text(i.title, style: _t(12))),
          Text('${_h(i.theirs)} ${i.unit}  ·  ${_inr2.format(i.theirsMoney)}',
              style: _t(11.5, weight: FontWeight.w700, color: Colors.white70)),
        ]),
      );

  Widget _settleCard() {
    final s = _state!;
    final o = _outcome!;
    final invoiceOpen = _invoiceItems.where((i) => i.isOpen).length;
    final questionsOpen =
        o.items.where((i) => i.kind != ReconKind.vehicle && i.isOpen).length;
    // Each unticked line says how many are left and goes to them.
    final checks = [
      (
        'Every vehicle placed',
        o.unknownVehicles == 0,
        '${o.unknownVehicles} to place',
        _kVehicles,
      ),
      (
        'Every question answered',
        o.cleared,
        '$questionsOpen to answer',
        _kQuestions,
      ),
      ('Invoice set against the month', s.invoice != null, 'not set yet', _kInvoice),
      (
        'Every invoice difference explained',
        s.invoice != null && invoiceOpen == 0,
        s.invoice == null ? 'after the invoice' : '$invoiceOpen to explain',
        _kInvoice,
      ),
    ];
    final ready = checks.every((c) => c.$2);
    final f = _figures;
    if (_settled) {
      final sum = s.settledSummary ?? const {};
      return _card(
        title: 'STEP 5 · SETTLED',
        icon: Icons.verified,
        accent: _green,
        trailing: _smallButton(Icons.lock_open, 'Reopen', _reopen,
            colour: _amber, busy: _busy.contains('settle')),
        children: [
          Text(
              'Settled ${DateFormat('d MMM yyyy, HH:mm').format(s.settledAt!.toLocal())}'
              '${s.settledBy == null ? '' : ' by ${s.settledBy}'}.',
              style: _t(12.5, color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (sum['invoice'] != null) _chip('${sum['invoice']}'),
            if (sum['invoice_excl'] != null)
              _chip('Invoice ${_inr.format(sum['invoice_excl'] as num)}', colour: Colors.white),
            _chip('To raise ${_inr.format((sum['to_raise'] ?? sum['disputed'] ?? 0) as num)}',
                colour: _red),
            if (sum['to_pay'] != null)
              _chip('To pay ${_inr.format(sum['to_pay'] as num)}', colour: _green),
            if (sum['invoice_excl'] == null)
              _chip('Agreed ${_inr.format((sum['agreed'] as num?) ?? 0)}', colour: _green),
          ]),
        ],
      );
    }
    return _card(
      title: 'STEP 5 · SETTLE THE MONTH',
      icon: Icons.verified_outlined,
      accent: ready ? _green : _muted,
      children: [
        for (final c in checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              Icon(c.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 15, color: c.$2 ? _green : _amber),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(c.$1, style: _t(12, color: c.$2 ? Colors.white : Colors.white70))),
              if (!c.$2)
                GestureDetector(
                  onTap: () => _goTo(c.$4),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('${c.$3}  →',
                        style: _t(11.5, weight: FontWeight.w700, color: _amber)),
                  ),
                ),
            ]),
          ),
        if (f.toPay != null) ...[
          const SizedBox(height: 8),
          Text(
              'On settling: invoice ${_inr.format(f.invoiceExcl)}, raise '
              '${_inr.format(f.toRaise)}, pay ${_inr.format(f.toPay)} (before GST).',
              style: _t(11.5, color: Colors.white70)),
        ],
        const SizedBox(height: 10),
        _smallButton(Icons.verified, 'Settle ${_monthLabel(_month)}', ready ? _settle : null,
            colour: _green, busy: _busy.contains('settle')),
      ],
    );
  }

  /// The month on one card: the figures, every remark made on a line, and
  /// the history of every decision — who, when, what, and why.
  Widget _summaryCard() {
    final f = _figures;
    final remarks = _remarks;
    IconData iconOf(String action) => switch (action) {
          'answered' || 'accepted (in our favour)' => Icons.check_circle_outline,
          'changed' || 'comment changed' => Icons.edit_outlined,
          'undone' => Icons.undo,
          'vehicle placed' => Icons.directions_car_outlined,
          'sheet uploaded' => Icons.description_outlined,
          'invoice set' || 'invoice removed' => Icons.receipt_long_outlined,
          'settled' => Icons.verified,
          'reopened' => Icons.lock_open,
          'runs added to TrackLog' => Icons.playlist_add,
          _ => Icons.circle_outlined,
        };
    Widget fig(String k, double? v, Color c, {bool bold = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: _t(9.5, weight: FontWeight.w800, color: _muted).copyWith(letterSpacing: 0.8)),
            Text(v == null ? '—' : _inr.format(v),
                style: _t(bold ? 17 : 15, weight: FontWeight.w800, color: c)),
          ]),
        );
    return _card(
      title: 'SUMMARY · ${_monthLabel(_month).toUpperCase()}',
      icon: Icons.summarize_outlined,
      trailing: _smallButton(Icons.download_rounded, 'Export', _export),
      children: [
        Row(children: [
          fig('NATRAX SHEET', f.sheet, _amber),
          fig('AGREED', f.agreed, _teal),
          fig('INVOICE', f.invoiceExcl, Colors.white),
          fig('TO RAISE', f.toRaise, _red),
          fig('TO PAY', f.toPay, _green, bold: true),
        ]),
        const SizedBox(height: 16),
        Text('REMARKS  ${remarks.length}',
            style: _t(10.5, weight: FontWeight.w800, color: _teal).copyWith(letterSpacing: 1)),
        const SizedBox(height: 6),
        if (remarks.isEmpty)
          Text('No comments on any line yet.', style: _t(11.5, color: _muted)),
        for (final r in remarks)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.backgroundDark.withAlpha(150),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.title, style: _t(12, weight: FontWeight.w700))),
                Text(r.kind == ReconKind.invoice ? 'invoice' : 'sheet',
                    style: _t(10, weight: FontWeight.w700, color: _muted)),
              ]),
              Text(r.chosen?.label ?? r.answer!.choice,
                  style: _t(11, weight: FontWeight.w600, color: _green)),
              Text('“${r.answer!.comment}”',
                  style: _t(11.5, color: const Color(0xFFE2C18C), height: 1.4)),
              Text(
                  '${r.answer!.by ?? ''}'
                  '${r.answer!.at == null ? '' : ' · ${DateFormat('d MMM, HH:mm').format(r.answer!.at!.toLocal())}'}',
                  style: _t(10, color: _muted)),
            ]),
          ),
        const SizedBox(height: 14),
        Text('HISTORY  ${_history.length}',
            style: _t(10.5, weight: FontWeight.w800, color: _teal).copyWith(letterSpacing: 1)),
        const SizedBox(height: 6),
        if (_svc.historyMissing)
          Text(
              'History needs one setup step: paste 20261117090000_recon_history.sql '
              'into the Supabase SQL editor and run it. Decisions save either way.',
              style: _t(11.5, color: _amber, height: 1.4))
        else if (_history.isEmpty)
          Text('Nothing recorded yet. Every decision from now on is kept here.',
              style: _t(11.5, color: _muted)),
        for (final h in _history)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(iconOf(h.action), size: 14, color: _muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${h.action[0].toUpperCase()}${h.action.substring(1)}',
                        style: _t(12, weight: FontWeight.w700)),
                    if ((h.title ?? '').isNotEmpty)
                      TextSpan(text: ' · ${h.title}', style: _t(12, color: Colors.white70)),
                  ])),
                  if ((h.choiceLabel ?? '').isNotEmpty)
                    Text(h.choiceLabel!, style: _t(11, color: _green)),
                  if ((h.comment ?? '').isNotEmpty)
                    Text('“${h.comment}”',
                        style: _t(11, color: const Color(0xFFE2C18C), height: 1.4)),
                  if (h.natraxAmount != null || h.agreedAmount != null)
                    Text(
                        '${h.natraxAmount == null ? '' : 'NATRAX ${_inr.format(h.natraxAmount)}'}'
                        '${h.natraxAmount != null && h.agreedAmount != null ? ' · ' : ''}'
                        '${h.agreedAmount == null ? '' : 'agreed ${_inr.format(h.agreedAmount)}'}',
                        style: _t(10.5, color: _muted)),
                  Text(
                      '${DateFormat('d MMM yyyy, HH:mm').format(h.at.toLocal())}'
                      '${h.by == null ? '' : ' · ${h.by}'}',
                      style: _t(10, color: _muted)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _moneyCard() {
    final o = _outcome!;
    // What NATRAX bill above our record on lines nobody has answered yet.
    // Rule lines restate a track line's hours, so they are left out.
    final openMore = o.items
        .where((i) =>
            i.isOpen && !i.bulkOk && i.kind != ReconKind.vehicle && i.kind != ReconKind.rule)
        .fold<double>(0, (s, i) => s + (i.theirsMoney - i.oursMoney).clamp(0, double.infinity));
    Widget row(String k, double v, Color c, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(k, style: _t(12, color: Colors.white70))),
            Text(_inr.format(v), style: _t(bold ? 16 : 13, weight: FontWeight.w800, color: c)),
          ]),
        );
    final f = _figures;
    final inv = _state?.invoice;
    final invoiceOpen = _invoiceItems.where((i) => i.isOpen).length;
    return _card(
      title: 'THE MONTH IN MONEY',
      icon: Icons.currency_rupee,
      accent: inv == null ? _teal : _green,
      children: [
        // Once the invoice is in, it leads: it is what will be paid.
        if (inv != null) ...[
          Text('FINAL INVOICE  ${_state?.invoiceNumber ?? ''}',
              style: _t(10, weight: FontWeight.w800, color: _green)
                  .copyWith(letterSpacing: 1)),
          const SizedBox(height: 4),
          row('Invoice, before GST', f.invoiceExcl ?? 0, Colors.white),
          row('GST', f.invoiceGst ?? 0, _muted),
          row('Invoice total', f.invoiceTotal ?? 0, Colors.white, bold: true),
          row('To raise with NATRAX', f.toRaise, f.toRaise >= 1 ? _red : _muted),
          const Divider(color: _line, height: 16),
          row('To pay, before GST', f.toPay ?? 0, _green, bold: true),
          if (invoiceOpen > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  '$invoiceOpen invoice line${invoiceOpen == 1 ? '' : 's'} still to '
                  'answer — the figure to pay is provisional until then.',
                  style: _t(10.5, color: _amber)),
            ),
          const SizedBox(height: 10),
          Text('THE SHEET',
              style: _t(10, weight: FontWeight.w800, color: _muted)
                  .copyWith(letterSpacing: 1)),
        ],
        row('NATRAX sheet, our vehicles', o.natraxMoney, _amber),
        row('Our record', o.oursMoney, _teal),
        if (inv == null) const Divider(color: _line, height: 16),
        row(o.cleared ? 'Agreed' : 'Agreed so far', o.agreedMoney, _green, bold: inv == null),
        if (openMore > 0) row('NATRAX more — still to decide', openMore, _amber),
        if (o.notOursMoney > 0) row('Not ours (disputed)', o.notOursMoney, _red),
        if (inv == null) row('To raise with NATRAX', f.toRaise, _red),
        if (!o.cleared)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Lines not yet answered count at NATRAX\'s figure until you decide.',
                style: _t(10.5, color: _amber)),
          ),
        const SizedBox(height: 6),
        Text(
            inv == null
                ? 'Before GST — NATRAX bill the SEZ entity under LUT. Upload the '
                    'final invoice and its amount leads this card.'
                : 'Before GST unless shown — NATRAX bill the SEZ entity under LUT.',
            style: _t(10.5, color: _muted)),
      ],
    );
  }

  Widget _todoCard() {
    final todos = _outcome!.todos;
    return _card(
      title: 'FIX IN TRACKLOG',
      icon: Icons.build_circle_outlined,
      accent: todos.isEmpty ? _green : _amber,
      trailing: Text('${todos.length}', style: _t(12, weight: FontWeight.w800, color: todos.isEmpty ? _green : _amber)),
      children: [
        if (todos.isEmpty)
          Text('Nothing — our record needs no correcting from what is answered so far.',
              style: _t(11.5, color: _muted, height: 1.4)),
        for (final t in todos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.arrow_right, size: 15, color: _amber)),
              Expanded(child: Text(t, style: _t(11.5, color: Colors.white70, height: 1.4))),
            ]),
          ),
      ],
    );
  }

  Widget _disputesCard() {
    final f = _figures;
    final ds = f.raise;
    return _card(
      title: 'TO RAISE WITH NATRAX',
      icon: Icons.outgoing_mail,
      accent: ds.isEmpty ? _green : _red,
      trailing: ds.isEmpty
          ? null
          : _smallButton(Icons.copy, 'Copy', () {
              Clipboard.setData(ClipboardData(text: _disputeText()));
              _say('Copied — paste it into the mail to NATRAX.');
            }, colour: _red),
      children: [
        Text(
            _state?.invoice != null
                ? 'From the invoice: lines where NATRAX charge more than you agreed.'
                : 'From the sheet. Once the invoice is set, its lines take over.',
            style: _t(10.5, color: _muted)),
        const SizedBox(height: 8),
        if (ds.isEmpty)
          Text('Nothing disputed.', style: _t(11.5, color: _muted)),
        for (final d in ds)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.flag_outlined, size: 14, color: _red)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.title, style: _t(12, weight: FontWeight.w700)),
                  Text(
                      d.kind == ReconKind.notOurs
                          ? '${_inr.format(d.theirsMoney)} — all of it'
                          : 'Charged ${_inr.format(d.theirsMoney)}, agreed '
                              '${_inr.format(d.agreedMoney)} — raise '
                              '${_inr.format(d.theirsMoney - d.agreedMoney)}',
                      style: _t(11, color: _muted)),
                  if ((d.answer?.comment ?? '').trim().isNotEmpty)
                    Text('“${d.answer!.comment}”',
                        style: _t(11, color: const Color(0xFFE2C18C))),
                ]),
              ),
            ]),
          ),
        if (ds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Total ${_inr.format(f.toRaise)}',
                style: _t(13, weight: FontWeight.w800, color: _red)),
          ),
      ],
    );
  }

  Widget _notesCard() {
    final notes = (_state?.notes ?? const <ReconNote>[]).reversed.toList();
    IconData iconOf(String k) => switch (k) {
          'sheet' => Icons.description_outlined,
          'invoice' => Icons.receipt_long_outlined,
          'settled' => Icons.verified,
          'reopened' => Icons.lock_open,
          _ => Icons.sticky_note_2_outlined,
        };
    return _card(
      title: 'NOTES FOR ${_monthLabel(_month).toUpperCase()}',
      icon: Icons.sticky_note_2_outlined,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _noteCtrl,
              style: _t(12),
              minLines: 1,
              maxLines: 3,
              decoration: _fieldDecoration('A note for this month — a call with NATRAX, '
                  'something to check…'),
              onSubmitted: (_) => _addNote(),
            ),
          ),
          const SizedBox(width: 8),
          _smallButton(Icons.add, 'Add', _addNote, busy: _busy.contains('note')),
        ]),
        const SizedBox(height: 10),
        if (notes.isEmpty) Text('No notes yet.', style: _t(11.5, color: _muted)),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(iconOf(n.kind), size: 14, color: _muted)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.note, style: _t(11.5, color: Colors.white70, height: 1.4)),
                  Text(
                      '${DateFormat('d MMM, HH:mm').format(n.createdAt.toLocal())}'
                      '${n.createdBy == null ? '' : ' · ${n.createdBy}'}',
                      style: _t(10, color: _muted)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

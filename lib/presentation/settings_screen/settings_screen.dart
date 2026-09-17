import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/app_settings_service.dart';
import '../../services/billing_baseline.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/excel_backup_downloader.dart';
import '../../services/excel_backup_service.dart';
import '../../services/invoice_opener.dart';
import '../../services/invoice_service.dart';
import '../../widgets/invoice_upload_flow.dart';
import '../../services/pin_lock_service.dart';
import '../../widgets/pin_pad.dart';
import '../../services/project_manager.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';
import '../../core/app_version.dart';
import '../../services/session_status.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  EngineerProfile? _profile;
  bool _loadingProfile = true;

  // Password
  final _curPassCtrl  = TextEditingController();
  final _newPassCtrl  = TextEditingController();
  final _confPassCtrl = TextEditingController();
  bool _obscureCur = true, _obscureNew = true, _obscureConf = true;
  bool _savingPass = false;

  // Notifications
  bool _notifySession = true;
  bool _notifyReport  = true;
  bool _notifyGate    = false;

  // Export
  String _exportFreq = 'monthly';

  // Original NATRAX invoices
  List<NatraxInvoice> _invoices = [];
  /// PO rows with their category, so the picker can say which is manpower and
  /// which is track booking rather than showing bare numbers.
  List<Map<String, dynamic>> _poOptions = [];
  List<String> _activeMonths = []; // 'YYYY-MM', newest first
  bool _loadingInvoices = true;
  bool _uploadingInvoice = false;
  bool _scanning = false;

  static final _inr = NumberFormat.currency(
      locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static final _dmy = DateFormat('dd MMM yyyy');

  // Workshop bay. These were constants in billing_baseline.dart until the
  // monthly "stop accruing for the invoiced month" edit proved it needed to
  // be a field, not a redeploy.
  DateTime? _wsSettledTo;
  DateTime? _wsResumedOn;
  DateTime? _wsReleasedOn;
  bool _loadingWorkshop = true;
  bool _savingWorkshop = false;
  /// Read from tracklog_writers, the same table RLS checks, so the screen
  /// never offers an edit the database will refuse.
  bool _canEditWorkshop = false;

  bool get _canEditInvoices => !(_profile?.isReadOnly ?? true);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadInvoices();
    _loadLastBackup();
    _loadPinState();
    _loadWorkshop();
  }

  /// Whether this device holds a sign-in PIN. Device-local, so it says
  /// nothing about the account — the same login on another machine has its
  /// own answer.
  bool _pinSet = false;

  /// Which settings tab is showing.
  ///
  /// The page was one scroll of seven sections, and Invoices alone is ~320
  /// lines of it, so anything below that was effectively unreachable -- which
  /// is how the change-password card ended up unrendered and unnoticed.
  int _tab = 0;

  static const _tabs = <({String label, IconData icon})>[
    (label: 'Account',       icon: Icons.person_outline_rounded),
    (label: 'Notifications', icon: Icons.notifications_none_rounded),
    (label: 'Billing',       icon: Icons.receipt_long_outlined),
    (label: 'Security',      icon: Icons.shield_outlined),
  ];

  Future<void> _loadPinState() async {
    final set = await PinLockService.instance.isEnabled();
    if (mounted) setState(() => _pinSet = set);
  }

  Future<void> _removePin() async {
    await PinLockService.instance.disable();
    if (!mounted) return;
    setState(() => _pinSet = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'PIN removed from this device. Sign in with your email and password; '
        'you will be offered a new PIN afterwards.',
        style: GoogleFonts.spaceGrotesk(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
      ),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Sets a PIN without signing out.
  ///
  /// The login screen offers one straight after sign-in, which is the only
  /// moment it holds the password. Anyone already signed in never passes
  /// through that, so this asks for the password and verifies it the same way
  /// [_changePassword] does, rather than making them sign out and back in.
  Future<void> _setPinFromSettings() async {
    final email = _profile?.email ?? '';
    if (email.isEmpty) return _snack('Profile not loaded yet', error: true);

    final passCtrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (ctx) => AlertDialog(
        // Scrolls rather than overflowing: a long list or a small laptop
        // screen otherwise pushes the buttons off the bottom, out of reach.
        scrollable: true,
        backgroundColor: const Color(0xFF0A1025),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withAlpha(20)),
        ),
        title: Text('Confirm your password',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'The PIN releases this login on this device, so the password has '
            'to be checked once before it can be stored.',
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF8A94B0), fontSize: 12),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: passCtrl,
            obscureText: true,
            autofocus: true,
            style: GoogleFonts.spaceGrotesk(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: GoogleFonts.spaceGrotesk(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withAlpha(13),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(passCtrl.text),
              child: Text('Continue',
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF00F3FF),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    passCtrl.dispose();
    if (password == null || password.isEmpty || !mounted) return;

    try {
      await EngineerAuthService.instance
          .signIn(email: email, password: password);
    } catch (_) {
      return _snack('Incorrect password', error: true);
    }
    if (!mounted) return;

    String? chosen;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (ctx) => PinPad(
        title: 'Set a PIN for this device',
        subtitle: 'Signs you in without typing your password. The PIN stays '
            'on this device and is never sent anywhere.',
        length: PinLockService.pinLength,
        escapeLabel: 'Cancel',
        onEscape: () => Navigator.of(ctx).pop(),
        onComplete: (pin) async {
          chosen = pin;
          Navigator.of(ctx).pop();
          return null;
        },
      ),
    );
    if (chosen == null || !mounted) return;

    var confirmed = false;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (ctx) => PinPad(
        title: 'Confirm your PIN',
        length: PinLockService.pinLength,
        escapeLabel: 'Cancel',
        onEscape: () => Navigator.of(ctx).pop(),
        onComplete: (pin) async {
          if (pin != chosen) return 'Those did not match. Try again.';
          confirmed = true;
          Navigator.of(ctx).pop();
          return null;
        },
      ),
    );
    if (!confirmed || !mounted) return;

    await PinLockService.instance
        .enable(pin: chosen!, email: email, password: password);
    if (!mounted) return;
    setState(() => _pinSet = true);
    _snack('PIN set. Next sign-in, use Unlock with PIN.');
  }

  @override
  void dispose() {
    _curPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final p = await EngineerAuthService.instance.getCurrentProfile();
    if (mounted) setState(() { _profile = p; _loadingProfile = false; });
  }

  Future<void> _changePassword() async {
    final cur  = _curPassCtrl.text.trim();
    final next = _newPassCtrl.text.trim();
    final conf = _confPassCtrl.text.trim();
    if (cur.isEmpty || next.isEmpty || conf.isEmpty) {
      return _snack('Fill in all password fields', error: true);
    }
    if (next.length < 8) return _snack('New password must be ≥ 8 characters', error: true);
    if (next != conf)    return _snack('New passwords do not match', error: true);

    setState(() => _savingPass = true);
    try {
      await EngineerAuthService.instance.signIn(
          email: _profile?.email ?? '', password: cur);
      await SupabaseService.instance.client.auth.updateUser(
          UserAttributes(password: next));
      _curPassCtrl.clear(); _newPassCtrl.clear(); _confPassCtrl.clear();
      _snack('Password updated successfully ✓');
    } catch (_) {
      _snack('Incorrect current password', error: true);
    } finally {
      if (mounted) setState(() => _savingPass = false);
    }
  }

  Future<void> _sendForgotPassword() async {
    final email = _profile?.email ?? '';
    if (email.isEmpty) return _snack('No email on profile', error: true);
    try {
      await SupabaseService.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseService.appUrl,
      );
      _snack('Reset link sent to $email');
    } catch (_) {
      _snack('Could not send reset email', error: true);
    }
  }

  // ─── Original NATRAX invoices ──────────────────────────────────────────────

  Future<void> _loadInvoices() async {
    try {
      final client = SupabaseService.instance.client;
      final invoices = await InvoiceService.instance.list();
      final poRows = await client
          .from('po_trackers')
          .select('po_number, category, vendor_name, po_status')
          .order('category');

      // Months that actually had track activity — these are the months an
      // invoice is expected for, so a missing one is visible rather than
      // simply absent from the list.
      final sessionRows = await client
          .from('engineer_sessions')
          .select('started_at, project_name')
          .inFilter('session_status', kBillableSessionStatuses);

      final pm = ProjectManager.instance;
      final months = <String>{};
      for (final row in sessionRows as List) {
        if (!pm.sessionBelongsToProject(row['project_name'] as String?)) continue;
        final started = DateTime.tryParse(row['started_at'] as String? ?? '');
        if (started != null) {
          months.add('${started.year}-'
              '${started.month.toString().padLeft(2, '0')}');
        }
      }
      months.addAll(invoices
          .map((i) => i.periodMonth ?? '')
          .where((m) => m.isNotEmpty));

      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _poOptions = (poRows as List)
            .cast<Map<String, dynamic>>()
            .where((r) => ((r['po_number'] as String?) ?? '').isNotEmpty)
            .toList();
        _activeMonths = months.toList()..sort((a, b) => b.compareTo(a));
        _loadingInvoices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingInvoices = false);
      _snack('Could not load invoices — $e', error: true);
    }
  }

  Future<void> _openInvoice(NatraxInvoice inv) async {
    final err = await openInvoice(inv);
    if (err != null) _snack(err, error: true);
  }


  /// Moves an invoice onto a different PO.
  ///
  /// Added because the only way to correct a wrong PO was to delete the
  /// invoice and upload it again — and deleting takes the stored PDF with it,
  /// so a mis-filed invoice cost you the document unless you still had the
  /// original file. InvoiceService.update() could already do this; nothing
  /// had ever called it.
  Future<void> _editInvoicePo(NatraxInvoice inv) async {
    final options = _poOptions
        .map((r) => (r['po_number'] as String?) ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      return _snack('No POs loaded to choose from', error: true);
    }

    var chosen = options.contains(inv.poNumber) ? inv.poNumber : options.first;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withAlpha(160),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          // Scrolls rather than overflowing: a long list or a small laptop
          // screen otherwise pushes the buttons off the bottom, out of reach.
          scrollable: true,
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withAlpha(20)),
          ),
          title: Text('Change PO',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '${inv.invoiceNumber} — ${_inr.format(inv.amountExclGst)} excl GST',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0), fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text('Currently on ${inv.poNumber ?? 'no PO'}',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF8A94B0), fontSize: 11)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: chosen,
              isExpanded: true,
              dropdownColor: const Color(0xFF0A1025),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Draws down PO',
                labelStyle: TextStyle(color: Colors.white70),
              ),
              items: [
                for (final r in _poOptions)
                  if (((r['po_number'] as String?) ?? '').isNotEmpty)
                    DropdownMenuItem(
                      value: r['po_number'] as String,
                      child: Text(
                        'PO # ${r['po_number']}'
                        ' · ${(r['category'] as String?) ?? 'other'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (v) => setLocal(() => chosen = v ?? chosen),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white54))),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Move',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );

    if (confirmed != true || chosen == inv.poNumber || !mounted) return;

    try {
      await InvoiceService.instance.updateAmounts(
        id: inv.id,
        // Amounts are resent unchanged: update() requires them, and this
        // dialog deliberately does not let you edit money.
        amountExclGst: inv.amountExclGst,
        gstAmount: inv.gstAmount,
        totalAmount: inv.totalAmount,
        poNumber: chosen,
      );
      if (!mounted) return;
      _snack('${inv.invoiceNumber} moved to PO $chosen');
      _loadInvoices();
    } catch (e) {
      if (mounted) _snack('Could not move it — $e', error: true);
    }
  }
  Future<void> _confirmDeleteInvoice(NatraxInvoice inv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Scrolls rather than overflowing: a long list or a small laptop
        // screen otherwise pushes the buttons off the bottom, out of reach.
        scrollable: true,
        backgroundColor: const Color(0xFF0A1025),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withAlpha(60)),
        ),
        title: Text('Remove invoice?',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'Invoice ${inv.invoiceNumber} (${_inr.format(inv.totalAmount)}) and its '
          'stored PDF will be deleted. The PO reconciliation will change.',
          style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF8A94B0), fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await InvoiceService.instance.delete(inv);
      if (!mounted) return;
      setState(() => _invoices.removeWhere((i) => i.id == inv.id));
      _snack('Invoice ${inv.invoiceNumber} removed');
    } catch (e) {
      _snack('Delete failed — $e', error: true);
    }
  }

  /// Picks the original PDF and reads the figures straight off it.
  ///
  /// Nothing needs typing: the parser fills every field, and the review sheet
  /// exists so a bad scan cannot silently feed wrong numbers into the PO
  /// reconciliation — not to make anyone re-key the invoice.
  Future<void> _uploadInvoice() async {
    if (!_canEditInvoices) {
      return _snack('Managers have read-only access to billing records',
          error: true);
    }

    setState(() => _scanning = true);
    final created = await InvoiceUploadFlow.start(
      context,
      poOptions: _poOptions,
      knownMonths: _activeMonths,
      uploadedBy: _profile?.email,
      onMessage: (m, {bool error = false}) => _snack(m, error: error),
    );
    if (!mounted) return;
    setState(() => _scanning = false);

    if (created != null) {
      setState(() => _invoices = [created, ..._invoices]);
      _loadInvoices(); // refresh the month grid and totals
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.spaceGrotesk(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background ambient glows
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
                    AppTheme.primary.withOpacity(0.12), // Primary/Cyan glow
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
                    const Color(0xFFA855F7).withOpacity(0.10), // Purple glow
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: _loadingProfile
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildPageHeader()),
                      SliverToBoxAdapter(child: _tabBar()),
                      // Keyed on the tab so switching rebuilds rather than
                      // trying to reuse element state across two unrelated
                      // lists of cards.
                      SliverList(
                        key: ValueKey(_tab),
                        delegate: SliverChildListDelegate(_tabContent()),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Page header ───────────────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(70)),
          ),
          child: const Icon(Icons.settings_rounded, color: AppTheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Settings', style: GoogleFonts.spaceGrotesk(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: const Color(0xFFdfe2f0))),
            Text('Account, preferences & communication',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, color: const Color(0xFF6B7490))),
          ]),
        ),
        Image.asset(
          'assets/images/goodyear_sightline_logo.png',
          height: 18,
          color: Colors.white70,
          fit: BoxFit.contain,
        ),
      ]),
    );
  }

  // ─── Section label ─────────────────────────────────────────────────────────


  /// The tab strip. Scrolls horizontally so it survives a phone width without
  /// the labels being cut or wrapped onto a second line.
  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final sel = i == _tab;
            final t = _tabs[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppTheme.primary.withAlpha(28)
                        : Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sel
                          ? AppTheme.primary.withAlpha(110)
                          : Colors.white.withAlpha(26),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.icon,
                        size: 15,
                        color: sel ? AppTheme.primary : Colors.white54),
                    const SizedBox(width: 7),
                    Text(t.label,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12.5,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                          color: sel ? AppTheme.primary : Colors.white60,
                        )),
                  ]),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Only the selected tab's content. Nothing else is built, so a tab switch
  /// costs nothing and no section can hide below another.
  List<Widget> _tabContent() {
    switch (_tab) {
      case 0:
        return [
          _buildProfileCard(),
          _sectionLabel('PASSWORD'),
          // Never rendered before this tab existed: the card was defined and
          // left out of the sliver list, so nobody could change a password
          // from Settings at all.
          _buildAccountSection(),
        ];
      case 1:
        return [
          _sectionLabel('REPORT RECIPIENTS'),
          _buildCommunicationSection(),
          _sectionLabel('ALERTS'),
          _buildNotificationsSection(),
          _sectionLabel('EXPORT FREQUENCY'),
          _buildExportSection(),
        ];
      case 2:
        return [
          _sectionLabel('INVOICES'),
          _buildInvoicesSection(),
          _sectionLabel('WORKSHOP BAY'),
          _buildWorkshopSection(),
          _sectionLabel('BACKUP'),
          _buildBackupSection(),
        ];
      default:
        return [_sectionLabel('SECURITY'), _buildSecuritySection()];
    }
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Text(label, style: GoogleFonts.spaceGrotesk(
        fontSize: 10, fontWeight: FontWeight.w700,
        color: const Color(0xFF6B7490), letterSpacing: 2)),
  );

  // ─── Profile card ──────────────────────────────────────────────────────────

  Widget _buildProfileCard() {
    final name    = _profile?.engineerName ?? 'Engineer';
    final email   = _profile?.email ?? '';
    final dept    = _profile?.department ?? 'Tyre Testing';
    final isAdmin = _profile?.isManager ?? false;

    return _card(
      child: Row(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.primary.withAlpha(90), AppTheme.primary.withAlpha(30)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withAlpha(100)),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'E',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.spaceGrotesk(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: const Color(0xFFdfe2f0)),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(email, style: GoogleFonts.spaceGrotesk(
              fontSize: 12, color: const Color(0xFFA8B0C8)),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            _badge(dept, AppTheme.info),
            _badge(isAdmin ? 'Manager' : 'Engineer',
                isAdmin ? const Color(0xFFFFB547) : AppTheme.primary),
          ]),
        ])),
      ]),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withAlpha(80)),
    ),
    child: Text(label, style: GoogleFonts.spaceGrotesk(
        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );

  // ─── Account section (Change Password) ────────────────────────────────────

  Widget _buildAccountSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.lock_outline_rounded, 'Change Password'),
        const SizedBox(height: 16),
        _passField(_curPassCtrl,  'Current Password',     _obscureCur,
            () => setState(() => _obscureCur  = !_obscureCur)),
        const SizedBox(height: 12),
        _passField(_newPassCtrl,  'New Password',         _obscureNew,
            () => setState(() => _obscureNew  = !_obscureNew)),
        const SizedBox(height: 12),
        _passField(_confPassCtrl, 'Confirm New Password', _obscureConf,
            () => setState(() => _obscureConf = !_obscureConf)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _savingPass ? null : _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF001A10),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _savingPass
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF001A10)))
                : Text('Update Password', style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _passField(TextEditingController ctrl, String label, bool obscure,
      VoidCallback onToggle) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: const Color(0xFFdfe2f0)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.spaceGrotesk(color: const Color(0xFF6B7490), fontSize: 12),
        filled: true,
        fillColor: Colors.white.withAlpha(6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        suffixIcon: GestureDetector(
          onTap: onToggle,
          child: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: const Color(0xFF6B7490), size: 18),
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(20))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withAlpha(15))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }

  // ─── Communication section ─────────────────────────────────────────────────

  Widget _buildCommunicationSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.hub_outlined, 'Communication Hub'),
        const SizedBox(height: 4),
        Text('Purchase orders, email reports and team communication',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
        const SizedBox(height: 16),
        _navRow(
          icon: Icons.email_rounded,
          iconColor: const Color(0xFF4CAF50),
          title: 'Email Reports',
          subtitle: 'Send NATRAX expense updates to Harsh & team',
          onTap: () => context.push(AppRoutes.emailReports),
        ),
        _divider(),
        _navRow(
          icon: Icons.location_on_rounded,
          iconColor: const Color(0xFFFF9800),
          title: 'Gate Management',
          subtitle: 'Configure geofenced track entry gates',
          onTap: () => context.go(AppRoutes.gateManagement),
        ),
        _divider(),
        _navRow(
          icon: Icons.campaign_rounded,
          iconColor: AppTheme.primary,
          title: 'Project Updates',
          subtitle: 'Bulletin board — milestones, alerts, attachments',
          onTap: () => context.go(AppRoutes.projectUpdates),
        ),
      ]),
    );
  }

  Widget _navRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: iconColor.withAlpha(50)),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.spaceGrotesk(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: const Color(0xFFdfe2f0))),
            Text(subtitle, style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
          ])),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: const Color(0xFF4A5470)),
        ]),
      ),
    );
  }

  Widget _divider() => Container(
    height: 1, color: const Color(0xFF2A3450),
    margin: const EdgeInsets.symmetric(vertical: 2),
  );

  // ─── Notifications section ─────────────────────────────────────────────────

  bool _backupBusy = false;
  String? _backupNote;
  bool _backupFailed = false;
  DateTime? _lastBackup;

  Future<void> _loadLastBackup() async {
    final at = await BackupRecency.last();
    if (mounted) setState(() => _lastBackup = at);
  }

  Widget _buildNotificationsSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.notifications_outlined, 'Notification Preferences'),
        const SizedBox(height: 14),
        _toggleRow(
          icon: Icons.timer_outlined,
          color: AppTheme.primary,
          label: 'Session Alerts',
          subtitle: 'Session start and end notifications',
          value: _notifySession,
          onChanged: (v) => setState(() => _notifySession = v),
        ),
        _toggleRow(
          icon: Icons.email_outlined,
          color: const Color(0xFF4CAF50),
          label: 'Report Ready',
          subtitle: 'Notify when an email report is sent',
          value: _notifyReport,
          onChanged: (v) => setState(() => _notifyReport = v),
        ),
        _toggleRow(
          icon: Icons.location_on_outlined,
          color: const Color(0xFFFFB547),
          label: 'Gate Alerts',
          subtitle: 'Entry / exit gate notifications',
          value: _notifyGate,
          onChanged: (v) => setState(() => _notifyGate = v),
        ),
      ]),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(22),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: const Color(0xFFdfe2f0))),
          Text(subtitle, style: GoogleFonts.spaceGrotesk(
              fontSize: 11, color: const Color(0xFF6B7490))),
        ])),
        Switch(
          value: value, onChanged: onChanged,
          activeColor: AppTheme.primary,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }

  // ─── Export section ────────────────────────────────────────────────────────

  /// Full download of everything entered in the app, as a real .xlsx.
  ///
  /// A browser cannot write into the master workbook on someone's desktop, so
  /// this produces a file to save wherever the backup lives. It reads Supabase
  /// directly rather than any screen's state, so it captures the database, not
  /// whatever happens to be loaded.
  Widget _buildBackupSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.backup_outlined, 'Backup to Excel'),
        const SizedBox(height: 6),
        Text(
            'Downloads every session, service line and muster day as a '
            'spreadsheet. Four sheets, with a Summary that carries row counts '
            'and totals so it can be checked against the app.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
        const SizedBox(height: 12),
        Builder(builder: (_) {
          final now = DateTime.now();
          final overdue = BackupRecency.isStale(_lastBackup, now);
          final colour = overdue
              ? const Color(0xFFF59E0B)
              : const Color(0xFF22C55E);
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colour.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colour.withAlpha(90)),
            ),
            child: Row(children: [
              Icon(overdue ? Icons.warning_amber_rounded : Icons.check_circle,
                  color: colour, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(BackupRecency.describe(_lastBackup, now),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 10.5, height: 1.4, color: colour)),
              ),
            ]),
          );
        }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _backupBusy ? null : _downloadBackup,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              disabledBackgroundColor: AppTheme.primary.withAlpha(70),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: _backupBusy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF001A10)))
                : const Icon(Icons.download_rounded,
                    size: 18, color: Color(0xFF001A10)),
            label: Text(_backupBusy ? 'Preparing…' : 'Download backup',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF001A10))),
          ),
        ),
        if (_backupNote != null) ...[
          const SizedBox(height: 10),
          Text(_backupNote!,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10.5,
                  color: _backupFailed
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E))),
        ],
      ]),
    );
  }

  Future<void> _downloadBackup() async {
    setState(() {
      _backupBusy = true;
      _backupNote = null;
      _backupFailed = false;
    });
    try {
      final result = await ExcelBackupDownloader.generate();
      ExcelBackupDownloader.save(result.bytes, result.name);
      if (!mounted) return;
      final d = result.data;
      await BackupRecency.record(DateTime.now());
      if (!mounted) return;
      await _loadLastBackup();
      if (!mounted) return;
      setState(() {
        _backupNote = 'Saved ${result.name} — '
            '${d.sessions.length} sessions, ${d.services.length} services, '
            '${d.muster.length} muster days.';
        _backupFailed = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Surfaced, never swallowed. A backup that fails quietly is believed to
      // have worked, which is worse than not having one.
      setState(() {
        _backupNote = 'Backup failed: $e';
        _backupFailed = true;
      });
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Widget _buildExportSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.download_rounded, 'Export Frequency'),
        const SizedBox(height: 6),
        Text('How often activity reports are exported and sent.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, color: const Color(0xFF6B7490))),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _freqChip('monthly', 'Monthly',
              Icons.calendar_month_outlined, 'Every month')),
          const SizedBox(width: 10),
          Expanded(child: _freqChip('yearly', 'Yearly',
              Icons.calendar_today_outlined, 'Once a year')),
        ]),
      ]),
    );
  }

  Widget _freqChip(String val, String label, IconData icon, String sub) {
    final sel = _exportFreq == val;
    return GestureDetector(
      onTap: () => setState(() => _exportFreq = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? AppTheme.primary.withAlpha(25) : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? AppTheme.primary.withAlpha(150) : Colors.white.withAlpha(15),
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon,
                color: sel ? AppTheme.primary : const Color(0xFF6B7490), size: 18),
            const Spacer(),
            if (sel) Container(
              width: 16, height: 16,
              decoration: const BoxDecoration(
                  color: AppTheme.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 10, color: Color(0xFF001A10)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: sel ? AppTheme.primary : const Color(0xFFdfe2f0))),
          Text(sub, style: GoogleFonts.spaceGrotesk(
              fontSize: 10, color: const Color(0xFF6B7490))),
        ]),
      ),
    );
  }

  // ─── Original invoices ─────────────────────────────────────────────────────

  Widget _buildInvoicesSection() {
    final totals = InvoiceTotals.from(_invoices);

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: _cardTitle(
                  Icons.receipt_long_rounded, 'Original Invoices')),
          if (_canEditInvoices)
            GestureDetector(
              onTap: (_uploadingInvoice || _scanning) ? null : _uploadInvoice,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withAlpha(90)),
                ),
                child: (_uploadingInvoice || _scanning)
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.primary)),
                        const SizedBox(width: 7),
                        Text(_scanning ? 'Reading…' : 'Uploading…',
                            style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ])
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.document_scanner_outlined,
                            size: 13, color: AppTheme.primary),
                        const SizedBox(width: 5),
                        Text('Scan & Upload',
                            style: GoogleFonts.spaceGrotesk(
                                color: AppTheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ]),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          _canEditInvoices
              ? 'Track and manpower invoices both go here — pick the PDF and '
                  'the figures are read off it, then choose the PO it draws '
                  'on. A non-NATRAX invoice may not read automatically; you '
                  'can enter it by hand.'
              : 'Invoices on file. Read-only for managers.',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 11, color: const Color(0xFF6B7490), height: 1.45),
        ),
        const SizedBox(height: 14),

        if (!_loadingInvoices && _activeMonths.isNotEmpty) ...[
          _buildMonthStatusGrid(),
          const SizedBox(height: 16),
        ],

        if (_loadingInvoices)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary))),
          )
        else if (_invoices.isEmpty && _activeMonths.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: Column(children: [
              Icon(Icons.description_outlined,
                  size: 26, color: Colors.white.withAlpha(50)),
              const SizedBox(height: 8),
              Text('No invoices uploaded yet',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF8A94B0))),
              const SizedBox(height: 3),
              Text(
                  'Until an original is uploaded, the PO balance rests on '
                  'app-computed costs alone.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10.5, color: const Color(0xFF6B7490))),
            ]),
          )
        else ...[
          ..._invoices.map(_invoiceTile),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2A3450), height: 1),
          const SizedBox(height: 12),
          Row(children: [
            Text('${totals.count} invoice${totals.count == 1 ? '' : 's'}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8A94B0))),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Total billed  ${_inr.format(totals.total)}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary)),
              Text(
                  '${_inr.format(totals.exclGst)} excl. GST  ·  '
                  '${_inr.format(totals.gst)} GST',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, color: const Color(0xFF6B7490))),
            ]),
          ]),
        ],
      ]),
    );
  }

  /// One row per month that had track activity, so a month with no invoice
  /// reads as a gap rather than simply being absent from the list.
  Widget _buildMonthStatusGrid() {
    final byMonth = <String, List<NatraxInvoice>>{};
    for (final inv in _invoices) {
      final m = inv.periodMonth;
      if (m == null || m.isEmpty) continue;
      byMonth.putIfAbsent(m, () => []).add(inv);
    }

    final covered = _activeMonths.where(byMonth.containsKey).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('MONTH-WISE STATUS',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: const Color(0xFF6B7490))),
        const Spacer(),
        Text('$covered of ${_activeMonths.length} invoiced',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: covered == _activeMonths.length
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFFB547))),
      ]),
      const SizedBox(height: 9),
      ..._activeMonths.map((month) => _monthRow(month, byMonth[month])),
    ]);
  }

  Widget _monthRow(String month, List<NatraxInvoice>? invoices) {
    final has = invoices != null && invoices.isNotEmpty;
    final total = has ? invoices.fold(0.0, (s, i) => s + i.totalAmount) : 0.0;
    final accent =
        has ? const Color(0xFF4CAF50) : const Color(0xFFFFB547);

    final parts = month.split('-');
    final label = parts.length == 2
        ? DateFormat('MMM yyyy').format(
            DateTime(int.parse(parts[0]), int.parse(parts[1])))
        : month;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GestureDetector(
        onTap: has && invoices.first.hasFile
            ? () => _openInvoice(invoices.first)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withAlpha(has ? 14 : 10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withAlpha(has ? 55 : 45)),
          ),
          child: Row(children: [
            Icon(has ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 15, color: accent),
            const SizedBox(width: 10),
            SizedBox(
              width: 66,
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text(
                has
                    ? invoices.map((i) => i.invoiceNumber).join(', ')
                    : 'No invoice uploaded',
                style: GoogleFonts.spaceGrotesk(
                    color: has ? const Color(0xFF8A94B0) : accent,
                    fontSize: 10.5,
                    fontWeight: has ? FontWeight.w500 : FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(has ? _inr.format(total) : '—',
                style: GoogleFonts.spaceGrotesk(
                    color: has ? Colors.white : const Color(0xFF4A5470),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            if (has && invoices.first.hasFile) ...[
              const SizedBox(width: 6),
              Icon(Icons.remove_red_eye_outlined,
                  size: 13, color: AppTheme.primary.withAlpha(160)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _invoiceTile(NatraxInvoice inv) {
    final flagged = inv.isInternallyInconsistent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: flagged
                  ? const Color(0xFFFFB547).withAlpha(90)
                  : Colors.white.withAlpha(15)),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                inv.hasFile
                    ? Icons.picture_as_pdf_rounded
                    : Icons.receipt_outlined,
                size: 17,
                color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Invoice ${inv.invoiceNumber}',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                [
                  if (inv.invoiceDate != null)
                    DateFormat('dd MMM yyyy').format(inv.invoiceDate!),
                  if ((inv.periodMonth ?? '').isNotEmpty) inv.periodMonth!,
                  if ((inv.poNumber ?? '').isNotEmpty) 'PO ${inv.poNumber}',
                ].join(' · '),
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 10, color: const Color(0xFF6B7490)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (flagged)
                Text('⚠ excl + GST ≠ total',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 9.5, color: const Color(0xFFFFB547))),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_inr.format(inv.totalAmount),
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
            Text('${_inr.format(inv.amountExclGst)} + GST',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9.5, color: const Color(0xFF6B7490))),
          ]),
          if (inv.hasFile)
            IconButton(
              onPressed: () => _openInvoice(inv),
              icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
              color: AppTheme.primary,
              tooltip: 'View original',
              visualDensity: VisualDensity.compact,
            ),
          if (_canEditInvoices)
            IconButton(
              onPressed: () => _editInvoicePo(inv),
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: AppTheme.primary,
              tooltip: 'Change PO',
              visualDensity: VisualDensity.compact,
            ),
          if (_canEditInvoices)
            IconButton(
              onPressed: () => _confirmDeleteInvoice(inv),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              color: Colors.redAccent.withAlpha(180),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
        ]),
      ),
    );
  }

  // ─── Security / Forgot Password ────────────────────────────────────────────

  Widget _buildSecuritySection() {
    return _card(
      borderColor: Colors.redAccent.withAlpha(60),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.security_rounded, 'Security', color: Colors.redAccent),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.redAccent.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withAlpha(40)),
          ),
          child: Row(children: [
            const Icon(Icons.lock_reset_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Forgot Password',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              Text('Send a reset link to ${_profile?.email ?? 'your email'}',
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF8A94B0), fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendForgotPassword,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withAlpha(80)),
                ),
                child: Text('Send Link',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.redAccent, fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // Device PIN. Present only so a PIN can be cleared — it is SET from
        // the login screen, which is the one place the password is in hand.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: Row(children: [
            Icon(_pinSet ? Icons.dialpad_rounded : Icons.dialpad_outlined,
                color: _pinSet ? const Color(0xFF00F3FF) : Colors.white38,
                size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sign-in PIN (this device)',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w700)),
              Text(
                  _pinSet
                      ? 'Set. Unlocks the saved login on this device only.'
                      : 'Not set. Needs your password once, then four digits.',
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF8A94B0), fontSize: 11)),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _pinSet ? _removePin : _setPinFromSettings,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: (_pinSet ? Colors.redAccent : const Color(0xFF00F3FF))
                      .withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (_pinSet
                              ? Colors.redAccent
                              : const Color(0xFF00F3FF))
                          .withAlpha(80)),
                ),
                child: Text(_pinSet ? 'Remove' : 'Set PIN',
                    style: GoogleFonts.spaceGrotesk(
                        color:
                            _pinSet ? Colors.redAccent : const Color(0xFF00F3FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // Sign out row
        GestureDetector(
          onTap: () async {
            await EngineerAuthService.instance.signOut();
            if (mounted) context.go('/login');
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(10)),
            ),
            child: Row(children: [
              Icon(Icons.logout_rounded,
                  color: Colors.white.withAlpha(150), size: 18),
              const SizedBox(width: 12),
              Text('Sign Out',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white.withAlpha(150),
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: Colors.white.withAlpha(60)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('TrackLog v${AppVersion.display} · NATRAX Proving Ground',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, color: const Color(0xFF3A4060))),
        ),
      ]),
    );
  }

  // ─── Shared helpers ────────────────────────────────────────────────────────

  // ─── Workshop bay ──────────────────────────────────────────────────────────

  /// The workshop accrual used to be governed by three constants in Dart, so
  /// closing off an invoiced month meant a code change and a redeploy. These
  /// dates now live in `app_settings` and are edited here.

  Future<void> _loadWorkshop() async {
    await AppSettingsService.instance.load(force: true);
    final canEdit = await EngineerAuthService.instance.canWrite();
    if (!mounted) return;
    setState(() {
      _wsSettledTo  = BillingBaseline.workshopSettledTo;
      _wsResumedOn  = BillingBaseline.workshopResumedOn;
      _wsReleasedOn = BillingBaseline.workshopReleasedOn;
      _canEditWorkshop = canEdit;
      _loadingWorkshop = false;
    });
  }

  Future<void> _setWorkshopDate(String key, DateTime? value) async {
    setState(() => _savingWorkshop = true);
    try {
      await AppSettingsService.instance.setDate(key, value);
      await _loadWorkshop();
      _snack('Saved. The report will use the new date.');
    } catch (_) {
      // Refresh either way, so the row never shows a value the database
      // rejected. A failed save that still looks saved is the worst outcome.
      await _loadWorkshop();
      _snack('Could not save that date. Check your connection.', error: true);
    } finally {
      if (mounted) setState(() => _savingWorkshop = false);
    }
  }

  Future<void> _pickWorkshopDate({
    required String key,
    required DateTime? current,
    required String label,
  }) async {
    if (!_canEditWorkshop || _savingWorkshop) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      // Future dates allowed: a bay can be given up on a date already agreed.
      lastDate: DateTime(DateTime.now().year + 2),
      helpText: label,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFB547), surface: Color(0xFF0A1025))),
        child: child!,
      ),
    );
    if (picked == null) return;
    await _setWorkshopDate(
        key, DateTime(picked.year, picked.month, picked.day));
  }

  Widget _buildWorkshopSection() {
    if (_loadingWorkshop) {
      return _card(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: Color(0xFFFFB547)),
            ),
          ),
        ),
      );
    }

    final today = DateTime.now();
    final openDays = BillingBaseline.openWorkshopDays(today);
    final openRent = BillingBaseline.openWorkshopRental(today);
    final countingFrom = _wsSettledTo?.add(const Duration(days: 1));

    return _card(
      borderColor: const Color(0xFFFFB547).withAlpha(70),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardTitle(Icons.home_repair_service_outlined, 'Workshop bay',
            color: const Color(0xFFFFB547)),
        const SizedBox(height: 12),
        Text(
          'The bay costs ${_inr.format(BillingBaseline.workshopDayRate)} a day '
          'whether or not anyone is testing. These dates tell the manager\u2019s '
          'report when to start and stop counting.',
          style: GoogleFonts.spaceGrotesk(
              fontSize: 12, height: 1.45, color: const Color(0xFF9AA3BE)),
        ),
        const SizedBox(height: 16),
        _workshopRow(
          label: 'Settled by invoice up to',
          hint: 'Move this forward the day NATRAX invoices another month.',
          value: _wsSettledTo,
          empty: 'Not set',
          onTap: () => _pickWorkshopDate(
              key: AppSettingsService.kWorkshopSettledTo,
              current: _wsSettledTo,
              label: 'Settled by invoice up to'),
        ),
        _workshopRow(
          label: 'Bay taken back on',
          hint: 'Nothing is counted before this date.',
          value: _wsResumedOn,
          empty: 'Not set',
          onTap: () => _pickWorkshopDate(
              key: AppSettingsService.kWorkshopResumedOn,
              current: _wsResumedOn,
              label: 'Bay taken back on'),
        ),
        _workshopRow(
          label: 'Bay given up on',
          hint: 'Leave empty while you still hold it.',
          value: _wsReleasedOn,
          empty: 'Still held',
          // Clearing matters as much as setting: a date entered by mistake
          // would silently stop the accrual with no way back from this screen.
          onClear: _wsReleasedOn == null
              ? null
              : () => _setWorkshopDate(
                  AppSettingsService.kWorkshopReleasedOn, null),
          onTap: () => _pickWorkshopDate(
              key: AppSettingsService.kWorkshopReleasedOn,
              current: _wsReleasedOn,
              label: 'Bay given up on'),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: (openDays > 0 ? const Color(0xFFFFB547) : AppTheme.success)
                .withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: (openDays > 0
                        ? const Color(0xFFFFB547)
                        : AppTheme.success)
                    .withAlpha(70)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              openDays == 0
                  ? 'Nothing waiting to be invoiced.'
                  : '$openDays day${openDays == 1 ? '' : 's'} not yet invoiced '
                      '\u2014 ${_inr.format(openRent)}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: openDays > 0
                      ? const Color(0xFFFFB547)
                      : AppTheme.success),
            ),
            const SizedBox(height: 3),
            Text(
              openDays == 0
                  ? 'Everything up to the settled date is on an invoice.'
                  : 'Counting from ${countingFrom == null ? '?' : _dmy.format(countingFrom)}'
                      ', and growing by ${_inr.format(BillingBaseline.workshopDayRate)} a day.',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 11.5, color: const Color(0xFF9AA3BE)),
            ),
          ]),
        ),
        if (!_canEditWorkshop) ...[
          const SizedBox(height: 10),
          Text(
            'You can see these dates but not change them. Ask an owner to '
            'update them.',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11.5, color: const Color(0xFF6B7490)),
          ),
        ],
      ]),
    );
  }

  Widget _workshopRow({
    required String label,
    required String hint,
    required DateTime? value,
    required String empty,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final locked = !_canEditWorkshop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(26)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFdfe2f0))),
                  const SizedBox(height: 2),
                  Text(hint,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, color: const Color(0xFF6B7490))),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value == null ? empty : _dmy.format(value),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: value == null
                      ? const Color(0xFF6B7490)
                      : const Color(0xFFFFB547)),
            ),
            if (onClear != null && !locked) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: _savingWorkshop ? null : onClear,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: const Color(0xFF9AA3BE),
                tooltip: 'Clear \u2014 the bay is still held',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ] else if (!locked) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: Color(0xFF6B7490)),
            ],
          ]),
        ),
      ),
    );
  }
  Widget _card({required Widget child, Color? borderColor}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: borderColor ?? const Color(0xFF849495).withAlpha(80)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _cardTitle(IconData icon, String title, {Color? color}) {
    final c = color ?? AppTheme.primary;
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: c.withAlpha(22),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.withAlpha(60)),
        ),
        child: Icon(icon, color: c, size: 15),
      ),
      const SizedBox(width: 10),
      Text(title, style: GoogleFonts.spaceGrotesk(
          fontSize: 14, fontWeight: FontWeight.w800,
          color: const Color(0xFFdfe2f0))),
    ]);
  }
}

import 'dart:ui';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/app_export.dart';
import '../../services/engineer_auth_service.dart';
import '../../services/project_catalog.dart';
import '../../services/project_manager.dart';
import '../../services/resource_service.dart';

/// Testing resources — who and what is available, what they are committed to,
/// and what they actually used.
class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  bool _loading = true;
  String? _error;
  bool _readOnly = true;

  List<ResourceUtilisation> _rows = [];
  List<ResourceAllocation> _allocations = [];
  List<ResourceAvailability> _availability = [];

  /// Months back from today that the figures cover.
  int _windowMonths = 3;

  static const _teal = AppTheme.primary;
  static const _amber = Color(0xFFFFB547);
  static const _green = Color(0xFF4CAF50);
  static const _red = Color(0xFFFF6B6B);

  DateTime get _from {
    final now = DateTime.now();
    return DateTime(now.year, now.month - (_windowMonths - 1), 1);
  }

  DateTime get _to => DateTime.now();

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
      final project = ProjectManager.instance.activeProject;
      final rows = await ResourceService.instance
          .utilisation(from: _from, to: _to, projectName: project);
      final allocations =
          await ResourceService.instance.listAllocations(projectName: project);
      final availability = await ResourceService.instance.listAvailability();

      if (!mounted) return;
      setState(() {
        _readOnly = profile?.isReadOnly ?? true;
        _rows = rows;
        _allocations = allocations;
        _availability = availability;
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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      floatingActionButton: _readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _addResourceSheet,
              backgroundColor: _teal,
              icon: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 18),
              label: Text('Add resource',
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
                          _windowSelector(),
                          const SizedBox(height: 16),
                          _summaryCard(),
                          const SizedBox(height: 16),
                          if (_rows.isEmpty)
                            _emptyState()
                          else
                            ..._rows.map(_resourceCard),
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
          Text('Could not load resources',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error ?? '',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490), fontSize: 11)),
          ),
          TextButton(
              onPressed: _load,
              child: Text('Retry',
                  style: GoogleFonts.spaceGrotesk(color: _teal))),
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
          child: const Icon(Icons.groups_2_outlined, color: _teal, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Testing Resources',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(
                'Availability, allocation and utilisation — '
                '${ProjectManager.instance.activeProject}',
                style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF6B7490),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
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
            child: const Icon(Icons.refresh, color: Color(0xFF6B7490), size: 18),
          ),
        ),
      ]);

  Widget _windowSelector() {
    Widget chip(int months, String label) {
      final sel = _windowMonths == months;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            setState(() => _windowMonths = months);
            _load();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: sel ? _teal.withAlpha(28) : Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: sel ? _teal.withAlpha(150) : Colors.white.withAlpha(18),
                  width: sel ? 1.4 : 1),
            ),
            child: Center(
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: sel ? _teal : const Color(0xFF8A94B0),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      chip(1, 'This month'),
      const SizedBox(width: 8),
      chip(3, 'Last 3 months'),
      const SizedBox(width: 8),
      chip(6, 'Last 6 months'),
    ]);
  }

  Widget _summaryCard() {
    final available = _rows.fold(0.0, (s, r) => s + r.availableHours);
    final allocated = _rows.fold(0.0, (s, r) => s + r.allocatedHours);
    final utilised = _rows.fold(0.0, (s, r) => s + r.utilisedHours);
    final overAllocated = _rows.where((r) => r.isOverAllocated).length;
    final unallocated = _rows.where((r) => r.allocatedHours <= 0).length;

    return _glass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${DateFormat('d MMM').format(_from)} – '
            '${DateFormat('d MMM yyyy').format(_to)}',
            style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFF6B7490),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 12),
        Row(children: [
          _metric('Available', '${available.toStringAsFixed(0)}h', _teal),
          _metric('Allocated', '${allocated.toStringAsFixed(0)}h', _amber),
          _metric('Utilised', '${utilised.toStringAsFixed(0)}h', _green),
        ]),
        if (overAllocated > 0 || unallocated > 0) ...[
          const SizedBox(height: 12),
          if (overAllocated > 0)
            _flag('$overAllocated over-allocated — commitments exceed '
                'available hours', _red),
          if (unallocated > 0)
            _flag('$unallocated with no allocation in this window', _amber),
        ],
      ]),
    );
  }

  Widget _metric(String label, String value, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  color: c, fontSize: 19, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _flag(String text, Color c) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(Icons.info_outline, size: 13, color: c),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: GoogleFonts.spaceGrotesk(
                    color: c, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _emptyState() => _glass(
        child: Column(children: [
          Icon(Icons.groups_2_outlined,
              size: 30, color: Colors.white.withAlpha(50)),
          const SizedBox(height: 9),
          Text('No active resources',
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              _readOnly
                  ? 'Managers have read-only access to resource records.'
                  : 'Add engineers, technicians, drivers, vehicles or equipment '
                      'to start tracking availability and allocation.',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF6B7490), fontSize: 11, height: 1.5)),
        ]),
      );

  Widget _resourceCard(ResourceUtilisation r) {
    final allocPct = r.allocationRate.clamp(0.0, 1.5);
    final utilPct = r.utilisationRate.clamp(0.0, 1.5);
    final myAllocations =
        _allocations.where((a) => a.resourceId == r.resource.id).toList();
    final myLeave = _availability
        .where((a) => a.resourceId == r.resource.id && a.reducesAvailability)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _glass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _typeColor(r.resource.type).withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(r.resource.type),
                  color: _typeColor(r.resource.type), size: 17),
            ),
            const SizedBox(width: 11),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.resource.name,
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    [
                      r.resource.roleTitle ?? r.resource.type,
                      r.resource.supplier,
                      if (!r.utilisationFromSessions) 'manual hours',
                    ].join(' · '),
                    style: GoogleFonts.spaceGrotesk(
                        color: const Color(0xFF6B7490), fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (r.isOverAllocated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _red.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _red.withAlpha(80)),
                ),
                child: Text('OVER',
                    style: GoogleFonts.spaceGrotesk(
                        color: _red, fontSize: 8.5, fontWeight: FontWeight.w800)),
              ),
            if (!_readOnly)
              GestureDetector(
                onTap: () => _removeResource(r.resource),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.more_horiz_rounded,
                      size: 17, color: Colors.white.withAlpha(90)),
                ),
              ),
          ]),
          const SizedBox(height: 12),

          _bar('Allocated', r.allocatedHours, r.availableHours, allocPct,
              r.isOverAllocated ? _red : _amber),
          const SizedBox(height: 7),
          _bar('Utilised', r.utilisedHours, r.allocatedHours, utilPct, _green),

          const SizedBox(height: 9),
          Row(children: [
            Expanded(
              child: Text(
                  '${r.availableHours.toStringAsFixed(0)}h available'
                  '${r.unavailableHours > 0 ? ' · ${r.unavailableHours.toStringAsFixed(0)}h out' : ''}'
                  '${r.unallocatedHours > 0 ? ' · ${r.unallocatedHours.toStringAsFixed(0)}h spare' : ''}',
                  style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF6B7490), fontSize: 10)),
            ),
          ]),

          if (myAllocations.isNotEmpty || myLeave.isNotEmpty) ...[
            const SizedBox(height: 9),
            const Divider(color: Color(0xFF2A3450), height: 1),
            const SizedBox(height: 8),
            ...myAllocations.map((a) => _chipLine(
                  Icons.assignment_outlined,
                  '${a.projectName} · '
                      '${DateFormat('d MMM').format(a.startDate)}–'
                      '${DateFormat('d MMM').format(a.endDate)} · '
                      '${a.allocatedHours.toStringAsFixed(0)}h',
                  _amber,
                  onDelete: _readOnly
                      ? null
                      : () async {
                          await ResourceService.instance.deleteAllocation(a.id);
                          _snack('Allocation removed');
                          _load();
                        },
                )),
            ...myLeave.map((a) => _chipLine(
                  Icons.event_busy_outlined,
                  '${a.type.replaceAll('_', ' ')} · '
                      '${DateFormat('d MMM').format(a.startDate)}–'
                      '${DateFormat('d MMM').format(a.endDate)}',
                  const Color(0xFF9C88FF),
                  onDelete: _readOnly
                      ? null
                      : () async {
                          await ResourceService.instance
                              .deleteAvailability(a.id);
                          _snack('Availability window removed');
                          _load();
                        },
                )),
          ],

          if (!_readOnly) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _action('Allocate', Icons.assignment_add, _amber,
                    () => _allocateSheet(r.resource)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action('Mark away', Icons.event_busy_outlined,
                    const Color(0xFF9C88FF), () => _availabilitySheet(r.resource)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _bar(String label, double value, double of, double pct, Color c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
        ),
        Text(
            '${value.toStringAsFixed(value < 10 ? 1 : 0)}h'
            '${of > 0 ? ' / ${of.toStringAsFixed(0)}h' : ''}',
            style: GoogleFonts.spaceGrotesk(
                color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: pct.clamp(0.0, 1.0),
          backgroundColor: const Color(0xFF2A3450),
          valueColor: AlwaysStoppedAnimation<Color>(c),
          minHeight: 6,
        ),
      ),
    ]);
  }

  Widget _chipLine(IconData icon, String text, Color c,
      {VoidCallback? onDelete}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Icon(icon, size: 12, color: c.withAlpha(190)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: GoogleFonts.spaceGrotesk(
                  color: const Color(0xFF8A94B0), fontSize: 10.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        if (onDelete != null)
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.close_rounded,
                size: 13, color: Colors.redAccent.withAlpha(160)),
          ),
      ]),
    );
  }

  Widget _action(String label, IconData icon, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.withAlpha(20),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.withAlpha(75)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  color: c, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _glass({required Widget child}) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1025).withAlpha(200),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF849495).withAlpha(120)),
            ),
            child: child,
          ),
        ),
      );

  IconData _typeIcon(String t) => switch (t) {
        'technician' => Icons.handyman_outlined,
        'driver' => Icons.airline_seat_recline_normal_outlined,
        'vehicle' => Icons.directions_car_filled_outlined,
        'equipment' => Icons.precision_manufacturing_outlined,
        _ => Icons.engineering_outlined,
      };

  Color _typeColor(String t) => switch (t) {
        'technician' => _amber,
        'driver' => const Color(0xFF4FC3F7),
        'vehicle' => const Color(0xFF9C88FF),
        'equipment' => const Color(0xFFFF8A65),
        _ => _teal,
      };

  // ─── Sheets ────────────────────────────────────────────────────────────────

  Future<void> _addResourceSheet() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '8');
    var type = 'engineer';
    var supplier = 'Goodyear';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _teal.withAlpha(60)),
          ),
          title: Text('Add resource',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _field(nameCtrl, 'Name *',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null),
                  _dropdown<String>(
                    label: 'Type',
                    value: type,
                    items: const [
                      'engineer',
                      'technician',
                      'driver',
                      'vehicle',
                      'equipment'
                    ],
                    labelOf: (v) => v[0].toUpperCase() + v.substring(1),
                    onChanged: (v) => setLocal(() => type = v ?? type),
                  ),
                  _field(roleCtrl, 'Role / designation'),
                  _field(codeCtrl, 'Employee code / asset tag'),
                  _dropdown<String>(
                    label: 'Supplier',
                    value: supplier,
                    items: const ['Goodyear', 'NATRAX', 'Contract'],
                    labelOf: (v) => v,
                    onChanged: (v) => setLocal(() => supplier = v ?? supplier),
                  ),
                  _field(capacityCtrl, 'Daily capacity (hours)', number: true),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white70))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _teal),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                try {
                  await ResourceService.instance.upsertResource(
                    TestResource(
                      id: '',
                      name: nameCtrl.text.trim(),
                      type: type,
                      roleTitle: roleCtrl.text.trim().isEmpty
                          ? null
                          : roleCtrl.text.trim(),
                      employeeCode: codeCtrl.text.trim().isEmpty
                          ? null
                          : codeCtrl.text.trim(),
                      supplier: supplier,
                      dailyCapacityHours:
                          double.tryParse(capacityCtrl.text.trim()) ?? 8,
                    ),
                    isNew: true,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx, false);
                  _snack('Could not add — $e', error: true);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      _snack('Resource added');
      _load();
    }
  }

  /// Take a resource off the list.
  ///
  /// Deactivating is offered first and is the safer choice: removing outright
  /// also deletes that resource's allocations and availability history through
  /// the cascade, which is not recoverable.
  Future<void> _removeResource(TestResource r) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1025),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withAlpha(60)),
        ),
        title: Text('Remove ${r.name}?',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        content: Text(
          'Deactivate keeps the record and its history but drops it from the '
          'Resources list and the management report.\n\n'
          'Delete removes the resource along with every allocation and '
          'availability window recorded against it. That cannot be undone.',
          style: GoogleFonts.spaceGrotesk(
              color: const Color(0xFF8A94B0), fontSize: 12, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text('Delete',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal),
            onPressed: () => Navigator.pop(ctx, 'deactivate'),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (choice == null) return;
    try {
      if (choice == 'deactivate') {
        await ResourceService.instance.upsertResource(
          TestResource(
            id: r.id,
            name: r.name,
            type: r.type,
            employeeCode: r.employeeCode,
            email: r.email,
            engineerProfileId: r.engineerProfileId,
            roleTitle: r.roleTitle,
            department: r.department,
            supplier: r.supplier,
            dailyCapacityHours: r.dailyCapacityHours,
            status: 'inactive',
            notes: r.notes,
          ),
        );
        _snack('${r.name} deactivated');
      } else {
        await ResourceService.instance.deleteResource(r.id);
        _snack('${r.name} removed');
      }
      _load();
    } catch (e) {
      _snack('Could not update — $e', error: true);
    }
  }

  Future<void> _allocateSheet(TestResource r) async {
    final hoursCtrl = TextEditingController();
    final actualCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 7));
    var project = ProjectManager.instance.activeProject;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _amber.withAlpha(70)),
          ),
          title: Text('Allocate ${r.name}',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _dropdown<String>(
                  label: 'Project',
                  value: project,
                  items: ProjectCatalog.displayNames,
                  labelOf: (v) => v,
                  onChanged: (v) => setLocal(() => project = v ?? project),
                ),
                _dateField(ctx, 'From', start,
                    (d) => setLocal(() => start = d)),
                _dateField(ctx, 'To', end, (d) => setLocal(() => end = d)),
                _field(hoursCtrl, 'Allocated hours *', number: true),
                _field(roleCtrl, 'Role on project'),
                if (!r.tracksSessions)
                  _field(actualCtrl, 'Actual hours used', number: true),
                if (!r.tracksSessions)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'This resource has no engineer profile, so utilisation '
                        'cannot be read from sessions — record actual hours here.',
                        style: GoogleFonts.spaceGrotesk(
                            color: const Color(0xFF6B7490),
                            fontSize: 10,
                            height: 1.45)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white70))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _amber),
              onPressed: () async {
                final hours = double.tryParse(hoursCtrl.text.trim()) ?? 0;
                if (hours <= 0) {
                  _snack('Enter the allocated hours', error: true);
                  return;
                }
                if (end.isBefore(start)) {
                  _snack('End date is before the start date', error: true);
                  return;
                }
                try {
                  await ResourceService.instance.addAllocation(
                    resourceId: r.id,
                    projectName: project,
                    start: start,
                    end: end,
                    allocatedHours: hours,
                    roleOnProject: roleCtrl.text.trim().isEmpty
                        ? null
                        : roleCtrl.text.trim(),
                    actualHours: double.tryParse(actualCtrl.text.trim()),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx, false);
                  _snack('Could not allocate — $e', error: true);
                }
              },
              child: const Text('Allocate',
                  style: TextStyle(color: Color(0xFF1A1200))),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      _snack('${r.name} allocated');
      _load();
    }
  }

  Future<void> _availabilitySheet(TestResource r) async {
    var start = DateTime.now();
    var end = DateTime.now().add(const Duration(days: 1));
    var type = 'leave';
    final notesCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF0A1025),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: const Color(0xFF9C88FF).withAlpha(70)),
          ),
          title: Text('${r.name} unavailable',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dropdown<String>(
                label: 'Reason',
                value: type,
                items: const [
                  'leave',
                  'training',
                  'other_project',
                  'unavailable'
                ],
                labelOf: (v) =>
                    v.replaceAll('_', ' ')[0].toUpperCase() +
                    v.replaceAll('_', ' ').substring(1),
                onChanged: (v) => setLocal(() => type = v ?? type),
              ),
              _dateField(ctx, 'From', start, (d) => setLocal(() => start = d)),
              _dateField(ctx, 'To', end, (d) => setLocal(() => end = d)),
              _field(notesCtrl, 'Notes'),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white70))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9C88FF)),
              onPressed: () async {
                if (end.isBefore(start)) {
                  _snack('End date is before the start date', error: true);
                  return;
                }
                try {
                  await ResourceService.instance.addAvailability(
                    resourceId: r.id,
                    start: start,
                    end: end,
                    type: type,
                    notes: notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx, false);
                  _snack('Could not save — $e', error: true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      _snack('Availability updated');
      _load();
    }
  }

  // ─── Small form helpers ────────────────────────────────────────────────────

  Widget _field(TextEditingController c, String label,
      {bool number = false, String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      style: const TextStyle(color: Colors.white),
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : null,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24)),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        dropdownColor: const Color(0xFF0A1025),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24)),
        ),
        items: items
            .map((i) => DropdownMenuItem(value: i, child: Text(labelOf(i))))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateField(BuildContext ctx, String label, DateTime value,
      void Function(DateTime) onPick) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: value,
            firstDate: DateTime(2025),
            lastDate: DateTime(2030),
          );
          if (d != null) onPick(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
          ),
          child: Row(children: [
            Text(DateFormat('dd MMM yyyy').format(value),
                style: const TextStyle(color: Colors.white)),
            const Spacer(),
            const Icon(Icons.calendar_today, size: 13, color: Colors.white38),
          ]),
        ),
      ),
    );
  }
}

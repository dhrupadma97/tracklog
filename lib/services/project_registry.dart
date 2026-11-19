import 'package:flutter/foundation.dart';

import 'project_catalog.dart';
import 'project_status_service.dart';
import 'supabase_service.dart';

/// A programme added from the app, with what its card shows.
class ProgrammeProfile {
  final String key;
  final String displayName;
  final String vehicle;

  /// 'bev' or 'ice'.
  final String powertrain;
  final String vehicleType;
  final String summary;
  final List<String> specs;
  final List<String> details;
  final String? imageUrl;
  final String? sourceUrl;

  const ProgrammeProfile({
    required this.key,
    required this.displayName,
    required this.vehicle,
    this.powertrain = 'ice',
    this.vehicleType = '',
    this.summary = '',
    this.specs = const [],
    this.details = const [],
    this.imageUrl,
    this.sourceUrl,
  });

  static String keyFor(String displayName) => displayName.trim().toLowerCase();

  Programme toProgramme(ProgrammeStatus status) => Programme(
        key: key,
        displayName: displayName,
        vehicle: vehicle,
        powertrain: powertrain == 'bev' ? Powertrain.bev : Powertrain.ice,
        status: status,
      );

  factory ProgrammeProfile.fromJson(Map<String, dynamic> j) => ProgrammeProfile(
        key: (j['key'] as String?) ?? '',
        displayName: (j['display_name'] as String?) ?? '',
        vehicle: (j['vehicle'] as String?) ?? '',
        powertrain: (j['powertrain'] as String?) ?? 'ice',
        vehicleType: (j['vehicle_type'] as String?) ?? '',
        summary: (j['summary'] as String?) ?? '',
        specs: [for (final s in (j['specs'] as List?) ?? const []) '$s'],
        details: [for (final s in (j['details'] as List?) ?? const []) '$s'],
        imageUrl: j['image_url'] as String?,
        sourceUrl: j['source_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'display_name': displayName.trim(),
        'vehicle': vehicle.trim(),
        'powertrain': powertrain,
        'vehicle_type': vehicleType.trim().isEmpty ? null : vehicleType.trim(),
        'summary': summary.trim().isEmpty ? null : summary.trim(),
        'specs': specs.where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList(),
        'details': details.where((s) => s.trim().isNotEmpty).map((s) => s.trim()).toList(),
        'image_url': (imageUrl ?? '').trim().isEmpty ? null : imageUrl!.trim(),
        'source_url': (sourceUrl ?? '').trim().isEmpty ? null : sourceUrl!.trim(),
      };
}

/// Programmes added from the Projects screen (public.projects), merged into
/// [ProjectCatalog] so every picker in the app offers them.
class ProjectRegistry extends ChangeNotifier {
  ProjectRegistry._();
  static final ProjectRegistry instance = ProjectRegistry._();

  final Map<String, ProgrammeProfile> profiles = {};

  /// The table has not been created yet — 20261119090000_projects.sql.
  bool tableMissing = false;

  dynamic get _db => SupabaseService.instance.client;

  Future<void> load() async {
    try {
      final rows = await _db.from('projects').select().order('created_at');
      profiles
        ..clear()
        ..addEntries([
          for (final r in (rows as List).cast<Map<String, dynamic>>())
            MapEntry((r['key'] as String?) ?? '', ProgrammeProfile.fromJson(r)),
        ].where((e) => e.key.isNotEmpty));
      tableMissing = false;
    } catch (e) {
      final s = e.toString();
      if (s.contains('PGRST205') || (s.contains('projects') && s.contains('does not exist'))) {
        tableMissing = true;
      }
      // Anything else: keep what was loaded before; the built-ins still work.
    }
    ProjectCatalog.setAdded([
      for (final p in profiles.values)
        p.toProgramme(ProjectStatusService.instance.statusFor(p.key)),
    ]);
    notifyListeners();
  }

  /// Adds a programme, sets its status, and reloads so it appears at once.
  Future<void> add(ProgrammeProfile p, ProgrammeStatus status) async {
    if (ProjectCatalog.byKey(p.key) != null) {
      throw StateError('A programme called "${p.displayName}" already exists.');
    }
    final user = _db.auth.currentUser;
    await _db.from('projects').insert({...p.toJson(), 'created_by': user?.email});
    await ProjectStatusService.instance.set(rawKey: p.key, status: status);
    await load();
  }

  /// Saves edits to an added programme. Built-in ones are not editable here.
  Future<void> update(ProgrammeProfile p) async {
    final json = p.toJson()..remove('key');
    await _db
        .from('projects')
        .update({...json, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('key', p.key);
    await load();
  }
}

import 'package:flutter/foundation.dart';

import 'project_catalog.dart';
import 'supabase_service.dart';

/// What has been recorded about one programme's lifecycle.
class ProjectStatusRecord {
  final String projectKey;
  final ProgrammeStatus status;
  final String notes;
  final DateTime? completedOn;
  final DateTime? updatedAt;
  final String? updatedBy;

  const ProjectStatusRecord({
    required this.projectKey,
    required this.status,
    this.notes = '',
    this.completedOn,
    this.updatedAt,
    this.updatedBy,
  });
}

/// Programme lifecycle, read from the database rather than compiled in.
///
/// Whether a PoC is running, upcoming or finished was a `const` in two
/// places — `ProgrammeStatus` here in the services layer and `ProjectStatus`
/// on the selection screen. Marking a demo complete meant editing both,
/// building the web bundle and deploying, and the two could drift apart with
/// nothing on screen saying which was being read.
///
/// The compiled values stay as the fallback. An unreadable table, or one that
/// has not been created yet, leaves the app exactly as it was rather than
/// showing every programme as unknown — the status is cosmetic to billing and
/// must never take a screen down.
class ProjectStatusService extends ChangeNotifier {
  ProjectStatusService._();
  static ProjectStatusService? _instance;
  static ProjectStatusService get instance =>
      _instance ??= ProjectStatusService._();

  final Map<String, ProjectStatusRecord> _records = {};
  bool _loaded = false;

  /// True once a load has returned, whether or not it found anything.
  bool get isLoaded => _loaded;

  /// Reads the overrides. Safe to call repeatedly; pass [force] to refetch.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final rows = await SupabaseService.instance.client
          .from('project_status')
          .select('project_key, status, notes, completed_on, updated_at, '
              'updated_by');
      _records.clear();
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final key = ProjectCatalog.normaliseKey(r['project_key'] as String?);
        _records[key] = ProjectStatusRecord(
          projectKey: key,
          status: _parse(r['status'] as String?) ?? ProgrammeStatus.active,
          notes: (r['notes'] as String? ?? '').trim(),
          completedOn: DateTime.tryParse(r['completed_on']?.toString() ?? ''),
          updatedAt: DateTime.tryParse(r['updated_at']?.toString() ?? ''),
          updatedBy: r['updated_by'] as String?,
        );
      }
    } catch (_) {
      // Table absent or unreadable. The compiled status still answers every
      // question below, so there is nothing to report and nothing to break.
    }
    _loaded = true;
    notifyListeners();
  }

  static ProgrammeStatus? _parse(String? raw) => switch ((raw ?? '').trim()) {
        'active' => ProgrammeStatus.active,
        'upcoming' => ProgrammeStatus.upcoming,
        'completed' => ProgrammeStatus.completed,
        _ => null,
      };

  static String wireName(ProgrammeStatus s) => switch (s) {
        ProgrammeStatus.active => 'active',
        ProgrammeStatus.upcoming => 'upcoming',
        ProgrammeStatus.completed => 'completed',
      };

  /// The status to show for [rawKey] — the override if there is one, the
  /// compiled value otherwise.
  ProgrammeStatus statusFor(String? rawKey) {
    final key = ProjectCatalog.normaliseKey(rawKey);
    final rec = _records[key];
    if (rec != null) return rec.status;
    return ProjectCatalog.byKey(key)?.status ?? ProgrammeStatus.upcoming;
  }

  ProjectStatusRecord? recordFor(String? rawKey) =>
      _records[ProjectCatalog.normaliseKey(rawKey)];

  String notesFor(String? rawKey) => recordFor(rawKey)?.notes ?? '';

  DateTime? completedOnFor(String? rawKey) => recordFor(rawKey)?.completedOn;

  /// Records a programme's status, and whatever was written about it.
  ///
  /// Writes then re-reads rather than patching the map in place: the row
  /// carries `updated_at` from the database clock, and a local guess at it
  /// would be wrong by however long the round trip took.
  Future<void> set({
    required String rawKey,
    required ProgrammeStatus status,
    String notes = '',
    DateTime? completedOn,
  }) async {
    final key = ProjectCatalog.normaliseKey(rawKey);
    final user = SupabaseService.instance.client.auth.currentUser;
    await SupabaseService.instance.client.from('project_status').upsert({
      'project_key': key,
      'status': wireName(status),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      // Cleared when a programme reopens, so a reopened PoC does not keep
      // claiming the date it closed.
      'completed_on': status == ProgrammeStatus.completed
          ? (completedOn ?? DateTime.now()).toIso8601String().split('T').first
          : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by': user?.email ?? user?.id,
    }, onConflict: 'project_key');
    await load(force: true);
  }
}

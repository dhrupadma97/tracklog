/// TrackLog — Instrumentation config repository (Phase 2)
/// Persists per-vehicle instrumentation schematics to Supabase
/// (`instrumentation_configs`, one JSONB row per config) with a
/// draft → locked lifecycle and versioning.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'instrumentation_data.dart';

/// Lock state of one schematic section (calibration / validation).
class SectionLockState {
  bool locked;
  String? by;
  DateTime? at;

  SectionLockState({this.locked = false, this.by, this.at});

  factory SectionLockState.fromJson(Map<String, dynamic> j) => SectionLockState(
        locked: j['locked'] as bool? ?? false,
        by: j['by'] as String?,
        at: j['at'] == null ? null : DateTime.tryParse(j['at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'locked': locked,
        'by': by,
        'at': at?.toIso8601String(),
      };
}

/// One vehicle instrumentation schematic (a row in `instrumentation_configs`).
class InstrConfig {
  final String id;
  String name;
  String manufacturer;
  List<VehicleBus> buses;
  List<OBDPin> obdPinout;
  List<SchematicNode> nodes;
  List<SchematicConnection> connections;
  String status; // 'draft' | 'locked'
  int version;
  String? lockedBy;
  DateTime? lockedAt;

  /// Per-section locks, keyed by [SchematicSection.name]
  /// ('calibration' | 'validation'). Base wiring is never section-locked.
  Map<String, SectionLockState> sectionLocks;

  InstrConfig({
    required this.id,
    required this.name,
    this.manufacturer = '',
    List<VehicleBus>? buses,
    List<OBDPin>? obdPinout,
    List<SchematicNode>? nodes,
    List<SchematicConnection>? connections,
    this.status = 'draft',
    this.version = 1,
    this.lockedBy,
    this.lockedAt,
    Map<String, SectionLockState>? sectionLocks,
  })  : buses = buses ?? [],
        obdPinout = obdPinout ?? [],
        nodes = nodes ?? [],
        connections = connections ?? [],
        sectionLocks = sectionLocks ?? {};

  bool get isLocked => status == 'locked';

  SectionLockState sectionLock(SchematicSection s) =>
      sectionLocks[s.name] ?? SectionLockState();

  bool isSectionLocked(SchematicSection s) =>
      s != SchematicSection.base && (sectionLocks[s.name]?.locked ?? false);

  bool get bothSectionsLocked =>
      isSectionLocked(SchematicSection.calibration) &&
      isSectionLocked(SchematicSection.validation);

  String get displayName =>
      isLocked ? '$name · v$version 🔒' : '$name · v$version (draft)';

  /// View of this config as a [VehicleProfile] (for painter/pinout/validation).
  VehicleProfile toProfile() => VehicleProfile(
        id: id,
        name: name,
        manufacturer: manufacturer,
        buses: buses,
        obdPinout: obdPinout,
        schematicNodes: nodes,
        schematicConnections: connections,
      );

  factory InstrConfig.fromRow(Map<String, dynamic> row) => InstrConfig(
        id: row['id'] as String,
        name: row['name'] as String? ?? 'Vehicle',
        manufacturer: row['manufacturer'] as String? ?? '',
        buses: ((row['buses'] as List?) ?? [])
            .map((e) => VehicleBus.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        obdPinout: ((row['obd_pinout'] as List?) ?? [])
            .map((e) => OBDPin.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        nodes: ((row['nodes'] as List?) ?? [])
            .map((e) => SchematicNode.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        connections: ((row['connections'] as List?) ?? [])
            .map((e) =>
                SchematicConnection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        status: row['status'] as String? ?? 'draft',
        version: (row['version'] as num?)?.toInt() ?? 1,
        lockedBy: row['locked_by'] as String?,
        lockedAt: row['locked_at'] == null
            ? null
            : DateTime.tryParse(row['locked_at'] as String),
        sectionLocks: ((row['section_locks'] as Map?) ?? {}).map(
          (k, v) => MapEntry(
            k as String,
            SectionLockState.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
      );

  Map<String, dynamic> toContentRow() => {
        'name': name,
        'manufacturer': manufacturer,
        'buses': buses.map((b) => b.toJson()).toList(),
        'obd_pinout': obdPinout.map((p) => p.toJson()).toList(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'connections': connections.map((c) => c.toJson()).toList(),
        'section_locks':
            sectionLocks.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class SchematicRepository {
  SupabaseClient get _client => Supabase.instance.client;
  static const _table = 'instrumentation_configs';

  /// All configs, newest first.
  Future<List<InstrConfig>> fetchConfigs() async {
    final rows = await _client
        .from(_table)
        .select('*')
        .order('name')
        .order('version', ascending: false);
    return (rows as List)
        .map((r) => InstrConfig.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Save the editable content of a draft config.
  Future<void> saveConfig(InstrConfig config) async {
    await _client.from(_table).update({
      ...config.toContentRow(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', config.id);
  }

  /// Create a new draft config seeded from a [VehicleProfile] (e.g. the
  /// built-in TATA BETA template). Returns the created config. Pass [name] to
  /// name it in the same insert — avoids clones stuck with the template name.
  Future<InstrConfig> createFromProfile(VehicleProfile profile,
      {String? name}) async {
    final row = await _client
        .from(_table)
        .insert({
          'name': name ?? profile.name,
          'manufacturer': profile.manufacturer,
          'buses': profile.buses.map((b) => b.toJson()).toList(),
          'obd_pinout': profile.obdPinout.map((p) => p.toJson()).toList(),
          'nodes': profile.schematicNodes.map((n) => n.toJson()).toList(),
          'connections':
              profile.schematicConnections.map((c) => c.toJson()).toList(),
          'status': 'draft',
          'version': 1,
        })
        .select()
        .single();
    return InstrConfig.fromRow(Map<String, dynamic>.from(row));
  }

  /// Lock one section (Calibration / Validation) of a config. When both
  /// sections are locked the whole config flips to status 'locked' (frozen,
  /// and protected from deletion by RLS).
  Future<void> lockSection(InstrConfig config, SchematicSection section,
      {required String lockedBy}) async {
    config.sectionLocks[section.name] = SectionLockState(
      locked: true,
      by: lockedBy,
      at: DateTime.now().toUtc(),
    );
    final fullyLocked = config.bothSectionsLocked;
    await _client.from(_table).update({
      ...config.toContentRow(), // persist latest edits along with the lock
      if (fullyLocked) 'status': 'locked',
      if (fullyLocked) 'locked_by': lockedBy,
      if (fullyLocked)
        'locked_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', config.id);
  }

  /// Unlock a section again. Always drops the whole-config status back to
  /// draft (a config is only fully locked while BOTH sections are locked).
  Future<void> unlockSection(
      InstrConfig config, SchematicSection section) async {
    config.sectionLocks[section.name] = SectionLockState(locked: false);
    await _client.from(_table).update({
      ...config.toContentRow(),
      'status': 'draft',
      'locked_by': null,
      'locked_at': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', config.id);
  }

  /// Start a new editable version from a locked config. Returns the new draft
  /// (section locks cleared).
  Future<InstrConfig> newVersionFrom(InstrConfig locked) async {
    final row = await _client
        .from(_table)
        .insert({
          ...locked.toContentRow(),
          'section_locks': <String, dynamic>{},
          'status': 'draft',
          'version': locked.version + 1,
        })
        .select()
        .single();
    return InstrConfig.fromRow(Map<String, dynamic>.from(row));
  }

  /// Delete a draft (locked versions are protected by RLS).
  Future<void> deleteDraft(String id) async {
    await _client.from(_table).delete().eq('id', id).eq('status', 'draft');
  }

  // ── DBC files (Phase 3) ───────────────────────────────────────────────────
  static const _dbcTable = 'dbc_files';

  /// Attach (or replace) a DBC on one bus of a config.
  Future<void> upsertDbc({
    required String configId,
    required String busId,
    required String fileName,
    required String content,
    required int messageCount,
    required int signalCount,
    String? uploadedBy,
  }) async {
    await _client.from(_dbcTable).upsert({
      'config_id': configId,
      'bus_id': busId,
      'file_name': fileName,
      'content': content,
      'message_count': messageCount,
      'signal_count': signalCount,
      'uploaded_by': uploadedBy,
      'uploaded_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'config_id,bus_id');
  }

  /// Fetch a bus's DBC content (lazy — only when viewing signals).
  Future<String?> getDbcContent(String configId, String busId) async {
    final rows = await _client
        .from(_dbcTable)
        .select('content')
        .eq('config_id', configId)
        .eq('bus_id', busId)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return list.first['content'] as String?;
  }

  /// Remove the DBC attached to a bus.
  Future<void> removeDbc(String configId, String busId) async {
    await _client
        .from(_dbcTable)
        .delete()
        .eq('config_id', configId)
        .eq('bus_id', busId);
  }
}

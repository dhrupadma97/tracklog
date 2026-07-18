/// TrackLog — Instrumentation config repository (Phase 2)
/// Persists per-vehicle instrumentation schematics to Supabase
/// (`instrumentation_configs`, one JSONB row per config) with a
/// draft → locked lifecycle and versioning.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'instrumentation_data.dart';

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
  })  : buses = buses ?? [],
        obdPinout = obdPinout ?? [],
        nodes = nodes ?? [],
        connections = connections ?? [];

  bool get isLocked => status == 'locked';

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
      );

  Map<String, dynamic> toContentRow() => {
        'name': name,
        'manufacturer': manufacturer,
        'buses': buses.map((b) => b.toJson()).toList(),
        'obd_pinout': obdPinout.map((p) => p.toJson()).toList(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'connections': connections.map((c) => c.toJson()).toList(),
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
  /// built-in TATA BETA template). Returns the created config.
  Future<InstrConfig> createFromProfile(VehicleProfile profile) async {
    final row = await _client
        .from(_table)
        .insert({
          'name': profile.name,
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

  /// Lock a validated draft: freezes schematic + instrument list for the test.
  Future<void> lockConfig(InstrConfig config, {required String lockedBy}) async {
    await _client.from(_table).update({
      ...config.toContentRow(), // persist latest edits along with the lock
      'status': 'locked',
      'locked_by': lockedBy,
      'locked_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', config.id);
  }

  /// Start a new editable version from a locked config. Returns the new draft.
  Future<InstrConfig> newVersionFrom(InstrConfig locked) async {
    final row = await _client
        .from(_table)
        .insert({
          ...locked.toContentRow(),
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

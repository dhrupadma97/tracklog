import 'package:supabase_flutter/supabase_flutter.dart';
import 'instrumentation_data.dart';

class SchematicRepository {
  final SupabaseClient _client = Supabase.instance.client;

  // 1. Fetch Vehicle Profiles
  Future<List<Map<String, dynamic>>> getVehicleProfiles() async {
    return await _client.from('vehicle_profiles').select('*');
  }

  // 2. Fetch Nodes for a given Vehicle Profile
  Future<List<SchematicNode>> getNodesForVehicle(String vehicleId) async {
    final response = await _client
        .from('schematic_nodes')
        .select('*')
        .eq('vehicle_id', vehicleId);
        
    return response.map((data) {
      return SchematicNode(
        id: data['id'],
        label: data['instrument_id'], 
        nodeType: InstrumentCategory.logger, // Defaulting for now
        x: (data['x'] as num).toDouble(),
        y: (data['y'] as num).toDouble(),
        instrumentId: data['instrument_id'],
      );
    }).toList();
  }

  // 3. Save Node Position (Dragging)
  Future<void> updateNodePosition(String nodeId, double x, double y) async {
    await _client.from('schematic_nodes').update({
      'x': x,
      'y': y,
    }).eq('id', nodeId);
  }

  // 4. Add new Node
  Future<void> addNode(String vehicleId, String instrumentId, double x, double y, String? notes) async {
    await _client.from('schematic_nodes').insert({
      'vehicle_id': vehicleId,
      'instrument_id': instrumentId,
      'x': x,
      'y': y,
      'notes': notes,
    });
  }

  // 5. Add Connection
  Future<void> addConnection(String vehicleId, String fromNodeId, String toNodeId, String protocol) async {
    await _client.from('schematic_connections').insert({
      'vehicle_id': vehicleId,
      'from_node_id': fromNodeId,
      'to_node_id': toNodeId,
      'protocol': protocol,
      'label': protocol,
    });
  }
}

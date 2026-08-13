import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// A person or asset available for testing.
class TestResource {
  final String id;
  final String name;
  final String type; // engineer | technician | driver | vehicle | equipment
  final String? employeeCode;
  final String? email;
  final String? engineerProfileId;
  final String? roleTitle;
  final String department;
  final String supplier; // Goodyear | NATRAX | Contract
  final double dailyCapacityHours;
  final String status; // active | inactive
  final String? notes;

  const TestResource({
    required this.id,
    required this.name,
    this.type = 'engineer',
    this.employeeCode,
    this.email,
    this.engineerProfileId,
    this.roleTitle,
    this.department = 'Tyre Testing',
    this.supplier = 'Goodyear',
    this.dailyCapacityHours = 8,
    this.status = 'active',
    this.notes,
  });

  bool get isActive => status == 'active';

  /// Utilisation can be derived from session data only for real engineers.
  bool get tracksSessions => (engineerProfileId ?? '').isNotEmpty;

  factory TestResource.fromJson(Map<String, dynamic> j) => TestResource(
        id: j['id'] as String,
        name: j['resource_name'] as String? ?? '',
        type: j['resource_type'] as String? ?? 'engineer',
        employeeCode: j['employee_code'] as String?,
        email: j['email'] as String?,
        engineerProfileId: j['engineer_profile_id'] as String?,
        roleTitle: j['role_title'] as String?,
        department: j['department'] as String? ?? 'Tyre Testing',
        supplier: j['supplier'] as String? ?? 'Goodyear',
        dailyCapacityHours:
            (j['daily_capacity_hours'] as num?)?.toDouble() ?? 8,
        status: j['status'] as String? ?? 'active',
        notes: j['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'resource_name': name,
        'resource_type': type,
        'employee_code': employeeCode,
        'email': email,
        'engineer_profile_id': engineerProfileId,
        'role_title': roleTitle,
        'department': department,
        'supplier': supplier,
        'daily_capacity_hours': dailyCapacityHours,
        'status': status,
        'notes': notes,
      };
}

/// A window carved out of a resource's default availability.
class ResourceAvailability {
  final String id;
  final String resourceId;
  final DateTime startDate;
  final DateTime endDate;
  final String type; // available | leave | training | other_project | unavailable
  final double? hoursPerDay;
  final String? notes;

  const ResourceAvailability({
    required this.id,
    required this.resourceId,
    required this.startDate,
    required this.endDate,
    this.type = 'available',
    this.hoursPerDay,
    this.notes,
  });

  bool get reducesAvailability => type != 'available';

  bool covers(DateTime day) =>
      !day.isBefore(startDate) && !day.isAfter(endDate);

  factory ResourceAvailability.fromJson(Map<String, dynamic> j) =>
      ResourceAvailability(
        id: j['id'] as String,
        resourceId: j['resource_id'] as String,
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: DateTime.parse(j['end_date'] as String),
        type: j['availability_type'] as String? ?? 'available',
        hoursPerDay: (j['hours_per_day'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
      );
}

/// A resource committed to a project over a period.
class ResourceAllocation {
  final String id;
  final String resourceId;
  final String projectName;
  final DateTime startDate;
  final DateTime endDate;
  final double allocatedHours;
  final double? allocationPercent;
  final String? roleOnProject;
  final double? actualHours;
  final String? notes;

  const ResourceAllocation({
    required this.id,
    required this.resourceId,
    required this.projectName,
    required this.startDate,
    required this.endDate,
    this.allocatedHours = 0,
    this.allocationPercent,
    this.roleOnProject,
    this.actualHours,
    this.notes,
  });

  bool overlaps(DateTime from, DateTime to) =>
      !startDate.isAfter(to) && !endDate.isBefore(from);

  factory ResourceAllocation.fromJson(Map<String, dynamic> j) =>
      ResourceAllocation(
        id: j['id'] as String,
        resourceId: j['resource_id'] as String,
        projectName: j['project_name'] as String? ?? '',
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: DateTime.parse(j['end_date'] as String),
        allocatedHours: (j['allocated_hours'] as num?)?.toDouble() ?? 0,
        allocationPercent: (j['allocation_percent'] as num?)?.toDouble(),
        roleOnProject: j['role_on_project'] as String?,
        actualHours: (j['actual_hours'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
      );
}

/// Availability, allocation and actual use for one resource over a window.
class ResourceUtilisation {
  final TestResource resource;
  final double capacityHours;
  final double unavailableHours;
  final double allocatedHours;
  final double utilisedHours;

  /// True when [utilisedHours] came from logged sessions rather than a manual
  /// figure — worth showing, because the two are not equally trustworthy.
  final bool utilisationFromSessions;

  const ResourceUtilisation({
    required this.resource,
    required this.capacityHours,
    required this.unavailableHours,
    required this.allocatedHours,
    required this.utilisedHours,
    required this.utilisationFromSessions,
  });

  double get availableHours =>
      (capacityHours - unavailableHours).clamp(0, double.infinity);

  /// Allocated against what the resource could actually give.
  double get allocationRate =>
      availableHours <= 0 ? 0 : allocatedHours / availableHours;

  /// Actually used against what was promised to the project.
  double get utilisationRate =>
      allocatedHours <= 0 ? 0 : utilisedHours / allocatedHours;

  double get unallocatedHours =>
      (availableHours - allocatedHours).clamp(0, double.infinity);

  bool get isOverAllocated => allocatedHours > availableHours;
}

class ResourceService {
  static ResourceService? _instance;
  static ResourceService get instance => _instance ??= ResourceService._();
  ResourceService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ── Resources ──────────────────────────────────────────────────────────────

  Future<List<TestResource>> listResources({bool activeOnly = false}) async {
    var q = _client.from('test_resources').select();
    if (activeOnly) q = q.eq('status', 'active');
    final rows = await q.order('resource_name');
    return (rows as List)
        .map((r) => TestResource.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<TestResource> upsertResource(TestResource r,
      {bool isNew = false}) async {
    final row = isNew
        ? await _client.from('test_resources').insert(r.toJson()).select().single()
        : await _client
            .from('test_resources')
            .update(r.toJson())
            .eq('id', r.id)
            .select()
            .single();
    return TestResource.fromJson(row);
  }

  Future<void> deleteResource(String id) =>
      _client.from('test_resources').delete().eq('id', id);

  // ── Availability ───────────────────────────────────────────────────────────

  Future<List<ResourceAvailability>> listAvailability() async {
    final rows =
        await _client.from('resource_availability').select().order('start_date');
    return (rows as List)
        .map((r) => ResourceAvailability.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> addAvailability({
    required String resourceId,
    required DateTime start,
    required DateTime end,
    required String type,
    double? hoursPerDay,
    String? notes,
  }) =>
      _client.from('resource_availability').insert({
        'resource_id': resourceId,
        'start_date': _d(start),
        'end_date': _d(end),
        'availability_type': type,
        'hours_per_day': hoursPerDay,
        'notes': notes,
      });

  Future<void> deleteAvailability(String id) =>
      _client.from('resource_availability').delete().eq('id', id);

  // ── Allocations ────────────────────────────────────────────────────────────

  Future<List<ResourceAllocation>> listAllocations({String? projectName}) async {
    var q = _client.from('resource_allocations').select();
    if (projectName != null && projectName.isNotEmpty) {
      q = q.eq('project_name', projectName);
    }
    final rows = await q.order('start_date', ascending: false);
    return (rows as List)
        .map((r) => ResourceAllocation.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> addAllocation({
    required String resourceId,
    required String projectName,
    required DateTime start,
    required DateTime end,
    required double allocatedHours,
    double? allocationPercent,
    String? roleOnProject,
    double? actualHours,
    String? notes,
  }) =>
      _client.from('resource_allocations').insert({
        'resource_id': resourceId,
        'project_name': projectName,
        'start_date': _d(start),
        'end_date': _d(end),
        'allocated_hours': allocatedHours,
        'allocation_percent': allocationPercent,
        'role_on_project': roleOnProject,
        'actual_hours': actualHours,
        'notes': notes,
      });

  Future<void> deleteAllocation(String id) =>
      _client.from('resource_allocations').delete().eq('id', id);

  // ── Utilisation ────────────────────────────────────────────────────────────

  /// Hours each engineer profile actually logged in [from]..[to], from
  /// completed sessions. Keyed by engineer profile id.
  Future<Map<String, double>> sessionHoursByEngineer({
    required DateTime from,
    required DateTime to,
    String? projectName,
  }) async {
    final rows = await _client
        .from('engineer_sessions')
        .select('engineer_id, duration_minutes, started_at, project_name')
        .eq('session_status', 'completed')
        .gte('started_at', from.toIso8601String())
        .lte('started_at', to.toIso8601String());

    final hours = <String, double>{};
    for (final r in rows as List) {
      if (projectName != null && projectName.isNotEmpty) {
        final p = (r['project_name'] as String?)?.trim().toLowerCase() ?? '';
        // Empty/General belongs to Mahindra EV PoC, matching ProjectManager.
        final normalised =
            (p.isEmpty || p == 'general') ? 'mahindra ev poc' : p;
        if (normalised != projectName.toLowerCase()) continue;
      }
      final id = r['engineer_id'] as String?;
      if (id == null) continue;
      hours[id] =
          (hours[id] ?? 0) + ((r['duration_minutes'] as int? ?? 0) / 60.0);
    }
    return hours;
  }

  /// Builds the availability / allocation / utilisation picture for a window.
  ///
  /// Capacity is working days in the window at each resource's daily capacity;
  /// availability rows subtract from it; allocations are what was promised;
  /// utilisation is logged sessions where the resource is a real engineer, and
  /// the allocation's own actual_hours otherwise.
  Future<List<ResourceUtilisation>> utilisation({
    required DateTime from,
    required DateTime to,
    String? projectName,
  }) async {
    final resources = await listResources(activeOnly: true);
    final availability = await listAvailability();
    final allocations = await listAllocations(projectName: projectName);
    final sessionHours = await sessionHoursByEngineer(
        from: from, to: to, projectName: projectName);

    final workingDays = _workingDaysBetween(from, to);

    return resources.map((r) {
      final capacity = workingDays * r.dailyCapacityHours;

      var unavailable = 0.0;
      for (final a in availability) {
        if (a.resourceId != r.id || !a.reducesAvailability) continue;
        final overlapDays = _workingDaysBetween(
          a.startDate.isAfter(from) ? a.startDate : from,
          a.endDate.isBefore(to) ? a.endDate : to,
        );
        unavailable += overlapDays * (a.hoursPerDay ?? r.dailyCapacityHours);
      }

      final mine = allocations
          .where((a) => a.resourceId == r.id && a.overlaps(from, to))
          .toList();
      final allocated = mine.fold(0.0, (s, a) => s + a.allocatedHours);

      final fromSessions = r.tracksSessions;
      final utilised = fromSessions
          ? (sessionHours[r.engineerProfileId] ?? 0)
          : mine.fold(0.0, (s, a) => s + (a.actualHours ?? 0));

      return ResourceUtilisation(
        resource: r,
        capacityHours: capacity,
        unavailableHours: unavailable,
        allocatedHours: allocated,
        utilisedHours: utilised,
        utilisationFromSessions: fromSessions,
      );
    }).toList();
  }

  /// Mon–Fri count, inclusive. NATRAX operates weekdays; weekend testing is
  /// booked as an exception rather than assumed capacity.
  static int _workingDaysBetween(DateTime from, DateTime to) {
    if (to.isBefore(from)) return 0;
    var days = 0;
    var d = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    while (!d.isAfter(end)) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) {
        days++;
      }
      d = d.add(const Duration(days: 1));
    }
    return days;
  }

  static String _d(DateTime d) => d.toIso8601String().split('T').first;
}

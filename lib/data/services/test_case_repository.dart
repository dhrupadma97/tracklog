import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/test_case_model.dart';

/// One overlay row over the read-only generated Goodyear DVP cases. A row can
/// edit a generated case (same test_id), hide it (hidden), or add a brand-new
/// case (isNew). Backed by the private `test_case_overrides` table.
class TestCaseOverride {
  final String testId;
  final bool hidden;
  final bool isNew;
  final TestCase testCase;

  TestCaseOverride({
    required this.testId,
    required this.hidden,
    required this.isNew,
    required this.testCase,
  });

  factory TestCaseOverride.fromRow(Map<String, dynamic> r) {
    String s(String k) => (r[k] as String?) ?? '';
    return TestCaseOverride(
      testId: s('test_id'),
      hidden: r['hidden'] as bool? ?? false,
      isNew: r['is_new'] as bool? ?? false,
      testCase: TestCase(
        testId: s('test_id'),
        testCasesName: s('test_cases_name'),
        tireType: s('tire_type'),
        tireCondition: s('tire_condition'),
        tirePressure: s('tire_pressure'),
        roadSurface: s('road_surface'),
        load: s('load'),
        testDescription: s('test_description'),
        testCaseLink: r['test_case_link'] as String?,
        testResult: r['test_result'] as String?,
        comments: r['comments'] as String?,
        feature: r['feature'] as String? ?? 'Unknown',
        activityType: r['activity_type'] as String? ?? 'Validation',
        drivetrain: r['drivetrain'] as String? ?? 'Both',
        waterDepth: r['water_depth'] as String? ?? 'N/A',
        loadCategory: r['load_category'] as String? ?? 'Driver Only',
        roadSurfaceType: r['road_surface_type'] as String? ?? 'N/A',
      ),
    );
  }
}

class TestCaseRepository {
  final SupabaseClient _c = Supabase.instance.client;
  static const _table = 'test_case_overrides';

  Future<List<TestCaseOverride>> fetchOverrides() async {
    final rows = await _c.from(_table).select();
    return (rows as List)
        .map((r) => TestCaseOverride.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> _toRow(TestCase t,
      {required bool hidden, required bool isNew}) {
    return {
      'test_id': t.testId,
      'hidden': hidden,
      'is_new': isNew,
      'test_cases_name': t.testCasesName,
      'tire_type': t.tireType,
      'tire_condition': t.tireCondition,
      'tire_pressure': t.tirePressure,
      'road_surface': t.roadSurface,
      'load': t.load,
      'test_description': t.testDescription,
      'test_case_link': t.testCaseLink,
      'test_result': t.testResult,
      'comments': t.comments,
      'feature': t.feature,
      'activity_type': t.activityType,
      'drivetrain': t.drivetrain,
      'water_depth': t.waterDepth,
      'load_category': t.loadCategory,
      'road_surface_type': t.roadSurfaceType,
      'updated_by': _c.auth.currentUser?.email,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Add or edit a case ([isNew] true for a brand-new one). Managers only (RLS).
  Future<void> save(TestCase t, {required bool isNew}) async {
    await _c
        .from(_table)
        .upsert(_toRow(t, hidden: false, isNew: isNew), onConflict: 'test_id');
  }

  /// Hide a generated case (keeps a row flagged hidden). Managers only (RLS).
  Future<void> hide(TestCase t) async {
    await _c
        .from(_table)
        .upsert(_toRow(t, hidden: true, isNew: false), onConflict: 'test_id');
  }

  /// Remove the override row — reverts a generated case to its baseline, or
  /// fully deletes a brand-new one. Managers only (RLS).
  Future<void> revert(String testId) async {
    await _c.from(_table).delete().eq('test_id', testId);
  }

  /// Merge overrides onto the base list (generated + supplements), preserving
  /// base order and appending brand-new cases at the end.
  static List<TestCase> applyOverrides(
      List<TestCase> base, List<TestCaseOverride> overrides) {
    final ovById = {for (final o in overrides) o.testId: o};
    final result = <TestCase>[];
    final baseIds = <String>{};
    for (final b in base) {
      baseIds.add(b.testId);
      final o = ovById[b.testId];
      if (o == null) {
        result.add(b);
      } else if (o.hidden) {
        // hidden — omit
      } else {
        result.add(o.testCase);
      }
    }
    for (final o in overrides) {
      if (o.isNew && !o.hidden && !baseIds.contains(o.testId)) {
        result.add(o.testCase);
      }
    }
    return result;
  }
}

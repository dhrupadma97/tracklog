import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/data/services/test_case_india_v02.dart';

/// Guards the dataset generated from "Sightline_Detailed Test cases
/// India_V02.xlsx". If the workbook is regenerated these counts should be
/// updated deliberately, not silently.
void main() {
  final cases = TestCaseIndiaV02.cases;

  test('imports every case from the V02 workbook', () {
    expect(cases.length, 1433);
  });

  test('test ids are unique — the override overlay keys on them', () {
    final ids = cases.map((c) => c.testId).toList();
    final dupes = <String>{};
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) dupes.add(id);
    }
    expect(dupes, isEmpty, reason: 'duplicate test ids: $dupes');
  });

  test('no case is missing an id or a name', () {
    expect(cases.where((c) => c.testId.trim().isEmpty), isEmpty);
    expect(cases.where((c) => c.testCasesName.trim().isEmpty), isEmpty);
  });

  test('per-feature counts match the workbook sheets', () {
    int count(String feature, String activity) => cases
        .where((c) => c.feature == feature && c.activityType == activity)
        .length;

    expect(count('AQD', 'Calibration'), 168); // 1.Test Cases_AQD_CAL
    expect(count('AQD', 'Validation'), 800); // EV 224 + ICE 242 + matrix 334
    expect(count('DFE', 'Calibration'), 201);
    expect(count('DFE', 'Validation'), 47);
    expect(count('DLE', 'Calibration'), 18);
    expect(count('DLE', 'Validation'), 20);
    expect(count('Leak Detection', 'Calibration'), 9);
    expect(count('Winter', 'Validation'), 170);
  });

  test('AQD validation is split by drivetrain (V02 change)', () {
    final aqdVal =
        cases.where((c) => c.feature == 'AQD' && c.activityType == 'Validation');
    expect(aqdVal.where((c) => c.drivetrain == 'EV').length, 224);
    expect(aqdVal.where((c) => c.drivetrain == 'ICE').length, 242);
  });

  test('winter cases keep their original workbook id in remarks', () {
    final winter = cases.where((c) => c.feature == 'Winter').toList();
    expect(winter.every((c) => c.testId.startsWith('GY.SL.WIN.')), isTrue);
    expect(winter.every((c) => c.remarks.contains('Source ID in workbook:')),
        isTrue);
  });

  test('the whole validation matrix is imported', () {
    // testSite is only populated for matrix-sourced cases.
    final matrix = cases.where((c) => c.testSite.isNotEmpty).toList();
    expect(matrix.length, 334);
  });

  test('the matrix system-level cases keep their ASPICE / ISO 26262 columns',
      () {
    // Only the 7 system-level rows of the matrix carry Req ID / ASIL / safety
    // mechanism; the remaining 327 are thin requirement-based rows that list
    // just the case name, method and test site. That is the workbook's shape.
    final withReq = cases.where((c) => c.reqId.isNotEmpty).toList();
    expect(withReq.length, 7);
    // The one QM row in the matrix (TIR-040) has no Val ID, so it is not a case.
    expect(withReq.where((c) => c.asil == 'ASIL B').length, 7);
    expect(withReq.every((c) => c.method.isNotEmpty), isTrue);
    expect(withReq.every((c) => c.acceptanceCriteria.isNotEmpty), isTrue);
  });

  test('metadata is normalised for the filters', () {
    // Every case must have filterable metadata, or it silently disappears
    // whenever a filter other than "All" is selected.
    expect(cases.where((c) => c.drivetrain.isEmpty), isEmpty);
    expect(cases.where((c) => c.waterDepth.isEmpty), isEmpty);
    expect(cases.where((c) => c.loadCategory.isEmpty), isEmpty);
    expect(cases.where((c) => c.roadSurfaceType.isEmpty), isEmpty);
  });
}

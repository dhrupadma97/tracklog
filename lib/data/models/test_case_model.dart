class TestCase {
  final String testId;
  final String testCasesName;
  final String tireType;
  final String tireCondition;
  final String tirePressure;
  final String roadSurface;
  final String load;
  final String testDescription;
  final String? testCaseLink;
  final String? testResult;
  final String? comments;

  // Metadata for grouping & filtering
  final String feature;          // 'AQD', 'DFE', 'Leak Detection'
  final String activityType;     // 'Validation', 'Calibration'
  final String drivetrain;       // 'EV', 'ICE', 'Both'
  final String waterDepth;       // '4mm', '8mm', 'N/A'
  final String loadCategory;     // 'Driver Only', 'Full', 'Unload', 'Driver + Ballast'
  final String roadSurfaceType;  // 'Jump Mu', 'Split Mu', 'Wet Basalt', 'Wet Ceramic', 'Dry', 'Wet Asphalt', 'N/A'

  // Vehicle Validation Matrix columns (Sightline India V01). Empty for the
  // legacy DFE/Leak calibration cases; populated for the AQD validation cases.
  final String reqId;              // Stakeholder / Req ID (e.g. TIR-041)
  final String asil;               // 'ASIL B', 'QM', ''
  final String method;             // 'Vehicle Test', 'Test', 'Demonstration'
  final String testSite;           // 'Proving Ground (wet basin)', 'Public Road'
  final String condition;          // Vehicle / Tire Condition, Road & Drive Cycle
  final String acceptanceCriteria; // incl. FTTI / safe state
  final String safetyMechanism;    // Safety Mechanism
  final String specRef;            // Standard / Spec Ref
  final String status;             // Status
  final String remarks;            // Remarks / Disposition

  TestCase({
    required this.testId,
    required this.testCasesName,
    required this.tireType,
    required this.tireCondition,
    required this.tirePressure,
    required this.roadSurface,
    required this.load,
    required this.testDescription,
    this.testCaseLink,
    this.testResult,
    this.comments,
    this.feature = 'Unknown',
    this.activityType = 'Validation',
    this.drivetrain = 'Both',
    this.waterDepth = 'N/A',
    this.loadCategory = 'Driver Only',
    this.roadSurfaceType = 'N/A',
    this.reqId = '',
    this.asil = '',
    this.method = '',
    this.testSite = '',
    this.condition = '',
    this.acceptanceCriteria = '',
    this.safetyMechanism = '',
    this.specRef = '',
    this.status = '',
    this.remarks = '',
  });

  TestCase copyWith({
    String? testId,
    String? testCasesName,
    String? tireType,
    String? tireCondition,
    String? tirePressure,
    String? roadSurface,
    String? load,
    String? testDescription,
    String? testCaseLink,
    String? testResult,
    String? comments,
    String? feature,
    String? activityType,
    String? drivetrain,
    String? waterDepth,
    String? loadCategory,
    String? roadSurfaceType,
    String? reqId,
    String? asil,
    String? method,
    String? testSite,
    String? condition,
    String? acceptanceCriteria,
    String? safetyMechanism,
    String? specRef,
    String? status,
    String? remarks,
  }) {
    return TestCase(
      testId: testId ?? this.testId,
      testCasesName: testCasesName ?? this.testCasesName,
      tireType: tireType ?? this.tireType,
      tireCondition: tireCondition ?? this.tireCondition,
      tirePressure: tirePressure ?? this.tirePressure,
      roadSurface: roadSurface ?? this.roadSurface,
      load: load ?? this.load,
      testDescription: testDescription ?? this.testDescription,
      testCaseLink: testCaseLink ?? this.testCaseLink,
      testResult: testResult ?? this.testResult,
      comments: comments ?? this.comments,
      feature: feature ?? this.feature,
      activityType: activityType ?? this.activityType,
      drivetrain: drivetrain ?? this.drivetrain,
      waterDepth: waterDepth ?? this.waterDepth,
      loadCategory: loadCategory ?? this.loadCategory,
      roadSurfaceType: roadSurfaceType ?? this.roadSurfaceType,
      reqId: reqId ?? this.reqId,
      asil: asil ?? this.asil,
      method: method ?? this.method,
      testSite: testSite ?? this.testSite,
      condition: condition ?? this.condition,
      acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
      safetyMechanism: safetyMechanism ?? this.safetyMechanism,
      specRef: specRef ?? this.specRef,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
    );
  }
}

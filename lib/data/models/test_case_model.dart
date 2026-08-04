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
    );
  }
}

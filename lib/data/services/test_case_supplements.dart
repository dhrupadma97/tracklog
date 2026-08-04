import '../models/test_case_model.dart';

/// Manually-maintained test cases kept OUTSIDE the auto-generated
/// `test_case_service.dart`, so they survive a regen from the Goodyear DVP
/// Excel.
///
/// Current set: **Temporary Spare Wheel** (space-saver) validation for AQD and
/// DFE on the upcoming-vehicle program. A temp spare has a smaller rolling
/// radius and is speed-limited (~80 kph), which shifts the wheel-speed baseline
/// the algorithms rely on — so they must neither false-trigger nor drop a real
/// detection while it is fitted.
class TestCaseSupplements {
  static const String _spareTire = 'Temp Spare (T125/80 R17)';
  static const String _spareCond = 'Temp Spare Fitted (rear)';
  static const String _sparePress = 'Temp-spare spec (60 psi)';

  static List<TestCase> get cases => [
        // ── AQD · Temporary Spare Wheel · Validation ──────────────────────
        TestCase(
          testId: 'GY.SL.AQD.TSW.1',
          testCasesName: 'Temp Spare — Straight Constant Speed 60 kph',
          tireType: _spareTire,
          tireCondition: _spareCond,
          tirePressure: _sparePress,
          roadSurface: 'Asphalt - 4mm water',
          load: 'Driver Only',
          testDescription:
              'Temporary spare fitted (speed-limited 80 kph). Hold 60 kph through a 4 mm '
              'film. Expected: the space-saver rolling-radius mismatch does NOT raise a false '
              'aquaplaning flag.',
          feature: 'AQD',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: '4mm',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Wet Asphalt',
          comments: 'Upcoming-vehicle program',
        ),
        TestCase(
          testId: 'GY.SL.AQD.TSW.2',
          testCasesName: 'Temp Spare — Aquaplaning Detection Entry',
          tireType: _spareTire,
          tireCondition: _spareCond,
          tirePressure: _sparePress,
          roadSurface: 'Asphalt - 8mm water',
          load: 'Driver Only',
          testDescription:
              'Enter an 8 mm film with the temporary spare fitted. Expected: AQD still detects a '
              'genuine aquaplaning event within threshold latency despite the space-saver '
              'wheel-speed offset.',
          feature: 'AQD',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: '8mm',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Wet Asphalt',
          comments: 'Upcoming-vehicle program',
        ),

        // ── DFE · Temporary Spare Wheel · Validation ──────────────────────
        TestCase(
          testId: 'GY.SL.DFE.TSW.1',
          testCasesName: 'Temp Spare — Friction Estimate Cruising',
          tireType: _spareTire,
          tireCondition: _spareCond,
          tirePressure: _sparePress,
          roadSurface: 'Split Mu',
          load: 'Driver Only',
          testDescription:
              'Cruise across a split-mu surface with the temporary spare fitted. Expected: DFE '
              'compensates for the space-saver rolling-radius offset and holds the friction '
              'estimate within tolerance.',
          feature: 'DFE',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Split Mu',
          comments: 'Upcoming-vehicle program',
        ),
        TestCase(
          testId: 'GY.SL.DFE.TSW.2',
          testCasesName: 'Temp Spare — Light Braking Friction',
          tireType: _spareTire,
          tireCondition: _spareCond,
          tirePressure: _sparePress,
          roadSurface: 'Dry Asphalt',
          load: 'Driver Only',
          testDescription:
              'Light braking on dry asphalt with the temporary spare fitted. Expected: the '
              'wheel-speed differential from the space-saver does not corrupt the friction '
              'estimate.',
          feature: 'DFE',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Dry Asphalt',
          comments: 'Upcoming-vehicle program',
        ),
      ];
}

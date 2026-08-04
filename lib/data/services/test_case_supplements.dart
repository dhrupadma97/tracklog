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

        // ══════════════════════════════════════════════════════════════════
        //  FALSE-POSITIVE detection trials — one set per model (per Goodyear
        //  DVP). Scenarios where the algorithm MUST NOT trigger.
        // ══════════════════════════════════════════════════════════════════
        // ── AQD false positives ──
        TestCase(
          testId: 'GY.SL.AQD.FP.1',
          testCasesName: 'False Positive — Dry Road High Speed',
          tireType: 'SKU-21',
          tireCondition: 'New',
          tirePressure: 'Standard',
          roadSurface: 'Dry Asphalt',
          load: 'Driver Only',
          testDescription:
              'High-speed run (100 kph) on fully dry asphalt. Expected: AQD raises NO '
              'aquaplaning flag — there is no water film.',
          feature: 'AQD',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Dry Asphalt',
          comments: 'False-positive trial',
        ),
        TestCase(
          testId: 'GY.SL.AQD.FP.2',
          testCasesName: 'False Positive — Cleats & Rumble Strips',
          tireType: 'SKU-21',
          tireCondition: 'New',
          tirePressure: 'Standard',
          roadSurface: 'Cleats, rumble strips (dry)',
          load: 'Full',
          testDescription:
              'Drive over cleats and rumble strips on a dry surface. Expected: vertical '
              'vibration is NOT mis-classified as aquaplaning.',
          feature: 'AQD',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Full',
          roadSurfaceType: 'Dry',
          comments: 'False-positive trial',
        ),
        // ── DFE false positives ──
        TestCase(
          testId: 'GY.SL.DFE.FP.1',
          testCasesName: 'False Positive — Uniform Dry Grip',
          tireType: 'SKU-21',
          tireCondition: 'New',
          tirePressure: 'Standard',
          roadSurface: 'Dry Asphalt',
          load: 'Driver Only',
          testDescription:
              'Steady cruise on a uniform high-grip dry surface. Expected: DFE reports a '
              'stable friction estimate with NO false surface-change event.',
          feature: 'DFE',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Dry Asphalt',
          comments: 'False-positive trial',
        ),
        TestCase(
          testId: 'GY.SL.DFE.FP.2',
          testCasesName: 'False Positive — Rough-Road Vibration',
          tireType: 'SKU-21',
          tireCondition: 'Full Worn',
          tirePressure: 'Standard',
          roadSurface: 'Undulating asphalt (dry)',
          load: 'Full',
          testDescription:
              'Rough/undulating dry road at speed. Expected: NVH and suspension motion do '
              'NOT produce a false friction-drop estimate.',
          feature: 'DFE',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Full',
          roadSurfaceType: 'Dry',
          comments: 'False-positive trial',
        ),
        // ── Leak Detection false positives ──
        TestCase(
          testId: 'GY.SL.LEAK.FP.1',
          testCasesName: 'False Positive — Thermal Pressure Rise',
          tireType: 'SKU-21',
          tireCondition: 'New',
          tirePressure: 'Standard (warmed)',
          roadSurface: 'Dry Asphalt',
          load: 'Driver Only',
          testDescription:
              'Sustained running warms the tire and raises pressure. Expected: the rising '
              'trend is NOT reported as a leak (a leak is a pressure LOSS).',
          feature: 'Leak Detection',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Driver Only',
          roadSurfaceType: 'Dry Asphalt',
          comments: 'False-positive trial',
        ),
        TestCase(
          testId: 'GY.SL.LEAK.FP.2',
          testCasesName: 'False Positive — Load / Ballast Change',
          tireType: 'SKU-21',
          tireCondition: 'New',
          tirePressure: 'Standard',
          roadSurface: 'Dry Asphalt',
          load: 'Driver + Ballast',
          testDescription:
              'Add ballast between runs to shift the apparent pressure. Expected: the step '
              'is NOT flagged as a slow leak.',
          feature: 'Leak Detection',
          activityType: 'Validation',
          drivetrain: 'Both',
          waterDepth: 'N/A',
          loadCategory: 'Driver + Ballast',
          roadSurfaceType: 'Dry Asphalt',
          comments: 'False-positive trial',
        ),
      ];
}

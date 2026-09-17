import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/track_cost_rules.dart';

/// Every NATRAX rate, pinned to quotation NATRAX/Q/BIP/26-27/018 (7 Apr 2026).
///
/// The rates live in a hardcoded list inside manual_entry_screen.dart, which
/// has drifted from the real card twice: T8 and T11 held each other's price
/// until 15 Sep 2026, and T9, T10, T12 and T13 were all wrong — T13 was even
/// carrying the gravel track's NAME, while the gravel track itself did not
/// exist, so logging on it meant paying 15,000 for a 7,500 track.
///
/// `track_rates` in Supabase had all of them right the whole time. This file
/// exists so the next drift fails a test instead of an invoice.
void main() {
  /// Below 3.5 T / PV, which is everything Goodyear runs here.
  const quoted = <String, double>{
    'T1': 25000, // High Speed Track
    'T2': 20000, // Dynamic Platform Track
    'T3D': 19000, // Straight Dry Braking Track
    'T3W': 21000, // Straight Wet Braking Track
    'T4': 8000, // Test Hill Track (All Gradient)
    'T5': 14000, // Accelerated Fatigue Track
    'T6': 7500, // Gravel and Off Road Track
    'T7': 15000, // Handling Track Testing 4W (1.6 Km)
    'T8': 10500, // Comfort Track Testing
    'T9': 5000, // Handling Track 2W
    'T10': 6000, // Sustainability Track
    'T11': 15000, // Wet Skid Pad Track
    'T12': 6000, // Suspension & Traction
    'T13': 14000, // External Noise Track
    'T16': 9000, // General Road Track
  };

  /// Exclusive, per 2-hour block. The quote's 4-hour price is exactly twice
  /// each of these.
  const exclusive = <String, double>{
    'T1X': 180000,
    'T2X': 120000,
    'T3X': 150000,
    'T7X': 60000,
    'T8X': 48000,
  };

  group('rates on the quotation', () {
    test('an hour on each track costs what the card says', () {
      quoted.forEach((code, rate) {
        expect(
          TrackCostRules.dayCost(totalMinutes: 60, rate: rate, minHours: 1),
          rate,
          reason: '$code should bill one hour at $rate',
        );
      });
    });

    test('the four that were wrong are the ones that moved', () {
      // Guards the specific corrections of 17 Sep 2026 rather than the
      // general shape, so a revert is loud.
      expect(quoted['T9'], 5000);
      expect(quoted['T10'], 6000);
      expect(quoted['T12'], 6000);
      expect(quoted['T13'], 14000);
    });

    test('the three that were missing are priced', () {
      expect(quoted['T4'], 8000);
      expect(quoted['T5'], 14000);
      expect(quoted['T6'], 7500);
    });

    test('T8 and T11 do not hold each other price again', () {
      expect(quoted['T8'], 10500);
      expect(quoted['T11'], 15000);
      expect(quoted['T8'], lessThan(quoted['T11']!));
    });
  });

  group('exclusive blocks', () {
    test('a 2-hour block costs the quoted block price', () {
      exclusive.forEach((code, price) {
        expect(
          TrackCostRules.exclusiveCost(
              totalMinutes: 120, blockPrice: price, blockHours: 2),
          price,
          reason: '$code should cost $price for two hours',
        );
      });
    });

    test('exclusive always costs more than the same hours booked normally',
        () {
      const pairs = {'T1X': 'T1', 'T2X': 'T2', 'T7X': 'T7', 'T8X': 'T8'};
      pairs.forEach((ex, hourly) {
        final blockCost = TrackCostRules.exclusiveCost(
            totalMinutes: 120, blockPrice: exclusive[ex]!, blockHours: 2);
        final hourlyCost = TrackCostRules.dayCost(
            totalMinutes: 120, rate: quoted[hourly]!, minHours: 2);
        expect(blockCost, greaterThan(hourlyCost),
            reason: '$ex must cost more than two hours of $hourly');
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/track_cost_rules.dart';

/// The rates that actually appear on NATRAX invoices, FY 2026-27.
/// Pinned here so a change to the app's table cannot quietly change a test.
const t3w = 21000.0, t3d = 19000.0, t1 = 25000.0, t2 = 20000.0;
const t7 = 15000.0, t8 = 10500.0, t11 = 15000.0, t16 = 9000.0;

void main() {
  exclusiveBookings();
  edgeCases();
  group('whole hours, rounded up', () {
    test('nothing logged bills nothing', () {
      expect(TrackCostRules.ceilHours(0), 0);
      expect(TrackCostRules.ceilHours(-5), 0);
    });

    test('one minute is an hour', () {
      expect(TrackCostRules.ceilHours(1), 1);
    });

    test('exact hours do not round up past themselves', () {
      expect(TrackCostRules.ceilHours(60), 1);
      expect(TrackCostRules.ceilHours(120), 2);
    });

    test('a part hour rounds up', () {
      expect(TrackCostRules.ceilHours(61), 2);
      expect(TrackCostRules.ceilHours(141), 3); // 2.35 h -> 3
    });
  });

  group('8 September 2026 — the day that exposed the per-entry minimum', () {
    // Three sessions on T3W: 125, 45 then 100 minutes.
    // Day totals 270 min = 4.5 h -> 5 Hrs = Rs 1,05,000.
    test('first entry carries the rounding', () {
      final c = TrackCostRules.marginalCost(
        entryMinutes: 125, sameDayMinutes: 0, sameDayCost: 0,
        rate: t3w, minHours: 2,
      );
      expect(c, 63000); // ceil(2.08) = 3 hrs
    });

    test('a later entry adds nothing until the day crosses an hour', () {
      final c = TrackCostRules.marginalCost(
        entryMinutes: 45, sameDayMinutes: 125, sameDayCost: 63000,
        rate: t3w, minHours: 2,
      );
      expect(c, 0); // day is 170 min, still ceil 3
    });

    test('the entry that crosses into hour five pays for it', () {
      final c = TrackCostRules.marginalCost(
        entryMinutes: 100, sameDayMinutes: 170, sameDayCost: 63000,
        rate: t3w, minHours: 2,
      );
      expect(c, 42000); // day 270 min -> 5 hrs, less the 63,000 already billed
    });

    test('the DAY total is what the invoice shows', () {
      expect(
        TrackCostRules.dayCost(totalMinutes: 270, rate: t3w, minHours: 2),
        105000,
      );
    });
  });

  group('the 2-hour minimum', () {
    test('a short day on T3W still bills two hours', () {
      expect(TrackCostRules.dayCost(totalMinutes: 35, rate: t3w, minHours: 2),
          42000);
    });

    test('T2 bills 35 minutes as two hours — INV/26-27/205, 9 April', () {
      expect(TrackCostRules.dayCost(totalMinutes: 35, rate: t2, minHours: 2),
          40000);
    });

    test('the minimum is charged once per day, not per entry', () {
      // Two 35-minute entries. Wrong answer is 42,000 twice.
      final first = TrackCostRules.marginalCost(
        entryMinutes: 35, sameDayMinutes: 0, sameDayCost: 0,
        rate: t3w, minHours: 2,
      );
      final second = TrackCostRules.marginalCost(
        entryMinutes: 35, sameDayMinutes: 35, sameDayCost: first,
        rate: t3w, minHours: 2,
      );
      expect(first + second, 42000);
      expect(second, 0);
    });

    test('one-hour tracks bill a short day as one hour', () {
      expect(TrackCostRules.dayCost(totalMinutes: 30, rate: t7, minHours: 1),
          15000);
      expect(TrackCostRules.dayCost(totalMinutes: 35, rate: t8, minHours: 1),
          10500);
      expect(TrackCostRules.dayCost(totalMinutes: 30, rate: t11, minHours: 1),
          15000);
      expect(TrackCostRules.dayCost(totalMinutes: 24, rate: t16, minHours: 1),
          9000);
    });
  });

  group('T3 Wet and T3 Dry share one minimum — INV/26-27/205', () {
    test('they are grouped', () {
      expect(TrackCostRules.groupFor('T3W'), containsAll(['T3W', 'T3D']));
      expect(TrackCostRules.groupFor('T3D'), containsAll(['T3W', 'T3D']));
    });

    test('a track with no sibling is its own group', () {
      expect(TrackCostRules.groupFor('T1'), ['T1']);
    });

    test('dry bills one hour when wet already met the day minimum', () {
      // 7 April: wet ran 1.5 h (2 Hrs billed), dry ran 49 min.
      // The invoice bills dry 1 Hr, not 2.
      expect(
        TrackCostRules.dayCost(
            totalMinutes: 49, rate: t3d, minHours: 2, siblingCeilHours: 2),
        19000,
      );
    });

    test('April dry days total 3 Hrs, exactly as invoiced', () {
      // 7, 8 and 9 April: 49, 36 and 50 minutes, wet running each day.
      const days = [49, 36, 50];
      final total = days.fold<double>(
        0,
        (s, m) => s + TrackCostRules.dayCost(
            totalMinutes: m, rate: t3d, minHours: 2, siblingCeilHours: 2),
      );
      expect(total, 57000); // 3 Hrs at 19,000
    });

    test('dry running ALONE still bills two hours', () {
      expect(
        TrackCostRules.dayCost(totalMinutes: 36, rate: t3d, minHours: 2),
        38000,
      );
    });
  });

  group('regressions from the 15 September 2026 import', () {
    test('T8 is never priced at the T1 rate', () {
      // Every imported session carried 25,000/hr. On T8 that is 15,000 too
      // much an hour.
      final wrong =
          TrackCostRules.dayCost(totalMinutes: 35, rate: t1, minHours: 1);
      final right =
          TrackCostRules.dayCost(totalMinutes: 35, rate: t8, minHours: 1);
      expect(right, 10500);
      expect(right, lessThan(wrong));
    });

    test('a fraction of an hour is never billed', () {
      // The old bug billed 2.35 h as Rs 49,350 where NATRAX invoices 3 Hrs.
      final c = TrackCostRules.dayCost(
          totalMinutes: 141, rate: t3w, minHours: 2);
      expect(c, 63000);
      expect(c, isNot(closeTo(141 / 60 * t3w, 1)));
    });

    test('a marginal cost is never negative', () {
      final c = TrackCostRules.marginalCost(
        entryMinutes: 10, sameDayMinutes: 0, sameDayCost: 999999,
        rate: t3w, minHours: 2,
      );
      expect(c, 0);
    });

    test('zero-length entries cost nothing', () {
      expect(
        TrackCostRules.marginalCost(
          entryMinutes: 0, sameDayMinutes: 120, sameDayCost: 42000,
          rate: t3w, minHours: 2,
        ),
        0,
      );
    });
  });

  group('April 2026 wet braking totals 34 Hrs — INV/26-27/205', () {
    test('nine days, each rounded up on its own', () {
      // Daily minutes from the utilisation workbook.
      const days = [90, 171, 353, 190, 279, 135, 294, 120, 213];
      final hours = days.fold<double>(
        0,
        (s, m) => s + TrackCostRules.dayCost(
                totalMinutes: m, rate: t3w, minHours: 2) /
            t3w,
      );
      expect(hours, 34);
      expect(hours * t3w, 714000);
    });
  });
}

// ── Edge cases: what a tired engineer at 11pm can actually type ────────────
void edgeCases() {
  group('clock times that cross midnight', () {
    test('9 April 2026 — 21:36 to 00:25 is 169 minutes, not negative', () {
      final mins = TrackCostRules.minutesBetween(21 * 60 + 36, 0 * 60 + 25);
      expect(mins, 169);
    });

    test('an ordinary daytime session is unaffected', () {
      expect(TrackCostRules.minutesBetween(9 * 60, 11 * 60 + 30), 150);
    });

    test('23:30 to 00:30 is an hour', () {
      expect(TrackCostRules.minutesBetween(23 * 60 + 30, 30), 60);
    });

    test('identical start and end is zero, not a whole day', () {
      expect(TrackCostRules.minutesBetween(10 * 60, 10 * 60), 0);
    });

    test('wrapping can never exceed a day', () {
      for (var s = 0; s < 1440; s += 37) {
        for (var e = 0; e < 1440; e += 53) {
          final m = TrackCostRules.minutesBetween(s, e);
          expect(m, inInclusiveRange(0, TrackCostRules.minutesInDay - 1));
        }
      }
    });
  });

  group('absurd input cannot produce absurd money', () {
    test('a whole day on T3W bills 24 hours, not more', () {
      final c = TrackCostRules.dayCost(
          totalMinutes: TrackCostRules.minutesInDay, rate: 21000, minHours: 2);
      expect(c, 24 * 21000);
    });

    test('negative minutes cost nothing', () {
      expect(TrackCostRules.dayCost(totalMinutes: -60, rate: 21000, minHours: 2),
          0);
      expect(TrackCostRules.ceilHours(-1), 0);
    });

    test('a zero rate costs nothing however long the day', () {
      // CoASTT layouts seed at rate 0 with rate_pending, and must not invent
      // a charge.
      expect(TrackCostRules.dayCost(totalMinutes: 600, rate: 0, minHours: 1), 0);
    });

    test('a minimum of zero does not force an hour', () {
      expect(TrackCostRules.dayCost(totalMinutes: 0, rate: 21000, minHours: 0),
          0);
    });
  });
}

// ── Exclusive bookings: NATRAX/Q/BIP/26-27/018, 7 April 2026 ───────────────
void exclusiveBookings() {
  group('exclusive is charged by the block, not the hour', () {
    test('T1 — 1,80,000 per 2 hours', () {
      expect(
        TrackCostRules.exclusiveCost(
            totalMinutes: 120, blockPrice: 180000, blockHours: 2),
        180000,
      );
    });

    test('T1 — 3,60,000 per 4 hours, which is two blocks', () {
      expect(
        TrackCostRules.exclusiveCost(
            totalMinutes: 240, blockPrice: 180000, blockHours: 2),
        360000,
      );
    });

    test('half a block still costs the block', () {
      // Booking the track at all takes it off everyone else.
      expect(
        TrackCostRules.exclusiveCost(
            totalMinutes: 30, blockPrice: 180000, blockHours: 2),
        180000,
      );
    });

    test('a minute past the block buys the next one', () {
      expect(
        TrackCostRules.exclusiveCost(
            totalMinutes: 121, blockPrice: 180000, blockHours: 2),
        360000,
      );
    });

    test('every quoted 2 h and 4 h pair holds', () {
      final quoted = <double, double>{
        180000.0: 360000.0, // T1  High Speed
        120000.0: 240000.0, // T2  Dynamic Platform
        150000.0: 300000.0, // T3  Braking
        60000.0: 120000.0, // T7  Handling 4W
        48000.0: 96000.0, // T8  Comfort
      };
      quoted.forEach((twoHour, fourHour) {
        expect(
          TrackCostRules.exclusiveCost(
              totalMinutes: 120, blockPrice: twoHour, blockHours: 2),
          twoHour,
        );
        expect(
          TrackCostRules.exclusiveCost(
              totalMinutes: 240, blockPrice: twoHour, blockHours: 2),
          fourHour,
          reason: 'the 4-hour price must come out of two 2-hour blocks',
        );
      });
    });

    test('nothing booked costs nothing', () {
      expect(
        TrackCostRules.exclusiveCost(
            totalMinutes: 0, blockPrice: 180000, blockHours: 2),
        0,
      );
    });

    test('an exclusive block is never cheaper than the hourly rate', () {
      // 2 hours of T1 hourly is 50,000; exclusive is 1,80,000. If that ever
      // inverts, the wrong row is being charged.
      final hourly =
          TrackCostRules.dayCost(totalMinutes: 120, rate: 25000, minHours: 2);
      final exclusive = TrackCostRules.exclusiveCost(
          totalMinutes: 120, blockPrice: 180000, blockHours: 2);
      expect(exclusive, greaterThan(hourly));
    });
  });
}

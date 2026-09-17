import 'dart:math' as math;

/// How NATRAX charges for track time.
///
/// Extracted from `manual_entry_screen.dart` so it can be tested. Every
/// billing bug found on 15 September 2026 lived in this arithmetic while it
/// sat inside a StatefulWidget, unreachable from a test:
///
///   * every imported session priced at a flat 25,000/hr
///   * the raw fraction billed instead of whole hours
///   * the 2-hour minimum charged per entry instead of per day
///   * T3 Wet and T3 Dry each charged their own minimum on a shared day
///
/// The widget now calls this. Tests in `test/track_cost_rules_test.dart` pin
/// it to real invoice lines, so the same mistakes cannot come back quietly.
class TrackCostRules {
  const TrackCostRules._();

  /// Minutes to whole billable hours, always rounding up.
  ///
  /// Zero stays zero: a day with nothing logged has nothing to bill. One
  /// minute is an hour, which is the floor NATRAX charges.
  static double ceilHours(int minutes) =>
      minutes <= 0 ? 0 : (minutes / 60.0).ceilToDouble();

  /// Tracks that share ONE minimum between them on a given day.
  ///
  /// T3 Wet and T3 Dry are two surfaces of the same braking track, and NATRAX
  /// applies the two-hour minimum to the track once a day rather than to each
  /// surface. INV/26-27/205 settles it: April has three dry days of 49, 36 and
  /// 50 minutes, wet ran on all three, and dry is billed 3 Hrs for the month —
  /// one hour each, the ceiling of its own time, with no minimum of its own.
  /// Two separate minimums give 6 Hrs and double the money.
  static const Map<String, List<String>> minimumGroups = {
    'T3W': ['T3W', 'T3D'],
    'T3D': ['T3W', 'T3D'],
  };

  /// Every track code sharing [code]'s day minimum, itself included.
  static List<String> groupFor(String code) =>
      minimumGroups[code] ?? <String>[code];

  /// What adding [entryMinutes] costs, given what the day already carries.
  ///
  /// Marginal, not absolute: the whole day is recosted and what has already
  /// been billed for it is taken off. So the first entry of a day carries the
  /// rounding up, and a later one adds nothing until the day crosses into the
  /// next whole hour. A session can therefore cost 0 legitimately — the DAY
  /// total is what NATRAX invoices; the split across sessions is internal.
  ///
  /// [siblingCeilHours] is the whole hours already taken by the OTHER surface
  /// of the same track that day. Pass 0 for a track with no sibling, and the
  /// formula reduces to `max(ceil(day), minHours) * rate`.
  static double marginalCost({
    required int entryMinutes,
    required int sameDayMinutes,
    required double sameDayCost,
    required double rate,
    required double minHours,
    double siblingCeilHours = 0,
  }) {
    if (entryMinutes <= 0) return 0;
    final thisCeil = ceilHours(sameDayMinutes + entryMinutes);
    final groupCeil = thisCeil + siblingCeilHours;
    // The minimum belongs to the group, so only the part it has not already
    // covered between the two surfaces is added here.
    final shortfall = math.max(0.0, minHours - groupCeil);
    final cost = (thisCeil + shortfall) * rate - sameDayCost;
    // Never negative: deleting or shortening an earlier entry could otherwise
    // make a later one refund money it never charged.
    return cost < 0 ? 0 : cost;
  }

  /// What a whole day on one track costs, ignoring how it is split.
  ///
  /// This is the figure that has to match an invoice line. Use it to check a
  /// day rather than summing [marginalCost] calls, which is only the internal
  /// apportionment.
  static double dayCost({
    required int totalMinutes,
    required double rate,
    required double minHours,
    double siblingCeilHours = 0,
  }) {
    if (totalMinutes <= 0) return 0;
    final ceil = ceilHours(totalMinutes);
    final shortfall = math.max(0.0, minHours - (ceil + siblingCeilHours));
    return (ceil + shortfall) * rate;
  }
}

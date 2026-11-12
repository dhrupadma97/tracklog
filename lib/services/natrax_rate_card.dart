import 'track_cost_rules.dart';

/// The NATRAX track rate card, in one place.
///
/// It lived as a private constant inside the Manual Entry screen, which meant
/// anything else needing a rate — the reconciliation that checks NATRAX's
/// utilisation sheet, for one — had to copy it. A second copy of a rate card
/// is how T8 and T11 came to hold each other's rate for months: one list was
/// corrected and the other was not. Manual Entry now reads this.
///
/// NATRAX rate card, reconciled line by line against real invoices:
/// INV/26-27/205 (April 2026) and INV/26-27/388 (18-25 May 2026), both of
/// which tie out to the rupee against BillingBaseline.
///
/// Five rates here were wrong and are corrected below:
///
///   T2  Dynamic Platform   25,000 -> 20,000   (April and May invoices)
///   T7  4W Handling        18,000 -> 15,000   (April invoice)
///   T16 General Road       absent -> 9,000    (May invoice; was not listed)
///   T8  Comfort Track      15,000 -> 10,500   (May invoice, 23 May)
///   T11 Wet Skid Pad Track 10,500 -> 15,000   (May invoice, 19 and 20 May)
///
/// T8 and T11 carried each other's rate AND each other's name. An earlier
/// pass read the right rupee values off the May invoice - a 10,500 Comfort
/// line and a 15,000 Wet Skid Pad line - but attached them to the wrong
/// codes, because every imported March-May session was labelled at 25,000
/// and could not be tied back to an invoice line. The workbook's Daily
/// Track Billing sheet settles it, and `track_rates` in Supabase has said
/// the same since the table was seeded:
///
///   23 May  T8   35 min  -> 1 Hr at 10,500   Comfort Track
///   19 May  T11  60 min  -> 1 Hr at 15,000   Wet Skid Pad Track
///   20 May  T11  30 min  -> 1 Hr at 15,000   Wet Skid Pad Track
///
/// Those three lines are part of May's 1,73,500 of track charges, which
/// ties to INV/26-27/388 exactly. T10 is renamed to match `track_rates`
/// only so it stops colliding with T11 in the picker; its rate has never
/// appeared on an invoice and is left alone.
///
/// T3W 21,000, T3D 19,000 and T1 25,000 were already right. T3W billed
/// 19,000 in March because March fell in FY 2025-26; the card below runs
/// 1 April 2026 to 31 March 2027, so a March figure will not reconcile
/// against it.
///
/// EVERY RATE NOW COMES FROM QUOTATION NATRAX/Q/BIP/26-27/018, 7 Apr 2026.
/// Four were wrong and three tracks were missing entirely:
///
///   T9  Noise Track 20,000        -> Handling Track 2W        5,000
///   T10 Wet Skid Pad 15,000       -> Sustainability Track     6,000
///   T12 Fatigue Track 20,000      -> Suspension & Traction    6,000
///   T13 Gravel & Off-Road 15,000  -> External Noise Track    14,000
///   T4  Test Hill Track (All Gradient)                        8,000  NEW
///   T5  Accelerated Fatigue Track                            14,000  NEW
///   T6  Gravel & Off-Road Track                               7,500  NEW
///
/// The names were wrong as well as the prices: T13 was carrying the gravel
/// track's name, and the gravel track (T6) did not exist, so logging on it
/// meant picking T13 and paying 15,000 for a 7,500 track.
///
/// `track_rates` in Supabase has had all of these right since the very
/// first migration. Only this hardcoded list drifted - the same way T8 and
/// T11 held each other's rate until 15 Sep 2026.
///
/// A day's usage on a track is summed, rounded UP to the whole hour, and
/// then floored at `minHrs`. T1, T2, T3W and T3D carry a two-hour minimum;
/// every other track bills from one hour.
///
/// The split is read off the invoices, not assumed:
///
///   T3W  two-hour  - May bills 41 min and 60 min on separate days as 4 Hrs
///   T2   two-hour  - April bills 35 min on 9 Apr within a 5 Hrs total
///   T3D  two-hour  - per the programme owner; both braking tracks are
///                    two-hour bookings
///   T7   one-hour  - April bills a 30 min day as 1 Hr
///   T8   one-hour  - May bills a 35 min day as 1 Hr
///   T11  one-hour  - May bills a 30 min day as 1 Hr
///
/// April's T3D days argue for one hour: 36, 49 and 50 minutes invoiced as
/// 3 Hrs, where a two-hour minimum gives 6. That is still NOT adopted. The
/// programme owner's position is that both braking tracks are booked on
/// two-hour terms, and booking terms win over arithmetic. Reaffirmed
/// 15 Sep 2026, with the T8/T11 mislabelling above now fixed - so this is a
/// deliberate choice against clean data, no longer a doubt about the data.
///
/// Minimums are NOT on the quotation - it prices per hour and says nothing
/// about a floor. T1, T2, T3W and T3D carry two hours from the booking
/// terms; the rest bill from one, per the programme owner. T12 is the one
/// exception at two hours, also his call.
class NatraxRateCard {
  const NatraxRateCard._();

  static const List<Map<String, dynamic>> tracks = [
    {'code': 'T3W',  'name': 'T3 Wet Braking Track',     'rate': 21000.0, 'minHrs': 2.0},
    {'code': 'T3D',  'name': 'T3 Dry Braking Track',     'rate': 19000.0, 'minHrs': 2.0},
    {'code': 'T1',   'name': 'High Speed Track',          'rate': 25000.0, 'minHrs': 2.0},
    {'code': 'T2',   'name': 'Dynamic Platform Track',    'rate': 20000.0, 'minHrs': 2.0},
    {'code': 'T7',   'name': 'Handling Track 4W (1.6km)', 'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T16',  'name': 'General Road Track',        'rate':  9000.0, 'minHrs': 1.0},
    {'code': 'T8',   'name': 'Comfort Track',             'rate': 10500.0, 'minHrs': 1.0},
    {'code': 'T9',   'name': 'Handling Track 2W',         'rate':  5000.0, 'minHrs': 1.0},
    {'code': 'T10',  'name': 'Sustainability Track',      'rate':  6000.0, 'minHrs': 1.0},
    {'code': 'T11',  'name': 'Wet Skid Pad Track',        'rate': 15000.0, 'minHrs': 1.0},
    {'code': 'T12',  'name': 'Suspension & Traction',      'rate':  6000.0, 'minHrs': 2.0},
    {'code': 'T13',  'name': 'External Noise Track',       'rate': 14000.0, 'minHrs': 1.0},
    {'code': 'T4',   'name': 'Test Hill Track (All Grad.)', 'rate':  8000.0, 'minHrs': 1.0},
    {'code': 'T5',   'name': 'Accelerated Fatigue Track',   'rate': 14000.0, 'minHrs': 1.0},
    {'code': 'T6',   'name': 'Gravel & Off-Road Track',    'rate':  7500.0, 'minHrs': 1.0},
    // ── EXCLUSIVE BOOKINGS ────────────────────────────────────────────────
    // Sold in fixed 2-hour blocks, not by the hour. Quotation
    // NATRAX/Q/BIP/26-27/018, 7 Apr 2026.
    //
    // One entry each rather than separate 2 h and 4 h rows, because every
    // 4-hour price in that quote is exactly twice the 2-hour price - T1 is
    // 1,80,000 and 3,60,000, T2 1,20,000 and 2,40,000, and so on - so a
    // second block gives the 4-hour figure on the nose.
    //
    // `rate` is the BLOCK price, and `blockHrs` is what marks the row as
    // exclusive. minHrs is irrelevant once a block is being charged.
    {'code': 'T1X',  'name': 'High Speed Track (Exclusive)',       'rate': 180000.0, 'minHrs': 0.0, 'blockHrs': 2.0},
    {'code': 'T2X',  'name': 'Dynamic Platform Track (Exclusive)', 'rate': 120000.0, 'minHrs': 0.0, 'blockHrs': 2.0},
    {'code': 'T3X',  'name': 'Braking Track (Exclusive)',          'rate': 150000.0, 'minHrs': 0.0, 'blockHrs': 2.0},
    {'code': 'T7X',  'name': 'Handling Track 4W (Exclusive)',      'rate':  60000.0, 'minHrs': 0.0, 'blockHrs': 2.0},
    {'code': 'T8X',  'name': 'Comfort Track (Exclusive)',          'rate':  48000.0, 'minHrs': 0.0, 'blockHrs': 2.0},
  ];

  static Map<String, dynamic>? _row(String code) {
    final c = code.trim().toUpperCase();
    for (final t in tracks) {
      if (t['code'] == c) return t;
    }
    return null;
  }

  /// Whether [code] is on the card at all.
  static bool knows(String code) => _row(code) != null;

  /// Hourly rate, or the block price for an exclusive code. Zero when the
  /// code is not on the card — the caller must treat that as "not known",
  /// never as "free".
  static double rateFor(String code) =>
      (_row(code)?['rate'] as num?)?.toDouble() ?? 0;

  static String nameFor(String code) =>
      (_row(code)?['name'] as String?) ?? code;

  /// The day floor. One hour for a code the card does not know, which is the
  /// floor NATRAX charge on every track that is not a two-hour booking.
  static double minHoursFor(String code) {
    final r = _row(code);
    if (r == null) return 1;
    return (r['minHrs'] as num).toDouble();
  }

  /// Exclusive bookings are sold in blocks, not hours.
  static bool isExclusive(String code) => _row(code)?['blockHrs'] != null;

  static double blockHoursFor(String code) =>
      (_row(code)?['blockHrs'] as num?)?.toDouble() ?? 0;

  /// What [hours] of an exclusive booking cost: whole blocks, rounded up.
  static double exclusiveCost(String code, double hours) {
    final block = blockHoursFor(code);
    if (block <= 0 || hours <= 0) return 0;
    return (hours / block).ceil() * rateFor(code);
  }

  /// Billable hours for one programme's day, per track code.
  ///
  /// [minutesByCode] is every standard (non-exclusive) code that programme
  /// ran that day. Each code rounds up to whole hours on its own; then any
  /// group sharing one floor — T3 Wet and T3 Dry — is topped up ONCE to that
  /// floor, the shortfall landing on whichever surface ran longest. Two
  /// separate floors would bill the April dry days at six hours where
  /// INV/26-27/205 charges three.
  static Map<String, double> billableForDay(Map<String, int> minutesByCode) {
    final out = <String, double>{};
    minutesByCode.forEach((code, mins) {
      out[code] = TrackCostRules.ceilHours(mins);
    });
    final seenGroups = <String>{};
    // Longest first, so the shortfall sits on the surface that actually ran.
    final codes = minutesByCode.keys.toList()
      ..sort((a, b) => minutesByCode[b]!.compareTo(minutesByCode[a]!));
    for (final code in codes) {
      final group = TrackCostRules.groupFor(code);
      final gk = (List<String>.from(group)..sort()).join('+');
      if (seenGroups.contains(gk)) continue;
      seenGroups.add(gk);
      final floor = group
          .map(minHoursFor)
          .fold<double>(0, (a, b) => a > b ? a : b);
      final covered = group.fold<double>(0, (s, c) => s + (out[c] ?? 0));
      final shortfall = floor - covered;
      if (shortfall > 0) out[code] = (out[code] ?? 0) + shortfall;
    }
    return out;
  }
}

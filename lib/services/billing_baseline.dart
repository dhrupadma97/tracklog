/// The canonical per-month billing figures for each project.
///
/// These were previously duplicated: the Analyser held them per month while
/// the PO Tracker held the same data pre-aggregated, which meant the two
/// screens could drift apart without anything failing. Both now read here.
///
/// Everything in this file is **ex-GST**, matching how session costs and the
/// source workbook (NATRAX_Comprehensive_Billing_Final_V15) record them.
/// These are an *estimate*; an uploaded invoice always outranks them.
library;

class MonthBaseline {
  /// 'YYYY-MM'
  final String month;
  final double trackAndAccessories;
  final double workshopRental;

  const MonthBaseline({
    required this.month,
    required this.trackAndAccessories,
    required this.workshopRental,
  });

  double get exclGst => trackAndAccessories + workshopRental;
  double get gst => exclGst * BillingBaseline.gstRate;
  double get inclGst => exclGst * (1 + BillingBaseline.gstRate);
}

/// A cost that is not attributable to any billing month, and therefore cannot
/// be reconciled against a monthly invoice.
class UnbilledExtra {
  final String label;
  final String detail;
  final double exclGst;

  const UnbilledExtra({
    required this.label,
    required this.detail,
    required this.exclGst,
  });
}

class BillingBaseline {
  const BillingBaseline._();

  /// The rate that applied to the billed months below, evidenced by the
  /// invoices on file: 18% IGST in March, 18% CGST+SGST in April.
  static const double gstRate = 0.18;

  /// The rate assumed when a new invoice is entered.
  ///
  /// GST treatment is a finance decision, so this is only a starting value —
  /// the field stays editable and whatever the invoice prints always wins.
  /// 18% is the default because every invoice received has carried it
  /// (INV/25-26/1869 at IGST, INV/26-27/205 at CGST+SGST). Nil rating under
  /// SEZ Bond / LUT is handled per invoice and per PO rather than by changing
  /// this, since the treatment can differ between them.
  static const double currentGstRate = 0.18;

  /// Mahindra EV PoC — from the V15 workbook.
  ///
  /// March is confirmed exact by invoice INV/25-26/1869 (taxable 1,93,605).
  /// April is confirmed *understated*: invoice INV/26-27/205 bills 11,62,450
  /// taxable against the 11,52,375 below, a 10,075 gap. The figure is left as
  /// the workbook recorded it so the reconciliation can surface the gap rather
  /// than quietly absorb it — the invoice is what draws down the PO either way.
  static const List<MonthBaseline> _mahindraEv = [
    MonthBaseline(
        month: '2026-03', trackAndAccessories: 138605, workshopRental: 55000),
    MonthBaseline(
        month: '2026-04', trackAndAccessories: 1002375, workshopRental: 150000),
    MonthBaseline(
        month: '2026-05', trackAndAccessories: 337739, workshopRental: 40000),
  ];

  /// Costs carried against the project that appear on no monthly invoice.
  ///
  /// They are kept visible rather than deleted, but they are excluded from any
  /// invoice comparison — counting them as drawdown is what made the PO read
  /// as overspent while ~6.4 lakh of it was still available.
  static const List<UnbilledExtra> _mahindraEvExtras = [
    UnbilledExtra(
      label: 'Vehicle Validation Learning',
      detail: 'Learning and testing validation',
      exclGst: 120000,
    ),
    UnbilledExtra(
      label: 'Instrumentation Parts',
      detail: 'Materials and assets upkeeping',
      exclGst: 85000,
    ),
  ];

  static bool isMahindraEv(String project) =>
      project.trim().toLowerCase() == 'mahindra ev poc';

  static List<MonthBaseline> forProject(String project) =>
      isMahindraEv(project) ? _mahindraEv : const [];

  static List<UnbilledExtra> extrasForProject(String project) =>
      isMahindraEv(project) ? _mahindraEvExtras : const [];

  /// Baseline for a single month, or null when that month has no baseline and
  /// live session costs should be used instead.
  static MonthBaseline? monthFor(String project, String month) {
    for (final m in forProject(project)) {
      if (m.month == month) return m;
    }
    return null;
  }

  static double trackAndAccessoriesTotal(String project) =>
      forProject(project).fold(0.0, (s, m) => s + m.trackAndAccessories);

  static double workshopTotal(String project) =>
      forProject(project).fold(0.0, (s, m) => s + m.workshopRental);

  /// The accessories portion of [trackAndAccessoriesTotal] per the V15
  /// workbook (charger, sand bags, refreshments, casual labour…).
  ///
  /// Only used so the PO Tracker can show track time and accessories on
  /// separate lines — invoices bill them together and the sum is what counts.
  static double accessoriesTotal(String project) =>
      isMahindraEv(project) ? 215219 : 0;

  static double extrasTotal(String project) =>
      extrasForProject(project).fold(0.0, (s, e) => s + e.exclGst);

  /// The months the baseline covers — the ones whose live session costs must
  /// be suppressed to avoid double counting.
  static Set<String> coveredMonths(String project) =>
      forProject(project).map((m) => m.month).toSet();
}

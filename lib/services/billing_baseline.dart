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

  /// Fixed track and accessories cost, or null when the month should be costed
  /// from the sessions logged in TrackLog instead.
  ///
  /// Workshop rental is never computed: it is a monthly booking, not something
  /// session records imply, so it stays here even for computed months.
  final double? trackAndAccessories;
  final double workshopRental;

  const MonthBaseline({
    required this.month,
    required this.trackAndAccessories,
    required this.workshopRental,
  });

  /// True when track cost comes from logged sessions rather than this record.
  bool get isTrackComputed => trackAndAccessories == null;

  /// The part of the month this record accounts for. For a computed month
  /// that is the workshop rental alone — callers must add the session cost.
  double get exclGst => (trackAndAccessories ?? 0) + workshopRental;
  double get gst => exclGst * BillingBaseline.gstRate;
  double get inclGst => exclGst * (1 + BillingBaseline.gstRate);

  /// Operational days the rental covers, derived from the flat day rate.
  ///
  /// Derived rather than stored because the rental is what the invoice states
  /// and the days follow from it — storing both invites the two disagreeing.
  double get workshopDays => BillingBaseline.workshopDayRate <= 0
      ? 0
      : workshopRental / BillingBaseline.workshopDayRate;
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

  /// Mahindra EV PoC — from the V15 workbook, corrected against the invoices
  /// actually raised.
  ///
  /// March matches invoice INV/25-26/1869 exactly (taxable 1,93,605).
  ///
  /// April was recorded as 10,02,375 track+accessories, but invoice
  /// INV/26-27/205 bills 11,62,450 taxable — 10,075 more. The invoice is what
  /// draws down the PO, so the workbook figure was the wrong one and has been
  /// brought into line rather than left to show a permanent variance.
  ///
  /// May is still computed; NATRAX has not raised it.
  static const List<MonthBaseline> _mahindraEv = [
    MonthBaseline(
        month: '2026-03', trackAndAccessories: 138605, workshopRental: 55000),
    MonthBaseline(
        month: '2026-04', trackAndAccessories: 1012450, workshopRental: 150000),
    // May's track cost now comes from the sessions logged in TrackLog rather
    // than a fixed figure, so the corrected utilisation feeds through on its
    // own. The workshop rental stays: it is a monthly booking, and no session
    // record implies it.
    MonthBaseline(
        month: '2026-05', trackAndAccessories: null, workshopRental: 40000),
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
      forProject(project).fold(0.0, (s, m) => s + (m.trackAndAccessories ?? 0));

  static double workshopTotal(String project) =>
      forProject(project).fold(0.0, (s, m) => s + m.workshopRental);

  /// Continuous Workshop Flat Rate — 5,000 per operational day.
  ///
  /// This is the rate NATRAX charges, evidenced on INV/25-26/1869 (11 days at
  /// 5,000 for 55,000) and consistent across April (30 days) and May (8 days).
  static const double workshopDayRate = 5000;

  static double workshopDaysTotal(String project) =>
      forProject(project).fold(0.0, (s, m) => s + m.workshopDays);

  /// The workshop was released over the June–July 2026 pause and re-occupied
  /// on 12 August 2026 — which is why those two months carry no row above.
  ///
  /// The period is deliberately open-ended: the bay accrues rental every day
  /// it is held, so the figure is computed as-on rather than frozen into a
  /// month row that would be wrong the next morning. When NATRAX invoices this
  /// period, add it as a normal [MonthBaseline] and clear this date, or the
  /// month will be counted twice.
  static final DateTime workshopResumedOn = DateTime(2026, 8, 12);

  /// Days the workshop has been held since it was re-occupied, counting both
  /// the resumption day and [asOn]. Zero before resumption.
  static int openWorkshopDays(DateTime asOn) {
    final to = DateTime(asOn.year, asOn.month, asOn.day);
    if (to.isBefore(workshopResumedOn)) return 0;
    return to.difference(workshopResumedOn).inDays + 1;
  }

  static double openWorkshopRental(DateTime asOn) =>
      openWorkshopDays(asOn) * workshopDayRate;

  /// The accessories portion of [trackAndAccessoriesTotal] per the V15
  /// workbook (charger, sand bags, refreshments, casual labour…).
  ///
  /// Only used so the PO Tracker can show track time and accessories on
  /// separate lines — invoices bill them together and the sum is what counts.
  static double accessoriesTotal(String project) =>
      isMahindraEv(project) ? 215219 : 0;

  /// The baseline describes track hire, accessories and workshop only, so a
  /// manpower invoice must never be compared against it.
  static const Set<String> baselineCategories = {'track_booking', 'workshop'};

  static double extrasTotal(String project) =>
      extrasForProject(project).fold(0.0, (s, e) => s + e.exclGst);

  /// Months whose live session costs must be suppressed to avoid double
  /// counting — only those carrying a fixed track figure. A month costed from
  /// sessions is deliberately not covered.
  static Set<String> coveredMonths(String project) => forProject(project)
      .where((m) => !m.isTrackComputed)
      .map((m) => m.month)
      .toSet();
}

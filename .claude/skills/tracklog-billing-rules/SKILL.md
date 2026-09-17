---
name: tracklog-billing-rules
description: The billing, muster and attribution rules TrackLog must obey — how NATRAX charges track time, how the 2-hour minimum applies, how manpower and workshop are counted and funded, which project a session belongs to, and which figures are pinned to invoices rather than computed. Use when touching cost calculation, the Analyser, History, Muster, PO Tracker, Manual Entry, invoices, the Excel backup, or any figure shown in rupees or days.
---

# TrackLog billing rules

Money on screen is reconciled against real NATRAX and MOICARS invoices. A figure
that is wrong here is wrong on an invoice. Read this before changing any
calculation.

## The three things NATRAX bills

They are counted differently and funded differently. Never collapse them.

| | Source table | Unit | Drawn against |
|---|---|---|---|
| **Track time** | `engineer_sessions` | hours × track rate | NATRAX track PO |
| **Manpower** | `manpower_muster`, `kind='manpower'` | `SUM(head_count)` man-days | MOICARS PO, contracted **in days** |
| **Workshop** | `manpower_muster`, `kind='workshop'` | `COUNT(rows)` × ₹5,000 | NATRAX **track_booking** PO, lumpsum on actuals |

Workshop rows carry `head_count = 0` always — forced in `MusterDay.toJson()`, so
it can never leak into the manpower sum. Manpower POs have a days-remaining
figure; workshop POs do not, because they are lumpsum and have no contracted day
count to draw down.

Additional services (`session_additional_services`) are **Track + Accessories**,
not workshop. A WORKSHOP service line in Manual Entry is rupees on an invoice;
`kind='workshop'` muster rows are which days. Both exist on purpose. Only the
muster moves the Workshop figure on any screen.

## The 2-hour minimum, and whole hours

NATRAX bills **whole hours, rounded up, per track per day**. Tracks also have a
minimum billable duration (`minHrs`, e.g. T3W = 2 h at ₹21,000).

**The minimum applies once per programme, per track, per day** — confirmed with
Dhrupad, 14 Sep 2026. Each PoC is invoiced separately, so one programme's session
must not satisfy another's minimum or one invoice silently subsidises the other.

Each entry charges only its **marginal** cost:

```
dayTotalMins  = minutesAlreadyLoggedForThisTrackDayProgramme + entryMinutes
billableHours = max(ceil(dayTotalMins / 60), minHrs)
thisCost      = billableHours * rate - costAlreadyBilledThatDay
```

Worked example (T3W, ₹21,000/h, 2 h min) — 8 Sep 2026, which reconciles exactly:
- 125 min first → `max(ceil(2.08), 2)` = 3 hrs → **₹63,000**
- 45 min second → day 170 min → `max(ceil(2.83), 2)` = 3 hrs → **₹0**
- 100 min third → day 270 min → `max(ceil(4.5), 2)` = 5 hrs → **₹42,000**
- Day total **₹1,05,000**

The ₹0 is correct, not a bug: the day had already rounded up before that session
started. The DAY total is what NATRAX invoices; the split across sessions is
internal.

Billing the raw fraction under-charged every part-hour day and was fixed in
`20260914270000_recalc_september_whole_hours.sql`. Charging the minimum per
entry rather than per day is a separate bug that over-billed 8 Sep 2026 by
₹7,000, fixed in `169bc94` (9 Sep 2026); data entered before that may carry it.

### T3 Wet and T3 Dry share one minimum

They are two surfaces of the **same braking track**, and NATRAX applies the
two-hour minimum to the track once a day, not to each surface. Each surface
still rounds up on its own; only the shortfall the pair has not covered between
them is added.

Invoice INV/26-27/205 settles it. April 2026 has exactly three dry days — 7, 8
and 9 April, running 49, 36 and 50 minutes — and wet ran on all three:

```
Braking Track Testing - WET   34 Hrs at 21,000 = 7,14,000
Braking Track Testing - DRY    3 Hrs at 19,000 =   57,000
```

Three dry days billed as 3 Hrs is one hour each — the ceiling of each day's own
time, with no minimum of its own, because wet had already met the day's two
hours. Two separate minimums give 6 Hrs and ₹1,14,000, double what was invoiced.

Dry running **alone** still bills two hours. `_minGroups` in
`manual_entry_screen.dart` holds the pairing; a track with no sibling reduces to
`max(ceil(day), minHrs)` exactly as before.

Ordering caveat: the shortfall lands on whichever surface is entered first, so on
a wet+dry day enter whichever ran first, first.

The same-day lookup must filter by **track_code (or its minimum group), date,
project and venue**. `track_code` is unique per venue, not globally, so an
unscoped match lets a CoASTT layout sharing a code count towards a NATRAX day.

## Which project a session belongs to

`ProjectManager.sessionBelongsTo(sessionProjectName, projectName)` is the single
implementation. Empty, blank, `null` or `'General'` → **Mahindra EV PoC**.

Never re-implement that rule, and never match `project_name` exactly in SQL:
doing so drops every empty/General row from *every* project, and those rows are
the bulk of the history (45 of 50 sessions as of 14 Sep 2026).

The Analyser is scoped to **its own vehicle picker**, deliberately independent of
the globally selected project. Filtering its sessions through `ProjectManager`
while labelling them with the Analyser's own selection is what put May figures
under a vehicle that arrived in September.

## Workshop is a worst-case accrual

Dhrupad books a workshop day for **every** operational day at the full ₹5,000, as
a ceiling. NATRAX has omitted workshop from some months entirely, and the
workshop is used on a **shared basis**, so the real charge is often lower.

**Accrued > invoiced is the normal state.** Never report the gap as money owed in
either direction. Label the figure "accrued / worst case" wherever it is shown.

`WorkshopPosition.balanceExclGst` measures the PO against **invoiced**, not
against days recorded — a day worked draws nothing down until somebody bills it.
Treating accrual as drawdown once made a PO read overspent with ₹6.4 lakh still
on it.

### An invoice is FINAL — retire the assumption it replaces

Confirmed with Dhrupad, 17 Sep 2026: *"though I add workshop charge as a worst
case, if invoicing is done which means that is the final. So remove those
assumptions."*

The worst-case accrual is a **placeholder for a bill that has not arrived**.
Once NATRAX invoices a period, the invoice is the figure of record and the
placeholder must stop — for the whole period, not just the days the invoice
happened to cover.

So if a month is invoiced and the invoice carries fewer workshop days than were
accrued, the difference is **not** owed and must never be shown as outstanding,
flagged for attention, or added to a total. NATRAX has decided what that month
costs. This is the same rule as "accrued > invoiced is the normal state", applied
forward in time instead of backwards.

Worked example. `workshopResumedOn` was 12 Aug 2026 and ran open-ended.
INV/26-27/467 (17 Sep, billing period August) carries 11 workshop days at 5,000
— 20 to 30 August — inside its ₹97,875 ex-GST. August is therefore settled in
full, 12–19 August included, and the accrual restarts only after it.

**Whenever a period is invoiced, move the settled-to date forward.** An accrual
that outlives its invoice asks twice for money already paid, and it reaches the
manager's report as a point needing attention — which is how a wrong figure gets
in front of Harsh.

## Which PO a day books against

**From August 2026 onwards, every resource books to 8242390552**
(`MusterService.kCurrentTrackBookingPo`). NATRAX quote the PO on the invoice and
use the latest one unless something else is explicitly agreed, so a day booked to
a superseded PO can never be invoiced against the PO the invoice will name.

**8242348442 is superseded — never book to it.** It is dropped from the muster
picker outright. Six September workshop days were booked to it by mistake and had
to be moved (`20260914220000_workshop_onto_552.sql`); one of them was a duplicate
of a day already on 552, so 3 Sep 2026 was accruing ₹10,000 for a ₹5,000 day.

**Track, workshop and services all draw the same NATRAX PO.** 8242390552 covers
track time, workshop rental and the S01–S15 service lines together — including
meals (`S08 Refreshment / Lunch`, ₹125 per number; 60 coupons = ₹7,500 were added
to 552). Anything consuming that PO's value must be counted against it, not just
track hours.

Manpower is the separate pool: it books against its MOICARS PO, and this rule is
about the NATRAX track/workshop/services PO only.

**When a PO runs out, roll to the next one in force.**
`MusterService.nextManpowerPo()` picks the earliest PO by `valid_from` that still
has contracted days, and the muster entry sheet defaults to it. 8242356330 hit
exactly its 38 days (28 opening + 10 mustered) with ₹68,400 of ₹68,400 invoiced
while the sheet still defaulted to it — every further day would have been an
overrun with nothing warning about it. 8242399275 (₹1,08,000, 60 days, from
13 Aug 2026) is the successor.

Only day-contracted POs can be shown as exhausted. A lumpsum track PO billed on
actuals has no contracted day count, so it gets no capacity bar rather than an
invented one.

## Session statuses

`kBillableSessionStatuses` = `['completed', 'warning']`. Warning is a finished
session carrying a note of concern and **bills**. Active is still running, its
cost not final, and must not bill. Ten call sites previously filtered on
`'completed'` alone, silently dropping every Warning session from the Analyser,
PO tracker, invoice totals, manager report and e-mail reports at once.

## Pinned figures — deliberate, do not "fix"

These are hardcoded on purpose because they are reconciled against real invoices.
Dhrupad has confirmed they stay:

- `BillingBaseline` — pinned monthly figures for closed Mahindra EV PoC months
- `project_selection_screen.dart` — **`₹17,32,719` / `₹20,44,608.42`** EV totals
- Track rates in `manual_entry_screen.dart` — **rates are fixed and will not
  change**, except the T8/T11 correction of 15 Sep 2026 (they held each other's
  rate; see the file's own doc comment)

Computed figures must never silently drift from these. If a change would make a
pinned month recompute from sessions, say so before making it.

**The EV totals moved once, on 15 Sep 2026, and the old values are not a
target to restore.** They were `₹17,23,719` / `₹20,33,988.42` — ₹9,000 light,
because the original Excel import dropped the 18-May-2026 T16 session (24 min,
1 billable hour at 9,000). That row is on INV/26-27/388 inside the ₹1,73,500 of
May track lines, so the invoice-backed figure has to include it. The same
₹9,000 hole was in the old `session_history_screen.dart` pins of `₹377,739` /
`₹1,152,375` — `₹3,86,739 − 9,000` — which are now gone from that file and
survive only as a comment explaining why a screen must not hardcode live
figures.

The arithmetic that closes it:

```
track from sessions   1,33,000 + 9,66,000 + 1,73,500 = 12,72,500
accessories           BillingBaseline.accessoriesTotal = 2,15,219
                                           Track + Acc = 14,87,719
14,78,719 − 2,15,219 = 12,63,500 ← the track total WITHOUT T16
```

## Half-logged days

A day with muster but no track session, or a session with no muster day, means a
day may be going unbilled. `day_notes` records **why**, one note per day per
project, with a category (`vehicle_downtime`, `track_unavailable`, `weather`,
`instrumentation`, `no_testing_planned`, `not_logged`, `other`) plus an optional
comment. `not_logged` is the only reason that means an entry is still owed.

Both directions matter: an unrecorded man-day never draws down the MOICARS PO and
is never invoiced, the same loss pointing the other way.

## Verification, because the data is not readable from here

`engineer_sessions`, `manpower_muster`, `natrax_invoices` and `po_trackers` are
RLS-protected to authenticated users. The repo holds only the anon key, which
reads zero rows and is refused on write (`42501`).

**Never propose granting `anon` access to fix this.** The anon key ships in plain
text inside the public web bundle, so anything granted to `anon` is public on the
internet.

To reconcile against real data, ask for **Settings → Backup to Excel**. It carries
Sessions, Other Services, Muster, Invoices, POs and a Summary, read through the
same RLS as the app. Manual entries auto-generate it. Read it with the `xlsx`
package in `node_modules` via the node binary (see `reference_machine_toolchain`).

## Before shipping a figure change

1. `flutter analyze lib` — zero errors; the pre-existing issue count is ~332.
2. `flutter test` — 51 tests. `widget_test.dart` fails to compile from a
   pre-existing `email_draft.dart` / `universal_html` `createRange` issue; that
   does not affect web builds.
3. Build with `flutter build web --release --dart-define-from-file=env.json`.
   **Grep the bundle for a string literal** to confirm the change shipped —
   dart2js minifies identifiers, so a missing method name proves nothing.
4. **Bump `version` in `pubspec.yaml`** whenever users must see the change, or
   the service worker keeps serving the old bundle.

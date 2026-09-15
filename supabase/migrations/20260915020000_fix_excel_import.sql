-- Correct the March-May 2026 utilisation import
--
-- The NATRAX utilisation workbook (NATRAX_Comprehensive_Billing_Final_V15,
-- "Detailed Utilisation" + "Daily Track Billing") was imported into
-- engineer_sessions by a script. Durations survived intact; three things did
-- not.
--
-- 1. EVERY SESSION CARRIES hourly_rate = 25,000.
--    That is the T1 High Speed rate, applied to T3 Wet, T3 Dry, T2, T7, T8 and
--    T11 alike. Costs were then computed as a flat minutes/60 x 25,000 with no
--    whole-hour rounding and no minimum, so not one of the 45 rows is right.
--
-- 2. EVERY TIMESTAMP IS +5:30.
--    The importer wrote IST wall-clock values as if they were UTC. The 24-Mar
--    session runs 12:30-16:30 in the workbook and 18:00-22:00 in the app. One
--    row crossed midnight as a result: 08-Apr 18:35 T2 is stored on 09-Apr at
--    00:05, moving 35 minutes onto the wrong day.
--
-- 3. ONE ROW NEVER ARRIVED.
--    18-May-2026, T16, 14:57-15:21, 24 min, 1 billable hour at 9,000. It is on
--    invoice INV/26-27/388 -- it is part of the 1,73,500 of May track lines --
--    so TrackLog has been a session and 9,000 short for May since the import.
--
-- Costs below come from the workbook's own "Daily Track Billing" sheet, which
-- already applies NATRAX's whole-hour rounding and per-track minimum, and is
-- the sheet the invoices reconcile against. Within a day the day's cost is
-- apportioned marginally in start-time order, matching how Manual Entry costs
-- a new entry (see 20260914270000_recalc_september_whole_hours.sql). Eleven
-- rows therefore come out at zero: the day had already rounded up before that
-- session started. That is correct -- the DAY total is what NATRAX invoices.
--
-- Month totals after this runs, all ex-GST:
--   2026-03   1,33,000  -> + 5,605 accessories = 1,38,605, invoice INV/25-26/1869
--   2026-04   9,66,000  -> the workbook April figure quoted in BillingBaseline
--   2026-05   1,73,500  -> the five track lines on invoice INV/26-27/388
--
-- NONE OF THOSE THREE MONTHS MOVES ON SCREEN. All three are pinned in
-- BillingBaseline with a non-null trackAndAccessories, so the Analyser and PO
-- Tracker read the pinned figure and ignore session cost for them. What this
-- changes is the Daily Log, the session lists and any future recompute -- the
-- rows stop claiming a T8 hour cost 25,000.
--
-- Safe to re-run: every statement is keyed on the corrected value.

BEGIN;

-- SET LOCAL needs a transaction, so it sits inside BEGIN. With the zone
-- pinned to UTC the comparisons below read the same whoever runs this, and
-- they work whether started_at is timestamptz or a bare timestamp.
SET LOCAL TimeZone = 'UTC';

-- Order matters. The rows are matched on their CURRENT (shifted) timestamps
-- first and moved afterwards -- rendered in UTC, a shifted row still shows
-- the workbook's own clock time, which is what makes it findable. Correct
-- the clock first and every key below would miss.
--
-- Both steps are gated on the importer's original note, which step 4
-- rewrites, so a second run is a no-op rather than a second -5:30 shift.

-- ── 1. Correct track, rate and cost ────────────────────────────────────────
-- The two March rows price T3W at 19,000, not the 21,000 used from April.
-- That is not an error and must not be "corrected": March 2026 fell in the
-- PREVIOUS FINANCIAL YEAR and NATRAX billed it on the FY 2025-26 rate card.
-- The invoice numbers carry the split on their face --
--   March  INV/25-26/1869      <- FY 2025-26 card, T3W at 19,000
--   April  INV/26-27/205       <- FY 2026-27 card, T3W at 21,000
--   May    INV/26-27/388       <- same FY 2026-27 card
-- At 21,000 March comes to 1,47,000 and stops matching invoice 1869.
--
-- The FY 2026-27 card then holds from 1 April 2026 to 31 March 2027, so
-- April, May, June and every month after run on the SAME rates the app
-- already has. 31 March 2026 is the only rate boundary in the data.
--
-- NOTE: the current card EXPIRES 31 MARCH 2027 and the next one takes effect
-- 1 April 2027. Neither track_rates nor the hardcoded table in
-- manual_entry_screen.dart can express a rate that applies only between two
-- dates -- track_rates has is_active and no period columns at all. Nothing
-- breaks until the next card lands, but when it does, every historical
-- session reprices unless dates are added first.
WITH fix(start_local, code, tname, mins, rate, cost) AS (VALUES
  ('2026-03-24 12:30:00', 'T3W', 'T3 Wet Braking Track', 240, 19000, 76000),
  ('2026-03-25 11:30:00', 'T3W', 'T3 Wet Braking Track', 180, 19000, 57000),
  ('2026-04-07 14:57:00', 'T3D', 'T3 Dry Braking Track', 12, 19000, 19000),
  ('2026-04-07 15:10:00', 'T3W', 'T3 Wet Braking Track', 23, 21000, 42000),
  ('2026-04-07 15:57:00', 'T3D', 'T3 Dry Braking Track', 37, 19000, 0),
  ('2026-04-07 16:35:00', 'T3W', 'T3 Wet Braking Track', 67, 21000, 0),
  ('2026-04-08 11:59:00', 'T3D', 'T3 Dry Braking Track', 36, 19000, 19000),
  ('2026-04-08 12:36:00', 'T3W', 'T3 Wet Braking Track', 86, 21000, 42000),
  ('2026-04-08 16:06:00', 'T3W', 'T3 Wet Braking Track', 85, 21000, 21000),
  ('2026-04-08 18:00:00', 'T7', 'Handling Track 4W (1.6km)', 30, 15000, 15000),
  ('2026-04-08 18:35:00', 'T2', 'Dynamic Platform Track', 35, 20000, 40000),
  ('2026-04-09 10:00:00', 'T3D', 'T3 Dry Braking Track', 50, 19000, 19000),
  ('2026-04-09 10:51:00', 'T3W', 'T3 Wet Braking Track', 184, 21000, 84000),
  ('2026-04-09 16:06:00', 'T3W', 'T3 Wet Braking Track', 169, 21000, 42000),
  ('2026-04-10 09:03:00', 'T3W', 'T3 Wet Braking Track', 132, 21000, 63000),
  ('2026-04-10 12:30:00', 'T2', 'Dynamic Platform Track', 100, 20000, 40000),
  ('2026-04-10 15:20:00', 'T2', 'Dynamic Platform Track', 60, 20000, 20000),
  ('2026-04-10 16:48:00', 'T3W', 'T3 Wet Braking Track', 58, 21000, 21000),
  ('2026-04-14 10:30:00', 'T3W', 'T3 Wet Braking Track', 190, 21000, 84000),
  ('2026-04-14 14:50:00', 'T3W', 'T3 Wet Braking Track', 89, 21000, 21000),
  ('2026-04-15 07:05:00', 'T3W', 'T3 Wet Braking Track', 135, 21000, 63000),
  ('2026-04-17 01:06:00', 'T7', 'Handling Track 4W (1.6km)', 21, 15000, 15000),
  ('2026-04-17 02:36:00', 'T7', 'Handling Track 4W (1.6km)', 23, 15000, 0),
  ('2026-04-17 03:13:00', 'T1', 'High Speed Track', 20, 25000, 50000),
  ('2026-04-17 03:58:00', 'T7', 'Handling Track 4W (1.6km)', 20, 15000, 15000),
  ('2026-04-17 04:22:00', 'T1', 'High Speed Track', 23, 25000, 0),
  ('2026-04-17 10:46:00', 'T1', 'High Speed Track', 20, 25000, 0),
  ('2026-04-17 11:59:00', 'T1', 'High Speed Track', 22, 25000, 0),
  ('2026-04-17 12:30:00', 'T1', 'High Speed Track', 20, 25000, 0),
  ('2026-04-26 08:30:00', 'T3W', 'T3 Wet Braking Track', 118, 21000, 42000),
  ('2026-04-26 11:45:00', 'T3W', 'T3 Wet Braking Track', 39, 21000, 21000),
  ('2026-04-26 13:58:00', 'T3W', 'T3 Wet Braking Track', 137, 21000, 42000),
  ('2026-04-27 10:00:00', 'T3W', 'T3 Wet Braking Track', 120, 21000, 42000),
  ('2026-04-28 09:12:00', 'T3W', 'T3 Wet Braking Track', 46, 21000, 42000),
  ('2026-04-28 10:08:00', 'T3W', 'T3 Wet Braking Track', 150, 21000, 42000),
  ('2026-04-28 16:20:00', 'T3W', 'T3 Wet Braking Track', 17, 21000, 0),
  ('2026-05-19 15:00:00', 'T11', 'Wet Skid Pad Track', 60, 15000, 15000),
  ('2026-05-20 15:00:00', 'T11', 'Wet Skid Pad Track', 30, 15000, 15000),
  ('2026-05-22 12:05:00', 'T2', 'Dynamic Platform Track', 46, 20000, 40000),
  ('2026-05-22 14:30:00', 'T2', 'Dynamic Platform Track', 30, 20000, 0),
  ('2026-05-23 01:25:00', 'T8', 'Comfort Track', 5, 10500, 10500),
  ('2026-05-23 08:37:00', 'T3W', 'T3 Wet Braking Track', 19, 21000, 42000),
  ('2026-05-23 09:00:00', 'T8', 'Comfort Track', 30, 10500, 0),
  ('2026-05-23 13:34:00', 'T3W', 'T3 Wet Braking Track', 22, 21000, 0),
  ('2026-05-25 12:00:00', 'T3W', 'T3 Wet Braking Track', 60, 21000, 42000))
UPDATE public.engineer_sessions s
   SET track_code  = f.code,
       track_name  = f.tname,
       hourly_rate = f.rate,
       total_cost  = f.cost
  FROM fix f
 WHERE s.notes LIKE 'Imported via%'
   AND (s.started_at AT TIME ZONE 'UTC') = f.start_local::timestamp
   AND s.duration_minutes = f.mins;

-- ── 2. Undo the +5:30 shift ────────────────────────────────────────────────
UPDATE public.engineer_sessions
   SET started_at = started_at - INTERVAL '5 hours 30 minutes',
       ended_at   = ended_at   - INTERVAL '5 hours 30 minutes'
 WHERE notes LIKE 'Imported via%';

-- ── 3. The row that never arrived ──────────────────────────────────────────
-- 18-May-2026 T16 14:57-15:21. engineer_id, venue and project_name are copied
-- from a sibling imported row so ownership matches the rest of the import --
-- a guessed engineer_id would leave the row invisible under RLS.
INSERT INTO public.engineer_sessions
       (engineer_id, venue, track_code, track_name, project_name,
        started_at, ended_at, duration_minutes, hourly_rate, total_cost,
        session_status, notes)
SELECT src.engineer_id, src.venue, 'T16', 'General Road Track',
       src.project_name,
       TIMESTAMPTZ '2026-05-18 14:57+05:30',
       TIMESTAMPTZ '2026-05-18 15:21+05:30',
       24, 9000, 9000, 'completed',
       'Imported from NATRAX utilisation workbook - added 15-Sep-2026, '
       'missing from the original import'
  FROM public.engineer_sessions src
 WHERE src.notes LIKE 'Imported%'
   AND NOT EXISTS (SELECT 1 FROM public.engineer_sessions t
                    WHERE t.track_code = 'T16'
                      AND t.started_at = TIMESTAMPTZ '2026-05-18 14:57+05:30')
 ORDER BY src.started_at
 LIMIT 1;

-- ── 4. Re-mark the rows so steps 1-2 cannot run twice ──────────────────────
UPDATE public.engineer_sessions
   SET notes = 'Imported from NATRAX utilisation workbook - '
               'corrected 15-Sep-2026 (rate, +5:30 clock shift)'
 WHERE notes LIKE 'Imported via%';

COMMIT;

-- ── Verification ───────────────────────────────────────────────────────────
-- Every `actual` must equal `expected`. Times are read back in IST, which is
-- what the app displays and what the workbook records.
WITH imp AS (
  SELECT *, (started_at AT TIME ZONE 'Asia/Kolkata') AS ist
    FROM public.engineer_sessions
   WHERE notes LIKE 'Imported%'
)
SELECT * FROM (VALUES
  ('started_at column type',
   (SELECT data_type FROM information_schema.columns
     WHERE table_schema='public' AND table_name='engineer_sessions'
       AND column_name='started_at'),
   'timestamp with time zone'),
  ('sessions imported Mar-May 2026',
   (SELECT COUNT(*)::TEXT FROM imp),
   '46 - was 45, the 18-May T16 row is restored'),
  ('March 2026 track cost',
   (SELECT COALESCE(SUM(total_cost),0)::BIGINT::TEXT FROM imp
     WHERE ist::date BETWEEN DATE '2026-03-01' AND DATE '2026-03-31'),
   '133000 - plus 5,605 accessories = 1,38,605 on INV/25-26/1869'),
  ('April 2026 track cost',
   (SELECT COALESCE(SUM(total_cost),0)::BIGINT::TEXT FROM imp
     WHERE ist::date BETWEEN DATE '2026-04-01' AND DATE '2026-04-30'),
   '966000 - the workbook April figure quoted in BillingBaseline'),
  ('May 2026 track cost',
   (SELECT COALESCE(SUM(total_cost),0)::BIGINT::TEXT FROM imp
     WHERE ist::date BETWEEN DATE '2026-05-01' AND DATE '2026-05-31'),
   '173500 - the track lines on INV/26-27/388'),
  ('rows still priced at a flat 25,000',
   (SELECT COUNT(*)::TEXT FROM imp WHERE hourly_rate = 25000 AND track_code <> 'T1'),
   '0 - 25,000 is the T1 rate and belongs only to T1'),
  ('18-May T16 session present',
   (SELECT COUNT(*)::TEXT FROM imp WHERE track_code = 'T16'),
   '1'),
  ('earliest clock time',
   (SELECT TO_CHAR(MIN(ist::time), 'HH24:MI') FROM imp),
   '01:06 - the 17-Apr T7 run, as the workbook has it'),
  ('midnight straggler moved off 09-Apr',
   (SELECT COUNT(*)::TEXT FROM imp
     WHERE ist::date = DATE '2026-04-09' AND ist::time = TIME '00:05'),
   '0 - those 35 minutes belong to 08-Apr 18:35')
) AS v(check_name, actual, expected);

-- Recalculate September track cost to whole billable hours
--
-- NATRAX bills whole hours, rounded up, per track per day. Verified against
-- invoice INV/26-27/205 (April 2026): 30.75 h of wet braking across ten days
-- invoiced as 34 Hrs, which is exactly the sum of each day rounded up. Dry
-- braking and 4W handling reconcile the same way, and the invoice totals to
-- the rupee. INV/26-27/388 (May) confirms the same shape.
--
-- The app had been billing the fraction, which under-charged every part-hour
-- day. September was quoted at Rs 1,85,850 where NATRAX will invoice
-- Rs 2,10,000 -- Rs 24,150 short.
--
--   8 Sep  270 min = 4.50 h -> 5 Hrs = Rs 1,05,000  (was Rs 94,500)
--   9 Sep   79 min = 1.32 h -> 2 Hrs = Rs   42,000  (unchanged)
--  10 Sep  141 min = 2.35 h -> 3 Hrs = Rs   63,000  (was Rs 49,350)
--
-- Within a day the cost is apportioned marginally, in start-time order: each
-- session carries what it added to the day's billable hours. That is how the
-- app computes a new entry, so stored rows and freshly entered ones agree.
--
-- It does mean the 19:25 session on 8 September becomes Rs 0: the day had
-- already rounded up to 3 hours before it started, and 45 more minutes did
-- not reach a 4th. The DAY total is what NATRAX invoices; the split across
-- sessions is internal. Do not "fix" that zero -- it would break the day.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, started_at::date AS day, track_code,
       started_at::time AS start_time, duration_minutes, total_cost
  FROM public.engineer_sessions
 WHERE started_at::date BETWEEN DATE '2026-09-01' AND DATE '2026-09-30'
 ORDER BY started_at;

-- ── 8 September: 3 sessions, day = 5 billable hours ─────────────────────────
UPDATE public.engineer_sessions SET total_cost = 63000
 WHERE started_at::date = DATE '2026-09-08'
   AND track_code = 'T3W' AND duration_minutes = 125;

UPDATE public.engineer_sessions SET total_cost = 0
 WHERE started_at::date = DATE '2026-09-08'
   AND track_code = 'T3W' AND duration_minutes = 45;

UPDATE public.engineer_sessions SET total_cost = 42000
 WHERE started_at::date = DATE '2026-09-08'
   AND track_code = 'T3W' AND duration_minutes = 100;

-- ── 10 September: 2 sessions, day = 3 billable hours ────────────────────────
UPDATE public.engineer_sessions SET total_cost = 21000
 WHERE started_at::date = DATE '2026-09-10'
   AND track_code = 'T3W' AND duration_minutes = 10;

UPDATE public.engineer_sessions SET total_cost = 42000
 WHERE started_at::date = DATE '2026-09-10'
   AND track_code = 'T3W' AND duration_minutes = 131;

-- 9 September already bills 2 Hrs at Rs 42,000 and is left alone.

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('8 Sep day total',
   (SELECT COALESCE(SUM(total_cost),0)::TEXT FROM public.engineer_sessions
     WHERE started_at::date = DATE '2026-09-08' AND track_code = 'T3W'),
   '105000 — 5 Hrs x 21,000'),
  ('9 Sep day total',
   (SELECT COALESCE(SUM(total_cost),0)::TEXT FROM public.engineer_sessions
     WHERE started_at::date = DATE '2026-09-09' AND track_code = 'T3W'),
   '42000 — 2 Hrs x 21,000'),
  ('10 Sep day total',
   (SELECT COALESCE(SUM(total_cost),0)::TEXT FROM public.engineer_sessions
     WHERE started_at::date = DATE '2026-09-10' AND track_code = 'T3W'),
   '63000 — 3 Hrs x 21,000'),
  ('September track total',
   (SELECT COALESCE(SUM(total_cost),0)::TEXT FROM public.engineer_sessions
     WHERE started_at::date BETWEEN DATE '2026-09-01' AND DATE '2026-09-30'),
   '210000'),
  ('every September day is a whole number of hours',
   (SELECT COALESCE(STRING_AGG(d::TEXT, ', '), 'none') FROM (
      SELECT started_at::date AS d, SUM(total_cost) c, MAX(hourly_rate) r
        FROM public.engineer_sessions
       WHERE started_at::date BETWEEN DATE '2026-09-01' AND DATE '2026-09-30'
       GROUP BY started_at::date
      HAVING MOD((SUM(total_cost))::numeric, MAX(hourly_rate)::numeric) <> 0) x),
   'none — each day divides exactly by the hourly rate')
) AS v(check_name, actual, expected);

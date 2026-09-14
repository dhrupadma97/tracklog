-- Correct the 2-hour minimum charged twice on 8 September 2026
--
-- Two T3W sessions ran that day on Mahindra ICE PoC. Both were entered before
-- the per-day minimum rule landed (169bc94, 9 Sep 2026), so each was charged
-- its own 2-hour minimum:
--
--   14:30  125 min  Rs 43,750   (2.083 h -- above the minimum, correct)
--   20:36  100 min  Rs 42,000   (1.667 h billed as 2 h -- the minimum again)
--                   ---------
--                   Rs 85,750   billed as 4.083 h
--
-- T3W is Rs 21,000/h with a 2-hour minimum, and the minimum applies once per
-- track per programme per day. The day is 225 minutes = 3.75 h, so it should
-- bill 3.75 x 21,000 = Rs 78,750. NATRAX was over-charged Rs 7,000.
--
-- The first session by start time already exceeds the minimum on its own and
-- stays as it is. The second carries the marginal time only:
--
--   (3.75 - 2.083) h x 21,000 = 1.667 h x 21,000 = Rs 35,000
--
-- Only the later session is touched. Scoped on date, track, duration and the
-- exact wrong figure, so it cannot match anything else.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, id, started_at, track_code, duration_minutes,
       hourly_rate, total_cost, project_name
  FROM public.engineer_sessions
 WHERE started_at::date = DATE '2026-09-08'
   AND track_code = 'T3W'
 ORDER BY started_at;

-- ── Correct the later session ───────────────────────────────────────────────
UPDATE public.engineer_sessions
   SET total_cost = 35000,
       notes = COALESCE(NULLIF(TRIM(notes), ''), 'Manual entry')
               || ' — cost corrected 14-Sep-2026: the 2 h minimum had been '
               || 'charged twice for this track on this day'
 WHERE started_at::date = DATE '2026-09-08'
   AND track_code       = 'T3W'
   AND duration_minutes = 100
   AND total_cost       = 42000;

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('8 Sep T3W day total',
   (SELECT COALESCE(SUM(total_cost), 0)::TEXT FROM public.engineer_sessions
     WHERE started_at::date = DATE '2026-09-08' AND track_code = 'T3W'),
   '78750'),
  ('8 Sep T3W minutes',
   (SELECT COALESCE(SUM(duration_minutes), 0)::TEXT
      FROM public.engineer_sessions
     WHERE started_at::date = DATE '2026-09-08' AND track_code = 'T3W'),
   '225 — 3.75 h'),
  ('day total matches hours x rate',
   (SELECT CASE WHEN ROUND(SUM(duration_minutes) / 60.0 * 21000) =
                     ROUND(SUM(total_cost))
                THEN 'yes' ELSE 'NO — investigate' END
      FROM public.engineer_sessions
     WHERE started_at::date = DATE '2026-09-08' AND track_code = 'T3W'),
   'yes'),
  ('other days charging a minimum twice',
   (SELECT COALESCE(STRING_AGG(d::TEXT || ' ' || tc, ', '), 'none')
      FROM (
        SELECT started_at::date AS d, track_code AS tc
          FROM public.engineer_sessions
         WHERE session_status IN ('completed', 'warning')
         GROUP BY started_at::date, track_code, project_name
        HAVING COUNT(*) > 1
           AND SUM(total_cost) > ROUND(SUM(duration_minutes) / 60.0 * MAX(hourly_rate)) + 1
      ) x),
   'none — any listed here are the same bug on another day')
) AS v(check_name, actual, expected);

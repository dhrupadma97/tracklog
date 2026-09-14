-- Remove the 'dummy' test session
--
-- One row, 10 Jun 2026, T1, zero duration, zero cost, status 'active', filed
-- under a project called 'dummy'. It is the only non-completed session in the
-- table and the only row whose project is not a real programme, so it shows up
-- as a fourth PoC anywhere sessions are grouped by project.
--
-- Confirmed with Dhrupad on 14 Sep 2026 as a test row to delete.
--
-- Scoped tightly on purpose: project_name AND status AND zero cost AND zero
-- duration. A DELETE on project_name alone would be one typo away from taking
-- real rows with it.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, id, started_at, track_code, project_name,
       session_status, duration_minutes, total_cost
  FROM public.engineer_sessions
 WHERE TRIM(LOWER(project_name)) = 'dummy';

-- ── Delete ──────────────────────────────────────────────────────────────────
DELETE FROM public.engineer_sessions
 WHERE TRIM(LOWER(project_name)) = 'dummy'
   AND session_status = 'active'
   AND COALESCE(duration_minutes, 0) = 0
   AND COALESCE(total_cost, 0) = 0;

-- ── Verification ────────────────────────────────────────────────────────────
-- Self-reports rather than leaving it to be checked by hand.
SELECT * FROM (VALUES
  ('dummy rows remaining',
   (SELECT COUNT(*)::TEXT FROM public.engineer_sessions
     WHERE TRIM(LOWER(project_name)) = 'dummy'),
   '0'),
  ('non-completed sessions remaining',
   (SELECT COALESCE(STRING_AGG(session_status || '=' || n::TEXT, ', '
                               ORDER BY session_status), 'none')
      FROM (SELECT session_status, COUNT(*) n
              FROM public.engineer_sessions
             WHERE session_status <> 'completed'
             GROUP BY session_status) s),
   'none, or only genuinely running sessions'),
  ('total sessions',
   (SELECT COUNT(*)::TEXT FROM public.engineer_sessions),
   '49 if the 14-Sep-2026 backup of 50 was accurate')
) AS v(check_name, actual, expected);

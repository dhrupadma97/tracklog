-- ============================================================
-- NATRAX TrackLog: let engineers read all session services
-- Migration: 20260915040000_services_visibility.sql
-- ============================================================
--
-- THE BUG, in one line: 20260521120000 gave engineer_sessions a
-- "view all" policy and never gave session_additional_services the
-- matching one.
--
-- engineer_sessions carries TWO policies, and RLS ORs them together:
--
--   engineers_manage_own_sessions   FOR ALL     USING (engineer_id = auth.uid())
--   Engineers can view all sessions FOR SELECT  USING (true)
--
-- session_additional_services carries ONE:
--
--   engineers_manage_own_session_services  FOR ALL
--     USING (session_id IN (SELECT id FROM engineer_sessions
--                            WHERE engineer_id = auth.uid()))
--
-- So a service row is readable only by the engineer who owns its parent
-- session. The 24 historical rows hang off sessions imported under a
-- different engineer_id, and there is no permissive policy to fall back on
-- -- so every screen reads zero while the rows sit there in the table.
--
-- That is why the Analyser, PO Tracker, manager report and the Excel backup
-- have all shown no accessories: the backup's "Other Services" sheet came
-- out with 0 rows against 24 in the table.
--
-- This mirrors the 21-May fix exactly: SELECT only, `authenticated` only.
-- Writes stay restricted to your own sessions, because the FOR ALL policy
-- above still governs INSERT, UPDATE and DELETE.
--
-- It grants nothing that engineer_sessions does not already grant -- a
-- service line is a cost row on a session every engineer can already read,
-- and this is a single-company app. `anon` is NOT granted anything here; the
-- anon key ships inside the public web bundle, so anything granted to it
-- would be public on the internet.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'session_additional_services'
       AND policyname = 'Engineers can view all session services'
  ) THEN
    CREATE POLICY "Engineers can view all session services"
      ON public.session_additional_services
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END
$$;

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('read policies on session_additional_services',
   (SELECT STRING_AGG(policyname || ' [' || cmd || ']', '  |  ' ORDER BY policyname)
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'session_additional_services'),
   'the FOR ALL one, plus the new SELECT one'),
  ('rows an engineer can now read',
   (SELECT COUNT(*)::TEXT FROM public.session_additional_services),
   '24 - all of them, not 0'),
  ('total accessories value (excl GST)',
   (SELECT TO_CHAR(COALESCE(SUM(total_cost), 0), 'FM9,99,99,999')
      FROM public.session_additional_services),
   'should match the workbook Other Services Log'),
  ('anon still has no policy (must stay this way)',
   (SELECT COUNT(*)::TEXT FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename  = 'session_additional_services'
       AND 'anon' = ANY(roles)),
   '0')
) AS v(check_name, actual, expected);

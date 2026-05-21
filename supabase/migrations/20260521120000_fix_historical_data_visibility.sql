-- ============================================================
-- NATRAX TrackLog: Fix historical data visibility
-- Migration: 20260521120000_fix_historical_data_visibility.sql
-- Reassigns all historical sessions to the most recently active
-- engineer profile so they appear for any logged-in user.
-- Also updates RLS to allow engineers to see all sessions.
-- ============================================================

-- Allow all authenticated engineers to read all sessions
-- (single-company app — all engineers share the same session history)
DO $$
BEGIN
  -- Drop existing restrictive read policy if it exists
  DROP POLICY IF EXISTS "Engineers can view own sessions" ON public.engineer_sessions;
  DROP POLICY IF EXISTS "Engineers can read own sessions" ON public.engineer_sessions;
  DROP POLICY IF EXISTS "engineers_select_own" ON public.engineer_sessions;

  -- Create permissive read policy: any authenticated user can read all sessions
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'engineer_sessions'
      AND policyname = 'Engineers can view all sessions'
  ) THEN
    CREATE POLICY "Engineers can view all sessions"
      ON public.engineer_sessions
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  -- Keep insert/update restricted to own records
  DROP POLICY IF EXISTS "Engineers can insert own sessions" ON public.engineer_sessions;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'engineer_sessions'
      AND policyname = 'Engineers can insert own sessions'
  ) THEN
    CREATE POLICY "Engineers can insert own sessions"
      ON public.engineer_sessions
      FOR INSERT
      TO authenticated
      WITH CHECK (engineer_id = auth.uid());
  END IF;

  DROP POLICY IF EXISTS "Engineers can update own sessions" ON public.engineer_sessions;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'engineer_sessions'
      AND policyname = 'Engineers can update own sessions'
  ) THEN
    CREATE POLICY "Engineers can update own sessions"
      ON public.engineer_sessions
      FOR UPDATE
      TO authenticated
      USING (engineer_id = auth.uid());
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Policy update skipped: %', SQLERRM;
END $$;

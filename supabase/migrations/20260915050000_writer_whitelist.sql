-- ============================================================
-- NATRAX TrackLog: only named owners may write. Everyone else reads.
-- Migration: 20260915050000_writer_whitelist.sql
-- ============================================================
--
-- Dhrupad, 15 Sep 2026: dhrupad_ma@goodyear.com is the other owner; anyone
-- else operating the app gets read-only access and no Manual Entry, unless
-- he changes it.
--
-- WHAT WAS WRONG: engineer_profiles.user_role defaults to 'engineer', and
-- 'engineer' is exactly the role the write policies allow. So every new
-- sign-up got full write access to sessions, muster, invoices and POs by
-- default. engineer_sessions did not even check the role -- its policy is
-- `engineer_id = auth.uid()`, so any authenticated user could create
-- sessions. Hiding the Manual Entry tab would not have stopped that: the
-- anon key is in the public web bundle, so anyone signed in could write
-- straight to PostgREST.
--
-- THE LIST LIVES IN A TABLE WITH NO WRITE POLICY. That is deliberate.
-- engineer_profiles carries `engineers_manage_own_profile FOR ALL
-- USING (id = auth.uid())`, so had the flag lived there, any user could have
-- granted it to themselves with a single UPDATE. public.tracklog_writers is
-- readable by authenticated users and writable by NO ONE through the API --
-- only the SQL editor and service_role, which bypass RLS, can change it.
--
-- TO GRANT OR REVOKE ACCESS LATER, in the Supabase SQL editor:
--   INSERT INTO public.tracklog_writers (email, note)
--        VALUES ('someone@goodyear.com', 'why') ON CONFLICT DO NOTHING;
--   DELETE FROM public.tracklog_writers WHERE email = 'someone@goodyear.com';
--
-- Matching is by EMAIL, not user id, so an owner who has not signed up yet
-- gets write access automatically the moment they do.

BEGIN;

CREATE TABLE IF NOT EXISTS public.tracklog_writers (
  email      TEXT PRIMARY KEY,
  note       TEXT,
  added_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.tracklog_writers ENABLE ROW LEVEL SECURITY;

-- Readable so the app can tell whether to show write controls. No INSERT,
-- UPDATE or DELETE policy exists, and that omission is the security boundary.
DROP POLICY IF EXISTS "authenticated_read_tracklog_writers" ON public.tracklog_writers;
CREATE POLICY "authenticated_read_tracklog_writers"
  ON public.tracklog_writers FOR SELECT TO authenticated USING (true);

INSERT INTO public.tracklog_writers (email, note) VALUES
  ('dhrupadma97@gmail.com',   'owner - Dhrupad, primary account'),
  ('dhrupad_ma@goodyear.com', 'owner - Dhrupad, Goodyear account')
ON CONFLICT (email) DO NOTHING;

-- SECURITY DEFINER so it can read auth.users, which authenticated cannot.
-- search_path is pinned: without it, a user-created schema earlier on the
-- path could shadow `tracklog_writers` and the function would trust the
-- wrong table.
CREATE OR REPLACE FUNCTION public.can_write_tracklog()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM auth.users u
      JOIN public.tracklog_writers w
        ON lower(w.email) = lower(u.email)
     WHERE u.id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.can_write_tracklog() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_write_tracklog() TO authenticated;

COMMIT;

-- ── Every data table: read for all, write for owners only ──────────────────
-- A read policy is created BEFORE the write policy is narrowed, so a
-- read-only user never loses sight of a table. Several of these tables had
-- only a FOR ALL policy and no separate SELECT one.
DO $$
DECLARE
  t TEXT;
  tables TEXT[] := ARRAY[
    'engineer_sessions', 'session_additional_services', 'manpower_muster',
    'day_notes', 'natrax_invoices', 'po_trackers', 'monthly_invoices',
    'daily_billing_summaries', 'rental_instruments', 'sand_bag_rentals',
    'instrumentation_configs', 'dbc_files', 'project_updates',
    'test_resources', 'email_report_subscriptions', 'email_send_log'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = t) THEN
      RAISE NOTICE 'skipping %, table not present', t;
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    -- Read: everyone signed in.
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   'authenticated_read_' || t, t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated '
                   || 'USING (true)', 'authenticated_read_' || t, t);

    -- Write: owners only. Every prior write policy is dropped by name, or it
    -- would keep granting access alongside the new one -- RLS ORs policies
    -- together, so leaving one behind silently defeats this whole migration.
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   'engineers_manage_' || t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   'engineers_manage_own_' || t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   'authenticated_manage_' || t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
                   'writers_manage_' || t, t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
                   || 'USING (public.can_write_tracklog()) '
                   || 'WITH CHECK (public.can_write_tracklog())',
                   'writers_manage_' || t, t);
  END LOOP;
END
$$;

-- Write policies whose names do not follow the pattern the loop drops.
-- RLS ORs policies together, so one left behind silently defeats the whole
-- migration. The loop has already created the read policy for each of these
-- tables, so only write policies are dropped here.
DROP POLICY IF EXISTS "engineers_manage_own_sessions"           ON public.engineer_sessions;
DROP POLICY IF EXISTS "Engineers can insert own sessions"       ON public.engineer_sessions;
DROP POLICY IF EXISTS "Engineers can update own sessions"       ON public.engineer_sessions;
DROP POLICY IF EXISTS "engineers_manage_own_session_services"   ON public.session_additional_services;
DROP POLICY IF EXISTS "engineers_manage_manpower_muster"        ON public.manpower_muster;
DROP POLICY IF EXISTS "engineers_manage_day_notes"              ON public.day_notes;
DROP POLICY IF EXISTS "engineers_manage_natrax_invoices"        ON public.natrax_invoices;
DROP POLICY IF EXISTS "engineers_manage_po_trackers"            ON public.po_trackers;
DROP POLICY IF EXISTS "authenticated_manage_email_subs"         ON public.email_report_subscriptions;
DROP POLICY IF EXISTS "authenticated_insert_email_log"          ON public.email_send_log;
DROP POLICY IF EXISTS "engineers_manage_own_daily_billing"      ON public.daily_billing_summaries;
DROP POLICY IF EXISTS "engineers_manage_own_monthly_invoices"   ON public.monthly_invoices;
DROP POLICY IF EXISTS "engineers_manage_own_rental_instruments" ON public.rental_instruments;
DROP POLICY IF EXISTS "engineers_manage_own_sand_bag_rentals"   ON public.sand_bag_rentals;

-- "Engineers can view all session services" from 20260915040000 is the read
-- policy for that table under a different name. Dropped so each table ends
-- with exactly one read policy and one write policy.
DROP POLICY IF EXISTS "Engineers can view all session services" ON public.session_additional_services;
DROP POLICY IF EXISTS "Engineers can view all sessions"         ON public.engineer_sessions;

-- ── Verification ───────────────────────────────────────────────────────────
-- Every row must read exactly "read: 1, write: 1".
SELECT t AS table_name,
       'read: '  || COUNT(*) FILTER (WHERE cmd = 'SELECT') ||
       ', write: '|| COUNT(*) FILTER (WHERE cmd = 'ALL') AS policies,
       COALESCE(STRING_AGG(policyname, ' | ' ORDER BY policyname), '(none)') AS names
  FROM unnest(ARRAY[
        'engineer_sessions', 'session_additional_services', 'manpower_muster',
        'day_notes', 'natrax_invoices', 'po_trackers', 'monthly_invoices',
        'daily_billing_summaries', 'rental_instruments', 'sand_bag_rentals',
        'instrumentation_configs', 'dbc_files', 'project_updates',
        'test_resources', 'email_report_subscriptions', 'email_send_log'
       ]) AS t
  LEFT JOIN pg_policies p
    ON p.schemaname = 'public' AND p.tablename = t
 GROUP BY t
 ORDER BY t;

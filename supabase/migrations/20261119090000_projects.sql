-- Programmes added from the app
--
-- The four programmes so far are compiled into the app (ProjectCatalog and
-- the Projects screen's card details), so a new one meant a code change and
-- a release. Asked for on 19 Nov 2026: "we are getting more projects, so how
-- will I add new projects" — with the vehicle's details looked up online.
--
-- One row per programme added from the Projects screen. The app merges these
-- with the compiled four; a key that matches a compiled programme is ignored
-- there, so the originals cannot be overwritten from here. Its status lives
-- in project_status like every other programme's.
--
-- Same posture as the other tables: signed-in users read; only accounts on
-- tracklog_writers write (public.can_write_tracklog(), 20260915050000).
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS public.projects (
  key           TEXT PRIMARY KEY CHECK (key = lower(btrim(key)) AND key <> ''),
  display_name  TEXT NOT NULL CHECK (btrim(display_name) <> ''),
  vehicle       TEXT NOT NULL CHECK (btrim(vehicle) <> ''),
  powertrain    TEXT NOT NULL DEFAULT 'ice' CHECK (powertrain IN ('bev', 'ice')),
  vehicle_type  TEXT,
  summary       TEXT,
  -- Three short chips for the card, and the longer facts shown on hover.
  specs         JSONB NOT NULL DEFAULT '[]'::jsonb,
  details       JSONB NOT NULL DEFAULT '[]'::jsonb,
  -- A picture and where the facts came from, when looked up online.
  image_url     TEXT,
  source_url    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by    TEXT,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated_read_projects" ON public.projects;
CREATE POLICY "authenticated_read_projects"
  ON public.projects FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "writers_manage_projects" ON public.projects;
CREATE POLICY "writers_manage_projects"
  ON public.projects FOR ALL TO authenticated
  USING (public.can_write_tracklog())
  WITH CHECK (public.can_write_tracklog());

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('table',
   (SELECT COUNT(*)::TEXT FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'projects'),
   '1'),
  ('policies',
   (SELECT COUNT(*)::TEXT FROM pg_policies WHERE tablename = 'projects'),
   '2')
) AS v(check_name, actual, expected);

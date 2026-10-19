-- Programme lifecycle, as data rather than as code
--
-- Whether a PoC is running, upcoming or finished was a `const` in two places:
-- ProgrammeStatus in project_catalog.dart and ProjectStatus in
-- project_selection_screen.dart. Marking a demo complete therefore meant a
-- code change, a web build and a deploy -- and the two copies could disagree
-- while nothing on screen said which was being read.
--
-- This table is the override. The hardcoded value stays as the fallback, so
-- the app works unchanged before this is applied and keeps working if the
-- table is ever unreadable.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS public.project_status (
  -- Matches ProjectCatalog.normaliseKey: lower-case, trimmed.
  project_key   TEXT PRIMARY KEY,
  status        TEXT NOT NULL
                CHECK (status IN ('active', 'upcoming', 'completed')),
  -- Why it closed, what was demonstrated, what is outstanding. Free text on
  -- purpose: the useful note is rarely one of five options.
  notes         TEXT,
  -- The date the PoC actually finished, which is not the date somebody got
  -- round to recording it. Null while a programme is still running.
  completed_on  DATE,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by    TEXT
);

COMMENT ON TABLE public.project_status IS
  'Programme lifecycle overrides. Absent row means fall back to the status '
  'compiled into the app.';

ALTER TABLE public.project_status ENABLE ROW LEVEL SECURITY;

-- Same posture as every other table here: signed-in users read and write,
-- anon gets nothing. The anon key ships inside the public web bundle.
DROP POLICY IF EXISTS project_status_read ON public.project_status;
CREATE POLICY project_status_read ON public.project_status
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS project_status_write ON public.project_status;
CREATE POLICY project_status_write ON public.project_status
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Seed from what the app currently compiles in, so applying this changes
-- nothing on screen until somebody edits a status.
INSERT INTO public.project_status (project_key, status, updated_by) VALUES
  ('mahindra ev poc',    'completed', 'seed'),
  ('mahindra ice poc',   'active',    'seed'),
  ('kia sonet poc',      'upcoming',  'seed'),
  ('tata harrier ev poc','active',    'seed')
ON CONFLICT (project_key) DO NOTHING;

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('rows seeded',
   (SELECT COUNT(*)::TEXT FROM public.project_status),
   '4'),
  ('anon is blocked',
   (SELECT CASE WHEN COUNT(*) = 2 THEN 'yes' ELSE 'policies missing' END
      FROM pg_policies
     WHERE tablename = 'project_status'),
   'yes'),
  ('statuses now',
   (SELECT STRING_AGG(project_key || '=' || status, ', ' ORDER BY project_key)
      FROM public.project_status),
   'kia sonet poc=upcoming, mahindra ev poc=completed, '
     || 'mahindra ice poc=active, tata harrier ev poc=active')
) AS v(check_name, actual, expected);

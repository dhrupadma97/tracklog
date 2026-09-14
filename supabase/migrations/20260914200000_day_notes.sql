-- Why a day looks the way it does
--
-- The register records what happened. It has no way to record why something
-- did NOT happen, and that gap is expensive: the 14 Sep 2026 backup shows
-- 7 days on Mahindra ICE PoC and 15 on Tata Harrier EV PoC carrying manpower
-- and workshop but no track session at all. People were on site, the workshop
-- was accrued, and no track time was logged. Six weeks later nobody can say
-- whether the vehicle was down, the track was wet, testing was not planned,
-- or somebody simply forgot to enter it — and those four answers have four
-- different consequences for what gets billed and what gets chased.
--
-- One note per day per project, written at the time, by the person who knows.
--
-- Deliberately NOT a column on manpower_muster: a day can carry two muster
-- rows (a manpower row and a workshop row), and hanging the explanation off
-- one of them makes it a lottery which one holds it. It is also not a column
-- on engineer_sessions, because the whole point is that on these days there
-- is no session to hang it from.

CREATE TABLE IF NOT EXISTS public.day_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  note_date DATE NOT NULL,
  -- Which programme the day belongs to. Required: a note that explains a gap
  -- in no particular project explains nothing.
  project_name TEXT NOT NULL,
  -- A short category, so gaps can be counted and compared across months
  -- rather than only read one at a time.
  reason TEXT NOT NULL,
  -- The detail. Optional, because the category alone is often the whole
  -- answer and demanding prose discourages recording anything at all.
  comment TEXT,
  recorded_by UUID REFERENCES public.engineer_profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  -- One note per day per project, so re-answering corrects the record rather
  -- than leaving two contradictory explanations for the same day. The app
  -- upserts on this.
  CONSTRAINT day_notes_one_per_day UNIQUE (note_date, project_name)
);

-- Only the categories the app offers. A typo'd reason would drop out of every
-- count while still looking recorded, which is the worst of both.
DO $reason$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'day_notes_reason_known'
  ) THEN
    ALTER TABLE public.day_notes
      ADD CONSTRAINT day_notes_reason_known
      CHECK (reason IN (
        'vehicle_downtime',    -- car off the road: fault, repair, swap
        'track_unavailable',   -- booked out, maintenance, closed
        'weather',             -- rain, heat, surface unusable
        'instrumentation',     -- sensors, DAQ, calibration
        'no_testing_planned',  -- on site for other work
        'not_logged',          -- testing ran; the entry was missed
        'other'
      ));
  END IF;
END
$reason$;

CREATE INDEX IF NOT EXISTS idx_day_notes_date
  ON public.day_notes(note_date DESC);
CREATE INDEX IF NOT EXISTS idx_day_notes_project
  ON public.day_notes(project_name);

-- RLS mirrors manpower_muster: any authenticated user reads, engineers write.
-- These notes are filled in from site, so they must not be manager-only.
DO $rls$
DECLARE
  engineer_check CONSTANT TEXT :=
    'EXISTS (SELECT 1 FROM public.engineer_profiles ep'
    || ' WHERE ep.id = auth.uid() AND ep.user_role = ''engineer'')';
BEGIN
  EXECUTE 'ALTER TABLE public.day_notes ENABLE ROW LEVEL SECURITY';

  EXECUTE 'DROP POLICY IF EXISTS "authenticated_read_day_notes"'
       || ' ON public.day_notes';
  EXECUTE 'CREATE POLICY "authenticated_read_day_notes"'
       || ' ON public.day_notes FOR SELECT TO authenticated USING (true)';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_manage_day_notes"'
       || ' ON public.day_notes';
  EXECUTE format(
    'CREATE POLICY "engineers_manage_day_notes"'
    || ' ON public.day_notes FOR ALL TO authenticated'
    || ' USING (%s) WITH CHECK (%s)', engineer_check, engineer_check);
END
$rls$;

CREATE OR REPLACE FUNCTION public.touch_day_notes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_day_notes_updated_at ON public.day_notes;
CREATE TRIGGER trg_day_notes_updated_at
  BEFORE UPDATE ON public.day_notes
  FOR EACH ROW EXECUTE FUNCTION public.touch_day_notes_updated_at();

-- ── Verification ────────────────────────────────────────────────────────────
-- Self-reports so the run says whether it worked rather than leaving it to be
-- checked by hand. The last row lists the days that currently have muster but
-- no track session — the gaps this table exists to explain.
SELECT * FROM (VALUES
  ('table present',
   (SELECT COUNT(*)::TEXT FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'day_notes'),
   '1'),
  ('reason check constraint',
   (SELECT COUNT(*)::TEXT FROM pg_constraint
     WHERE conname = 'day_notes_reason_known'),
   '1'),
  ('unique is 2-column',
   (SELECT COUNT(*)::TEXT FROM information_schema.key_column_usage
     WHERE constraint_name = 'day_notes_one_per_day'),
   '2'),
  ('rls enabled',
   (SELECT CASE WHEN relrowsecurity THEN 'yes' ELSE 'no' END
      FROM pg_class WHERE relname = 'day_notes'),
   'yes'),
  ('unexplained gaps today',
   (SELECT COUNT(*)::TEXT FROM (
      SELECT DISTINCT m.muster_date, m.project_name
        FROM public.manpower_muster m
       WHERE NOT EXISTS (
         SELECT 1 FROM public.engineer_sessions s
          WHERE s.started_at::date = m.muster_date
            AND COALESCE(NULLIF(TRIM(s.project_name), ''), 'Mahindra EV PoC')
              = COALESCE(NULLIF(TRIM(m.project_name), ''), 'Mahindra EV PoC'))
         AND NOT EXISTS (
         SELECT 1 FROM public.day_notes n
          WHERE n.note_date = m.muster_date
            AND n.project_name = m.project_name)
    ) g),
   'expect 22 on the 14-Sep-2026 data: 7 ICE + 15 Harrier')
) AS v(check_name, actual, expected);

-- Let a PoC be paused, not just active / upcoming / completed.
--
-- A programme that has stopped for now — waiting on a vehicle, on tyres, on
-- the customer — had nowhere to sit. Marking it completed takes it out of the
-- running rail and off the open-commitment figures as though the work were
-- finished, which it is not. Asked for by Dhrupad, 3 Nov 2026.
--
-- Paused is a LIVE state: the app files it with the running programmes,
-- between active and upcoming.

ALTER TABLE public.project_status
  DROP CONSTRAINT IF EXISTS project_status_status_check;

ALTER TABLE public.project_status
  ADD CONSTRAINT project_status_status_check
  CHECK (status IN ('active', 'paused', 'upcoming', 'completed'));

-- Self-report, so the run says whether it worked.
SELECT
  v.check_name,
  v.expected,
  CASE v.check_name
    WHEN 'paused now allowed' THEN (
      SELECT CASE WHEN pg_get_constraintdef(oid) LIKE '%paused%'
                  THEN 'yes' ELSE 'no' END
        FROM pg_constraint
       WHERE conrelid = 'public.project_status'::regclass
         AND conname = 'project_status_status_check')
    WHEN 'rows still valid' THEN (
      SELECT COUNT(*)::TEXT FROM public.project_status
       WHERE status NOT IN ('active', 'paused', 'upcoming', 'completed'))
    WHEN 'statuses in use' THEN (
      SELECT COALESCE(STRING_AGG(DISTINCT status, ', '), 'none')
        FROM public.project_status)
  END AS actual
FROM (VALUES
  ('paused now allowed', 'yes'),
  ('rows still valid', '0'),
  ('statuses in use', 'whatever is recorded today')
) AS v(check_name, expected);

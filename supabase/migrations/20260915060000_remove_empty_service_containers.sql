-- Delete the empty "Other Services" containers
--
-- Manual Entry creates a MISC session first and then inserts the service
-- lines that give it meaning. When that second step failed -- and it failed
-- every time until today, first on the rate/unit_rate column name and then on
-- the generated total_cost column -- the container was left behind: a session
-- with no cost, no duration and nothing attached to it.
--
-- Those empties are why Mahindra EV PoC read 47 sessions against 46 days of
-- testing. They move no money; they inflate a count.
--
-- ONLY EMPTIES ARE REMOVED. A MISC row that carries service lines is the only
-- record of that accessory spend -- both History and the PO Tracker look up
-- their service costs through it -- so anything with a child row stays.
--
-- The app no longer creates these: a failed service insert now deletes its
-- own container before reporting the error.
--
-- Safe to re-run.

-- ── Before ─────────────────────────────────────────────────────────────────
SELECT 'before' AS stage,
       COUNT(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.session_additional_services s
          WHERE s.session_id = e.id))            AS empty_containers,
       COUNT(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.session_additional_services s
          WHERE s.session_id = e.id))            AS containers_with_services
  FROM public.engineer_sessions e
 WHERE e.track_code = 'MISC';

DELETE FROM public.engineer_sessions e
 WHERE e.track_code = 'MISC'
   AND NOT EXISTS (
         SELECT 1 FROM public.session_additional_services s
          WHERE s.session_id = e.id);

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('empty containers left',
   (SELECT COUNT(*)::TEXT FROM public.engineer_sessions e
     WHERE e.track_code = 'MISC'
       AND NOT EXISTS (SELECT 1 FROM public.session_additional_services s
                        WHERE s.session_id = e.id)),
   '0'),
  ('containers still holding services',
   (SELECT COUNT(*)::TEXT FROM public.engineer_sessions e
     WHERE e.track_code = 'MISC'
       AND EXISTS (SELECT 1 FROM public.session_additional_services s
                    WHERE s.session_id = e.id)),
   'kept - each one is a real accessory record'),
  ('service rows still linked',
   (SELECT COUNT(*)::TEXT FROM public.session_additional_services s
      JOIN public.engineer_sessions e ON e.id = s.session_id),
   '25 - none orphaned by the delete'),
  ('sessions now on Mahindra EV PoC',
   (SELECT COUNT(*)::TEXT FROM public.engineer_sessions
     WHERE COALESCE(NULLIF(TRIM(project_name), ''), 'General') = 'General'
        OR LOWER(TRIM(project_name)) = 'mahindra ev poc'),
   '46 - one per logged day, no container')
) AS v(check_name, actual, expected);

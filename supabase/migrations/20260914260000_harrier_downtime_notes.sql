-- Tata Harrier EV is off the road from 20 August 2026
--
-- The vehicle broke down and went to the TATA service centre on 20 August.
-- Its last track session is 18 August, and its manpower stops on 20 August --
-- the technician stood down when the car went in. Everything recorded on the
-- programme after that is workshop rent, which is payable for every day of the
-- hire whether or not anybody can test.
--
-- Without this, those days read as a record-keeping failure: muster present,
-- no track session, reason unknown. They are not. No testing was possible.
-- The distinction matters commercially -- 'not_logged' would mean billable
-- track time is still owed, and here nothing is owed at all.
--
-- Recorded as vehicle_downtime for every Harrier day from 20 August that has
-- muster but no session. Written against the day, not the muster row, because
-- a day can carry both a manpower and a workshop row.
--
-- Requires day_notes (20260914200000), already applied.
-- Run AFTER the workshop fill, so the added days are covered too.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, m.muster_date, TO_CHAR(m.muster_date,'Dy') AS day,
       STRING_AGG(m.kind, ' + ' ORDER BY m.kind) AS recorded
  FROM public.manpower_muster m
 WHERE m.project_name = 'Tata Harrier EV PoC'
   AND m.muster_date >= DATE '2026-08-20'
 GROUP BY m.muster_date
 ORDER BY m.muster_date;

-- ── Record the reason ───────────────────────────────────────────────────────
-- Only days that actually carry muster and genuinely have no session, so this
-- cannot invent an explanation for a day that was fine.
INSERT INTO public.day_notes (note_date, project_name, reason, comment)
SELECT DISTINCT m.muster_date, m.project_name, 'vehicle_downtime',
       'Vehicle at TATA service centre from 20 Aug 2026. No testing possible; '
       || 'workshop rent continues to accrue for the days of the hire.'
  FROM public.manpower_muster m
 WHERE m.project_name = 'Tata Harrier EV PoC'
   AND m.muster_date >= DATE '2026-08-20'
   AND NOT EXISTS (
     SELECT 1 FROM public.engineer_sessions s
      WHERE s.started_at::date = m.muster_date
        AND COALESCE(NULLIF(TRIM(s.project_name), ''), 'Mahindra EV PoC')
          = m.project_name)
ON CONFLICT (note_date, project_name) DO NOTHING;

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('Harrier downtime days recorded',
   (SELECT COUNT(*)::TEXT FROM public.day_notes
     WHERE project_name = 'Tata Harrier EV PoC'
       AND reason = 'vehicle_downtime'),
   '11 — 20 to 30 Aug, the workshop days on Harrier'),
  ('workshop rent accrued during downtime',
   (SELECT (COUNT(*) * 5000)::TEXT FROM public.manpower_muster
     WHERE project_name = 'Tata Harrier EV PoC' AND kind = 'workshop'
       AND muster_date >= DATE '2026-08-20'),
   '55000 — payable, not recoverable'),
  ('Harrier days still unexplained',
   (SELECT COALESCE(STRING_AGG(d::TEXT, ', '), 'none') FROM (
      SELECT DISTINCT m.muster_date AS d FROM public.manpower_muster m
       WHERE m.project_name = 'Tata Harrier EV PoC'
         AND NOT EXISTS (SELECT 1 FROM public.engineer_sessions s
                          WHERE s.started_at::date = m.muster_date
                            AND COALESCE(NULLIF(TRIM(s.project_name),''),
                                'Mahindra EV PoC') = m.project_name)
         AND NOT EXISTS (SELECT 1 FROM public.day_notes n
                          WHERE n.note_date = m.muster_date
                            AND n.project_name = m.project_name)) x),
   '13,14,15,17,19 Aug — before the breakdown, still need a reason'),
  ('Harrier last track session',
   (SELECT COALESCE(MAX(started_at)::date::TEXT, 'none')
      FROM public.engineer_sessions
     WHERE project_name = 'Tata Harrier EV PoC'),
   '2026-08-18'),
  ('Harrier last manpower day',
   (SELECT COALESCE(MAX(muster_date)::TEXT, 'none')
      FROM public.manpower_muster
     WHERE project_name = 'Tata Harrier EV PoC' AND kind = 'manpower'),
   '2026-08-20')
) AS v(check_name, actual, expected);

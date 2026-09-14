-- Workshop rent runs every calendar day from 20 August 2026
--
-- The workshop is hired by the day and the rent is payable whether or not
-- anybody is in it, so the hire is a continuous block: all seven days of the
-- week, no weekend exclusion. This is the opposite of manpower, where only
-- days actually worked are paid.
--
-- Hiring restarted on Thursday 20 August 2026 after a pause from May and has
-- run continuously since. The register only reached 9 September, and had
-- skipped scattered days in between -- 23 and 30 August, 6 September -- which
-- were Sundays that the range entry drops by default. Those days were still
-- charged.
--
--   currently booked   18 days   Rs 90,000
--   should be          26 days   Rs 1,30,000   (20 Aug -> 14 Sep inclusive)
--   to add              8 days   Rs 40,000
--
-- Missing: 23 and 30 August; 6, 10, 11, 12, 13 and 14 September.
--
-- Nothing is deleted. Every day already recorded is a day of the hire.
--
-- Run this AFTER 20260914220000_workshop_onto_552.sql, which moved the
-- September workshop days onto 8242390552 and dropped the 3 Sep duplicate.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, muster_date,
       TO_CHAR(muster_date, 'Dy') AS day, po_number, project_name
  FROM public.manpower_muster
 WHERE kind = 'workshop'
 ORDER BY muster_date;

-- ── Fill every day of the hire ──────────────────────────────────────────────
-- generate_series builds the whole block; ON CONFLICT leaves existing rows
-- untouched, so this is safe to re-run and cannot disturb a day that is
-- already recorded against its own project.
INSERT INTO public.manpower_muster
       (muster_date, head_count, po_number, project_name, kind)
SELECT d::date, 0, '8242390552', 'Mahindra ICE PoC', 'workshop'
  FROM generate_series(DATE '2026-08-20', DATE '2026-09-14', INTERVAL '1 day') d
ON CONFLICT (muster_date, po_number, kind) DO NOTHING;

-- The hire changes programme on 31 August: 20 to 30 August is Tata Harrier EV
-- PoC, and Mahindra ICE PoC runs from 31 August onwards. The insert above
-- labels everything ICE, so the August days it created (23 and 30) are put
-- back to Harrier.
UPDATE public.manpower_muster
   SET project_name = 'Tata Harrier EV PoC'
 WHERE kind = 'workshop'
   AND muster_date BETWEEN DATE '2026-08-20' AND DATE '2026-08-30'
   AND project_name = 'Mahindra ICE PoC';

-- 31 August is recorded as Harrier on the workshop and must be Mahindra ICE
-- PoC. ON CONFLICT preserved the existing wrong label, so it is corrected
-- explicitly. The manpower day of 31 August is already ICE, so this also
-- stops the two registers disagreeing about the same date.
UPDATE public.manpower_muster
   SET project_name = 'Mahindra ICE PoC'
 WHERE kind = 'workshop'
   AND muster_date = DATE '2026-08-31';

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('workshop days total',
   (SELECT COUNT(*)::TEXT FROM public.manpower_muster WHERE kind = 'workshop'),
   '26 — 20 Aug to 14 Sep inclusive'),
  ('workshop accrual',
   (SELECT (COUNT(*) * 5000)::TEXT FROM public.manpower_muster
     WHERE kind = 'workshop'),
   '130000'),
  ('first and last workshop day',
   (SELECT MIN(muster_date)::TEXT || ' to ' || MAX(muster_date)::TEXT
      FROM public.manpower_muster WHERE kind = 'workshop'),
   '2026-08-20 to 2026-09-14'),
  ('any day missed in the block',
   (SELECT COALESCE(STRING_AGG(d::date::TEXT, ', '), 'none')
      FROM generate_series(DATE '2026-08-20', DATE '2026-09-14',
                           INTERVAL '1 day') d
     WHERE NOT EXISTS (SELECT 1 FROM public.manpower_muster m
                        WHERE m.kind = 'workshop' AND m.muster_date = d::date)),
   'none'),
  ('any date counted twice',
   (SELECT COALESCE(STRING_AGG(muster_date::TEXT, ', '), 'none')
      FROM (SELECT muster_date FROM public.manpower_muster
             WHERE kind = 'workshop'
             GROUP BY muster_date HAVING COUNT(*) > 1) x),
   'none'),
  ('workshop POs in use',
   (SELECT STRING_AGG(DISTINCT po_number, ', ')
      FROM public.manpower_muster WHERE kind = 'workshop'),
   '8242390552 only'),
  ('split by programme',
   (SELECT STRING_AGG(project_name || '=' || n::TEXT, ', ' ORDER BY project_name)
      FROM (SELECT project_name, COUNT(*) n FROM public.manpower_muster
             WHERE kind = 'workshop' GROUP BY project_name) p),
   'Tata Harrier EV PoC=11 (20-30 Aug), Mahindra ICE PoC=15 (31 Aug-14 Sep)'),
  ('31 Aug agrees across both registers',
   (SELECT COALESCE(STRING_AGG(DISTINCT kind || '=' || project_name, ', '), 'none')
      FROM public.manpower_muster WHERE muster_date = DATE '2026-08-31'),
   'both manpower and workshop on Mahindra ICE PoC')
) AS v(check_name, actual, expected);

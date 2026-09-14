-- The seven September manpower days, on the live PO
--
-- 8242356330 reached exactly its 38 contracted days on 3 September -- 28
-- opening plus 10 mustered -- and all Rs 68,400 of it is invoiced (MOI/TV-2082
-- for 28 days, MOI/TV-2236 for 10). It has nothing left. 8242399275 is the
-- successor: Rs 1,08,000, 60 days at the same Rs 1,800/day, in force from
-- 13 August 2026.
--
-- The GOODYEAR ManPower Attendance sheet records a technician on site for
-- seven days after 3 September that the muster never captured:
--
--   4 Sep Fri, 5 Sep Sat, 7 Sep Mon, 8 Sep Tue, 9 Sep Wed, 10 Sep Thu,
--   11 Sep Fri
--
-- 5 September is a Saturday and belongs here: manpower is paid for days
-- actually worked, and the attendance sheet shows that one was. 1, 6, 12, 13
-- and 14 September are blank on the sheet and are not added.
--
-- Seven days at Rs 1,800 = Rs 12,600 ex-GST. Afterwards 8242399275 stands at
-- 7 of 60 days used, Rs 95,400 remaining.
--
-- Booked to Mahindra ICE PoC, the programme running through September.
--
-- No existing manpower row falls on any of these dates, and the unique
-- constraint is (muster_date, po_number, kind), so ON CONFLICT is belt and
-- braces rather than load-bearing -- it makes the file safe to re-run.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, muster_date, TO_CHAR(muster_date, 'Dy') AS day,
       head_count, po_number, project_name
  FROM public.manpower_muster
 WHERE kind = 'manpower'
 ORDER BY muster_date;

-- ── Add the seven days ──────────────────────────────────────────────────────
INSERT INTO public.manpower_muster
       (muster_date, head_count, po_number, project_name, kind)
VALUES
  (DATE '2026-09-04', 1, '8242399275', 'Mahindra ICE PoC', 'manpower'),
  (DATE '2026-09-05', 1, '8242399275', 'Mahindra ICE PoC', 'manpower'),
  (DATE '2026-09-07', 1, '8242399275', 'Mahindra ICE PoC', 'manpower'),
  (DATE '2026-09-08', 1, '8242399275', 'Mahindra ICE PoC', 'manpower'),
  (DATE '2026-09-09', 1, '8242399275', 'Mahindra ICE PoC', 'manpower'),
  (DATE '2026-09-10', 1, '8242399275', 'Mahindra ICE PoC', 'manpower'),
  (DATE '2026-09-11', 1, '8242399275', 'Mahindra ICE PoC', 'manpower')
ON CONFLICT (muster_date, po_number, kind) DO NOTHING;

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('man-days on 8242399275',
   (SELECT COALESCE(SUM(head_count), 0)::TEXT FROM public.manpower_muster
     WHERE kind = 'manpower' AND po_number = '8242399275'),
   '7'),
  ('value drawn on 8242399275',
   (SELECT (COALESCE(SUM(head_count), 0) * 1800)::TEXT
      FROM public.manpower_muster
     WHERE kind = 'manpower' AND po_number = '8242399275'),
   '12600'),
  ('8242399275 days remaining',
   (SELECT (60 - COALESCE(SUM(head_count), 0))::TEXT
      FROM public.manpower_muster
     WHERE kind = 'manpower' AND po_number = '8242399275'),
   '53'),
  ('man-days still on the exhausted 8242356330',
   (SELECT COALESCE(SUM(head_count), 0)::TEXT FROM public.manpower_muster
     WHERE kind = 'manpower' AND po_number = '8242356330'),
   '10 — unchanged, 28 opening + 10 = its full 38'),
  ('total man-days recorded',
   (SELECT COALESCE(SUM(head_count), 0)::TEXT FROM public.manpower_muster
     WHERE kind = 'manpower'),
   '17'),
  ('any date carrying manpower on two POs',
   (SELECT COALESCE(STRING_AGG(muster_date::TEXT, ', '), 'none')
      FROM (SELECT muster_date FROM public.manpower_muster
             WHERE kind = 'manpower'
             GROUP BY muster_date HAVING COUNT(*) > 1) x),
   'none'),
  ('last manpower day',
   (SELECT MAX(muster_date)::TEXT FROM public.manpower_muster
     WHERE kind = 'manpower'),
   '2026-09-11')
) AS v(check_name, actual, expected);

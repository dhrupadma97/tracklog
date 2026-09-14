-- Everything from August 2026 books to 8242390552
--
-- NATRAX quotes the PO on the invoice, and they use the latest one unless it is
-- explicitly agreed otherwise. So from August onwards every resource -- track,
-- workshop, manpower -- belongs on 8242390552. 8242348442 is the previous
-- Track & Workshop Booking PO and must stop taking new rows.
--
-- Confirmed with Dhrupad, 14 Sep 2026. This supersedes the earlier reading that
-- the September days on 442 were a deliberate drawdown of remaining balance.
--
-- As found in the 14-Sep-2026 backup, 442 carries six workshop days, all
-- Mahindra ICE PoC, all September: 3, 4, 5, 7, 8 and 9. Rs 30,000 accrued.
--
-- Five of them move. The sixth cannot: 3 September ALREADY has a workshop row
-- on 552, so the day is currently counted twice -- Rs 10,000 accrued for one
-- day of a workshop that bills Rs 5,000. Repointing it would collide with
-- manpower_muster_one_row_per_day (muster_date, po_number, kind); deleting it
-- is both what the constraint requires and what the arithmetic requires.

-- ── Before ──────────────────────────────────────────────────────────────────
SELECT 'before' AS stage, muster_date, kind, po_number, project_name
  FROM public.manpower_muster
 WHERE po_number = '8242348442'
 ORDER BY muster_date;

-- ── 1. Drop the duplicated day ──────────────────────────────────────────────
-- Only where the same date and kind already sit on 552, so this can never
-- delete a day that has nowhere else to live.
DELETE FROM public.manpower_muster m
 WHERE m.po_number = '8242348442'
   AND EXISTS (
     SELECT 1 FROM public.manpower_muster k
      WHERE k.muster_date = m.muster_date
        AND k.kind        = m.kind
        AND k.po_number   = '8242390552');

-- ── 2. Move the rest ────────────────────────────────────────────────────────
-- Scoped to August onwards, so anything genuinely older stays where it is.
UPDATE public.manpower_muster
   SET po_number = '8242390552'
 WHERE po_number = '8242348442'
   AND muster_date >= DATE '2026-08-01';

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('rows left on 442',
   (SELECT COUNT(*)::TEXT FROM public.manpower_muster
     WHERE po_number = '8242348442'),
   '0'),
  ('workshop days on 552',
   (SELECT COUNT(*)::TEXT FROM public.manpower_muster
     WHERE po_number = '8242390552' AND kind = 'workshop'),
   '18 — was 13, gains 5, and the 3 Sep duplicate is gone'),
  ('any date counted twice for workshop',
   (SELECT COALESCE(STRING_AGG(muster_date::TEXT, ', '), 'none')
      FROM (SELECT muster_date FROM public.manpower_muster
             WHERE kind = 'workshop'
             GROUP BY muster_date HAVING COUNT(*) > 1) d),
   'none'),
  ('total workshop accrual',
   (SELECT (COUNT(*) * 5000)::TEXT FROM public.manpower_muster
     WHERE kind = 'workshop'),
   '90000 — 18 days at 5,000'),
  ('August-onwards rows still off 552',
   (SELECT COALESCE(STRING_AGG(DISTINCT po_number, ', '), 'none')
      FROM public.manpower_muster
     WHERE muster_date >= DATE '2026-08-01'
       AND po_number NOT IN ('8242390552', '8242356330')),
   'none — track/workshop on 552, manpower on the MOICARS PO')
) AS v(check_name, actual, expected);

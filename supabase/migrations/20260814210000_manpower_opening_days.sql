-- Man-days consumed before the muster existed
--
-- 8242356330 had 28 of its 68 man-days worked before there was any register to
-- record them in. Those days are real and must count against the PO, but they
-- cannot go into manpower_muster: that table is keyed by date with one row per
-- day, and the dates and daily headcounts were never recorded. Writing 28
-- invented rows would put fabricated detail into a billing record, and a
-- single lump row is rejected by the head_count <= 50 sanity check.
--
-- So it is carried as an opening balance on the PO instead. Days used =
-- opening + mustered, and everything from here is recorded properly by date.
--
-- 28 is corroborated rather than recalled: MOI/TV-2082 bills 59,472, which is
-- 50,400 ex-GST at 18%, and 50,400 / 1,800 is exactly 28.00. Consumption and
-- billing are therefore level on this PO — nothing worked is unbilled.

ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS manpower_days_opening NUMERIC(8, 2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.po_trackers.manpower_days_opening IS
  'Man-days consumed before the muster began. Added to mustered days to give '
  'total consumption. NULL/0 for POs mustered from day one.';

-- 8242356330 — restated to 38 days, correcting the 68 recorded earlier.
--
-- The restatement is self-checking: 38 days at 1,800 is 68,400 ex-GST, the
-- invoice accounts for 28 of them, and the 10 remaining is the figure the
-- programme owner had throughout. At 68 days none of that reconciled.
UPDATE public.po_trackers
   SET total_po_value        = 68400.00,   -- 38 x 1,800
       tax_amount            = 12312.00,   -- 18%
       manpower_days         = 38,
       manpower_days_opening = 28,         -- worked pre-muster, all invoiced
       description           = 'Manpower resource support for SightLine '
                            || 'validation at NATRAX. 38 manpower days at '
                            || '1,800/day.'
 WHERE po_number = '8242356330';

-- 8242399275 went live 13 Aug 2026, after the muster existed, so it opens at
-- zero and every one of its days should be recorded by date.
UPDATE public.po_trackers
   SET manpower_days_opening = 0
 WHERE po_number = '8242399275';

-- ── Verification ────────────────────────────────────────────────────────────
SELECT
  p.po_number,
  p.po_status,
  p.manpower_days                                          AS days_contracted,
  p.manpower_days_opening                                  AS days_opening,
  COALESCE(mus.man_days, 0)                                AS days_mustered,
  p.manpower_days_opening + COALESCE(mus.man_days, 0)      AS days_used,
  p.manpower_days
    - p.manpower_days_opening - COALESCE(mus.man_days, 0)  AS days_left,
  round(p.total_po_value / NULLIF(p.manpower_days, 0), 2)  AS rate_per_day,
  round(COALESCE(inv.billed_excl, 0)
        / NULLIF(p.total_po_value / NULLIF(p.manpower_days, 0), 0), 2)
                                                           AS days_invoiced
FROM public.po_trackers p
LEFT JOIN (
  SELECT po_number, SUM(head_count) AS man_days
    FROM public.manpower_muster GROUP BY po_number
) mus ON mus.po_number = p.po_number
LEFT JOIN (
  SELECT po_number, SUM(amount_excl_gst) AS billed_excl
    FROM public.natrax_invoices GROUP BY po_number
) inv ON inv.po_number = p.po_number
WHERE p.category = 'manpower'
ORDER BY p.po_number;

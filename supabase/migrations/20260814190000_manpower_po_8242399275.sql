-- 8242399275 — the second manpower PO, now valued
--
-- 60 manpower days at 1,800/day, per the programme owner. The rate matches
-- 8242356330 exactly, which is the check that mattered: a different rate
-- between two concurrent manpower POs would have meant one of them was
-- misread. GST at 18%, as charged on MOI/TV-2082.
--
-- Live since 13 Aug 2026 (set in the muster migration), so cover now runs on
-- two POs at once and the muster attributes each day to the one it draws on.

UPDATE public.po_trackers
   SET total_po_value = 108000.00,   -- 60 x 1,800
       tax_amount     =  19440.00,   -- 18%
       manpower_days  =     60,
       description    = 'Manpower resource support for SightLine validation '
                     || 'at NATRAX. 60 manpower days at 1,800/day.'
 WHERE po_number = '8242399275';

-- ── Verification ────────────────────────────────────────────────────────────
-- Both manpower POs, with days billed derived from invoices and days worked
-- from the muster. The two are different numbers whenever work runs ahead of
-- billing, which is the gap this whole exercise exists to surface.
SELECT
  p.po_number,
  p.po_status,
  p.valid_from,
  p.total_po_value                                        AS value_excl_gst,
  p.manpower_days                                         AS days_contracted,
  round(p.total_po_value / NULLIF(p.manpower_days, 0), 2) AS rate_per_day,
  COALESCE(inv.billed_excl, 0)                            AS invoiced_excl_gst,
  round(COALESCE(inv.billed_excl, 0)
        / NULLIF(p.total_po_value / NULLIF(p.manpower_days, 0), 0), 2)
                                                          AS days_invoiced,
  COALESCE(mus.man_days, 0)                               AS days_mustered,
  p.manpower_days - COALESCE(mus.man_days, 0)             AS days_left,
  CASE
    WHEN p.total_po_value = 0 THEN 'VALUE PENDING'
    WHEN p.manpower_days IS NULL THEN 'DAYS PENDING'
    ELSE 'ok'
  END                                                     AS note
FROM public.po_trackers p
LEFT JOIN (
  SELECT po_number, SUM(amount_excl_gst) AS billed_excl
    FROM public.natrax_invoices GROUP BY po_number
) inv ON inv.po_number = p.po_number
LEFT JOIN (
  SELECT po_number, SUM(head_count) AS man_days
    FROM public.manpower_muster GROUP BY po_number
) mus ON mus.po_number = p.po_number
WHERE p.category = 'manpower'
ORDER BY p.po_number;

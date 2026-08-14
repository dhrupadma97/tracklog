-- Manpower POs are contracted in days, not only in rupees
--
-- A manpower PO with a rupee balance still cannot answer the question that
-- actually gets asked — "how many days of support are left" — because the day
-- count was never recorded. The report now prints the days and the rate they
-- imply, so this column is what feeds it.
--
-- Track POs leave it NULL: they are booked by the hour against a rate card and
-- a day count would mean nothing there.

ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS manpower_days NUMERIC(8, 2);

COMMENT ON COLUMN public.po_trackers.manpower_days IS
  'Days of manpower the PO contracts for. NULL for non-manpower POs.';

-- ── 8242356330 — active manpower PO ─────────────────────────────────────────
-- 68 manpower days at 1,800/day, per the programme owner.
--
-- The rate is corroborated by the only MOICARS invoice on record: MOI/TV-2082
-- bills 59,472, which is 50,400 ex-GST at 18%, and 50,400 / 1,800 is exactly
-- 28 days. That the division comes out whole is the check — a wrong rate would
-- not.
UPDATE public.po_trackers
   SET total_po_value = 122400.00,   -- 68 x 1,800
       tax_amount     =  22032.00,   -- 18%, as charged on MOI/TV-2082
       manpower_days  =     68,
       description    = 'Manpower resource support for SightLine validation '
                     || 'at NATRAX. 68 manpower days at 1,800/day.'
 WHERE po_number = '8242356330';

-- ── 8242399275 — upcoming manpower PO ───────────────────────────────────────
-- Still unrecorded: no value, day count or document. Left at zero rather than
-- assumed to match the PO above.
--
-- UPDATE public.po_trackers
--    SET total_po_value = <BASE>,
--        tax_amount     = <TAX>,
--        manpower_days  = <DAYS>
--  WHERE po_number = '8242399275';

-- ── Verification ────────────────────────────────────────────────────────────
-- Manpower position in days, not just rupees. days_invoiced is derived from
-- the invoices actually raised, so it answers "how many days has MOICARS
-- billed" — which is not the same as how many have been worked.
SELECT
  p.po_number,
  p.po_status,
  p.total_po_value,
  p.manpower_days                                   AS days_contracted,
  round(p.total_po_value / NULLIF(p.manpower_days, 0), 2) AS rate_per_day,
  COALESCE(SUM(i.amount_excl_gst), 0)               AS invoiced_excl_gst,
  round(COALESCE(SUM(i.amount_excl_gst), 0)
        / NULLIF(p.total_po_value / NULLIF(p.manpower_days, 0), 0), 2)
                                                    AS days_invoiced,
  round(p.manpower_days - COALESCE(SUM(i.amount_excl_gst), 0)
        / NULLIF(p.total_po_value / NULLIF(p.manpower_days, 0), 0), 2)
                                                    AS days_left_by_invoice,
  CASE
    WHEN p.total_po_value = 0 THEN 'VALUE PENDING — fill in and re-run'
    WHEN p.manpower_days IS NULL OR p.manpower_days = 0
      THEN 'DAYS PENDING — fill in and re-run'
    ELSE 'ok'
  END                                               AS note
FROM public.po_trackers p
LEFT JOIN public.natrax_invoices i ON i.po_number = p.po_number
WHERE p.category = 'manpower'
GROUP BY p.po_number, p.po_status, p.total_po_value, p.manpower_days
ORDER BY p.po_status, p.po_number;

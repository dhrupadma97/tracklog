-- What each PO is actually for
--
-- Spend was only ever tracked in aggregate, so there was no way to answer
-- "which PO paid for track time and which paid for manpower". Invoices already
-- name their PO (Tally prints it as Buyer's Order No. and the parser stores it
-- in natrax_invoices.po_number), so attribution just needs the PO to say what
-- it covers.

ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'other';

-- track_booking | manpower | workshop | instrumentation | other
ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS po_status TEXT NOT NULL DEFAULT 'active';

-- active | used | upcoming | closed
ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS valid_from DATE;

CREATE INDEX IF NOT EXISTS idx_po_trackers_category
  ON public.po_trackers(category);

-- The one PO already loaded covers track hire and the workshop, per its own
-- description ("Track & Workshop Booking at Natrax").
UPDATE public.po_trackers
   SET category = 'track_booking'
 WHERE po_number = '8242348442'
   AND category = 'other';

-- Verification: every PO and what it is attributed to, with anything invoiced
-- against it. An invoice citing a PO that is not loaded shows up as a NULL po.
SELECT
  COALESCE(p.po_number, '(not in tracker)') AS po,
  COALESCE(p.category, '—')                 AS category,
  COALESCE(p.po_status, '—')                AS status,
  COALESCE(p.total_po_value, 0)
    + COALESCE(p.tax_amount, 0)             AS po_incl_tax,
  COUNT(i.id)                               AS invoices,
  COALESCE(SUM(i.total_amount), 0)          AS invoiced,
  COALESCE(p.total_po_value, 0) + COALESCE(p.tax_amount, 0)
    - COALESCE(SUM(i.total_amount), 0)      AS balance
FROM public.po_trackers p
FULL OUTER JOIN public.natrax_invoices i
  ON i.po_number = p.po_number
GROUP BY p.po_number, p.category, p.po_status, p.total_po_value, p.tax_amount
ORDER BY p.po_number NULLS LAST;

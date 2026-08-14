-- Which Goodyear entity raised each PO
--
-- Not cosmetic: the buying entity determines who procurement deals with and
-- which entity the invoice bills. The latest track PO came from GTCI while
-- everything before it came from Goodyear SATL, and the tracker had no way to
-- show that.

ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS issued_by TEXT NOT NULL DEFAULT 'Goodyear SATL';

-- 8242390552 (27.05.2026) is the latest track PO and was raised by GTCI.
UPDATE public.po_trackers
   SET issued_by = 'GTCI'
 WHERE po_number = '8242390552';

-- Everything else on record came from Goodyear South Asia Tyres.
UPDATE public.po_trackers
   SET issued_by = 'Goodyear SATL'
 WHERE po_number <> '8242390552'
   AND (issued_by IS NULL OR issued_by = '');

-- Verification
SELECT
  po_number,
  category,
  issued_by,
  vendor_name,
  total_po_value + tax_amount AS po_incl_tax
FROM public.po_trackers
ORDER BY issued_by, category, po_number;

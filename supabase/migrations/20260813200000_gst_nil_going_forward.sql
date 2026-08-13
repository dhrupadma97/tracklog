-- GST is nil on new supplies
--
-- Supplies now run under SEZ Bond / LUT, so no integrated tax is charged. The
-- open-PO drafts already anticipated this ("GST @ 18%, nil if under SEZ Bond /
-- LUT"); this makes it the actual position from here on.
--
-- Deliberately NOT retrospective. Invoices INV/25-26/1869 and INV/26-27/205
-- really did carry tax — 34,848.90 IGST and 2,09,241 CGST+SGST respectively —
-- and PO 8242348442 was raised with 3,42,788 of GST against it. Rewriting
-- those would misstate what was actually billed and break the reconciliation
-- against the invoices on file.

-- 8242390552 was loaded with 18% assumed, before the nil-rating was confirmed.
UPDATE public.po_trackers
   SET tax_amount = 0,
       description = regexp_replace(
         description,
         '\s*GST[^.]*\.',
         '',
         'g'
       ) || ' Supply under SEZ Bond / LUT — no integrated tax.'
 WHERE po_number = '8242390552';

-- Any PO raised from here should carry nil tax unless it says otherwise.
ALTER TABLE public.po_trackers
  ALTER COLUMN tax_amount SET DEFAULT 0;

-- Verification — historical tax preserved, new PO nil-rated.
SELECT
  po_number,
  category,
  total_po_value,
  tax_amount,
  total_po_value + tax_amount AS po_incl_tax,
  CASE
    WHEN po_number IN ('8242348442') THEN 'historical — tax retained, correct'
    WHEN tax_amount = 0 AND total_po_value > 0 THEN 'nil-rated, correct'
    WHEN total_po_value = 0 THEN 'value pending'
    ELSE 'check this'
  END AS status
FROM public.po_trackers
ORDER BY category, po_number;

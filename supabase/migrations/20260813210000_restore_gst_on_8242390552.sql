-- Restore GST on 8242390552
--
-- The nil-rating applied in 20260813200000 is reverted: GST treatment is a
-- finance decision, not something the tracker should assume. Defaulting to
-- 18% matches every invoice actually received (INV/25-26/1869 at 18% IGST,
-- INV/26-27/205 at 18% CGST+SGST) and PO 8242348442 as raised.
--
-- If finance later confirms the supply runs under SEZ Bond / LUT, set
-- tax_amount to 0 for the affected PO rather than changing a default — the
-- treatment can differ per PO.

UPDATE public.po_trackers
   SET tax_amount = 448524.00,          -- 18% of 24,91,800
       description = replace(
         description,
         ' Supply under SEZ Bond / LUT — no integrated tax.',
         ' GST at 18%; confirm with finance whether SEZ Bond / LUT applies.'
       )
 WHERE po_number = '8242390552';

-- Verification
SELECT
  po_number,
  category,
  total_po_value,
  tax_amount,
  total_po_value + tax_amount AS po_incl_tax,
  CASE
    WHEN total_po_value = 0 THEN 'value pending'
    WHEN tax_amount = 0     THEN 'nil-rated'
    ELSE round(tax_amount / total_po_value * 100, 1) || '% tax'
  END AS treatment
FROM public.po_trackers
ORDER BY category, po_number;

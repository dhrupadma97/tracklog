-- Flag GST treatment as unconfirmed, rather than guessing at it again
--
-- 8242390552 is a GTCI PO and the supply runs into an SEZ, so GST may not be
-- chargeable at all. Nobody knows until NATRAX raise the invoice.
--
-- This has already been guessed twice. 20260813200000 set the tax to 0 on the
-- strength of SEZ Bond / LUT; 20260813210000 put the 18% back, because the
-- treatment is a finance decision and every invoice actually received had
-- carried tax. Both migrations asserted a figure nobody had confirmed, and
-- the second one said what to do about it: record the uncertainty rather than
-- change a default.
--
-- So the amount is left exactly as it is. What changes is that the screens
-- can now say it is unconfirmed, the same way track_rates.rate_pending tells
-- "the rate is zero" apart from "the rate is not known". Guessing nil and
-- guessing 18% are both wrong; only one of them looks wrong.
--
-- When the invoice arrives, settle it with ONE of:
--   UPDATE public.po_trackers
--      SET tax_amount = 0, tax_pending = false
--    WHERE po_number = '8242390552';          -- SEZ, nil-rated
--   UPDATE public.po_trackers
--      SET tax_pending = false
--    WHERE po_number = '8242390552';          -- taxed at 18% as loaded
--
-- Safe to re-run.

ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS tax_pending BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.po_trackers.tax_pending IS
  'True when the GST treatment is not yet confirmed. The tax_amount still '
  'holds the working assumption; this says not to rely on it.';

UPDATE public.po_trackers
   SET tax_pending = TRUE,
       description = regexp_replace(
         description,
         '\s*GST at 18%; confirm with finance whether SEZ Bond / LUT applies\.',
         '',
         'g'
       ) || ' GST treatment unconfirmed: GTCI PO supplying an SEZ, so the '
          || '18% carried here may be nil. Settles on the first invoice.'
 WHERE po_number = '8242390552';

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('552 flagged pending',
   (SELECT tax_pending::TEXT FROM public.po_trackers
     WHERE po_number = '8242390552'),
   'true'),
  ('552 tax amount unchanged',
   (SELECT tax_amount::TEXT FROM public.po_trackers
     WHERE po_number = '8242390552'),
   '448524.00'),
  ('nothing else flagged',
   (SELECT COUNT(*)::TEXT FROM public.po_trackers WHERE tax_pending),
   '1')
) AS v(check_name, actual, expected);

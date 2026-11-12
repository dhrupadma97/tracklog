-- GTCI track & workshop PO 8242440093, and nil GST on 8242390552
--
-- ── 1. The new PO ──────────────────────────────────────────────────────────
-- Goodyear Technology Center India Pvt Ltd, Hyderabad. Dated 21.09.2026,
-- delivery from 01.10.2026. One open line: "GTIS Tire Validation Test at
-- NATRAX", 1 AU at 50,00,000.00, HSN/SAC 9987. Vendor 622867. Our ref
-- 0136159050. Payment cycle 15 days from trigger date.
--
-- Tax is NIL on the face of the PO, and the PO tells NATRAX so in terms:
-- "The vendor must not charge GST and should state: 'Supply to SEZ Unit Bond
-- or Letter of Undertaking without payment of Integrated Tax'". So unlike
-- 8242390552, which was loaded at 18% and argued about for two months, there
-- is nothing to guess here.
--
-- Category track_booking: it funds track time AND workshop rental, which is
-- how 8242390552 is used too. It is lumpsum on actuals, so manpower_days
-- stays 0 and it gets no days-remaining bar.
--
-- ── 2. Nil GST on 8242390552, now confirmed ────────────────────────────────
-- 20261019100000 would have flagged this PO's tax as "not confirmed" until
-- the first invoice settled it either way. That migration was never applied,
-- and the invoice has now arrived: INV/26-27/802 (29 Oct 2026, September
-- testing, billed to GTCI) is issued "UNDER BOND OR LETTER OF UNDERTAKING
-- WITHOUT PAYMENT OF IGST", LUT AD230326020782E, and its total of 7,72,350.00
-- is the taxable value plus 0.40 round-off with no tax added. The IGST figure
-- in its tax-analysis box is informational only.
--
-- That migration is deleted rather than left to be pasted by mistake: the
-- question it existed to hold open is answered.
--
-- Safe to re-run.

-- ── 0. The issuing-company column ──────────────────────────────────────────
-- issued_by was meant to arrive with 20260814120000_po_issuing_entity.sql,
-- but that file was never run on the live database: the first paste of
-- this one failed with 42703, column "issued_by" does not exist (12 Nov
-- 2026). Its two statements are repeated here so this file stands alone.
-- Until now the PO Tracker's "via GTCI" tag and the manager report's issuer
-- split have been reading a column that was not there, and showing nothing.
ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS issued_by TEXT NOT NULL DEFAULT 'Goodyear SATL';

UPDATE public.po_trackers
   SET issued_by = 'GTCI'
 WHERE po_number = '8242390552';

INSERT INTO public.po_trackers (
  po_number, vendor_name, description,
  total_po_value, tax_amount, delivery_date, valid_from,
  category, po_status, issued_by
) VALUES (
  '8242440093',
  'NATIONAL AUTOMOTIVE TEST TRACKS (NATRAX)',
  'Track & Workshop at NATRAX, Indore - GTIS Tire Validation Test, open PO. '
    || 'Vendor 622867, our ref 0136159050, HSN/SAC 9987. Dated 21.09.2026, '
    || 'delivery from 01.10.2026. SEZ supply under LUT - no GST. Payment '
    || 'cycle 15 days from trigger date.',
  5000000.00,
  0.00,
  '2026-10-01',
  '2026-10-01',
  'track_booking',
  'active',
  'GTCI'
)
ON CONFLICT (po_number) DO UPDATE
  SET vendor_name    = EXCLUDED.vendor_name,
      description    = EXCLUDED.description,
      total_po_value = EXCLUDED.total_po_value,
      tax_amount     = EXCLUDED.tax_amount,
      delivery_date  = EXCLUDED.delivery_date,
      valid_from     = EXCLUDED.valid_from,
      category       = EXCLUDED.category,
      po_status      = EXCLUDED.po_status,
      issued_by      = EXCLUDED.issued_by;

UPDATE public.po_trackers
   SET tax_amount  = 0,
       description = description
         || ' GST nil: confirmed by INV/26-27/802 (SEZ, LUT AD230326020782E).'
 WHERE po_number = '8242390552'
   AND tax_amount <> 0;

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('new PO present',
   (SELECT po_number || ' ' || category || ' ' || po_status || ' ' || issued_by
      FROM public.po_trackers WHERE po_number = '8242440093'),
   '8242440093 track_booking active GTCI'),
  ('new PO value',
   (SELECT (total_po_value + tax_amount)::TEXT
      FROM public.po_trackers WHERE po_number = '8242440093'),
   '5000000.00'),
  ('552 tax now',
   (SELECT tax_amount::TEXT
      FROM public.po_trackers WHERE po_number = '8242390552'),
   '0.00'),
  ('GTCI track POs',
   (SELECT STRING_AGG(po_number, ', ' ORDER BY po_number)
      FROM public.po_trackers
     WHERE issued_by = 'GTCI' AND category = 'track_booking'),
   '8242390552, 8242440093')
) AS v(check_name, actual, expected);

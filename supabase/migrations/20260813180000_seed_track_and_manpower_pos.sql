-- The remaining POs: NATRAX for track use, MOICARS for manpower
--
-- Only 8242348442 was loaded, so every rupee attributed to track booking and
-- manpower had nowhere to go. The PO PDFs are scans with no text layer, so
-- nothing could be read out of them automatically — the values below come from
-- the open-PO request drafts, and anything not evidenced there is left for a
-- human to fill in rather than guessed at.

-- ── NATRAX 8242390552 — track & workshop ────────────────────────────────────
-- Value and date are from "NATRAX Open PO Request" (INR 24,91,800, dated
-- 27.05.2026). GST is taken at 18%, matching 8242348442 and the GST actually
-- charged on invoices INV/25-26/1869 and INV/26-27/205. Note the drafts flag
-- that GST is nil if the supply runs under SEZ Bond / LUT — if that applies
-- here, set tax_amount to 0.
INSERT INTO public.po_trackers (
  po_number, vendor_name, description,
  total_po_value, tax_amount, delivery_date, category, po_status
) VALUES (
  '8242390552',
  'NATIONAL AUTOMOTIVE TEST TRACKS (NATRAX)',
  'Track & Workshop Booking at NATRAX, Indore. Vendor 622867. Open PO on '
    || 'lumpsum value, billed on actuals, HSN/SAC 9987. Dated 27.05.2026. '
    || 'Committed to the TATA programme; forecast exhausted by October 2026.',
  2491800.00,
  448524.00,          -- 18% of 24,91,800
  NULL,               -- validity not stated in the source documents
  'track_booking',
  'active'
)
ON CONFLICT (po_number) DO UPDATE
  SET category   = EXCLUDED.category,
      po_status  = EXCLUDED.po_status,
      vendor_name = EXCLUDED.vendor_name;

-- ── MOICARS — manpower ──────────────────────────────────────────────────────
-- Both POs are scans, and no value for either appears in any document in the
-- project. They are recorded so manpower is visible as its own funding stream
-- and so any invoice naming them attributes correctly, but the values are
-- deliberately left at zero rather than invented.
--
-- TO COMPLETE: replace the two zeros in each statement with the PO's base
-- value and GST, then re-run this file. Nothing else needs changing.
INSERT INTO public.po_trackers (
  po_number, vendor_name, description,
  total_po_value, tax_amount, category, po_status
) VALUES
  ('8242356330', 'MOICARS',
   'Manpower resource support for SightLine validation at NATRAX. '
     || 'VALUE PENDING — PO document is a scan; figure not yet recorded.',
   0, 0, 'manpower', 'active'),
  ('8242399275', 'MOICARS',
   'Manpower resource support for SightLine validation at NATRAX. '
     || 'VALUE PENDING — PO document is a scan; figure not yet recorded.',
   0, 0, 'manpower', 'upcoming')
ON CONFLICT (po_number) DO UPDATE
  SET category  = EXCLUDED.category,
      po_status = EXCLUDED.po_status;

-- ── Where things stand ──────────────────────────────────────────────────────
SELECT
  p.po_number,
  p.category,
  p.po_status,
  p.total_po_value + p.tax_amount            AS po_incl_tax,
  COALESCE(SUM(i.total_amount), 0)           AS invoiced,
  p.total_po_value + p.tax_amount
    - COALESCE(SUM(i.total_amount), 0)       AS balance,
  CASE WHEN p.total_po_value = 0
       THEN 'VALUE PENDING — fill in and re-run'
       ELSE 'ok' END                         AS note
FROM public.po_trackers p
LEFT JOIN public.natrax_invoices i ON i.po_number = p.po_number
GROUP BY p.po_number, p.category, p.po_status, p.total_po_value, p.tax_amount
ORDER BY p.category, p.po_number;

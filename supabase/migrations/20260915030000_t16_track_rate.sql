-- Give T16 a row in track_rates
--
-- The table was seeded with 'GR' / General Road Track at 9,000. Nothing in the
-- app has ever used that code: manual_entry_screen.dart calls the track T16,
-- the NATRAX workbook calls it T16, and INV/26-27/388 bills it as part of the
-- May track lines. Sessions are now stored with track_code 'T16' as well, so
-- the rates table held the only 'GR' left anywhere.
--
-- Renamed rather than added alongside, so the track does not end up with two
-- rows at the same rate. `grep -rn "'GR'" lib/` returns nothing, so no code
-- path loses its lookup.
--
-- Rate and minimum are unchanged: 9,000/hr, bills from one hour. Confirmed by
-- the workbook's Daily Track Billing for 18-May-2026 -- 24 minutes billed as
-- 1 Hr at 9,000 -- which is inside the 1,73,500 of May track charges on
-- INV/26-27/388.
--
-- Safe to re-run.

BEGIN;

-- Rename the seeded row when T16 is not already present for the venue.
UPDATE public.track_rates
   SET track_code = 'T16',
       track_name = 'General Road Track'
 WHERE track_code = 'GR'
   AND NOT EXISTS (
         SELECT 1 FROM public.track_rates t2
          WHERE t2.track_code = 'T16'
            AND t2.venue = public.track_rates.venue);

-- If the seed never ran, create it outright.
INSERT INTO public.track_rates
       (track_code, track_name, rate_below_3_5t, rate_above_3_5t,
        min_hours_per_day, venue, is_active)
SELECT 'T16', 'General Road Track', 9000, 10000, 1, 'NATRAX', true
 WHERE NOT EXISTS (
         SELECT 1 FROM public.track_rates
          WHERE track_code = 'T16' AND venue = 'NATRAX');

COMMIT;

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('T16 rows at NATRAX',
   (SELECT COUNT(*)::TEXT FROM public.track_rates
     WHERE track_code = 'T16' AND venue = 'NATRAX'),
   '1'),
  ('T16 rate / minimum',
   (SELECT rate_below_3_5t::BIGINT || ' per hr, min ' || min_hours_per_day || ' hr'
      FROM public.track_rates WHERE track_code = 'T16' AND venue = 'NATRAX'),
   '9000 per hr, min 1 hr'),
  ('GR rows left (should be none)',
   (SELECT COUNT(*)::TEXT FROM public.track_rates WHERE track_code = 'GR'),
   '0 - renamed to T16'),
  ('sessions already using T16',
   (SELECT COUNT(*)::TEXT FROM public.engineer_sessions WHERE track_code = 'T16'),
   '1 - the 18-May-2026 session')
) AS v(check_name, actual, expected);

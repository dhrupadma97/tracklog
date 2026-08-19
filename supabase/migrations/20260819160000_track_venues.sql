-- Testing venues
--
-- Every track and every session so far belongs to NATRAX, but that was implicit:
-- track_rates held T1..T13 with nothing saying where they are, and
-- engineer_sessions recorded a track_code with nothing saying which proving
-- ground it belonged to. The moment a second venue exists, every historical row
-- becomes ambiguous - so the column is added with a NOT NULL default of 'NATRAX'
-- rather than as nullable. A NULL would be indistinguishable from "not known".
--
-- CoASTT Coimbatore is seeded from its own deck (CoASTT High Performance Centre
-- - Coimbatore.pptx, slides 6/7/9). That deck contains no rate card, so the
-- rates go in as 0 with rate_pending = true. The app reads that flag and shows
-- "not recorded" instead of a confident zero.
--
-- MSPT is not seeded. No track list has been supplied and inventing Mahindra's
-- layout would be worse than an empty venue.

ALTER TABLE public.track_rates
  ADD COLUMN IF NOT EXISTS venue TEXT NOT NULL DEFAULT 'NATRAX';

-- Distinguishes "rate is zero" from "rate is not known". Without it a CoASTT
-- session would price at zero and look billed rather than unpriced.
ALTER TABLE public.track_rates
  ADD COLUMN IF NOT EXISTS rate_pending BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.engineer_sessions
  ADD COLUMN IF NOT EXISTS venue TEXT NOT NULL DEFAULT 'NATRAX';

CREATE INDEX IF NOT EXISTS idx_track_rates_venue
  ON public.track_rates(venue);
CREATE INDEX IF NOT EXISTS idx_engineer_sessions_venue
  ON public.engineer_sessions(venue);

-- track_code was unique only by convention. With more than one venue it has to
-- be unique per venue instead, or getTrackRate's maybeSingle() throws the first
-- time two venues share a code.
DO $u$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'track_rates_code_per_venue'
  ) THEN
    ALTER TABLE public.track_rates
      ADD CONSTRAINT track_rates_code_per_venue UNIQUE (venue, track_code);
  END IF;
END
$u$;

-- ── CoASTT Coimbatore layouts ───────────────────────────────────────────────
-- Rates are 0 / rate_pending because the deck states none. Replace the zeros
-- and clear rate_pending when the rate card arrives; nothing else changes.
INSERT INTO public.track_rates (
  track_code, track_name, venue, rate_pending,
  rate_below_3_5t, rate_above_3_5t, min_hours_per_day, is_active
) VALUES
  ('CO-INT', 'International Circuit (3.80 km)', 'COASTT', true, 0, NULL, 1, true),
  ('CO-NAT', 'National Circuit (2.02 km)',      'COASTT', true, 0, NULL, 1, true),
  ('CO-HND', 'Handling Circuit (1.58 km)',      'COASTT', true, 0, NULL, 1, true),
  ('CO-EV',  'EV Testing Track (>1 km)',        'COASTT', true, 0, NULL, 1, true)
ON CONFLICT (venue, track_code) DO UPDATE
  SET track_name   = EXCLUDED.track_name,
      rate_pending  = EXCLUDED.rate_pending,
      is_active     = EXCLUDED.is_active;

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('venue on track_rates',
   (SELECT COUNT(*)::TEXT FROM information_schema.columns
     WHERE table_schema='public' AND table_name='track_rates'
       AND column_name='venue'), '1'),
  ('venue on engineer_sessions',
   (SELECT COUNT(*)::TEXT FROM information_schema.columns
     WHERE table_schema='public' AND table_name='engineer_sessions'
       AND column_name='venue'), '1'),
  ('rate_pending column',
   (SELECT COUNT(*)::TEXT FROM information_schema.columns
     WHERE table_schema='public' AND table_name='track_rates'
       AND column_name='rate_pending'), '1'),
  ('unique is (venue, track_code)',
   (SELECT COUNT(*)::TEXT FROM information_schema.key_column_usage
     WHERE constraint_name='track_rates_code_per_venue'), '2'),
  ('tracks per venue',
   (SELECT STRING_AGG(venue || '=' || n::TEXT, ', ' ORDER BY venue)
      FROM (SELECT venue, COUNT(*) n FROM public.track_rates
             GROUP BY venue) v), 'NATRAX=13, COASTT=4'),
  ('sessions still all NATRAX',
   (SELECT COALESCE(STRING_AGG(DISTINCT venue, ', '), 'no sessions')
      FROM public.engineer_sessions), 'NATRAX')
) AS v(check_name, actual, expected);

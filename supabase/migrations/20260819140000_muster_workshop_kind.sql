-- Workshop days in the muster
--
-- The muster recorded contract manpower only. Workshop rental — the other
-- thing NATRAX bills by the operational day, at Rs 5,000/day — had to be
-- entered as a service line under Manual Entry instead. Two per-day registers
-- in two places, and only one of them drew anything down.
--
-- A `kind` discriminator puts both in one register while keeping them separate
-- rows, because they are counted differently and funded differently:
--
--   manpower  one row per person-day. Two people for a day is two man-days,
--             so days used is SUM(head_count). Drawn against a MOICARS PO
--             (category 'manpower'), which is contracted in days.
--
--   workshop  one row per day, flat, whoever is in it. Days used is a row
--             COUNT and head_count is always 0. Drawn against the NATRAX
--             track PO (category 'track_booking' — 8242390552 is literally
--             "Track & Workshop Booking"), which is a lumpsum billed on
--             actuals rather than a day count, so it accrues rupees rather
--             than drawing down a contracted number of days.
--
-- Splitting on kind rather than adding a boolean to the existing row is what
-- lets the two draw on different POs. A flag would have tied every workshop
-- day to whichever manpower PO happened to be on that date's row.

ALTER TABLE public.manpower_muster
  ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'manpower';

-- Only two kinds exist. Without this a typo'd kind drops silently out of both
-- counts: it is neither summed as manpower nor counted as workshop.
DO $kind$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'manpower_muster_kind_known'
  ) THEN
    ALTER TABLE public.manpower_muster
      ADD CONSTRAINT manpower_muster_kind_known
      CHECK (kind IN ('manpower', 'workshop'));
  END IF;
END
$kind$;

-- One row per day per PO *per kind*. Without widening this, a workshop day and
-- a manpower day on the same date and PO collide on upsert and the second
-- silently overwrites the first.
ALTER TABLE public.manpower_muster
  DROP CONSTRAINT IF EXISTS manpower_muster_one_row_per_day;
ALTER TABLE public.manpower_muster
  ADD CONSTRAINT manpower_muster_one_row_per_day
  UNIQUE (muster_date, po_number, kind);

CREATE INDEX IF NOT EXISTS idx_manpower_muster_kind
  ON public.manpower_muster(kind);

-- Existing rows are all manpower — the DEFAULT above has already labelled
-- them, this is only here so a re-run over a partially applied state is safe.
UPDATE public.manpower_muster SET kind = 'manpower' WHERE kind IS NULL;

-- ── Verification ────────────────────────────────────────────────────────────
-- Self-reports so the run says whether it worked rather than leaving it to be
-- checked by hand.
SELECT * FROM (VALUES
  ('kind column present',
   (SELECT COUNT(*)::TEXT FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'manpower_muster'
       AND column_name = 'kind'),
   '1'),
  ('kind check constraint',
   (SELECT COUNT(*)::TEXT FROM pg_constraint
     WHERE conname = 'manpower_muster_kind_known'),
   '1'),
  ('unique is 3-column',
   (SELECT COUNT(*)::TEXT FROM information_schema.key_column_usage
     WHERE constraint_name = 'manpower_muster_one_row_per_day'),
   '3'),
  ('rows by kind',
   (SELECT COALESCE(STRING_AGG(kind || '=' || n::TEXT, ', ' ORDER BY kind), 'none')
      FROM (SELECT kind, COUNT(*) n FROM public.manpower_muster
             GROUP BY kind) k),
   'all should read manpower'),
  ('workshop PO available',
   (SELECT COALESCE(STRING_AGG(po_number, ', '), 'NONE - see note')
      FROM public.po_trackers WHERE category = 'track_booking'),
   '8242390552')
) AS v(check_name, actual, expected);

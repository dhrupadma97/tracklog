-- Dead weight as its own muster kind
--
-- MOI/TV-2331 (5 Nov 2026, October) billed 27 "Nos" of man power at 1,800.
-- Only 23 of those were people. MOICARS had folded 16 days of dead-weight
-- hire at 450/day -- 7,200, which is 4 days at the man-day rate -- into the
-- man-days line, as their covering mail says: "considered in the Man days".
--
-- The rupees are right. The day count is not, and the day count is what
-- matters: 8242399275 is contracted in DAYS, so four days of manpower cover
-- were spent on a piece of steel. The PO runs out four days sooner than the
-- work justifies, and nothing in the register said why.
--
-- So dead weight gets its own kind. It draws the same manpower PO, because
-- that is who bills it, but it is never a man-day:
--   * head_count is forced to 0, as workshop already is, so it cannot reach
--     SUM(head_count) and be counted as a person
--   * it is costed per day of hire at 450, not per ton -- NATRAX's own card
--     prices dead weight at 200/ton/day, which is a different supplier
--     selling a different thing
--
-- Safe to re-run.

ALTER TABLE public.manpower_muster
  DROP CONSTRAINT IF EXISTS manpower_muster_kind_known;

ALTER TABLE public.manpower_muster
  ADD CONSTRAINT manpower_muster_kind_known
  CHECK (kind IN ('manpower', 'workshop', 'deadweight'));

-- A dead-weight row is hire, not attendance. Belt and braces behind the app,
-- which already forces it: a row that slipped through with a head count would
-- be invisibly wrong, because it would look exactly like a man-day.
ALTER TABLE public.manpower_muster
  DROP CONSTRAINT IF EXISTS manpower_muster_deadweight_no_head_count;

ALTER TABLE public.manpower_muster
  ADD CONSTRAINT manpower_muster_deadweight_no_head_count
  CHECK (kind <> 'deadweight' OR COALESCE(head_count, 0) = 0);

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('deadweight now allowed',
   (SELECT CASE WHEN pg_get_constraintdef(oid) LIKE '%deadweight%'
                THEN 'yes' ELSE 'no' END
      FROM pg_constraint WHERE conname = 'manpower_muster_kind_known'),
   'yes'),
  ('head count blocked on deadweight',
   (SELECT CASE WHEN COUNT(*) = 1 THEN 'yes' ELSE 'no' END
      FROM pg_constraint
     WHERE conname = 'manpower_muster_deadweight_no_head_count'),
   'yes'),
  ('existing rows untouched',
   (SELECT STRING_AGG(kind || '=' || n, ', ' ORDER BY kind)
      FROM (SELECT kind, COUNT(*)::TEXT AS n
              FROM public.manpower_muster GROUP BY kind) t),
   'manpower and workshop counts unchanged')
) AS v(check_name, actual, expected);

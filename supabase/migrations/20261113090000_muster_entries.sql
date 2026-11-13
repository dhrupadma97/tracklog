-- Muster: other daily entries, beside attendance
--
-- The muster records manpower, workshop days and dead weight, one row per
-- day per PO per kind. Asked for on 13 Nov 2026: room to log anything else
-- by the day as well — the office or porta cabin, the conference hall, food
-- coupons, water jars, a weigh-bridge visit, a visitor.
--
-- A table of its own rather than a fourth kind in manpower_muster. That
-- table's unique key (muster_date, po_number, kind) would allow only one
-- "other" row per day, and widening it to take an item name would change
-- the ON CONFLICT target every manpower save uses — breaking them the
-- moment the app and the database disagreed. Here nothing existing moves.
--
-- A record of what happened on a day, with a quantity and an optional rate.
-- It is NOT added to any programme's cost: money NATRAX bill is entered in
-- Manual Entry → Other Services, and counting it here too would count it
-- twice.
--
-- Same posture as manpower_muster: signed-in users read; only accounts on
-- tracklog_writers write (public.can_write_tracklog(), 20260915050000).
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS public.muster_entries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_date    DATE NOT NULL,
  item          TEXT NOT NULL CHECK (btrim(item) <> ''),
  quantity      NUMERIC(10, 2) NOT NULL DEFAULT 1 CHECK (quantity >= 0),
  -- Null means "not priced", which is not the same as free.
  rate          NUMERIC(12, 2) CHECK (rate IS NULL OR rate >= 0),
  project_name  TEXT,
  po_number     TEXT,
  notes         TEXT,
  created_by    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_muster_entries_date
  ON public.muster_entries (entry_date DESC);

ALTER TABLE public.muster_entries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "authenticated_read_muster_entries" ON public.muster_entries;
CREATE POLICY "authenticated_read_muster_entries"
  ON public.muster_entries FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "writers_manage_muster_entries" ON public.muster_entries;
CREATE POLICY "writers_manage_muster_entries"
  ON public.muster_entries FOR ALL TO authenticated
  USING (public.can_write_tracklog())
  WITH CHECK (public.can_write_tracklog());

CREATE OR REPLACE FUNCTION public.touch_muster_entries_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_muster_entries_updated_at ON public.muster_entries;
CREATE TRIGGER trg_muster_entries_updated_at
  BEFORE UPDATE ON public.muster_entries
  FOR EACH ROW EXECUTE FUNCTION public.touch_muster_entries_updated_at();

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('table',
   (SELECT COUNT(*)::TEXT FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'muster_entries'),
   '1'),
  ('policies',
   (SELECT COUNT(*)::TEXT FROM pg_policies WHERE tablename = 'muster_entries'),
   '2'),
  ('writer check exists',
   (SELECT COUNT(*)::TEXT FROM pg_proc WHERE proname = 'can_write_tracklog'),
   '1')
) AS v(check_name, actual, expected);

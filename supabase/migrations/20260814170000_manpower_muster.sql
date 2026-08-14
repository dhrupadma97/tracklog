-- Daily manpower muster
--
-- Contract manpower is billed in man-days: one person on site for one day is
-- one day off the PO, so two people for a day consumes two. Nothing recorded
-- headcount, which meant days worked could only ever be inferred backwards
-- from an invoice — and that is exactly what left 8242356330 showing 28 days
-- billed against 58 believed worked.
--
-- This is the interim register kept until a permanent technician is in place.
-- It records what is actually needed to answer "how many days have we used":
-- a date and a headcount. No names, no in/out times.

CREATE TABLE IF NOT EXISTS public.manpower_muster (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  muster_date DATE NOT NULL,
  -- People on site that day. Zero is meaningful: it records a day checked and
  -- found empty, which is not the same as a day nobody logged.
  head_count INTEGER NOT NULL DEFAULT 0,
  -- Which manpower PO the day draws against. Required: a muster day that
  -- attributes to no PO cannot draw anything down, and would silently vanish
  -- from the position it exists to report.
  po_number TEXT NOT NULL,
  project_name TEXT,
  notes TEXT,
  recorded_by UUID REFERENCES public.engineer_profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT manpower_muster_head_count_sane
    CHECK (head_count >= 0 AND head_count <= 50),
  -- One row per day per PO, so re-recording a day corrects it rather than
  -- double counting it. The app upserts on this.
  CONSTRAINT manpower_muster_one_row_per_day UNIQUE (muster_date, po_number)
);

CREATE INDEX IF NOT EXISTS idx_manpower_muster_date
  ON public.manpower_muster(muster_date DESC);
CREATE INDEX IF NOT EXISTS idx_manpower_muster_po
  ON public.manpower_muster(po_number);

-- RLS — mirrors po_trackers and test_resources: authenticated reads, engineers
-- write. The muster is filled in from site, so it must not be manager-only.
DO $rls$
DECLARE
  engineer_check CONSTANT TEXT :=
    'EXISTS (SELECT 1 FROM public.engineer_profiles ep'
    || ' WHERE ep.id = auth.uid() AND ep.user_role = ''engineer'')';
BEGIN
  EXECUTE 'ALTER TABLE public.manpower_muster ENABLE ROW LEVEL SECURITY';

  EXECUTE 'DROP POLICY IF EXISTS "authenticated_read_manpower_muster"'
       || ' ON public.manpower_muster';
  EXECUTE 'CREATE POLICY "authenticated_read_manpower_muster"'
       || ' ON public.manpower_muster FOR SELECT TO authenticated USING (true)';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_manage_manpower_muster"'
       || ' ON public.manpower_muster';
  EXECUTE format(
    'CREATE POLICY "engineers_manage_manpower_muster"'
    || ' ON public.manpower_muster FOR ALL TO authenticated'
    || ' USING (%s) WITH CHECK (%s)', engineer_check, engineer_check);
END
$rls$;

CREATE OR REPLACE FUNCTION public.touch_manpower_muster_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_manpower_muster_updated_at ON public.manpower_muster;
CREATE TRIGGER trg_manpower_muster_updated_at
  BEFORE UPDATE ON public.manpower_muster
  FOR EACH ROW EXECUTE FUNCTION public.touch_manpower_muster_updated_at();

-- ── 8242399275 is live ──────────────────────────────────────────────────────
-- Confirmed as having started 13 Aug 2026, so it is no longer 'upcoming'.
-- Its value and day count are still unknown and stay at zero rather than being
-- assumed to match 8242356330.
UPDATE public.po_trackers
   SET po_status = 'active',
       valid_from = DATE '2026-08-13'
 WHERE po_number = '8242399275';

-- ── Verification ────────────────────────────────────────────────────────────
SELECT
  p.po_number,
  p.po_status,
  p.valid_from,
  p.total_po_value,
  p.manpower_days                              AS days_contracted,
  COALESCE(SUM(m.head_count), 0)               AS man_days_mustered,
  p.manpower_days - COALESCE(SUM(m.head_count), 0)
                                               AS days_left_by_muster,
  CASE
    WHEN p.total_po_value = 0 THEN 'VALUE PENDING'
    WHEN p.manpower_days IS NULL THEN 'DAYS PENDING'
    ELSE 'ok'
  END                                          AS note
FROM public.po_trackers p
LEFT JOIN public.manpower_muster m ON m.po_number = p.po_number
WHERE p.category = 'manpower'
GROUP BY p.po_number, p.po_status, p.valid_from, p.total_po_value,
         p.manpower_days
ORDER BY p.po_status, p.po_number;

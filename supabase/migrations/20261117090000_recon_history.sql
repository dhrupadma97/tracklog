-- NATRAX reconciliation: a history of every decision, with its comment
--
-- recon_answers keeps one answer per question — the latest. Changing an
-- answer overwrote the one before, so a month could not show how it got
-- to where it is: who accepted a line, who then disputed it, and why.
-- Asked for on 17 Nov 2026: "whatever the adjustments we are doing should
-- be recorded based on my comments and there should be the history".
--
-- One row per action — an answer given, changed or undone; a vehicle
-- placed; the sheet or invoice set; the month settled or reopened — with
-- the line it was about, the decision, the comment, and the two amounts
-- (NATRAX's and the agreed one) as they stood at that moment.
--
-- Append-only: signed-in users may add and read rows; nobody may change or
-- delete one, so the trail can be relied on. Anon gets nothing.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS public.recon_history (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  month          TEXT NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),
  action         TEXT NOT NULL,
  item_key       TEXT,
  title          TEXT,
  choice         TEXT,
  choice_label   TEXT,
  comment        TEXT,
  natrax_amount  NUMERIC(14, 2),
  agreed_amount  NUMERIC(14, 2),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by     TEXT
);
CREATE INDEX IF NOT EXISTS recon_history_month
  ON public.recon_history (month, created_at DESC);

ALTER TABLE public.recon_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS recon_history_read ON public.recon_history;
CREATE POLICY recon_history_read ON public.recon_history
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS recon_history_add ON public.recon_history;
CREATE POLICY recon_history_add ON public.recon_history
  FOR INSERT TO authenticated WITH CHECK (true);
-- No UPDATE or DELETE policy: with RLS on, both are refused for everyone.

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('table',
   (SELECT COUNT(*)::TEXT FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'recon_history'),
   '1'),
  ('policies (read + add only)',
   (SELECT STRING_AGG(cmd, ', ' ORDER BY cmd) FROM pg_policies
     WHERE tablename = 'recon_history'),
   'INSERT, SELECT')
) AS v(check_name, actual, expected);

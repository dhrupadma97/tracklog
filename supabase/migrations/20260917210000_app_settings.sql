-- App settings: values that change with the business, not with the code.
--
-- WHY THIS TABLE EXISTS
-- The workshop accrual dates lived as `static final DateTime` in
-- lib/services/billing_baseline.dart. That made a routine monthly chore --
-- "NATRAX invoiced August, stop accruing for August" -- into a code change
-- and a redeploy. Forget it and the manager's report asks a second time for
-- money already paid, which is the exact bug fixed on 17 Sep 2026.
--
-- Anything here must be editable by the person who does the billing, from
-- the app, without help. Structure and permissions stay in SQL; values do not.

CREATE TABLE IF NOT EXISTS public.app_settings (
    key         TEXT PRIMARY KEY,
    value       TEXT,                    -- NULL is meaningful: "not set yet"
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.app_settings IS
  'Key/value settings the app edits at runtime. Dates are ISO yyyy-MM-dd.';
COMMENT ON COLUMN public.app_settings.value IS
  'NULL means deliberately unset (e.g. workshop not released), not missing.';

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Everyone signed in reads: the accrual shows in the report and the PO
-- tracker, so every session needs the dates whether or not it can edit them.
DROP POLICY IF EXISTS "authenticated_read_app_settings" ON public.app_settings;
CREATE POLICY "authenticated_read_app_settings"
  ON public.app_settings FOR SELECT TO authenticated USING (true);

-- Only whitelisted writers change them, by the same test every other write
-- policy uses, so the UI and RLS cannot disagree about who is an owner.
DROP POLICY IF EXISTS "writers_manage_app_settings" ON public.app_settings;
CREATE POLICY "writers_manage_app_settings"
  ON public.app_settings FOR ALL TO authenticated
  USING (public.can_write_tracklog())
  WITH CHECK (public.can_write_tracklog());

-- Stamp who changed what, so a wrong date can be traced rather than argued.
CREATE OR REPLACE FUNCTION public.touch_app_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    NEW.updated_by := auth.uid();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS app_settings_touch ON public.app_settings;
CREATE TRIGGER app_settings_touch
    BEFORE INSERT OR UPDATE ON public.app_settings
    FOR EACH ROW EXECUTE FUNCTION public.touch_app_settings();

-- ── Seed: exactly what the Dart constants held on 17 Sep 2026 ──────────────
-- Seeded so day one changes nothing. ON CONFLICT DO NOTHING because a value
-- the user has since edited must never be pushed back by a re-run.

INSERT INTO public.app_settings (key, value, description) VALUES
  ('workshop.settled_to',  '2026-08-31',
   'Workshop is settled BY INVOICE up to and including this date. An invoice is final, so the accrual stops for the whole period it covers. Move it forward when NATRAX invoices another month.'),
  ('workshop.resumed_on',  '2026-08-12',
   'Date the bay was most recently taken back. The accrual never counts days before this.'),
  ('workshop.released_on', NULL,
   'Date the bay was given up. Empty means it is still held. Without it the accrual runs for ever.')
ON CONFLICT (key) DO NOTHING;

-- ── Verification: this run reports on itself ──────────────────────────────
SELECT k.key,
       COALESCE(s.value, '(unset)') AS value,
       CASE WHEN s.key IS NULL THEN 'MISSING - seed did not run'
            ELSE 'ok' END AS status
FROM (VALUES ('workshop.settled_to'),
             ('workshop.resumed_on'),
             ('workshop.released_on')) AS k(key)
LEFT JOIN public.app_settings s ON s.key = k.key
ORDER BY k.key;

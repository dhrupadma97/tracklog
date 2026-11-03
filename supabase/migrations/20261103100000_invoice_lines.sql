-- What NATRAX invoiced, line by line, beside what we recorded.
--
-- Our register and the invoice disagree in both directions and for different
-- reasons. In September NATRAX under-billed High Speed by four hours while our
-- own record carried nearly 100 extra EV units, somebody else's weighing pad,
-- and no water jars at all. Correcting our entries to match the bill would
-- destroy the evidence of both.
--
-- So neither side is edited. This table holds the invoiced figure for a line;
-- the app shows ours, theirs and the difference, and the difference is the
-- thing worth looking at. Asked for by Dhrupad, 3 Nov 2026 — "always maintain
-- our record and NATRAX record".
--
-- `line_key` identifies a line within a month, as the panel builds it:
--     track:<programme>:<track code or name>
--     service:<service name>
--     workshop
--     manpower
-- A key with no row simply has no invoiced figure yet, and the panel falls
-- back to our own number for that line.

CREATE TABLE IF NOT EXISTS public.invoice_lines (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  month       text NOT NULL,
  line_key    text NOT NULL,
  invoiced    numeric(12, 2) NOT NULL,
  note        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invoice_lines_month_format CHECK (month ~ '^\d{4}-\d{2}$'),
  CONSTRAINT invoice_lines_key_not_blank CHECK (btrim(line_key) <> ''),
  CONSTRAINT invoice_lines_unique UNIQUE (month, line_key)
);

CREATE INDEX IF NOT EXISTS invoice_lines_month_idx
  ON public.invoice_lines (month);

ALTER TABLE public.invoice_lines ENABLE ROW LEVEL SECURITY;

-- Same posture as every other billing table: signed-in users only. The anon
-- key ships inside the public web bundle and is never granted here.
DROP POLICY IF EXISTS invoice_lines_read ON public.invoice_lines;
CREATE POLICY invoice_lines_read ON public.invoice_lines
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS invoice_lines_write ON public.invoice_lines;
CREATE POLICY invoice_lines_write ON public.invoice_lines
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.invoice_lines_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS invoice_lines_touch ON public.invoice_lines;
CREATE TRIGGER invoice_lines_touch
  BEFORE UPDATE ON public.invoice_lines
  FOR EACH ROW EXECUTE FUNCTION public.invoice_lines_touch();

-- Self-report, so the run says whether it worked.
SELECT
  v.check_name,
  v.expected,
  CASE v.check_name
    WHEN 'table exists' THEN (
      SELECT COUNT(*)::TEXT FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = 'invoice_lines')
    WHEN 'rls enabled' THEN (
      SELECT relrowsecurity::TEXT FROM pg_class
       WHERE oid = 'public.invoice_lines'::regclass)
    WHEN 'policies' THEN (
      SELECT COUNT(*)::TEXT FROM pg_policies
       WHERE schemaname = 'public' AND tablename = 'invoice_lines')
  END AS actual
FROM (VALUES
  ('table exists', '1'),
  ('rls enabled', 'true'),
  ('policies', '2')
) AS v(check_name, expected);

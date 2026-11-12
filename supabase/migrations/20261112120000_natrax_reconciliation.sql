-- NATRAX reconciliation: one month at a time, from utilisation sheet to settled
--
-- NATRAX send a Service Utilization Sheet each month, then an invoice. Until
-- now the sheet was checked by hand — a backup, a script, an afternoon — and
-- that check found 16 hours of another customer's Ertiga billed to Goodyear
-- in September (2,45,700), and a register that had stopped on 15 October.
-- The Reconcile tab does it in the app: upload the sheet, answer what does
-- not agree, then set the invoice against what was agreed and settle.
--
-- Four tables.
--
--   recon_months   — the month's sheet (as read), the invoice tallied
--                    against it, and whether the month is settled.
--   recon_answers  — one answer per question per month, with the figures the
--                    question showed, so an answer given before a missing run
--                    was added can be shown as needing another look.
--   recon_vehicles — whose each NATRAX vehicle is, decided once and reused
--                    every month after. Keyed on the vehicle as NATRAX write
--                    it, normalised (XUV-7X0 and XUV 7X0 are one key).
--   recon_notes    — the month's own running notes, and the record of it
--                    being settled or reopened.
--
-- Same posture as every other table: signed-in users read and write, anon
-- gets nothing — the anon key ships inside the public web bundle.
--
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS public.recon_months (
  month               TEXT PRIMARY KEY
                      CHECK (month ~ '^\d{4}-\d{2}$'),
  sheet_json          JSONB,
  sheet_file          TEXT,
  sheet_reference     TEXT,
  sheet_uploaded_at   TIMESTAMPTZ,
  sheet_uploaded_by   TEXT,
  invoice_id          UUID,
  invoice_number      TEXT,
  invoice_json        JSONB,
  invoice_tallied_at  TIMESTAMPTZ,
  settled_at          TIMESTAMPTZ,
  settled_by          TEXT,
  -- Frozen at settlement: the agreed, disputed and invoiced totals as they
  -- stood, so a settled month does not drift when somebody later edits a
  -- session in it.
  settled_summary     JSONB,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.recon_answers (
  month        TEXT NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),
  item_key     TEXT NOT NULL,
  choice       TEXT NOT NULL,
  comment      TEXT,
  snapshot     TEXT,
  answered_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  answered_by  TEXT,
  PRIMARY KEY (month, item_key)
);

CREATE TABLE IF NOT EXISTS public.recon_vehicles (
  vehicle_key   TEXT PRIMARY KEY,
  label         TEXT NOT NULL,
  project_name  TEXT,
  not_ours      BOOLEAN NOT NULL DEFAULT FALSE,
  note          TEXT,
  decided_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_by    TEXT,
  CONSTRAINT recon_vehicles_owner CHECK (not_ours OR project_name IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.recon_notes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  month       TEXT NOT NULL CHECK (month ~ '^\d{4}-\d{2}$'),
  note        TEXT NOT NULL CHECK (btrim(note) <> ''),
  kind        TEXT NOT NULL DEFAULT 'note'
              CHECK (kind IN ('note', 'sheet', 'invoice', 'settled', 'reopened')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by  TEXT
);
CREATE INDEX IF NOT EXISTS recon_notes_month ON public.recon_notes (month, created_at);

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['recon_months', 'recon_answers', 'recon_vehicles', 'recon_notes']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (true)',
                   t || '_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_write', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
                   'USING (true) WITH CHECK (true)', t || '_write', t);
  END LOOP;
END $$;

-- Vehicles already settled in conversation, so the first month does not ask
-- again. The Ertiga and its weigh-bridge plate were confirmed not Goodyear's
-- on 12 Nov 2026 (booking BUK/26-27/01283). The EV charger's plate EP09349 is
-- deliberately NOT seeded: it is very probably the Harrier, but nobody has
-- said so, and the tab will suggest it for a one-click confirmation.
INSERT INTO public.recon_vehicles (vehicle_key, label, project_name, not_ours, note, decided_by) VALUES
  ('XUV7X0',        'XUV-7X0',         'Mahindra ICE PoC',    FALSE, 'Mahindra XUV 7XO', 'seed'),
  ('TATAHARRIER',   'Tata Harrier',    'Tata Harrier EV PoC', FALSE, NULL,               'seed'),
  ('TATAHARRIEREV', 'Tata Harrier EV', 'Tata Harrier EV PoC', FALSE, NULL,               'seed'),
  ('ERTIGA',        'Ertiga',          NULL,                  TRUE,
     'Booking BUK/26-27/01283, RFID 38174 - another customer''s; confirmed 12 Nov 2026', 'seed'),
  ('MP09AR1597',    'MP09 AR 1597',    NULL,                  TRUE,
     'The Ertiga''s plate on the services table, booking 1283', 'seed')
ON CONFLICT (vehicle_key) DO NOTHING;

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('tables',
   (SELECT STRING_AGG(table_name, ', ' ORDER BY table_name)
      FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name LIKE 'recon\_%'),
   'recon_answers, recon_months, recon_notes, recon_vehicles'),
  ('policies',
   (SELECT COUNT(*)::TEXT FROM pg_policies WHERE tablename LIKE 'recon\_%'),
   '8'),
  ('vehicles seeded',
   (SELECT STRING_AGG(vehicle_key || '=' || COALESCE(project_name, 'not ours'), ', '
                      ORDER BY vehicle_key)
      FROM public.recon_vehicles),
   'ERTIGA=not ours, MP09AR1597=not ours, TATAHARRIER=Tata Harrier EV PoC, '
     || 'TATAHARRIEREV=Tata Harrier EV PoC, XUV7X0=Mahindra ICE PoC')
) AS v(check_name, actual, expected);

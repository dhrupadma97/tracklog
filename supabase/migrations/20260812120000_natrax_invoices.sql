-- NATRAX Original Invoices
-- Stores the invoices NATRAX actually raised (PDF + the amounts printed on them)
-- so the PO balance can be reconciled against real billed values instead of
-- relying only on app-computed session costs.

-- 1. Invoice metadata table
CREATE TABLE IF NOT EXISTS public.natrax_invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number TEXT NOT NULL,
  invoice_date DATE,
  period_month TEXT,                                     -- 'YYYY-MM' the invoice bills for
  project_name TEXT NOT NULL DEFAULT 'Mahindra EV PoC',
  po_number TEXT,                                        -- PO this invoice draws down
  amount_excl_gst NUMERIC(14, 2) NOT NULL DEFAULT 0,
  gst_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
  total_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
  notes TEXT,
  file_name TEXT,
  storage_path TEXT,                                     -- object path inside the natrax-invoices bucket
  file_size_bytes BIGINT,
  uploaded_by TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT natrax_invoices_unique_per_project UNIQUE (invoice_number, project_name)
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_natrax_invoices_project
  ON public.natrax_invoices(project_name);
CREATE INDEX IF NOT EXISTS idx_natrax_invoices_period
  ON public.natrax_invoices(period_month);
CREATE INDEX IF NOT EXISTS idx_natrax_invoices_po
  ON public.natrax_invoices(po_number);

-- 3. RLS — mirrors po_trackers: everyone authenticated reads, engineers write.
--    (Managers are read-only in TrackLog; see EngineerProfile.isReadOnly.)
ALTER TABLE public.natrax_invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_read_natrax_invoices" ON public.natrax_invoices;
CREATE POLICY "authenticated_read_natrax_invoices"
ON public.natrax_invoices
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "engineers_manage_natrax_invoices" ON public.natrax_invoices;
CREATE POLICY "engineers_manage_natrax_invoices"
ON public.natrax_invoices
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.engineer_profiles ep
    WHERE ep.id = auth.uid() AND ep.user_role = 'engineer'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.engineer_profiles ep
    WHERE ep.id = auth.uid() AND ep.user_role = 'engineer'
  )
);

-- 4. Private storage bucket + its policies.
--
-- storage.objects is owned by supabase_storage_admin. The dashboard SQL editor
-- can usually manage it, but not on every project — so this section is wrapped
-- and downgraded to a NOTICE on permission failure. If it is skipped, create
-- the bucket and its four policies from Dashboard → Storage instead; the table
-- above is already in place either way.
DO $storage$
DECLARE
  engineer_check CONSTANT TEXT :=
    'EXISTS (SELECT 1 FROM public.engineer_profiles ep'
    || ' WHERE ep.id = auth.uid() AND ep.user_role = ''engineer'')';
BEGIN
  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'natrax-invoices',
    'natrax-invoices',
    false,
    26214400,                                            -- 25 MB per invoice
    ARRAY['application/pdf', 'image/png', 'image/jpeg']
  )
  ON CONFLICT (id) DO UPDATE
    SET file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

  -- Read: any authenticated user. Write: engineers only (managers are
  -- read-only in TrackLog, matching the po_trackers policy).
  EXECUTE 'DROP POLICY IF EXISTS "authenticated_read_invoice_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "authenticated_read_invoice_files" ON storage.objects '
       || 'FOR SELECT TO authenticated '
       || 'USING (bucket_id = ''natrax-invoices'')';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_write_invoice_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "engineers_write_invoice_files" ON storage.objects '
       || 'FOR INSERT TO authenticated '
       || 'WITH CHECK (bucket_id = ''natrax-invoices'' AND ' || engineer_check || ')';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_update_invoice_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "engineers_update_invoice_files" ON storage.objects '
       || 'FOR UPDATE TO authenticated '
       || 'USING (bucket_id = ''natrax-invoices'' AND ' || engineer_check || ')';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_delete_invoice_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "engineers_delete_invoice_files" ON storage.objects '
       || 'FOR DELETE TO authenticated '
       || 'USING (bucket_id = ''natrax-invoices'' AND ' || engineer_check || ')';

  RAISE NOTICE 'Storage bucket natrax-invoices and its 4 policies are in place.';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'SKIPPED storage setup (insufficient privilege on storage.objects). '
                 'Create the private bucket "natrax-invoices" and its policies '
                 'from Dashboard → Storage. The natrax_invoices table is unaffected.';
END
$storage$;

-- 5. Keep updated_at fresh
CREATE OR REPLACE FUNCTION public.touch_natrax_invoices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_natrax_invoices_updated_at ON public.natrax_invoices;
CREATE TRIGGER trg_natrax_invoices_updated_at
BEFORE UPDATE ON public.natrax_invoices
FOR EACH ROW EXECUTE FUNCTION public.touch_natrax_invoices_updated_at();

-- 6. Verification — every row should read OK.
SELECT
  check_name,
  CASE WHEN passed THEN 'OK' ELSE 'MISSING' END AS status
FROM (
  VALUES
    ('table public.natrax_invoices',
     to_regclass('public.natrax_invoices') IS NOT NULL),
    ('RLS enabled',
     COALESCE((SELECT relrowsecurity FROM pg_class
               WHERE oid = to_regclass('public.natrax_invoices')), false)),
    ('table policies (expect 2)',
     (SELECT count(*) FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'natrax_invoices') = 2),
    ('storage bucket natrax-invoices',
     EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'natrax-invoices')),
    ('storage policies (expect 4)',
     (SELECT count(*) FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND policyname LIKE '%invoice_files') = 4),
    ('updated_at trigger',
     EXISTS (SELECT 1 FROM pg_trigger
             WHERE tgname = 'trg_natrax_invoices_updated_at'))
) AS t(check_name, passed);

-- Attach the PO document itself
--
-- POs could only be typed in as figures. The actual PDF lived on someone's
-- desktop, so nothing in the tracker could be checked against the document it
-- came from — the same gap the invoice originals closed on the billing side.

ALTER TABLE public.po_trackers
  ADD COLUMN IF NOT EXISTS file_name TEXT,
  ADD COLUMN IF NOT EXISTS storage_path TEXT,
  ADD COLUMN IF NOT EXISTS file_size_bytes BIGINT,
  ADD COLUMN IF NOT EXISTS uploaded_by TEXT;

-- Private bucket + policies, mirroring natrax-invoices: authenticated read,
-- engineers write. Wrapped because storage.objects is owned by
-- supabase_storage_admin and the SQL editor cannot always manage it.
DO $storage$
DECLARE
  engineer_check CONSTANT TEXT :=
    'EXISTS (SELECT 1 FROM public.engineer_profiles ep'
    || ' WHERE ep.id = auth.uid() AND ep.user_role = ''engineer'')';
BEGIN
  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'po-documents',
    'po-documents',
    false,
    26214400,                                            -- 25 MB per document
    ARRAY['application/pdf', 'image/png', 'image/jpeg']
  )
  ON CONFLICT (id) DO UPDATE
    SET file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

  EXECUTE 'DROP POLICY IF EXISTS "authenticated_read_po_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "authenticated_read_po_files" ON storage.objects '
       || 'FOR SELECT TO authenticated '
       || 'USING (bucket_id = ''po-documents'')';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_write_po_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "engineers_write_po_files" ON storage.objects '
       || 'FOR INSERT TO authenticated '
       || 'WITH CHECK (bucket_id = ''po-documents'' AND ' || engineer_check || ')';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_update_po_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "engineers_update_po_files" ON storage.objects '
       || 'FOR UPDATE TO authenticated '
       || 'USING (bucket_id = ''po-documents'' AND ' || engineer_check || ')';

  EXECUTE 'DROP POLICY IF EXISTS "engineers_delete_po_files" ON storage.objects';
  EXECUTE 'CREATE POLICY "engineers_delete_po_files" ON storage.objects '
       || 'FOR DELETE TO authenticated '
       || 'USING (bucket_id = ''po-documents'' AND ' || engineer_check || ')';

  RAISE NOTICE 'Bucket po-documents and its 4 policies are in place.';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'SKIPPED storage setup (insufficient privilege). Create the '
                 'private bucket "po-documents" from Dashboard -> Storage. '
                 'The po_trackers columns are unaffected.';
END
$storage$;

-- Verification
SELECT
  check_name,
  CASE WHEN passed THEN 'OK' ELSE 'MISSING' END AS status
FROM (
  VALUES
    ('po_trackers.storage_path',
     EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'po_trackers'
                AND column_name = 'storage_path')),
    ('bucket po-documents',
     EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'po-documents')),
    ('storage policies (expect 4)',
     (SELECT count(*) FROM pg_policies
       WHERE schemaname = 'storage' AND tablename = 'objects'
         AND policyname LIKE '%_po_files') = 4)
) AS t(check_name, passed);

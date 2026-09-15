-- Storage for the original invoice PDFs
--
-- InvoiceService.upload() writes the PDF to the 'natrax-invoices' bucket and
-- then records the metadata row. The bucket does not exist, so the upload
-- throws before the row is ever written and the invoice cannot be added at
-- all -- which is what stopped the May invoice (INV/26-27/388) going in.
--
-- Private, not public. These are supplier invoices carrying rates, PO numbers
-- and amounts; a public bucket is readable by anyone who guesses a path, and
-- the app already fetches them through short-lived signed URLs
-- (InvoiceService.signedUrl), which only work on a private bucket anyway.

-- ── Bucket ──────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'natrax-invoices',
  'natrax-invoices',
  FALSE,
  -- 25 MB. An e-invoice with a QR block and a watermark runs to a few MB;
  -- this leaves room without letting an accidental upload of something huge
  -- sit in storage.
  26214400,
  ARRAY['application/pdf', 'image/png', 'image/jpeg']
)
ON CONFLICT (id) DO UPDATE
  SET public             = EXCLUDED.public,
      file_size_limit    = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ── Policies ────────────────────────────────────────────────────────────────
-- Mirrors natrax_invoices itself: any authenticated user may read, engineers
-- may write. Invoices are uploaded from site, so this must not be
-- manager-only.
--
-- storage.objects is owned by supabase_storage_admin and the SQL editor is
-- sometimes refused on it, so the DDL is wrapped and the failure reported
-- rather than taking the whole migration down. If it is skipped, create the
-- four policies from Storage -> Policies in the dashboard instead.
DO $storage$
DECLARE
  engineer_check CONSTANT TEXT :=
    'EXISTS (SELECT 1 FROM public.engineer_profiles ep'
    || ' WHERE ep.id = auth.uid() AND ep.user_role = ''engineer'')';
BEGIN
  EXECUTE 'DROP POLICY IF EXISTS "authenticated_read_natrax_invoices"'
       || ' ON storage.objects';
  EXECUTE 'CREATE POLICY "authenticated_read_natrax_invoices"'
       || ' ON storage.objects FOR SELECT TO authenticated'
       || ' USING (bucket_id = ''natrax-invoices'')';

  EXECUTE format(
    'DROP POLICY IF EXISTS "engineers_insert_natrax_invoices" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "engineers_insert_natrax_invoices"'
    || ' ON storage.objects FOR INSERT TO authenticated'
    || ' WITH CHECK (bucket_id = ''natrax-invoices'' AND %s)', engineer_check);

  EXECUTE format(
    'DROP POLICY IF EXISTS "engineers_update_natrax_invoices" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "engineers_update_natrax_invoices"'
    || ' ON storage.objects FOR UPDATE TO authenticated'
    || ' USING (bucket_id = ''natrax-invoices'' AND %s)', engineer_check);

  -- Delete matters: upload() removes the stored object when the metadata
  -- insert is rejected, so without this a failed upload leaves an orphan.
  EXECUTE format(
    'DROP POLICY IF EXISTS "engineers_delete_natrax_invoices" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "engineers_delete_natrax_invoices"'
    || ' ON storage.objects FOR DELETE TO authenticated'
    || ' USING (bucket_id = ''natrax-invoices'' AND %s)', engineer_check);

EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'storage.objects policies skipped: insufficient privilege. '
                 'Create them from Storage -> Policies in the dashboard.';
END
$storage$;

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('bucket exists',
   (SELECT COUNT(*)::TEXT FROM storage.buckets WHERE id = 'natrax-invoices'),
   '1'),
  ('bucket is private',
   (SELECT CASE WHEN public THEN 'public — WRONG' ELSE 'private' END
      FROM storage.buckets WHERE id = 'natrax-invoices'),
   'private'),
  ('size limit (MB)',
   (SELECT (file_size_limit / 1024 / 1024)::TEXT
      FROM storage.buckets WHERE id = 'natrax-invoices'),
   '25'),
  ('policies on the bucket',
   (SELECT COUNT(*)::TEXT FROM pg_policies
     WHERE schemaname = 'storage' AND tablename = 'objects'
       AND policyname LIKE '%natrax_invoices%'),
   '4 — read, insert, update, delete'),
  ('objects already stored',
   (SELECT COUNT(*)::TEXT FROM storage.objects
     WHERE bucket_id = 'natrax-invoices'),
   '0 on a first run'),
  ('invoice rows claiming a stored file',
   (SELECT COUNT(*)::TEXT FROM public.natrax_invoices
     WHERE storage_path IS NOT NULL),
   'rows here with no object are earlier uploads that lost their PDF')
) AS v(check_name, actual, expected);

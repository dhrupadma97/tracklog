-- Seed the current CC list into email_report_subscriptions
--
-- The CC list for reports used to be a const array hardcoded in FOUR files —
-- email_reports_screen, project_updates_screen, email_report_service and
-- management_report_service, ten lines in all. Changing a name meant a code
-- change and a deploy, and missing one of the ten sent the report to somebody
-- who should not have had it. That is exactly what happened when yeswanth and
-- niranjan came off the list.
--
-- The app now reads this table instead, so adding or removing a recipient is
-- the Add Subscriber sheet on the Email Reports screen.
--
-- These three rows are the list as it stands today, so behaviour does not
-- change the moment the new build ships.
--
-- Safe to re-run.

INSERT INTO public.email_report_subscriptions
       (manager_name, email, report_type, is_active)
SELECT v.name, v.email, 'both', true
  FROM (VALUES
    ('Vimal V',          'v_vimal@goodyear.com'),
    ('Ashish Pandit',    'ashish_pandit@goodyear.com'),
    ('Kartheek Nedunuri','kartheek_nedunuri@goodyear.com')
  ) AS v(name, email)
 WHERE NOT EXISTS (
   SELECT 1 FROM public.email_report_subscriptions s
    WHERE lower(s.email) = lower(v.email));

-- ── Verification ───────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('active subscribers',
   (SELECT STRING_AGG(email, ', ' ORDER BY email)
      FROM public.email_report_subscriptions WHERE is_active),
   'v_vimal, ashish_pandit and kartheek_nedunuri'),
  ('anyone removed still listed?',
   (SELECT COALESCE(STRING_AGG(email, ', '), 'no')
      FROM public.email_report_subscriptions
     WHERE email ILIKE '%yeswanth%' OR email ILIKE '%niranjan%'),
   'no - both came off the list on 17 Sep 2026'),
  ('total rows',
   (SELECT COUNT(*)::TEXT FROM public.email_report_subscriptions),
   '3, unless you have added more')
) AS v(check_name, actual, expected);

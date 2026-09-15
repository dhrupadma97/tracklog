-- How a service line's quantity was arrived at
--
-- Manual Entry builds a short working for the services whose quantity is
-- derived rather than typed — "7.0 kWh x Rs 25/unit", "1.5 tons x 3 days ·
-- 2 bags" — and sent it as `notes`. The column does not exist, so PostgREST
-- rejected the whole insert with PGRST204 and every service line ever entered
-- failed. session_additional_services has stood empty since it was created.
--
-- The code was also writing `unit_rate` where the column is `rate`; that is
-- fixed in the app rather than by adding a second rate column.
--
-- The note is worth keeping: for a dead-weight or EV-charger line the
-- quantity alone (4.5, say) does not say whether that was tons times days or
-- anything else, and the invoice has to be reconciled against it.

ALTER TABLE public.session_additional_services
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- ── Verification ────────────────────────────────────────────────────────────
SELECT * FROM (VALUES
  ('notes column present',
   (SELECT COUNT(*)::TEXT FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'session_additional_services'
       AND column_name = 'notes'),
   '1'),
  ('unit_rate column (should NOT exist)',
   (SELECT COUNT(*)::TEXT FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'session_additional_services'
       AND column_name = 'unit_rate'),
   '0 — the app now writes `rate`'),
  ('columns on the table',
   (SELECT STRING_AGG(column_name, ', ' ORDER BY ordinal_position)
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'session_additional_services'),
   'id, session_id, service_name, quantity, rate, total_cost, created_at, notes'),
  ('service rows recorded',
   (SELECT COUNT(*)::TEXT FROM public.session_additional_services),
   '0 until the first line saves — every attempt so far was rejected')
) AS v(check_name, actual, expected);

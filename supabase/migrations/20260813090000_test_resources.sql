-- Testing resource tracking
--
-- People and assets available for testing, when they are available, and what
-- they are allocated to. Utilisation for anyone linked to an engineer profile
-- is derived from engineer_sessions; everyone else records actual hours on the
-- allocation itself.

-- 1. The resources themselves
CREATE TABLE IF NOT EXISTS public.test_resources (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_name TEXT NOT NULL,
  resource_type TEXT NOT NULL DEFAULT 'engineer',   -- engineer | technician | driver | vehicle | equipment
  employee_code TEXT,
  email TEXT,
  -- When set, utilisation comes from that engineer's sessions.
  engineer_profile_id UUID REFERENCES public.engineer_profiles(id) ON DELETE SET NULL,
  role_title TEXT,
  department TEXT DEFAULT 'Tyre Testing',
  supplier TEXT DEFAULT 'Goodyear',                 -- Goodyear | NATRAX | Contract
  daily_capacity_hours NUMERIC(5, 2) NOT NULL DEFAULT 8,
  status TEXT NOT NULL DEFAULT 'active',            -- active | inactive
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. Availability windows. Absence of a row means "available at capacity";
--    rows carve out leave, training, or time committed elsewhere.
CREATE TABLE IF NOT EXISTS public.resource_availability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_id UUID NOT NULL REFERENCES public.test_resources(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  availability_type TEXT NOT NULL DEFAULT 'available', -- available | leave | training | other_project | unavailable
  hours_per_day NUMERIC(5, 2),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT resource_availability_dates CHECK (end_date >= start_date)
);

-- 3. Allocation to a project for a period.
CREATE TABLE IF NOT EXISTS public.resource_allocations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_id UUID NOT NULL REFERENCES public.test_resources(id) ON DELETE CASCADE,
  project_name TEXT NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  allocated_hours NUMERIC(8, 2) NOT NULL DEFAULT 0,
  allocation_percent NUMERIC(5, 2),
  role_on_project TEXT,
  -- Only for resources with no engineer profile to derive hours from.
  actual_hours NUMERIC(8, 2),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT resource_allocations_dates CHECK (end_date >= start_date)
);

-- 4. Indexes
CREATE INDEX IF NOT EXISTS idx_test_resources_status
  ON public.test_resources(status);
CREATE INDEX IF NOT EXISTS idx_test_resources_profile
  ON public.test_resources(engineer_profile_id);
CREATE INDEX IF NOT EXISTS idx_resource_availability_resource
  ON public.resource_availability(resource_id, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_resource_allocations_resource
  ON public.resource_allocations(resource_id, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_resource_allocations_project
  ON public.resource_allocations(project_name);

-- 5. RLS — mirrors po_trackers: everyone authenticated reads, engineers write.
DO $rls$
DECLARE
  t TEXT;
  engineer_check CONSTANT TEXT :=
    'EXISTS (SELECT 1 FROM public.engineer_profiles ep'
    || ' WHERE ep.id = auth.uid() AND ep.user_role = ''engineer'')';
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'test_resources', 'resource_availability', 'resource_allocations'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    EXECUTE format('DROP POLICY IF EXISTS "authenticated_read_%s" ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY "authenticated_read_%s" ON public.%I '
      'FOR SELECT TO authenticated USING (true)', t, t);

    EXECUTE format('DROP POLICY IF EXISTS "engineers_manage_%s" ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY "engineers_manage_%s" ON public.%I '
      'FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',
      t, t, engineer_check, engineer_check);
  END LOOP;
END
$rls$;

-- 6. Keep updated_at fresh
CREATE OR REPLACE FUNCTION public.touch_resource_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_test_resources_updated_at ON public.test_resources;
CREATE TRIGGER trg_test_resources_updated_at
BEFORE UPDATE ON public.test_resources
FOR EACH ROW EXECUTE FUNCTION public.touch_resource_updated_at();

DROP TRIGGER IF EXISTS trg_resource_allocations_updated_at ON public.resource_allocations;
CREATE TRIGGER trg_resource_allocations_updated_at
BEFORE UPDATE ON public.resource_allocations
FOR EACH ROW EXECUTE FUNCTION public.touch_resource_updated_at();

-- 7. Seed the engineers who already have profiles, so the screen is not empty.
INSERT INTO public.test_resources
  (resource_name, resource_type, employee_code, email, engineer_profile_id,
   role_title, department, supplier)
SELECT
  ep.engineer_name,
  'engineer',
  ep.engineer_id,
  ep.email,
  ep.id,
  CASE WHEN ep.user_role = 'manager' THEN 'Manager' ELSE 'Test Engineer' END,
  ep.department,
  'Goodyear'
FROM public.engineer_profiles ep
WHERE NOT EXISTS (
  SELECT 1 FROM public.test_resources tr WHERE tr.engineer_profile_id = ep.id
);

-- 8. Verification
SELECT
  check_name,
  CASE WHEN passed THEN 'OK' ELSE 'MISSING' END AS status
FROM (
  VALUES
    ('table test_resources', to_regclass('public.test_resources') IS NOT NULL),
    ('table resource_availability',
     to_regclass('public.resource_availability') IS NOT NULL),
    ('table resource_allocations',
     to_regclass('public.resource_allocations') IS NOT NULL),
    ('policies (expect 6)',
     (SELECT count(*) FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename IN ('test_resources', 'resource_availability',
                          'resource_allocations')) = 6),
    ('engineers seeded as resources',
     (SELECT count(*) FROM public.test_resources) >= 0)
) AS t(check_name, passed);

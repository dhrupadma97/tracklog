-- PO Tracker & Manager Role Migration
-- Adds po_trackers table and manager role support to engineer_profiles

-- 1. Add role column to engineer_profiles if not exists
ALTER TABLE public.engineer_profiles
ADD COLUMN IF NOT EXISTS user_role TEXT NOT NULL DEFAULT 'engineer';

-- 2. PO Trackers table
CREATE TABLE IF NOT EXISTS public.po_trackers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  po_number TEXT NOT NULL UNIQUE,
  vendor_name TEXT NOT NULL,
  description TEXT,
  total_po_value NUMERIC(14, 2) NOT NULL DEFAULT 0,
  tax_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
  delivery_date DATE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_po_trackers_po_number ON public.po_trackers(po_number);
CREATE INDEX IF NOT EXISTS idx_engineer_profiles_role ON public.engineer_profiles(user_role);

-- 4. Enable RLS
ALTER TABLE public.po_trackers ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies — all authenticated users can read PO data (managers + engineers)
DROP POLICY IF EXISTS "authenticated_read_po_trackers" ON public.po_trackers;
CREATE POLICY "authenticated_read_po_trackers"
ON public.po_trackers
FOR SELECT
TO authenticated
USING (true);

-- Only engineers (non-managers) can insert/update (admin-level in practice)
DROP POLICY IF EXISTS "engineers_manage_po_trackers" ON public.po_trackers;
CREATE POLICY "engineers_manage_po_trackers"
ON public.po_trackers
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

-- 6. Seed PO 8242348442 from Goodyear South Asia Tyres Pvt. Limited
DO $$
BEGIN
  INSERT INTO public.po_trackers (
    po_number,
    vendor_name,
    description,
    total_po_value,
    tax_amount,
    delivery_date
  ) VALUES (
    '8242348442',
    'NATIONAL AUTOMOTIVE TEST TRACKS (NATRAX)',
    'Track & Workshop Booking at Natrax — Hiring test tracks at NATRAX, Dhar, MP. Ref: NATRAX/Q/TT/25-26/029 dated 25-02-2026. Issued by Goodyear South Asia Tyres Pvt. Limited dated 05.03.2026.',
    1904375.00,
    342788.00,
    '2026-09-30'
  )
  ON CONFLICT (po_number) DO NOTHING;
END $$;

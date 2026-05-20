-- ============================================================
-- NATRAX TrackLog: Additional Services Catalog
-- Migration: 20260520140000_additional_services_catalog.sql
-- ============================================================

-- 1. Additional services catalog table
CREATE TABLE IF NOT EXISTS public.additional_services_catalog (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_name TEXT NOT NULL UNIQUE,
    rate NUMERIC(10,2) NOT NULL,
    unit TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. Session additional services usage table (links sessions to services)
CREATE TABLE IF NOT EXISTS public.session_additional_services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES public.engineer_sessions(id) ON DELETE CASCADE,
    service_name TEXT NOT NULL,
    quantity NUMERIC(10,2) NOT NULL DEFAULT 0,
    rate NUMERIC(10,2) NOT NULL,
    total_cost NUMERIC(12,2) GENERATED ALWAYS AS (quantity * rate) STORED,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_session_additional_services_session_id ON public.session_additional_services(session_id);
CREATE INDEX IF NOT EXISTS idx_additional_services_catalog_name ON public.additional_services_catalog(service_name);

-- 4. RLS
ALTER TABLE public.additional_services_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_additional_services ENABLE ROW LEVEL SECURITY;

-- Catalog: readable by all authenticated users
DROP POLICY IF EXISTS "authenticated_read_services_catalog" ON public.additional_services_catalog;
CREATE POLICY "authenticated_read_services_catalog"
ON public.additional_services_catalog
FOR SELECT
TO authenticated
USING (true);

-- Session services: own sessions only
DROP POLICY IF EXISTS "engineers_manage_own_session_services" ON public.session_additional_services;
CREATE POLICY "engineers_manage_own_session_services"
ON public.session_additional_services
FOR ALL
TO authenticated
USING (
    session_id IN (
        SELECT id FROM public.engineer_sessions WHERE engineer_id = auth.uid()
    )
)
WITH CHECK (
    session_id IN (
        SELECT id FROM public.engineer_sessions WHERE engineer_id = auth.uid()
    )
);

-- 5. Seed updated additional services catalog
INSERT INTO public.additional_services_catalog (service_name, rate, unit, description)
VALUES
    ('Refreshment/Lunch', 125.00, 'nos', 'Refreshment or lunch per person'),
    ('Universal EV Charger', 25.00, 'unit', 'Universal EV charger usage per unit'),
    ('Sand bags 20/50kg', 150.00, 'nos/day', 'Sand bags (20kg or 50kg) per nos per day'),
    ('Unskilled Labour', 1100.00, 'day', 'Unskilled labour charges per day'),
    ('Electricity Charges', 15.00, 'unit', 'Electricity consumption per unit'),
    ('Big Conference Hall', 11000.00, 'day', 'Big conference hall booking per day')
ON CONFLICT (service_name) DO UPDATE
    SET rate = EXCLUDED.rate,
        unit = EXCLUDED.unit,
        description = EXCLUDED.description,
        is_active = true;

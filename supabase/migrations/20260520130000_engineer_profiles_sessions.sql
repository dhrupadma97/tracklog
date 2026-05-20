-- ============================================================
-- NATRAX TrackLog: Engineer Profiles, Sessions & Billing
-- Migration: 20260520130000_engineer_profiles_sessions.sql
-- ============================================================

-- 1. TYPES
DROP TYPE IF EXISTS public.vehicle_category CASCADE;
CREATE TYPE public.vehicle_category AS ENUM ('below_3_5t', 'above_3_5t');

DROP TYPE IF EXISTS public.booking_type CASCADE;
CREATE TYPE public.booking_type AS ENUM ('standard', 'exclusive');

DROP TYPE IF EXISTS public.session_status CASCADE;
CREATE TYPE public.session_status AS ENUM ('active', 'completed', 'warning');

-- 2. CORE TABLES

-- Engineer profiles (linked to auth.users)
CREATE TABLE IF NOT EXISTS public.engineer_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    engineer_name TEXT NOT NULL,
    engineer_id TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    department TEXT DEFAULT 'Tyre Testing',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- NATRAX track billing rates (reference table)
CREATE TABLE IF NOT EXISTS public.track_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    track_code TEXT NOT NULL,
    track_name TEXT NOT NULL,
    rate_below_3_5t NUMERIC(10,2) NOT NULL,
    rate_above_3_5t NUMERIC(10,2),
    exclusive_rate_below_3_5t NUMERIC(10,2),
    exclusive_rate_above_3_5t NUMERIC(10,2),
    exclusive_block_hours_below INTEGER DEFAULT 2,
    exclusive_block_hours_above INTEGER DEFAULT 4,
    min_hours_per_day INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Engineer sessions
CREATE TABLE IF NOT EXISTS public.engineer_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engineer_id UUID NOT NULL REFERENCES public.engineer_profiles(id) ON DELETE CASCADE,
    track_code TEXT NOT NULL,
    track_name TEXT NOT NULL,
    vehicle_category public.vehicle_category DEFAULT 'below_3_5t',
    booking_type public.booking_type DEFAULT 'standard',
    session_status public.session_status DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMPTZ,
    duration_minutes INTEGER,
    hourly_rate NUMERIC(10,2) NOT NULL,
    total_cost NUMERIC(12,2),
    notes TEXT,
    gate_entry_lat DOUBLE PRECISION,
    gate_entry_lng DOUBLE PRECISION,
    gate_exit_lat DOUBLE PRECISION,
    gate_exit_lng DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. INDEXES
CREATE INDEX IF NOT EXISTS idx_engineer_profiles_engineer_id ON public.engineer_profiles(engineer_id);
CREATE INDEX IF NOT EXISTS idx_engineer_sessions_engineer_id ON public.engineer_sessions(engineer_id);
CREATE INDEX IF NOT EXISTS idx_engineer_sessions_started_at ON public.engineer_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_engineer_sessions_status ON public.engineer_sessions(session_status);
CREATE INDEX IF NOT EXISTS idx_track_rates_code ON public.track_rates(track_code);

-- 4. FUNCTIONS

-- Auto-create engineer profile on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_engineer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.engineer_profiles (id, engineer_name, engineer_id, email, department)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'engineer_name', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'engineer_id', 'ENG-' || substring(NEW.id::TEXT, 1, 6)),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'department', 'Tyre Testing')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

-- 5. ENABLE RLS
ALTER TABLE public.engineer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.engineer_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.track_rates ENABLE ROW LEVEL SECURITY;

-- 6. RLS POLICIES

-- Engineer profiles: own profile only
DROP POLICY IF EXISTS "engineers_manage_own_profile" ON public.engineer_profiles;
CREATE POLICY "engineers_manage_own_profile"
ON public.engineer_profiles
FOR ALL
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Sessions: own sessions only
DROP POLICY IF EXISTS "engineers_manage_own_sessions" ON public.engineer_sessions;
CREATE POLICY "engineers_manage_own_sessions"
ON public.engineer_sessions
FOR ALL
TO authenticated
USING (engineer_id = auth.uid())
WITH CHECK (engineer_id = auth.uid());

-- Track rates: all authenticated users can read
DROP POLICY IF EXISTS "authenticated_read_track_rates" ON public.track_rates;
CREATE POLICY "authenticated_read_track_rates"
ON public.track_rates
FOR SELECT
TO authenticated
USING (true);

-- 7. TRIGGERS
DROP TRIGGER IF EXISTS on_auth_engineer_created ON auth.users;
CREATE TRIGGER on_auth_engineer_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_engineer();

DROP TRIGGER IF EXISTS update_engineer_profiles_updated_at ON public.engineer_profiles;
CREATE TRIGGER update_engineer_profiles_updated_at
    BEFORE UPDATE ON public.engineer_profiles
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_engineer_sessions_updated_at ON public.engineer_sessions;
CREATE TRIGGER update_engineer_sessions_updated_at
    BEFORE UPDATE ON public.engineer_sessions
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 8. SEED TRACK RATES (NATRAX Quotation NATRAX/Q/BIP/26-27/018)
INSERT INTO public.track_rates (track_code, track_name, rate_below_3_5t, rate_above_3_5t, exclusive_rate_below_3_5t, exclusive_rate_above_3_5t, exclusive_block_hours_below, exclusive_block_hours_above, min_hours_per_day)
VALUES
    ('T1',  'High Speed Track',                    25000, 27500, 180000, 360000, 2, 4, 2),
    ('T2',  'Dynamic Platform Track',              20000, 22000, 120000, 240000, 2, 4, 2),
    ('T3D', 'Straight Dry Braking Track',          19000, 21000, 150000, 300000, 2, 4, 2),
    ('T3W', 'Straight Wet Braking Track',          21000, 23000, 150000, 300000, 2, 4, 2),
    ('T4',  'Test Hill Track',                     8000,  9000,  NULL,   NULL,   0, 0, 1),
    ('T5',  'Accelerated Fatigue Track',           14000, 17000, NULL,   NULL,   0, 0, 1),
    ('T6',  'Gravel and Off Road Track',           7500,  8500,  NULL,   NULL,   0, 0, 1),
    ('T7',  'Handling Track 4W (1.6 Km)',          15000, 17500, 60000,  120000, 2, 4, 1),
    ('T8',  'Comfort Track',                       10500, 11500, 48000,  96000,  2, 4, 1),
    ('T9',  'Handling Track 2W',                   5000,  NULL,  NULL,   NULL,   0, 0, 1),
    ('T10', 'Sustainability Track',                6000,  7000,  NULL,   NULL,   0, 0, 1),
    ('T11', 'Wet Skid Pad Track',                  15000, NULL,  NULL,   NULL,   0, 0, 1),
    ('T12', 'Suspension and Traction Track',       6000,  7000,  NULL,   NULL,   0, 0, 1),
    ('T13', 'External Noise Track',                14000, 16500, NULL,   NULL,   0, 0, 1),
    ('GR',  'General Road Track',                  9000,  10000, NULL,   NULL,   0, 0, 1),
    ('CC',  'Cut and Chip Track',                  10500, 10500, NULL,   NULL,   0, 0, 1)
ON CONFLICT (id) DO NOTHING;

-- 9. MOCK ENGINEER ACCOUNTS (for testing)
DO $$
DECLARE
    eng1_uuid UUID := gen_random_uuid();
    eng2_uuid UUID := gen_random_uuid();
    eng3_uuid UUID := gen_random_uuid();
    t1_rate NUMERIC := 25000;
    t7_rate NUMERIC := 15000;
    t11_rate NUMERIC := 15000;
BEGIN
    -- Create auth users (trigger auto-creates engineer_profiles)
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_user_meta_data, raw_app_meta_data,
        is_sso_user, is_anonymous, confirmation_token, confirmation_sent_at,
        recovery_token, recovery_sent_at, email_change_token_new, email_change,
        email_change_sent_at, email_change_token_current, email_change_confirm_status,
        reauthentication_token, reauthentication_sent_at, phone, phone_change,
        phone_change_token, phone_change_sent_at
    ) VALUES
        (eng1_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'arjun.sharma@goodyear.com', crypt('Goodyear@2026', gen_salt('bf', 10)), now(), now(), now(),
         jsonb_build_object('engineer_name', 'Arjun Sharma', 'engineer_id', 'GY-ENG-001', 'department', 'Tyre Testing'),
         jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (eng2_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'priya.nair@goodyear.com', crypt('Goodyear@2026', gen_salt('bf', 10)), now(), now(), now(),
         jsonb_build_object('engineer_name', 'Priya Nair', 'engineer_id', 'GY-ENG-002', 'department', 'Vehicle Dynamics'),
         jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (eng3_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'rahul.mehta@goodyear.com', crypt('Goodyear@2026', gen_salt('bf', 10)), now(), now(), now(),
         jsonb_build_object('engineer_name', 'Rahul Mehta', 'engineer_id', 'GY-ENG-003', 'department', 'Braking Systems'),
         jsonb_build_object('provider', 'email', 'providers', ARRAY['email']::TEXT[]),
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null)
    ON CONFLICT (id) DO NOTHING;

    -- Seed sample sessions for eng1
    INSERT INTO public.engineer_sessions (
        id, engineer_id, track_code, track_name, vehicle_category, booking_type,
        session_status, started_at, ended_at, duration_minutes, hourly_rate, total_cost, notes
    ) VALUES
        (gen_random_uuid(), eng1_uuid, 'T1', 'High Speed Track', 'below_3_5t', 'standard',
         'completed', now() - INTERVAL '2 days' + INTERVAL '8 hours',
         now() - INTERVAL '2 days' + INTERVAL '11 hours 7 minutes',
         187, t1_rate, ROUND((187.0/60.0) * t1_rate, 2),
         'Wet grip validation — Goodyear EfficientGrip 2'),
        (gen_random_uuid(), eng1_uuid, 'T7', 'Handling Track 4W (1.6 Km)', 'below_3_5t', 'standard',
         'warning', now() - INTERVAL '3 days' + INTERVAL '7 hours 45 minutes',
         now() - INTERVAL '3 days' + INTERVAL '13 hours 3 minutes',
         318, t7_rate, ROUND((318.0/60.0) * t7_rate, 2),
         'High-speed circuit — exceeded 4hr booking window')
    ON CONFLICT (id) DO NOTHING;

    -- Seed sample sessions for eng2
    INSERT INTO public.engineer_sessions (
        id, engineer_id, track_code, track_name, vehicle_category, booking_type,
        session_status, started_at, ended_at, duration_minutes, hourly_rate, total_cost, notes
    ) VALUES
        (gen_random_uuid(), eng2_uuid, 'T2', 'Dynamic Platform Track', 'below_3_5t', 'standard',
         'completed', now() - INTERVAL '1 day' + INTERVAL '9 hours 30 minutes',
         now() - INTERVAL '1 day' + INTERVAL '13 hours 35 minutes',
         245, 20000, ROUND((245.0/60.0) * 20000, 2),
         'Vehicle dynamics — tyre development run')
    ON CONFLICT (id) DO NOTHING;

    -- Seed sample sessions for eng3
    INSERT INTO public.engineer_sessions (
        id, engineer_id, track_code, track_name, vehicle_category, booking_type,
        session_status, started_at, ended_at, duration_minutes, hourly_rate, total_cost, notes
    ) VALUES
        (gen_random_uuid(), eng3_uuid, 'T3D', 'Straight Dry Braking Track', 'below_3_5t', 'standard',
         'completed', now() - INTERVAL '1 day' + INTERVAL '14 hours',
         now() - INTERVAL '1 day' + INTERVAL '15 hours 32 minutes',
         92, 19000, ROUND((92.0/60.0) * 19000, 2),
         'ABS homologation — aquaplaning tests'),
        (gen_random_uuid(), eng3_uuid, 'T11', 'Wet Skid Pad Track', 'below_3_5t', 'standard',
         'completed', now() - INTERVAL '4 days' + INTERVAL '10 hours',
         now() - INTERVAL '4 days' + INTERVAL '12 hours',
         120, t11_rate, ROUND((120.0/60.0) * t11_rate, 2),
         'ESP development — basalt surface')
    ON CONFLICT (id) DO NOTHING;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Mock data insertion failed: %', SQLERRM;
END $$;

-- ============================================================
-- NATRAX TrackLog: Database Clean & Admin Account Setup (CORRECTED)
-- Run this in the Supabase SQL Editor to initialize.
-- ============================================================

-- 1. Enable pgcrypto extension for crypt
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Clear all existing sessions, profiles, and auth users to start fresh
DO $$
DECLARE
    engineer_ids UUID[];
BEGIN
    -- Collect all existing profile IDs
    SELECT ARRAY_AGG(id) INTO engineer_ids FROM public.engineer_profiles;
    
    IF engineer_ids IS NOT NULL AND array_length(engineer_ids, 1) > 0 THEN
        -- Delete dependent data
        DELETE FROM public.session_additional_services WHERE session_id IN (SELECT id FROM public.engineer_sessions);
        DELETE FROM public.sand_bag_rentals WHERE engineer_id = ANY(engineer_ids);
        DELETE FROM public.rental_instruments WHERE engineer_id = ANY(engineer_ids);
        DELETE FROM public.daily_billing_summaries WHERE engineer_id = ANY(engineer_ids);
        DELETE FROM public.monthly_invoices WHERE engineer_id = ANY(engineer_ids);
        DELETE FROM public.engineer_sessions WHERE engineer_id = ANY(engineer_ids);
        DELETE FROM public.engineer_profiles WHERE id = ANY(engineer_ids);
        DELETE FROM auth.users WHERE id = ANY(engineer_ids);
    END IF;

    -- Also clean up any loose users in auth.users by email
    DELETE FROM auth.users WHERE email IN (
        'dhrupad_ma@goodyear.com',
        'arjun.sharma@goodyear.com',
        'priya.nair@goodyear.com',
        'rahul.mehta@goodyear.com'
    );
END $$;

-- 3. Create the Main Admin Account (Dhrupad Mullath Anilkumar)
-- NOTE: We delegate the admin account creation to the `register_admin.js` script using the Supabase API.
-- This guarantees that both `auth.users` and `auth.identities` tables are populated correctly
-- for your Supabase instance, preventing login schema issues.
--
-- Running setup_db.sql will delete any existing corrupted users with this email to allow fresh registration.

-- 5. Add unique constraint on track_code so ON CONFLICT works, and delete old rates to avoid duplicates
ALTER TABLE public.track_rates DROP CONSTRAINT IF EXISTS track_rates_track_code_key;
ALTER TABLE public.track_rates ADD CONSTRAINT track_rates_track_code_key UNIQUE (track_code);

DELETE FROM public.track_rates;

-- 6. Seed default track rates (NATRAX Quotation rates)
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
ON CONFLICT (track_code) DO NOTHING;

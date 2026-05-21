-- ============================================================
-- NATRAX TrackLog: Re-seed Historical Data (Idempotent)
-- Migration: 20260521032000_reseed_historical_data.sql
-- Safely re-inserts all historical entries; skips duplicates.
-- ============================================================

DO $$
DECLARE
    eng_id UUID;
    -- Session UUIDs (stable, deterministic)
    s_24mar UUID := 'a1000001-0000-0000-0000-000000000001';
    s_25mar UUID := 'a1000001-0000-0000-0000-000000000002';
    s_07apr_t3d_1 UUID := 'a1000001-0000-0000-0000-000000000003';
    s_07apr_t3d_2 UUID := 'a1000001-0000-0000-0000-000000000004';
    s_07apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000005';
    s_07apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000006';
    s_08apr_t3d_1 UUID := 'a1000001-0000-0000-0000-000000000007';
    s_08apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000008';
    s_08apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000009';
    s_08apr_t7    UUID := 'a1000001-0000-0000-0000-000000000010';
    s_08apr_t2    UUID := 'a1000001-0000-0000-0000-000000000011';
    s_09apr_t3d   UUID := 'a1000001-0000-0000-0000-000000000012';
    s_09apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000013';
    s_09apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000014';
    s_10apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000015';
    s_10apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000016';
    s_10apr_t2_1  UUID := 'a1000001-0000-0000-0000-000000000017';
    s_10apr_t2_2  UUID := 'a1000001-0000-0000-0000-000000000018';
    s_14apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000019';
    s_14apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000020';
    s_15apr_t3w   UUID := 'a1000001-0000-0000-0000-000000000021';
    s_17apr_t1_1  UUID := 'a1000001-0000-0000-0000-000000000022';
    s_17apr_t1_2  UUID := 'a1000001-0000-0000-0000-000000000023';
    s_17apr_t1_3  UUID := 'a1000001-0000-0000-0000-000000000024';
    s_17apr_t7_1  UUID := 'a1000001-0000-0000-0000-000000000025';
    s_17apr_t7_2  UUID := 'a1000001-0000-0000-0000-000000000026';
    s_17apr_t1_4  UUID := 'a1000001-0000-0000-0000-000000000027';
    s_17apr_t7_3  UUID := 'a1000001-0000-0000-0000-000000000028';
    s_17apr_t1_5  UUID := 'a1000001-0000-0000-0000-000000000029';
    s_26apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000030';
    s_26apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000031';
    s_26apr_t3w_3 UUID := 'a1000001-0000-0000-0000-000000000032';
    s_27apr_t3w   UUID := 'a1000001-0000-0000-0000-000000000033';
    s_28apr_t3w_1 UUID := 'a1000001-0000-0000-0000-000000000034';
    s_28apr_t3w_2 UUID := 'a1000001-0000-0000-0000-000000000035';
    s_28apr_t3w_3 UUID := 'a1000001-0000-0000-0000-000000000036';
    -- Daily billing UUIDs (stable)
    db_24mar      UUID := 'b1000001-0000-0000-0000-000000000001';
    db_25mar      UUID := 'b1000001-0000-0000-0000-000000000002';
    db_07apr_t3d  UUID := 'b1000001-0000-0000-0000-000000000003';
    db_07apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000004';
    db_08apr_t3d  UUID := 'b1000001-0000-0000-0000-000000000005';
    db_08apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000006';
    db_08apr_t7   UUID := 'b1000001-0000-0000-0000-000000000007';
    db_08apr_t2   UUID := 'b1000001-0000-0000-0000-000000000008';
    db_09apr_t3d  UUID := 'b1000001-0000-0000-0000-000000000009';
    db_09apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000010';
    db_10apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000011';
    db_10apr_t2   UUID := 'b1000001-0000-0000-0000-000000000012';
    db_14apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000013';
    db_15apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000014';
    db_17apr_t1   UUID := 'b1000001-0000-0000-0000-000000000015';
    db_17apr_t7   UUID := 'b1000001-0000-0000-0000-000000000016';
    db_26apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000017';
    db_27apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000018';
    db_28apr_t3w  UUID := 'b1000001-0000-0000-0000-000000000019';
BEGIN
    -- Get the first engineer profile
    SELECT id INTO eng_id FROM public.engineer_profiles ORDER BY created_at ASC LIMIT 1;

    IF eng_id IS NULL THEN
        RAISE NOTICE 'No engineer profile found. Skipping historical re-seed.';
        RETURN;
    END IF;

    RAISE NOTICE 'Re-seeding historical data for engineer: %', eng_id;

    -- ================================================================
    -- TRACK SESSIONS
    -- ================================================================
    INSERT INTO public.engineer_sessions (
        id, engineer_id, track_code, track_name, vehicle_category, booking_type,
        session_status, started_at, ended_at, duration_minutes, hourly_rate, total_cost, notes
    ) VALUES
        -- 24-Mar-2026 T3 Wet  12:30 PM - 04:30 PM  4.00 hrs
        (s_24mar, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-03-24 12:30:00+05:30', '2026-03-24 16:30:00+05:30', 240, 21000, 84000, 'Historical session'),
        -- 25-Mar-2026 T3 Wet  11:30 AM - 02:30 PM  3.00 hrs
        (s_25mar, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-03-25 11:30:00+05:30', '2026-03-25 14:30:00+05:30', 180, 21000, 63000, 'Historical session'),
        -- 07-Apr-2026 T3 Dry  03:57 PM - 04:34 PM  0.62 hrs
        (s_07apr_t3d_1, eng_id, 'T3D', 'Straight Dry Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-07 15:57:00+05:30', '2026-04-07 16:34:00+05:30', 37, 19000, 11717, 'Historical session'),
        -- 07-Apr-2026 T3 Dry  02:57 PM - 03:09 PM  0.20 hrs
        (s_07apr_t3d_2, eng_id, 'T3D', 'Straight Dry Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-07 14:57:00+05:30', '2026-04-07 15:09:00+05:30', 12, 19000, 3800, 'Historical session'),
        -- 07-Apr-2026 T3 Wet  03:10 PM - 03:33 PM  0.38 hrs
        (s_07apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-07 15:10:00+05:30', '2026-04-07 15:33:00+05:30', 23, 21000, 8050, 'Historical session'),
        -- 07-Apr-2026 T3 Wet  04:35 PM - 05:42 PM  1.12 hrs
        (s_07apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-07 16:35:00+05:30', '2026-04-07 17:42:00+05:30', 67, 21000, 23450, 'Historical session'),
        -- 08-Apr-2026 T3 Dry  11:59 AM - 12:35 PM  0.60 hrs
        (s_08apr_t3d_1, eng_id, 'T3D', 'Straight Dry Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-08 11:59:00+05:30', '2026-04-08 12:35:00+05:30', 36, 19000, 11400, 'Historical session'),
        -- 08-Apr-2026 T3 Wet  12:36 PM - 02:02 PM  1.43 hrs
        (s_08apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-08 12:36:00+05:30', '2026-04-08 14:02:00+05:30', 86, 21000, 30100, 'Historical session'),
        -- 08-Apr-2026 T3 Wet  04:06 PM - 05:31 PM  1.42 hrs
        (s_08apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-08 16:06:00+05:30', '2026-04-08 17:31:00+05:30', 85, 21000, 29750, 'Historical session'),
        -- 08-Apr-2026 T7  06:00 PM - 06:30 PM  0.50 hrs
        (s_08apr_t7, eng_id, 'T7', 'Handling Track 4W (1.6 Km)', 'below_3_5t', 'standard',
         'completed', '2026-04-08 18:00:00+05:30', '2026-04-08 18:30:00+05:30', 30, 15000, 7500, 'Historical session'),
        -- 08-Apr-2026 T2  06:35 PM - 07:10 PM  0.58 hrs
        (s_08apr_t2, eng_id, 'T2', 'Dynamic Platform Track', 'below_3_5t', 'standard',
         'completed', '2026-04-08 18:35:00+05:30', '2026-04-08 19:10:00+05:30', 35, 20000, 11667, 'Historical session'),
        -- 09-Apr-2026 T3 Dry  10:00 AM - 10:50 AM  0.83 hrs
        (s_09apr_t3d, eng_id, 'T3D', 'Straight Dry Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-09 10:00:00+05:30', '2026-04-09 10:50:00+05:30', 50, 19000, 15833, 'Historical session'),
        -- 09-Apr-2026 T3 Wet  10:51 AM - 01:55 PM  3.07 hrs
        (s_09apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-09 10:51:00+05:30', '2026-04-09 13:55:00+05:30', 184, 21000, 64400, 'Historical session'),
        -- 09-Apr-2026 T3 Wet  04:06 PM - 06:55 PM  2.82 hrs
        (s_09apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-09 16:06:00+05:30', '2026-04-09 18:55:00+05:30', 169, 21000, 58800, 'Historical session'),
        -- 10-Apr-2026 T3 Wet  09:03 AM - 11:15 AM  2.20 hrs
        (s_10apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-10 09:03:00+05:30', '2026-04-10 11:15:00+05:30', 132, 21000, 46200, 'Historical session'),
        -- 10-Apr-2026 T3 Wet  04:48 PM - 05:46 PM  0.97 hrs
        (s_10apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-10 16:48:00+05:30', '2026-04-10 17:46:00+05:30', 58, 21000, 20370, 'Historical session'),
        -- 10-Apr-2026 T2  12:30 PM - 02:10 PM  1.67 hrs
        (s_10apr_t2_1, eng_id, 'T2', 'Dynamic Platform Track', 'below_3_5t', 'standard',
         'completed', '2026-04-10 12:30:00+05:30', '2026-04-10 14:10:00+05:30', 100, 20000, 33333, 'Historical session'),
        -- 10-Apr-2026 T2  03:20 PM - 04:20 PM  1.00 hrs
        (s_10apr_t2_2, eng_id, 'T2', 'Dynamic Platform Track', 'below_3_5t', 'standard',
         'completed', '2026-04-10 15:20:00+05:30', '2026-04-10 16:20:00+05:30', 60, 20000, 20000, 'Historical session'),
        -- 14-Apr-2026 T3 Wet  10:30 AM - 01:40 PM  3.17 hrs
        (s_14apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-14 10:30:00+05:30', '2026-04-14 13:40:00+05:30', 190, 21000, 66500, 'Historical session'),
        -- 14-Apr-2026 T3 Wet  02:50 PM - 04:19 PM  1.48 hrs
        (s_14apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-14 14:50:00+05:30', '2026-04-14 16:19:00+05:30', 89, 21000, 31150, 'Historical session'),
        -- 15-Apr-2026 T3 Wet  07:05 AM - 09:20 AM  2.25 hrs
        (s_15apr_t3w, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-15 07:05:00+05:30', '2026-04-15 09:20:00+05:30', 135, 21000, 47250, 'Historical session'),
        -- 17-Apr-2026 T1  10:46 AM - 11:06 AM  0.33 hrs
        (s_17apr_t1_1, eng_id, 'T1', 'High Speed Track', 'below_3_5t', 'standard',
         'completed', '2026-04-17 10:46:00+05:30', '2026-04-17 11:06:00+05:30', 20, 25000, 8333, 'Historical session'),
        -- 17-Apr-2026 T1  11:59 AM - 12:21 PM  0.37 hrs
        (s_17apr_t1_2, eng_id, 'T1', 'High Speed Track', 'below_3_5t', 'standard',
         'completed', '2026-04-17 11:59:00+05:30', '2026-04-17 12:21:00+05:30', 22, 25000, 9167, 'Historical session'),
        -- 17-Apr-2026 T1  12:30 PM - 12:50 PM  0.33 hrs
        (s_17apr_t1_3, eng_id, 'T1', 'High Speed Track', 'below_3_5t', 'standard',
         'completed', '2026-04-17 12:30:00+05:30', '2026-04-17 12:50:00+05:30', 20, 25000, 8333, 'Historical session'),
        -- 17-Apr-2026 T7  01:06 AM - 01:27 AM  0.35 hrs
        (s_17apr_t7_1, eng_id, 'T7', 'Handling Track 4W (1.6 Km)', 'below_3_5t', 'standard',
         'completed', '2026-04-17 01:06:00+05:30', '2026-04-17 01:27:00+05:30', 21, 15000, 5250, 'Historical session'),
        -- 17-Apr-2026 T7  02:36 AM - 02:59 AM  0.38 hrs
        (s_17apr_t7_2, eng_id, 'T7', 'Handling Track 4W (1.6 Km)', 'below_3_5t', 'standard',
         'completed', '2026-04-17 02:36:00+05:30', '2026-04-17 02:59:00+05:30', 23, 15000, 5750, 'Historical session'),
        -- 17-Apr-2026 T1  03:13 AM - 03:33 AM  0.33 hrs
        (s_17apr_t1_4, eng_id, 'T1', 'High Speed Track', 'below_3_5t', 'standard',
         'completed', '2026-04-17 03:13:00+05:30', '2026-04-17 03:33:00+05:30', 20, 25000, 8333, 'Historical session'),
        -- 17-Apr-2026 T7  03:58 AM - 04:18 AM  0.33 hrs
        (s_17apr_t7_3, eng_id, 'T7', 'Handling Track 4W (1.6 Km)', 'below_3_5t', 'standard',
         'completed', '2026-04-17 03:58:00+05:30', '2026-04-17 04:18:00+05:30', 20, 15000, 5000, 'Historical session'),
        -- 17-Apr-2026 T1  04:22 AM - 04:45 AM  0.38 hrs
        (s_17apr_t1_5, eng_id, 'T1', 'High Speed Track', 'below_3_5t', 'standard',
         'completed', '2026-04-17 04:22:00+05:30', '2026-04-17 04:45:00+05:30', 23, 25000, 9583, 'Historical session'),
        -- 26-Apr-2026 T3 Wet  08:30 AM - 10:28 AM  1.97 hrs
        (s_26apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-26 08:30:00+05:30', '2026-04-26 10:28:00+05:30', 118, 21000, 41370, 'Historical session'),
        -- 26-Apr-2026 T3 Wet  11:45 AM - 12:24 PM  0.65 hrs
        (s_26apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-26 11:45:00+05:30', '2026-04-26 12:24:00+05:30', 39, 21000, 13650, 'Historical session'),
        -- 26-Apr-2026 T3 Wet  01:58 PM - 04:15 PM  2.28 hrs
        (s_26apr_t3w_3, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-26 13:58:00+05:30', '2026-04-26 16:15:00+05:30', 137, 21000, 47880, 'Historical session'),
        -- 27-Apr-2026 T3 Wet  10:00 AM - 12:00 PM  2.00 hrs
        (s_27apr_t3w, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-27 10:00:00+05:30', '2026-04-27 12:00:00+05:30', 120, 21000, 42000, 'Historical session'),
        -- 28-Apr-2026 T3 Wet  09:12 AM - 09:58 AM  0.77 hrs
        (s_28apr_t3w_1, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-28 09:12:00+05:30', '2026-04-28 09:58:00+05:30', 46, 21000, 16170, 'Historical session'),
        -- 28-Apr-2026 T3 Wet  10:08 AM - 12:38 PM  2.50 hrs
        (s_28apr_t3w_2, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-28 10:08:00+05:30', '2026-04-28 12:38:00+05:30', 150, 21000, 52500, 'Historical session'),
        -- 28-Apr-2026 T3 Wet  04:20 PM - 04:37 PM  0.28 hrs
        (s_28apr_t3w_3, eng_id, 'T3W', 'Straight Wet Braking Track', 'below_3_5t', 'standard',
         'completed', '2026-04-28 16:20:00+05:30', '2026-04-28 16:37:00+05:30', 17, 21000, 5950, 'Historical session')
    ON CONFLICT (id) DO NOTHING;

    -- ================================================================
    -- ADDITIONAL SERVICES
    -- Delete old ones for these sessions first, then re-insert cleanly
    -- ================================================================
    DELETE FROM public.session_additional_services
    WHERE session_id IN (
        s_24mar, s_25mar, s_07apr_t3d_1, s_07apr_t3d_2, s_07apr_t3w_1, s_07apr_t3w_2,
        s_08apr_t3d_1, s_08apr_t3w_1, s_08apr_t3w_2, s_08apr_t7, s_08apr_t2,
        s_09apr_t3d, s_09apr_t3w_1, s_09apr_t3w_2,
        s_10apr_t3w_1, s_10apr_t3w_2, s_10apr_t2_1, s_10apr_t2_2,
        s_14apr_t3w_1, s_14apr_t3w_2, s_15apr_t3w,
        s_17apr_t1_1, s_17apr_t1_2, s_17apr_t1_3, s_17apr_t7_1, s_17apr_t7_2,
        s_17apr_t1_4, s_17apr_t7_3, s_17apr_t1_5,
        s_26apr_t3w_1, s_26apr_t3w_2, s_26apr_t3w_3,
        s_27apr_t3w, s_28apr_t3w_1, s_28apr_t3w_2, s_28apr_t3w_3
    );

    INSERT INTO public.session_additional_services (id, session_id, service_name, quantity, rate)
    VALUES
        -- 25-Mar-2026: Refreshment/Lunch x17 @ ₹125
        (gen_random_uuid(), s_25mar, 'Refreshment/Lunch', 17, 125),
        -- 24-Mar-2026: Universal EV Charger x139.2 kWh @ ₹25
        (gen_random_uuid(), s_24mar, 'Universal EV Charger', 139.2, 25),
        -- 07-Apr-2026: Universal EV Charger x45 kWh @ ₹25
        (gen_random_uuid(), s_07apr_t3w_1, 'Universal EV Charger', 45, 25),
        -- 07-Apr-2026: Sand bags 20/50kg x36 days @ ₹150
        (gen_random_uuid(), s_07apr_t3w_1, 'Sand bags 20/50kg', 36, 150),
        -- 07-Apr-2026: Unskilled Labour x2 @ ₹1100
        (gen_random_uuid(), s_07apr_t3w_1, 'Unskilled Labour', 2, 1100),
        -- 08-Apr-2026: Electricity Charges x45 units @ ₹15
        (gen_random_uuid(), s_08apr_t3w_1, 'Electricity Charges', 45, 15),
        -- 09-Apr-2026: Electricity Charges x45 units @ ₹15
        (gen_random_uuid(), s_09apr_t3w_1, 'Electricity Charges', 45, 15),
        -- 10-Apr-2026: Electricity Charges x45 units @ ₹15
        (gen_random_uuid(), s_10apr_t3w_1, 'Electricity Charges', 45, 15),
        -- 15-Apr-2026: Electricity Charges x50 units @ ₹15
        (gen_random_uuid(), s_15apr_t3w, 'Electricity Charges', 50, 15),
        -- 17-Apr-2026: Electricity Charges x30 units @ ₹15
        (gen_random_uuid(), s_17apr_t1_1, 'Electricity Charges', 30, 15),
        -- 17-Apr-2026: Sand bags 20/50kg x39 days @ ₹150
        (gen_random_uuid(), s_17apr_t1_1, 'Sand bags 20/50kg', 39, 150),
        -- 17-Apr-2026: Unskilled Labour x2 @ ₹1100
        (gen_random_uuid(), s_17apr_t1_1, 'Unskilled Labour', 2, 1100),
        -- 17-Apr-2026: Universal EV Charger x20 kWh @ ₹25
        (gen_random_uuid(), s_17apr_t1_2, 'Universal EV Charger', 20, 25),
        -- 17-Apr-2026: Universal EV Charger x40 kWh @ ₹25
        (gen_random_uuid(), s_17apr_t1_3, 'Universal EV Charger', 40, 25),
        -- 26-Apr-2026: Universal EV Charger x20 kWh @ ₹25
        (gen_random_uuid(), s_26apr_t3w_1, 'Universal EV Charger', 20, 25),
        -- 26-Apr-2026: Universal EV Charger x45 kWh @ ₹25
        (gen_random_uuid(), s_26apr_t3w_2, 'Universal EV Charger', 45, 25),
        -- 27-Apr-2026: Universal EV Charger x45 kWh @ ₹25
        (gen_random_uuid(), s_27apr_t3w, 'Universal EV Charger', 45, 25),
        -- 28-Apr-2026: Universal EV Charger x45 kWh @ ₹25
        (gen_random_uuid(), s_28apr_t3w_1, 'Universal EV Charger', 45, 25),
        -- 28-Apr-2026: Big Conference Hall x1 @ ₹11000
        (gen_random_uuid(), s_28apr_t3w_2, 'Big Conference Hall', 1, 11000);

    -- ================================================================
    -- DAILY BILLING SUMMARIES
    -- ================================================================
    INSERT INTO public.daily_billing_summaries (
        id, engineer_id, billing_date, track_code, track_name,
        total_accumulated_hrs, subject_to_min, final_billable_hrs,
        rate_per_hr, final_track_cost, accessories_services_cost, total_track_acc_cost
    ) VALUES
        (db_24mar, eng_id, '2026-03-24', 'T3W', 'Straight Wet Braking Track',
         4.00, true, 4.00, 19000, 76000, 3480, 79480),
        (db_25mar, eng_id, '2026-03-25', 'T3W', 'Straight Wet Braking Track',
         3.00, true, 3.00, 19000, 57000, 2125, 59125),
        (db_07apr_t3d, eng_id, '2026-04-07', 'T3D', 'Straight Dry Braking Track',
         0.82, true, 1.00, 19000, 19000, 0, 19000),
        (db_07apr_t3w, eng_id, '2026-04-07', 'T3W', 'Straight Wet Braking Track',
         1.50, true, 2.00, 21000, 42000, 8725, 50725),
        (db_08apr_t3d, eng_id, '2026-04-08', 'T3D', 'Straight Dry Braking Track',
         0.60, true, 1.00, 19000, 19000, 0, 19000),
        (db_08apr_t3w, eng_id, '2026-04-08', 'T3W', 'Straight Wet Braking Track',
         2.85, true, 3.00, 21000, 63000, 675, 63675),
        (db_08apr_t7, eng_id, '2026-04-08', 'T7', 'Handling Track 4W (1.6 Km)',
         0.50, false, 1.00, 15000, 15000, 0, 15000),
        (db_08apr_t2, eng_id, '2026-04-08', 'T2', 'Dynamic Platform Track',
         0.58, true, 2.00, 20000, 40000, 0, 40000),
        (db_09apr_t3d, eng_id, '2026-04-09', 'T3D', 'Straight Dry Braking Track',
         0.83, true, 1.00, 19000, 19000, 675, 19675),
        (db_09apr_t3w, eng_id, '2026-04-09', 'T3W', 'Straight Wet Braking Track',
         5.88, true, 6.00, 21000, 126000, 0, 126000),
        (db_10apr_t3w, eng_id, '2026-04-10', 'T3W', 'Straight Wet Braking Track',
         3.17, true, 4.00, 21000, 84000, 675, 84675),
        (db_10apr_t2, eng_id, '2026-04-10', 'T2', 'Dynamic Platform Track',
         2.67, true, 3.00, 20000, 60000, 0, 60000),
        (db_14apr_t3w, eng_id, '2026-04-14', 'T3W', 'Straight Wet Braking Track',
         4.65, true, 5.00, 21000, 105000, 0, 105000),
        (db_15apr_t3w, eng_id, '2026-04-15', 'T3W', 'Straight Wet Braking Track',
         2.25, true, 3.00, 21000, 63000, 750, 63750),
        (db_17apr_t1, eng_id, '2026-04-17', 'T1', 'High Speed Track',
         1.75, true, 2.00, 25000, 50000, 10000, 60000),
        (db_17apr_t7, eng_id, '2026-04-17', 'T7', 'Handling Track 4W (1.6 Km)',
         1.07, false, 2.00, 15000, 30000, 0, 30000),
        (db_26apr_t3w, eng_id, '2026-04-26', 'T3W', 'Straight Wet Braking Track',
         4.90, true, 5.00, 21000, 105000, 1625, 106625),
        (db_27apr_t3w, eng_id, '2026-04-27', 'T3W', 'Straight Wet Braking Track',
         2.00, true, 2.00, 21000, 42000, 1125, 43125),
        (db_28apr_t3w, eng_id, '2026-04-28', 'T3W', 'Straight Wet Braking Track',
         3.55, true, 4.00, 21000, 84000, 12125, 96125)
    ON CONFLICT (id) DO UPDATE
        SET total_accumulated_hrs = EXCLUDED.total_accumulated_hrs,
            final_billable_hrs = EXCLUDED.final_billable_hrs,
            final_track_cost = EXCLUDED.final_track_cost,
            accessories_services_cost = EXCLUDED.accessories_services_cost,
            total_track_acc_cost = EXCLUDED.total_track_acc_cost;

    -- ================================================================
    -- MONTHLY INVOICES
    -- March 2026: Track+Acc ₹138605 + Workshop ₹55000 = ₹193605 + GST 18% = ₹228453.90
    -- April 2026: Track+Acc ₹1002375 + Workshop ₹150000 = ₹1152375 + GST 18% = ₹1359802.50
    -- ================================================================
    INSERT INTO public.monthly_invoices (
        engineer_id, billing_month,
        track_acc_subtotal, workshop_cost, subtotal_excl_gst,
        gst_rate, gst_amount, total_invoice_amount
    ) VALUES
        (eng_id, '2026-03-01',
         138605.00, 55000.00, 193605.00,
         18.00, 34848.90, 228453.90),
        (eng_id, '2026-04-01',
         1002375.00, 150000.00, 1152375.00,
         18.00, 207427.50, 1359802.50)
    ON CONFLICT (engineer_id, billing_month) DO UPDATE
        SET track_acc_subtotal = EXCLUDED.track_acc_subtotal,
            workshop_cost = EXCLUDED.workshop_cost,
            subtotal_excl_gst = EXCLUDED.subtotal_excl_gst,
            gst_amount = EXCLUDED.gst_amount,
            total_invoice_amount = EXCLUDED.total_invoice_amount;

    RAISE NOTICE 'Historical re-seed completed successfully for engineer: %', eng_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Historical re-seed failed: %', SQLERRM;
END $$;

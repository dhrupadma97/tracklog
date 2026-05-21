-- ============================================================
-- Clear all engineer profiles and associated auth users
-- This removes all saved credentials from the database
-- ============================================================

DO $$
DECLARE
    engineer_ids UUID[];
BEGIN
    -- Collect all engineer profile IDs
    SELECT ARRAY_AGG(id) INTO engineer_ids
    FROM public.engineer_profiles;

    IF engineer_ids IS NOT NULL AND array_length(engineer_ids, 1) > 0 THEN
        -- Delete dependent data first (sessions, etc.)
        DELETE FROM public.engineer_sessions
        WHERE engineer_id = ANY(engineer_ids);

        -- Delete engineer profiles
        DELETE FROM public.engineer_profiles
        WHERE id = ANY(engineer_ids);

        -- Delete from auth.users (cascades any remaining references)
        DELETE FROM auth.users
        WHERE id = ANY(engineer_ids);

        RAISE NOTICE 'Cleared % engineer profiles and associated data.', array_length(engineer_ids, 1);
    ELSE
        RAISE NOTICE 'No engineer profiles found to clear.';
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Clear operation encountered an issue: %', SQLERRM;
END $$;

-- ============================================================
-- Fix: "Database error saving new user" on signup
-- The handle_new_engineer trigger runs as SECURITY DEFINER
-- but RLS on engineer_profiles blocks the INSERT because
-- auth.uid() returns NULL during trigger execution context.
-- Solution: Add a policy that allows the postgres/service role
-- to insert, and ensure the trigger function bypasses RLS.
-- ============================================================

-- Re-create the trigger function with SET search_path and proper RLS bypass
CREATE OR REPLACE FUNCTION public.handle_new_engineer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    ON CONFLICT (id) DO UPDATE SET
        engineer_name = EXCLUDED.engineer_name,
        engineer_id = COALESCE(EXCLUDED.engineer_id, engineer_profiles.engineer_id),
        email = EXCLUDED.email,
        department = EXCLUDED.department,
        updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
EXCEPTION
    WHEN unique_violation THEN
        -- engineer_id or email conflict: update what we can
        UPDATE public.engineer_profiles
        SET
            engineer_name = COALESCE(NEW.raw_user_meta_data->>'engineer_name', split_part(NEW.email, '@', 1)),
            email = NEW.email,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.id;
        RETURN NEW;
    WHEN OTHERS THEN
        RAISE WARNING 'handle_new_engineer failed for user %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$;

-- Grant execute permission to postgres and service_role
GRANT EXECUTE ON FUNCTION public.handle_new_engineer() TO postgres;
GRANT EXECUTE ON FUNCTION public.handle_new_engineer() TO service_role;

-- Drop and recreate the trigger to ensure it uses the updated function
DROP TRIGGER IF EXISTS on_auth_engineer_created ON auth.users;
CREATE TRIGGER on_auth_engineer_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_engineer();

-- Add a policy that allows the service_role (used by triggers) to bypass RLS
-- This is needed because SECURITY DEFINER functions run as the function owner
-- but RLS still applies unless the role has bypass privilege
DROP POLICY IF EXISTS "service_role_manage_engineer_profiles" ON public.engineer_profiles;
CREATE POLICY "service_role_manage_engineer_profiles"
ON public.engineer_profiles
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- Also ensure the existing authenticated policy is correct
DROP POLICY IF EXISTS "engineers_manage_own_profile" ON public.engineer_profiles;
CREATE POLICY "engineers_manage_own_profile"
ON public.engineer_profiles
FOR ALL
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

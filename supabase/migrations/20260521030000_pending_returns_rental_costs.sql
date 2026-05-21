-- ============================================================
-- NATRAX TrackLog: Pending Returns & Rental Cost Tracking
-- Migration: 20260521030000_pending_returns_rental_costs.sql
-- ============================================================

-- 1. Sand bag rentals table (tracks active/returned sand bag rentals)
CREATE TABLE IF NOT EXISTS public.sand_bag_rentals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engineer_id UUID NOT NULL REFERENCES public.engineer_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.engineer_sessions(id) ON DELETE SET NULL,
    bag_quantity INTEGER NOT NULL DEFAULT 1,
    daily_rate NUMERIC(10,2) NOT NULL DEFAULT 150.00,
    taken_date DATE NOT NULL DEFAULT CURRENT_DATE,
    return_date DATE,
    is_returned BOOLEAN NOT NULL DEFAULT false,
    accrued_cost NUMERIC(12,2) DEFAULT 0,
    last_cost_calculated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. Rental instruments table (tracks active/returned instrument rentals)
CREATE TABLE IF NOT EXISTS public.rental_instruments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    engineer_id UUID NOT NULL REFERENCES public.engineer_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.engineer_sessions(id) ON DELETE SET NULL,
    instrument_name TEXT NOT NULL,
    daily_rate NUMERIC(10,2) NOT NULL,
    taken_date DATE NOT NULL DEFAULT CURRENT_DATE,
    return_date DATE,
    is_returned BOOLEAN NOT NULL DEFAULT false,
    accrued_cost NUMERIC(12,2) DEFAULT 0,
    last_cost_calculated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_sand_bag_rentals_engineer_id ON public.sand_bag_rentals(engineer_id);
CREATE INDEX IF NOT EXISTS idx_sand_bag_rentals_is_returned ON public.sand_bag_rentals(is_returned);
CREATE INDEX IF NOT EXISTS idx_sand_bag_rentals_taken_date ON public.sand_bag_rentals(taken_date);
CREATE INDEX IF NOT EXISTS idx_rental_instruments_engineer_id ON public.rental_instruments(engineer_id);
CREATE INDEX IF NOT EXISTS idx_rental_instruments_is_returned ON public.rental_instruments(is_returned);
CREATE INDEX IF NOT EXISTS idx_rental_instruments_taken_date ON public.rental_instruments(taken_date);

-- 4. Function: calculate daily rental costs for sand bags
CREATE OR REPLACE FUNCTION public.calculate_sand_bag_cost(
    p_bag_quantity INTEGER,
    p_daily_rate NUMERIC,
    p_taken_date DATE,
    p_return_date DATE DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_end_date DATE;
    v_days INTEGER;
BEGIN
    v_end_date := COALESCE(p_return_date, CURRENT_DATE);
    v_days := (v_end_date - p_taken_date);
    IF v_days < 0 THEN v_days := 0; END IF;
    RETURN p_bag_quantity * p_daily_rate * v_days;
END;
$$;

-- 5. Function: calculate daily rental costs for instruments
CREATE OR REPLACE FUNCTION public.calculate_instrument_cost(
    p_daily_rate NUMERIC,
    p_taken_date DATE,
    p_return_date DATE DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_end_date DATE;
    v_days INTEGER;
BEGIN
    v_end_date := COALESCE(p_return_date, CURRENT_DATE);
    v_days := (v_end_date - p_taken_date);
    IF v_days < 0 THEN v_days := 0; END IF;
    RETURN p_daily_rate * v_days;
END;
$$;

-- 6. Function: update accrued costs for all active rentals (called daily by cron or on-demand)
CREATE OR REPLACE FUNCTION public.update_all_rental_costs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Update sand bag rentals
    UPDATE public.sand_bag_rentals
    SET
        accrued_cost = public.calculate_sand_bag_cost(bag_quantity, daily_rate, taken_date, return_date),
        last_cost_calculated_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE is_returned = false;

    -- Update instrument rentals
    UPDATE public.rental_instruments
    SET
        accrued_cost = public.calculate_instrument_cost(daily_rate, taken_date, return_date),
        last_cost_calculated_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE is_returned = false;
END;
$$;

-- 7. Function: mark sand bag rental as returned
CREATE OR REPLACE FUNCTION public.return_sand_bag_rental(
    p_rental_id UUID,
    p_engineer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rental public.sand_bag_rentals%ROWTYPE;
    v_final_cost NUMERIC;
BEGIN
    SELECT * INTO v_rental
    FROM public.sand_bag_rentals
    WHERE id = p_rental_id AND engineer_id = p_engineer_id AND is_returned = false;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Rental not found or already returned');
    END IF;

    v_final_cost := public.calculate_sand_bag_cost(
        v_rental.bag_quantity, v_rental.daily_rate, v_rental.taken_date, CURRENT_DATE
    );

    UPDATE public.sand_bag_rentals
    SET
        is_returned = true,
        return_date = CURRENT_DATE,
        accrued_cost = v_final_cost,
        last_cost_calculated_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_rental_id;

    RETURN jsonb_build_object('success', true, 'final_cost', v_final_cost, 'return_date', CURRENT_DATE);
END;
$$;

-- 8. Function: mark instrument rental as returned
CREATE OR REPLACE FUNCTION public.return_instrument_rental(
    p_rental_id UUID,
    p_engineer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rental public.rental_instruments%ROWTYPE;
    v_final_cost NUMERIC;
BEGIN
    SELECT * INTO v_rental
    FROM public.rental_instruments
    WHERE id = p_rental_id AND engineer_id = p_engineer_id AND is_returned = false;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Rental not found or already returned');
    END IF;

    v_final_cost := public.calculate_instrument_cost(
        v_rental.daily_rate, v_rental.taken_date, CURRENT_DATE
    );

    UPDATE public.rental_instruments
    SET
        is_returned = true,
        return_date = CURRENT_DATE,
        accrued_cost = v_final_cost,
        last_cost_calculated_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_rental_id;

    RETURN jsonb_build_object('success', true, 'final_cost', v_final_cost, 'return_date', CURRENT_DATE);
END;
$$;

-- 9. Enable RLS
ALTER TABLE public.sand_bag_rentals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rental_instruments ENABLE ROW LEVEL SECURITY;

-- 10. RLS Policies
DROP POLICY IF EXISTS "engineers_manage_own_sand_bag_rentals" ON public.sand_bag_rentals;
CREATE POLICY "engineers_manage_own_sand_bag_rentals"
ON public.sand_bag_rentals
FOR ALL
TO authenticated
USING (engineer_id = auth.uid())
WITH CHECK (engineer_id = auth.uid());

DROP POLICY IF EXISTS "engineers_manage_own_rental_instruments" ON public.rental_instruments;
CREATE POLICY "engineers_manage_own_rental_instruments"
ON public.rental_instruments
FOR ALL
TO authenticated
USING (engineer_id = auth.uid())
WITH CHECK (engineer_id = auth.uid());

-- 11. Updated_at trigger function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_sand_bag_rentals_updated_at ON public.sand_bag_rentals;
CREATE TRIGGER set_sand_bag_rentals_updated_at
    BEFORE UPDATE ON public.sand_bag_rentals
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_rental_instruments_updated_at ON public.rental_instruments;
CREATE TRIGGER set_rental_instruments_updated_at
    BEFORE UPDATE ON public.rental_instruments
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

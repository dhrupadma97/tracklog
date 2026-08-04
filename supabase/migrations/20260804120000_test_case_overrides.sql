-- Test-case overrides: an editable overlay on top of the read-only generated
-- Goodyear DVP cases. A row can EDIT a generated case (same test_id), HIDE it
-- (hidden = true), or ADD a brand-new case (is_new = true, unique test_id).
--
-- Strictly private: RLS grants access to AUTHENTICATED users only (never the
-- anon/public key). All signed-in users may VIEW; only managers may write.

create table if not exists public.test_case_overrides (
  id                 uuid primary key default gen_random_uuid(),
  test_id            text not null unique,     -- merge key (generated id, or a new id)
  hidden             boolean not null default false,
  is_new             boolean not null default false,
  test_cases_name    text,
  tire_type          text,
  tire_condition     text,
  tire_pressure      text,
  road_surface       text,
  load               text,
  test_description   text,
  test_case_link     text,
  test_result        text,
  comments           text,
  feature            text,
  activity_type      text,
  drivetrain         text,
  water_depth        text,
  load_category      text,
  road_surface_type  text,
  updated_by         text,
  updated_at         timestamptz not null default now()
);

alter table public.test_case_overrides enable row level security;

-- VIEW — any signed-in user (never anon/public).
drop policy if exists tco_select_authenticated on public.test_case_overrides;
create policy tco_select_authenticated
  on public.test_case_overrides
  for select
  to authenticated
  using (true);

-- WRITE (insert / update / delete) — managers only.
drop policy if exists tco_write_managers on public.test_case_overrides;
create policy tco_write_managers
  on public.test_case_overrides
  for all
  to authenticated
  using (
    exists (
      select 1 from public.engineer_profiles p
      where p.id = auth.uid() and p.user_role = 'manager'
    )
  )
  with check (
    exists (
      select 1 from public.engineer_profiles p
      where p.id = auth.uid() and p.user_role = 'manager'
    )
  );

create index if not exists test_case_overrides_test_id_idx
  on public.test_case_overrides (test_id);

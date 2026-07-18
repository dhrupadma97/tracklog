-- Instrumentation Intelligence — DBC files per vehicle bus (Phase 3)
-- One row = one DBC attached to one bus of one config. Content stored as text
-- and fetched lazily (list queries exclude it).

create table if not exists public.dbc_files (
  id uuid primary key default gen_random_uuid(),
  config_id uuid not null references public.instrumentation_configs(id) on delete cascade,
  bus_id text not null,
  file_name text not null,
  content text not null,
  message_count integer not null default 0,
  signal_count integer not null default 0,
  uploaded_by text,
  uploaded_at timestamptz not null default now(),
  unique (config_id, bus_id)
);

comment on table public.dbc_files is
  'TrackLog Instrumentation Intelligence: DBC database files attached per vehicle bus';

alter table public.dbc_files enable row level security;

drop policy if exists "dbc_files_select" on public.dbc_files;
create policy "dbc_files_select" on public.dbc_files
  for select to authenticated using (true);

drop policy if exists "dbc_files_insert" on public.dbc_files;
create policy "dbc_files_insert" on public.dbc_files
  for insert to authenticated with check (true);

drop policy if exists "dbc_files_update" on public.dbc_files;
create policy "dbc_files_update" on public.dbc_files
  for update to authenticated using (true) with check (true);

drop policy if exists "dbc_files_delete" on public.dbc_files;
create policy "dbc_files_delete" on public.dbc_files
  for delete to authenticated using (true);

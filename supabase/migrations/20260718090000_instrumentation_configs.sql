-- Instrumentation Intelligence — per-vehicle schematic configs (Phase 2)
-- One row = one vehicle instrumentation schematic (draft or locked version).
-- Whole schematic stored as JSONB for simplicity: one round-trip to load/save.

create table if not exists public.instrumentation_configs (
  id uuid primary key default gen_random_uuid(),
  name text not null,                                   -- e.g. 'TATA BETA (EV)'
  manufacturer text not null default '',
  buses jsonb not null default '[]'::jsonb,             -- [{id,name,protocol,obdPinHigh,obdPinLow,description,dbcFile}]
  obd_pinout jsonb not null default '[]'::jsonb,        -- [{pinNumber,description,protocol,isHighLine,isPresent}]
  nodes jsonb not null default '[]'::jsonb,             -- [{id,label,sublabel,nodeType,instrumentId,x,y}]
  connections jsonb not null default '[]'::jsonb,       -- [{fromNodeId,toNodeId,label,protocol,busIndex}]
  status text not null default 'draft' check (status in ('draft','locked')),
  version integer not null default 1,
  locked_by text,
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.instrumentation_configs is
  'TrackLog Instrumentation Intelligence: editable + lockable vehicle instrumentation schematics';

alter table public.instrumentation_configs enable row level security;

-- All signed-in engineers can read and edit drafts / create versions.
drop policy if exists "instr_configs_select" on public.instrumentation_configs;
create policy "instr_configs_select" on public.instrumentation_configs
  for select to authenticated using (true);

drop policy if exists "instr_configs_insert" on public.instrumentation_configs;
create policy "instr_configs_insert" on public.instrumentation_configs
  for insert to authenticated with check (true);

drop policy if exists "instr_configs_update" on public.instrumentation_configs;
create policy "instr_configs_update" on public.instrumentation_configs
  for update to authenticated using (true) with check (true);

drop policy if exists "instr_configs_delete" on public.instrumentation_configs;
create policy "instr_configs_delete" on public.instrumentation_configs
  for delete to authenticated using (status = 'draft');  -- locked versions are permanent

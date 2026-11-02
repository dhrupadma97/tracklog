-- Month adjustments: putting a computed month onto the invoice that arrived.
--
-- What the sessions compute and what NATRAX bill can differ by a few hundred
-- rupees — a part-hour rounded their way, a support line priced on the day, the
-- round-off at the foot of the invoice (INV/26-27/802 carries ₹0.40 of it). The
-- invoice is the figure of record, so the Analyser can nudge a month onto it.
--
-- One row per month, shared by every programme, because one NATRAX invoice
-- covers the whole account rather than a single PoC. `reason` is NOT NULL and
-- checked non-empty on purpose: an unexplained correction on a billing screen
-- is worse than none, since nobody can later tell a real invoice difference
-- from a typo, and this figure reaches the manager's report.

create table if not exists public.month_adjustments (
  id          uuid primary key default gen_random_uuid(),
  month       text not null,                       -- 'YYYY-MM'
  amount      numeric(12, 2) not null,             -- signed; negative brings the total down
  reason      text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint month_adjustments_month_format check (month ~ '^\d{4}-\d{2}$'),
  constraint month_adjustments_reason_not_blank check (btrim(reason) <> ''),
  constraint month_adjustments_month_unique unique (month)
);

alter table public.month_adjustments enable row level security;

-- Same posture as the rest of the billing tables: signed-in users only. The
-- anon key ships inside the public web bundle, so it is never granted here.
drop policy if exists month_adjustments_read on public.month_adjustments;
create policy month_adjustments_read
  on public.month_adjustments for select
  to authenticated using (true);

drop policy if exists month_adjustments_write on public.month_adjustments;
create policy month_adjustments_write
  on public.month_adjustments for all
  to authenticated using (true) with check (true);

create or replace function public.month_adjustments_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists month_adjustments_touch on public.month_adjustments;
create trigger month_adjustments_touch
  before update on public.month_adjustments
  for each row execute function public.month_adjustments_touch();

-- Self-report, so the run says whether it worked rather than leaving it to be
-- checked by hand afterwards.
select
  v.check_name,
  v.expected,
  case v.check_name
    when 'table exists' then (
      select count(*)::text from information_schema.tables
      where table_schema = 'public' and table_name = 'month_adjustments')
    when 'rls enabled' then (
      select relrowsecurity::text from pg_class
      where oid = 'public.month_adjustments'::regclass)
    when 'policies' then (
      select count(*)::text from pg_policies
      where schemaname = 'public' and tablename = 'month_adjustments')
  end as actual
from (values
  ('table exists', '1'),
  ('rls enabled', 'true'),
  ('policies', '2')
) as v(check_name, expected);

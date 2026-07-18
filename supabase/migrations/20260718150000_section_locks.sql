-- Instrumentation Intelligence — per-section locks (Calibration / Validation)
-- Each schematic now has two independently lockable sections; the whole config
-- flips to status 'locked' only when BOTH are locked.
-- Shape: {"calibration": {"locked": true, "by": "...", "at": "..."},
--         "validation":  {"locked": false, ...}}

alter table public.instrumentation_configs
  add column if not exists section_locks jsonb not null default '{}'::jsonb;

-- NOTE: an earlier revision of this migration also deleted drafts named
-- 'TATA BETA (EV)' to refresh the demo. That was removed — user-created
-- configs could share that name (the create dialog didn't force a rename).
-- Clean up stale demo drafts manually, by id, after inspecting:
--   select id, name, status, version, created_at
--     from public.instrumentation_configs order by created_at;

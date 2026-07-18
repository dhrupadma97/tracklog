-- Instrumentation Intelligence — per-section locks (Calibration / Validation)
-- Each schematic now has two independently lockable sections; the whole config
-- flips to status 'locked' only when BOTH are locked.
-- Shape: {"calibration": {"locked": true, "by": "...", "at": "..."},
--         "validation":  {"locked": false, ...}}

alter table public.instrumentation_configs
  add column if not exists section_locks jsonb not null default '{}'::jsonb;

-- Refresh the demo draft so it re-seeds from the corrected template
-- (ADAS bus is classic CAN, not CAN FD; CANape/CANoe are separate nodes).
-- Only removes the never-renamed TATA BETA draft; renamed vehicles are kept.
delete from public.instrumentation_configs
  where status = 'draft' and name = 'TATA BETA (EV)';

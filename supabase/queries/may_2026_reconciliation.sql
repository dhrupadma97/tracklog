-- May 2026 — TrackLog sessions vs the NATRAX service sheet
--
-- Read-only. Run this before trusting the computed May figure: the month is
-- now costed from logged sessions, so anything missing from TrackLog is
-- missing from the PO drawdown.
--
-- NATRAX "Service Sheet May-26 - Godyear.xlsx" records 10 charged hours:
--
--   (GVW<3.5T)(T3wet-002)   4 hrs    23-May x2, 25-May x2
--   (GVW<3.5T)(T2-002)      2 hrs    22-May
--   (GVW<3.5T)(T11-002)     2 hrs    19-May, 20-May
--   (GVW<3.5T)(T16-002)     1 hr     18-May
--   (GVW<3.5T)(T8-002)      1 hr     23-May
--                          ------
--                          10 hrs
--
--   EV charging: 122.58 units (28.28 + 40.52 + 53.78) on 20 and 22 May
--
--   Vehicles: XVE-9E / XEV-9 on 18, 23 and 25 May; EC-170 on 19, 20 and 22 May.
--   EC-170 is not the Mahindra EV. If those sessions are logged under a
--   different project they will not be counted; if they are logged under
--   Mahindra EV PoC they are attributed to a programme they do not belong to.

-- 1. Every May session TrackLog holds, whatever the project
SELECT
  s.started_at::date              AS date,
  s.project_name,
  s.vehicle_name,
  s.track_code,
  s.track_name,
  round(s.duration_minutes / 60.0, 2) AS hours,
  s.total_cost,
  s.session_status
FROM public.engineer_sessions s
WHERE s.started_at >= '2026-05-01'
  AND s.started_at <  '2026-06-01'
ORDER BY s.started_at;

-- 2. Totals per track, to line up against the sheet's 10 hours
SELECT
  COALESCE(NULLIF(s.track_code, ''), s.track_name) AS track,
  count(*)                                          AS sessions,
  round(sum(s.duration_minutes) / 60.0, 2)          AS hours,
  sum(s.total_cost)                                 AS cost_excl_gst
FROM public.engineer_sessions s
WHERE s.started_at >= '2026-05-01'
  AND s.started_at <  '2026-06-01'
  AND s.session_status = 'completed'
GROUP BY 1
ORDER BY hours DESC;

-- 3. The single number the app will use for May, and the gap to the sheet
SELECT
  round(sum(s.duration_minutes) / 60.0, 2) AS tracklog_hours,
  10.0                                     AS sheet_hours,
  round(sum(s.duration_minutes) / 60.0, 2) - 10.0 AS hours_gap,
  sum(s.total_cost)                        AS track_cost_excl_gst,
  COALESCE((
    SELECT sum(a.total_cost)
      FROM public.session_additional_services a
      JOIN public.engineer_sessions e ON e.id = a.session_id
     WHERE e.started_at >= '2026-05-01' AND e.started_at < '2026-06-01'
  ), 0)                                    AS accessories_excl_gst,
  40000                                    AS workshop_excl_gst
FROM public.engineer_sessions s
WHERE s.started_at >= '2026-05-01'
  AND s.started_at <  '2026-06-01'
  AND s.session_status = 'completed'
  AND (
    lower(coalesce(nullif(trim(s.project_name), ''), 'general')) IN
      ('mahindra ev poc', 'general')
  );

-- 4. Sessions in May that are NOT attributed to Mahindra EV PoC — likely the
--    EC-170 rows. These are excluded from the figure above.
SELECT
  s.started_at::date AS date,
  s.project_name,
  s.vehicle_name,
  s.track_code,
  round(s.duration_minutes / 60.0, 2) AS hours
FROM public.engineer_sessions s
WHERE s.started_at >= '2026-05-01'
  AND s.started_at <  '2026-06-01'
  AND lower(coalesce(nullif(trim(s.project_name), ''), 'general'))
      NOT IN ('mahindra ev poc', 'general')
ORDER BY s.started_at;

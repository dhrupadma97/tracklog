# TrackLog — Claude Code Project Context

## What this is
**NATRAX TrackLog** — a Flutter web + mobile app for Goodyear SightLine tire intelligence testing at NATRAX Proving Ground, Indore. Tracks session utilisation, billing, project analytics, and manager email reports.

## This is a standalone project
- **GitHub**: `https://github.com/dhrupadma97/tracklog.git` (separate from AntiGravity)
- **Firebase Hosting**: `sightlinevalidation.web.app`
- **Supabase**: `qmcsxfqizvjbzffbrakp.supabase.co` (shared infra — TrackLog uses these tables: `engineer_sessions`, `engineer_profiles`, `track_rates`, `po_trackers`, `email_report_subscriptions`, `email_send_log`, `session_additional_services`, `instrumentation_configs`, `dbc_files`)
- **Flutter SDK**: Must be added to PATH before rebuilding (`flutter build web --release`)

## Key decisions & constraints
- Background image: `GYRacing_DesktopTeamsWallpaper_5-1779284234231.png` — DO NOT REMOVE
- Goodyear SightLine logo in splash and project selection — DO NOT REMOVE
- Admin tab is shown ONLY to `userRole == 'manager'` (fixed from inverted bug)
- Web sidebar (`app_scaffold.dart`) and mobile bottom nav (`app_navigation.dart`)
  are two separate lists and drift apart easily — add a tab to both. Web shows:
  Projects, Analyser, Daily Log, Tracks, Manual Entry, Settings, Admin (if
  manager), Updates, Trends, Instruments, Test Cases, Resources, Muster.
  No Session or Gates tabs on web.
- Daily Log = `SessionHistoryScreen`, router branch 14 (`/daily-log-screen`).
  Branch 1 is still named `AppRoutes.sessionHistory` but renders `TracksScreen`;
  do not confuse the two.
- Mobile shows all tabs
- `ProjectManager` is the single source of truth for active project across all screens
- Workshop rental hardcoded: ₹5,000/operational day (matches VBA macro).
  Recorded in two places on purpose: as a WORKSHOP service line in Manual Entry
  (rupees on an invoice) and as `kind = 'workshop'` rows in the muster (which
  days). Workshop draws the NATRAX **track_booking** PO, not a manpower PO —
  8242390552 is "Track & Workshop Booking". Those POs are lumpsum on actuals,
  so workshop accrues rupees and has no days-remaining figure; manpower POs are
  contracted in days and do. Manpower days = SUM(head_count); workshop days =
  COUNT(rows), with head_count forced to 0.
- Email reports To: `praharshithkumar_komaragiri@goodyear.com`, CC: vimal, ashish, yeswanth, niranjan

## Projects tracked
| Key | Display Name | Vehicle | Status |
|---|---|---|---|
| `mahindra ev poc` | Mahindra EV PoC | XEV 9e | Closed |
| `mahindra ice poc` | Mahindra ICE PoC | XUV 7XO | Active |
| `kia sonet poc` | Kia Sonet PoC | Kia Sonet | Upcoming |
| `tata harrier ev poc` | Tata Harrier EV PoC | Harrier.ev QWD | Active |

`lib/services/project_catalog.dart` is the single source of this list. Every
project picker reads `ProjectCatalog.displayNames` from it — add a programme
there and it appears in manual entry, the muster, the Analyser, resources,
invoice upload and the manager report without further edits. The selection
screen keeps a parallel `_knownProjects` map for hero image, accent colour and
vehicle specs only; add the matching entry there, keyed identically.

Empty/General `project_name` in DB → treated as Mahindra EV PoC.

The selection screen partitions this list by status rather than showing it
verbatim: active programmes lead the rail, upcoming ones bring up the rear,
and completed programmes sit behind their own COMPLETED tab. Their spend and
sessions still count towards the headline totals — Mahindra EV is most of both.

Kia Sonet OEM tyre size is confirmed at 215/60 R16. Its engine, transmission and
output figures are still unconfirmed placeholders. The hero image is an AVIF
photo carrying its own scenery, so it uses `imageHasBackdrop: true`; Flutter web
decodes AVIF via the browser `ImageDecoder`, verified supported.

Only Mahindra EV PoC has a hardcoded `BillingBaseline`. Every other programme
costs live from what is logged — sessions for track time, `session_additional_
services` for other costs, the muster for manpower days. POs are a shared pool
and are deliberately not project-scoped.

## Supabase Edge Functions needed
- `send-report-email` — must accept: `recipientEmail`, `recipientName`, `ccEmails[]`, `subject`, `htmlBody`, `reportType`

## Do NOT commit
- `NATRAX Invoices/`, `NATRAX PO/` — sensitive billing docs
- `*.js` utility scripts in root (fix_*.js, check_*.js, etc.)
- `*.py` scripts
- `stitch_tracklog_design_system (4)/`
- `.bak` files

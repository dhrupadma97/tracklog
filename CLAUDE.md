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
- Web shows: History, Manual, Analyser, Settings, Admin (if manager) — no Session or Gates tabs
- Mobile shows all tabs
- `ProjectManager` is the single source of truth for active project across all screens
- Workshop rental hardcoded: ₹5,000/operational day (matches VBA macro)
- Email reports To: `praharshithkumar_komaragiri@goodyear.com`, CC: vimal, ashish, yeswanth, niranjan

## Projects tracked
| Key | Display Name | Vehicle | Status |
|---|---|---|---|
| `mahindra ev poc` | Mahindra EV PoC | XEV 9e | Closed |
| `mahindra ice poc` | Mahindra ICE PoC | XUV 7XO | Active |
| `hyundai poc` | Hyundai PoC | CRETA EV | Upcoming |
| `tata harrier ev poc` | Tata Harrier EV PoC | Harrier.ev QWD | Active |

`lib/services/project_catalog.dart` is the single source of this list. Every
project picker reads `ProjectCatalog.displayNames` from it — add a programme
there and it appears in manual entry, the muster, the Analyser, resources,
invoice upload and the manager report without further edits. The selection
screen keeps a parallel `_knownProjects` map for hero image, accent colour and
vehicle specs only; add the matching entry there, keyed identically.

Empty/General `project_name` in DB → treated as Mahindra EV PoC.

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

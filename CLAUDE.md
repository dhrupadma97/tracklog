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
| Key | Display Name | Vehicle |
|---|---|---|
| `mahindra ev poc` | Mahindra EV PoC | XEV 9e |
| `mahindra ice poc` | Mahindra ICE PoC | XUV 7XO |
| `hyundai poc` | Hyundai PoC | CRETA EV |

Empty/General `project_name` in DB → treated as Mahindra EV PoC.

## Supabase Edge Functions needed
- `send-report-email` — must accept: `recipientEmail`, `recipientName`, `ccEmails[]`, `subject`, `htmlBody`, `reportType`

## Do NOT commit
- `NATRAX Invoices/`, `NATRAX PO/` — sensitive billing docs
- `*.js` utility scripts in root (fix_*.js, check_*.js, etc.)
- `*.py` scripts
- `stitch_tracklog_design_system (4)/`
- `.bak` files

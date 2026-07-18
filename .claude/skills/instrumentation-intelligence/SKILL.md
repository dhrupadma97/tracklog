---
name: instrumentation-intelligence
description: Build, extend, or resume the TrackLog Instrumentation Intelligence feature — a physics-aware instrumentation setup planner (instrument knowledge base, rule-based compatibility/reasoning engine, editable + lockable schematics, DBC management, and a query interface). Use when working on the Instruments tab, the instrument catalog / compatibility / schematic code, the instrument knowledge base, or when the user asks instrumentation setup / compatibility questions.
---

# Instrumentation Intelligence

## Goal (the vision)
Turn the Instruments tab from a static display into a **physics-aware setup planner** for NATRAX /
Goodyear SightLine tire-intelligence testing. Before a vehicle arrives, the engineer plans the
instrumentation; when the vehicle is received, setup is fast; once validated, the schematic +
exact instrument list + DBCs are **locked**. The knowledge base understands each instrument's
electrical/signal capabilities so it can flag problems when the setup changes (e.g. "CAN FD works
for CANoe/CANape but a GL1000 logger can't join an FD bus") and **answer queries** deterministically.

## Locked decisions (from the user)
- **Query engine:** rule-based / deterministic logic first (no LLM, no API cost). An LLM
  natural-language layer can be added later on top of the same rules.
- **Scope:** build all three pieces — knowledge base + smart compatibility → editable/lockable
  schematics → DBC management.
- **Instruments:** only **real owned gear**; the 8 reference/qty-0 items were dropped. See
  [reference/instrument-knowledge.md](reference/instrument-knowledge.md) for the confirmed list.
- **Nav:** Instruments tab is now shown on **web AND mobile** (mobile-nav gate removed in
  `app_navigation.dart`).

## UX direction (2026-07-17 — ease-first, from Dhrupad; revised 2026-07-18)
- **Simplicity over compatibility policing.** FD compatibility is NOT the headline — keep the data
  correct (GL2000 = classic CAN only) but do not build the UI around FD warnings. Emphasize making
  setup **easy**.
- **Only real owned gear** — never introduce general/reference instruments.
- **NO Catalog tab, no filter nav bars** (Dhrupad 2026-07-18: "those nav bars making more
  complicated") — the owned-gear list lives in an **info bottom sheet** (header "Instruments"
  button), grouped by the 3 verticals. Screen has just 2 tabs: Compatibility · Schematic.
- **Schematic has two separately lockable sections** — locked headings **Calibration** and
  **Validation** rendered as zones on the canvas; base wiring (OBD → buses → GL2000/sensors) is
  effectively the data-collection layer and stays around them (Dhrupad picked: separately lockable;
  just Cal+Val headings; keep Compatibility tab).
  - Schematic section mapping (`sectionForInstrument`): Calibration = CANape, Kvaser;
    Validation = Raptor CAL, CANoe, Display; everything else = base.
- **⚠ ADAS is NOT CAN FD** — Dhrupad 2026-07-18: TATA BETA CAN 3 (ADAS) is classic CAN. The FD
  demo value was synthetic and wrong. All three TATA BETA buses are CAN 2.0. Do not reintroduce
  FD example data without a real vehicle spec.
- **Animated OBD-II pinout per vehicle** — render the 16-pin OBD-II connector from each vehicle's
  `obdPinout`, glow/animate active pins by bus (CAN/LIN/power/ground). Data already exists
  (`tataBetaOBDPinout`).

## Where the code lives
- `lib/presentation/instrumentation_screen/instrumentation_screen.dart` — 3-tab UI (Catalog ·
  Compatibility · Schematic).
- `lib/data/instrumentation_data.dart` — instrument catalog + vehicle profiles + schematic nodes.
  **Has factual errors** (see knowledge base) — Phase 1 corrects these.
- `lib/data/compatibility_engine.dart` — current ad-hoc `if`-based checks; Phase 1 refactors it to
  consume the explicit rules R1–R7.
- `lib/data/schematic_repository.dart` — Supabase CRUD **stub** (unused). Bugs: hardcodes
  `nodeType: logger` and uses `instrument_id` as the label. Rework in Phase 2; needs new tables.
- Routing: `lib/routes/app_routes.dart` (branch 9, `/instrumentation-screen`).
- Nav: `lib/widgets/app_scaffold.dart` (wide left rail) + `lib/widgets/app_navigation.dart`
  (bottom nav). Both list "Instruments" → branch 9.

## Build plan
**Phase 1 — Physics knowledge base + reasoning engine** *(done — analyze clean + web build OK)*
1. ✅ Rewrote `instrumentation_data.dart` to the real owned inventory (GL2000, Kvaser, Raptor CAL,
   CANoe, CANape, VBOX 3i Dual, IMU + HUF/Display/Power accessories). Added capability flags:
   `requiresInterface`, `mustReceiveAllSignals` (R8 backbone), `dualAntenna` (R4). Added
   `VehicleBus.isCanFD`, `VehicleProfile.canBuses/hasCanFD`, `Instrument.canChannels`. TATA BETA
   example now shows the parallel backbone + a CAN FD bus (CAN 3) that trips R9.
2. ✅ Reworked `compatibility_engine.dart`: `validateSetup` now also checks R2 (software needs
   interface), R8 (backbone presence), R4 (slip angle). Fixed stale FD recommendation. Added
   `validateVehicle(vehicle, selected)` — the **per-bus** engine (R8/R9/R5/R2/R4). 
3. ⏳ TODO: build the **query surface** (deterministic Q&A over the knowledge base + rules).
   (`validateVehicle` is wired into the UI via the Validate & Lock sheet — Phase 2.)

**Phase 1.5 — Simplify + restructure (ease-first)** *(done — analyze clean + web build OK)*
- ✅ Catalog filters are now the **3 verticals** (All / Calibration / Validation / Data Collection),
  driven by `verticalInstrumentIds` in `instrumentation_data.dart`. Dropped the jargon + FD-only
  filters.
- ✅ Added the **animated OBD-II pinout** to the Schematic tab (`_ObdPinoutView`) with a
  Schematic ⇄ OBD Pinout toggle; glows active pins per the selected vehicle's `obdPinout`.
- Chose layout **Option C** (keep tabs, verticals as filters, pinout in Schematic tab).

**Phase 2 — Editable + lockable schematic builder** *(built 2026-07-18 — analyze clean + web build OK)*
- ✅ Supabase migration `supabase/migrations/20260718090000_instrumentation_configs.sql` — ONE
  JSONB table `instrumentation_configs` (name, buses, obd_pinout, nodes, connections, status
  draft|locked, version, locked_by/at). RLS: authenticated CRUD; locked rows cannot be deleted.
  **First two migrations applied in prod 2026-07-18** (Dhrupad, SQL editor; verified via REST
  probe). Third migration `20260718150000_section_locks.sql` (section_locks column + stale demo
  draft cleanup) must also be applied for section locking to save. If the Schematic tab shows
  the cloud-off banner, suspect auth/network, not missing schema.
- ✅ `schematic_repository.dart` rewritten: `InstrConfig` model (+`toProfile()`), fetch/save/
  createFromProfile (auto-seeds TATA BETA on first run)/lock/newVersion/deleteDraft.
- ✅ JSON serialization on OBDPin/VehicleBus/SchematicNode/SchematicConnection
  (+ `busProtocolFromName`/`instrumentCategoryFromName` helpers).
- ✅ Schematic tab editor: config dropdown (+ "＋" new vehicle seeded from template), Edit mode
  with node dragging (pan), Add node dialog, Link mode (tap 2 nodes → protocol+label dialog),
  Wires sheet (delete connections), node sheet Remove button, Save, and **Validate & Lock** sheet
  (runs `validateVehicle`; lock blocked while errors exist; locked = green badge + New Version).
**Phase 2.5 — Ease-first restructure + section locks** *(built 2026-07-18, after Dhrupad's live
feedback)*
- ✅ Catalog tab REMOVED (2 tabs left: Compatibility · Schematic); owned gear moved to an
  info bottom sheet via the header "Instruments" button (grouped by the 3 verticals, with the
  tire-models strip under Validation).
- ✅ ADAS bus corrected to classic CAN everywhere (pinout pins 2/10, bus def, template nodes +
  connections); pc_sw node split into `pc_canape` (Calibration) + `pc_canoe` (Validation).
- ✅ `SchematicSection` enum (base/calibration/validation) + `SchematicNode.section` (serialized;
  legacy rows derive from instrumentId via `sectionForInstrument`).
- ✅ Per-section locks: `SectionLockState` map on InstrConfig → column `section_locks` (migration
  `20260718150000_section_locks.sql`, which ALSO deletes the stale 'TATA BETA (EV)' draft so it
  re-seeds corrected). Repo: `lockSection`/`unlockSection` replace `lockConfig`; both-locked ⇒
  row status 'locked' (+ RLS delete protection); unlock any section ⇒ back to 'draft'.
  `newVersionFrom` clears section locks.
- ✅ UI: amber Calibration / purple Validation zone outlines auto-bounding their nodes, heading
  chips with lock state (tap → per-section Validate & Lock sheet; locked → unlock confirm
  dialog). Toolbar: Calibration/Validation lock buttons replace the old global Validate & Lock.
  Locked sections: no drag/remove/link/add/wire-delete for member nodes (lock note shown in the
  node sheet; wires list shows a lock icon).

**Phase 3 — DBC management** *(built 2026-07-18 — analyze clean)*
- ✅ `lib/data/dbc_parser.dart` — minimal Vector DBC parser (BO_ messages + SG_ signal names,
  extended-ID detection). Browsing-grade, not a full toolchain.
- ✅ Migration `supabase/migrations/20260718120000_dbc_files.sql` — table `dbc_files`: one row per
  (config_id, bus_id) with file_name + full `content` as text, message/signal counts, RLS
  authenticated CRUD. Content is fetched lazily; list queries exclude it. Applied in prod
  2026-07-18 (ordering note: it must run after instrumentation_configs — FK).
- ✅ `schematic_repository.dart`: `upsertDbc` / `getDbcContent` / `removeDbc`.
- ✅ UI (Schematic tab bus editor): per-bus DBC chip — attach via `file_picker` (.dbc), parses and
  shows message/signal counts, viewer sheet (lazy fetch + message/signal browser), Replace /
  Remove; removing a bus also deletes its DBC row; `dbcFile` name persists on the bus JSON.

## Build / run / deploy notes (this machine)
- **Flutter SDK lives at `C:\Users\AE12230\src\flutter\bin`** (not on PATH by default). Prepend it
  per-command in PowerShell: `$env:PATH = "C:\Users\AE12230\src\flutter\bin;$env:PATH"` then
  `flutter analyze <files>` or `flutter build web --release`. Verified 2026-07-17: analyze = 0
  errors, `flutter build web --release` succeeds (~90s). Ignore the wasm dry-run / font warnings.
- The Instruments UI is **login-gated** (router redirects to /login when signed out), so it can't be
  screenshotted without credentials — verify code via `flutter analyze` + build, not browser shots.
- Firebase Hosting: `sightlinevalidation.web.app` (login-gated; Flutter renders to canvas, so
  browser screenshots time out and there's no DOM text to scrape). **Deploying:** firebase/node
  are NOT on PATH — run the cached standalone CLI:
  `& "C:\Users\AE12230\AppData\Local\ms-playwright-go\1.57.0\node.exe" "C:\Users\AE12230\.cache\firebase\tools\lib\node_modules\firebase-tools\lib\bin\firebase.js" deploy --only hosting`
  (already logged in as dhrupadma97@gmail.com; hosting serves `build/web`).
- Supabase project `qmcsxfqizvjbzffbrakp` (shared infra). Edge-function pattern exists
  (`supabase/functions/send-report-email`) — a future LLM query endpoint would follow it.
- `dio` and `file_picker` already in `pubspec.yaml` — no new plumbing for HTTP / DBC uploads.

## Open questions to resolve (domain — needed to finish Phase 1 rules)
- Which signals MUST always be captured for SightLine (TPMS pressure/temp, wheel speeds, GPS
  pos/speed, slip angle, steering, brake, IMU, load)? → drives "required-signal" validation.
- DBCs: OEM-provided per vehicle/bus? One DBC per bus? Any undocumented/proprietary buses?
- Topology: always OBD-II breakout → split buses → loggers, or tap elsewhere?
- VBOX 3i: run single or dual antenna? Standalone logging or CAN into the GL logger?
- Validate & Lock sign-off: who approves (user / manager Harsh)? Need a PDF/export? Immutable
  after lock, or editable via new version?

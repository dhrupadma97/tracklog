# Instrument Knowledge Base — NATRAX / Goodyear SightLine

> Real-instrument specs and physics/compatibility rules for the TrackLog Instrumentation
> Intelligence feature. This is the **source of truth** the rule-based reasoning engine must
> encode. Each fact should map to a deterministic rule so the app can answer queries and
> validate setups.
>
> ⚠ = needs confirmation against Dhrupad's actual hardware/firmware or from a datasheet.

## Confirmed real inventory (owned)

Confirmed by Dhrupad 2026-07-17: **GLM 2000 (GL2000), Kvaser, Raptor CAL, CANoe, CANape,
VBOX 3i Dual Antenna, IMU.** Dropped everything else (GL1000, GL3000/4000, VN5610/7640, Kvaser
U100, VBOX Touch, dSPACE MicroAutoBox, GeneSys ADMA, RT3000, CANalyzer).

| ID | Instrument | Category | Buses / signals | CAN FD? | Notes |
|---|---|---|---|---|---|
| gl2000 | Vector **GL2000** ("GLM 2000") | Logger (standalone) | up to 4ch CAN 2.0, LIN | **No** | Classic CAN only. The **primary data logger** — every signal must reach it (see R8). Cannot log CAN FD → the key conflict. |
| kvaser | **Kvaser** interface | Flashing tool | CAN | — | **Used to FLASH the Raptor ECUs — its one main function.** Not in the live capture path. Vertical: Calibration. ⚠ confirm model. |
| raptor_cal | New Eagle **Raptor CAL** (RCM80) | ECU / rapid-proto controller | CAN/CAN FD, analog, DIO | **Yes** | Runs the SightLine models (AQD, Leak, Friction, Load) → Display. **MANDATORY for Validation, OPTIONAL for Calibration.** Flashed via Kvaser. |
| canoe | Vector **CANoe** | Software | simulation + analysis + test | via HW | Needs a Vector VN interface to reach the bus (or Kvaser?). FD only with FD-capable HW. |
| canape | Vector **CANape** | Software | ECU measure + calibrate | via HW | XCP/CCP, A2L. Needs VN/VX HW. Can do **XCP on CAN FD w/ same A2L** (CANoe cannot). |
| vbox_3i_dual | Racelogic **VBOX 3i Dual Antenna** | GNSS logger (standalone) | GNSS, CAN in/out, analog | n/a | 100 Hz GPS+GLONASS. Dual antenna ⇒ **true heading + slip angle + pitch/roll + yaw**, valid at rest. |
| imu | Racelogic **IMU** (integrated w/ VBOX 3i) | Inertial sensor | accel/gyro | n/a | Kalman-fused with VBOX 3i for better slip/attitude + dropout bridging. ⚠ confirm model (IMU04?). |

**Setup components (confirm if in scope):** HUF Receiver (TPMS → tire pressure/temp, CAN), custom
Display, Power Breakout Bar. Vehicle-specific accessories, not core instruments.

**Open hardware gap:** Kvaser is used to **flash the Raptor** (not for bus capture), so CANoe/CANape
still need a Vector **VN** interface to touch the bus. ⚠ Confirm what interface CANoe/CANape use.

## Verticals & tire-intelligence models (2026-07-17, from Dhrupad)
- **Calibration** → CANape, Kvaser (flashes Raptor), Raptor (**OPTIONAL**), Power.
- **Validation** → Raptor (**MANDATORY** — runs models → Display), Display, GL2000, CANoe,
  VBOX 3i dual, IMU, HUF, Power.
- **Data Collection** → GL2000, HUF, VBOX 3i dual, IMU, Display, Power.

The SightLine models run on the Raptor and output to the Display (path: **Vehicle CAN → Raptor →
Display**). Current plan of models:
1. **AQD** — **Aquaplaning Detection** (confirmed by Dhrupad 2026-07-18).
2. **Leak Detection** — tire pressure loss / slow leaks.
3. **Dynamic Friction Estimate** — real-time road–tire friction.
4. **Dynamic Load Estimation** — per-tire load via a **tire-mounted sensor**.

⚠ Open: is the "tire-mounted sensor" the HUF/TPMS sensor or a separate SightLine sensor? What does
**AQD** stand for?

## Physics & compatibility rules (the engine's logic)

### R1 — CAN FD requires FD-capable hardware
A bus running **CAN FD** cannot be logged/joined by a **classic-CAN-only** device. On our gear
that means **GL1000, GL2000, Kvaser Leaf Light v2, HUF, Display** cannot handle an FD bus.
FD-capable: **VN1610, VN1630, Raptor RCM80**. → If vehicle bus = CAN FD and selected logger is
classic-only ⇒ **ERROR** (frames lost / bus errors).

### R2 — Software cannot touch the bus without hardware
**CANalyzer / CANoe / CANape are software.** They need a **Vector VN interface** (VN1610/VN1630)
to physically connect to a vehicle bus. Software alone selected with no VN interface ⇒ **ERROR**
("no hardware path to bus"). Standalone loggers (**GL1000/GL2000, VBOX 3i, RT3000**) need no PC.

### R3 — Software + CAN FD needs FD-capable interface (and license)
CANoe/CANape "support CAN FD," but only when paired with an **FD-capable VN** + FD option.
Pairing CANoe with a classic-only interface on an FD bus ⇒ **ERROR**. (This is the user's example:
"CAN FD works for CANoe/CANape but not for the GL logger.")

### R4 — GPS/INS heading & slip angle: single vs dual antenna
- **Single antenna** (VBOX 3i single): heading is **derived from motion** (Doppler). Invalid at
  low/zero speed. **No slip angle, no pitch/roll.**
- **Dual antenna** (VBOX 3i dual / RT3000 dual): **true heading + slip angle + pitch/roll + yaw
  rate**, valid even stationary, all at 100 Hz (VBOX) / up to 250 Hz (RT3000).
- → If the test requires **slip angle** or **low-speed heading** and only a single-antenna GNSS is
  selected ⇒ **ERROR/WARNING**: "need dual-antenna (VBOX 3i dual or RT3000)."

### R5 — CAN channel budget
Σ(CAN channels of selected loggers/interfaces) must ≥ number of vehicle CAN buses to log.
Shortfall ⇒ **WARNING** with recommendation to add an interface/logger.

### R6 — Sample-rate adequacy (vehicle dynamics / tire)
GNSS/INS **≥ 100 Hz** recommended for dynamics/tire work. VBOX 3i = 100 Hz ✓, RT3000 = up to 250 Hz ✓.

### R7 — Inventory / status gates
`faulty` ⇒ ERROR; `underCalibration` ⇒ WARNING; `quantity == 0` ⇒ WARNING (not in inventory).

### R8 — Parallel backbone: every signal → Raptor CAL AND GL2000 (the fixed topology)
In our PoC setup, **every captured vehicle bus must be tapped in parallel to BOTH the Raptor CAL
and the Vector GL2000 logger** (redundant capture: Raptor for real-time/calibration, GL for
logging). The schematic for any vehicle should always fan each bus out to both. If a config omits
either path for a bus ⇒ **WARNING** ("bus not reaching Raptor / GL2000").
**Raptor is MANDATORY for Validation** (models run on it → Display) but **OPTIONAL for
Calibration**. So the "must reach Raptor" half of this rule is enforced for Validation setups.

### R9 — Per-vehicle FD conflict (the headline check)
Because of R8, **every** bus is supposed to reach the GL2000 — but the **GL2000 is classic-CAN
only**. So for each vehicle bus:
- bus = classic CAN → GL2000 OK, Raptor OK ✓
- bus = **CAN FD** → Raptor OK, **GL2000 CANNOT log it** ⇒ **ERROR** per bus. Resolution options the
  engine should surface: log that FD bus via **CANoe/CANape + FD-capable interface**, or route it
  through the **Raptor** only, or (if available) an FD-capable logger. ⚠ Confirm Dhrupad's real
  workaround for FD vehicles — this drives the recommendation text.

## Per-vehicle configuration model (the interactive core)
Each PoC vehicle is its own config the engineer builds:
- **Vehicle**: name, OEM/PoC, notes.
- **Buses[]**: name, protocol (CAN 2.0A/2.0B / **CAN FD**), bitrate, OBD pin H/L, DBC file, signal
  list. Count of buses drives the **CAN channel budget** (R5): 1 bus ⇒ 1 channel needed, etc.
- **Instrument backbone**: fixed = Raptor CAL + GL2000 (R8) + VBOX 3i dual + IMU; optional = HUF,
  Display, plus CANoe/CANape on the PC via interface.
- **Validation** runs R1–R9 over the config → per-bus + overall report → then **Validate & Lock**.

## Known data errors fixed / notes
1. **GL3000 / GL4000 / GL1000** removed — only **GL2000** is owned.
2. Reasoning in `compatibility_engine.dart` was ad-hoc `if` branches; Phase 1 refactors it to
   evaluate R1–R9 explicitly and per-bus.
3. ⚠ Confirm: exact Kvaser model (FD?), IMU model, whether a Vector VN exists for CANoe/CANape,
   and the real FD-vehicle workaround.

## Sources
- VBOX 3i Dual Antenna datasheet — racelogic.co.uk `/_downloads/vbox/Datasheets/Data_Loggers/RLVB3iD_Data.pdf`
- Vector GL Logger product info — cdn.vector.com `/products/gl_logger/Docs/GL_Logger_ProductInformation_EN.pdf`
- Vector VN1600 family — vector.com `/products-a-z/hardware/network-interfaces/vn16xx/`
- Vector CANape — vector.com `/products-a-z/software/canape/`; Vector KB "XCP on CAN FD A2L CANape vs CANoe"
- OxTS RT3000 v3 — oxts.com `/navigation-hardware/rt3000-v3/`

> ⚠ Verify VN1610 FD, RT3000 v3 exact rate, and any per-unit firmware limits before locking a config.

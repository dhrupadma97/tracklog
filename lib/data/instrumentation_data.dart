/// TrackLog — Instrumentation Intelligence Data Layer
/// Real owned inventory + per-vehicle CAN configs + schematic backbone.
/// Source of truth: .claude/skills/instrumentation-intelligence/reference/instrument-knowledge.md
///
/// Owned gear (confirmed 2026-07-17): GL2000 ("GLM 2000"), Kvaser, Raptor CAL,
/// CANoe, CANape, VBOX 3i Dual Antenna, IMU. Everything else was dropped.

// ─── Protocol Enum ──────────────────────────────────────────────────────────
enum BusProtocol {
  can2A,    // CAN 2.0A (11-bit)
  can2B,    // CAN 2.0B (29-bit)
  canFD,    // CAN FD
  lin,      // LIN
  flexRay,  // FlexRay
  ethernet, // Automotive Ethernet (DoIP / SOME/IP)
  analog,   // Analog (voltage, current, thermocouple)
  digitalIO,// Digital I/O
  gpsGnss,  // GPS / GNSS
  imu,      // IMU / Accelerometer / INS
  video,    // Video / Camera sync
  sent,     // SENT protocol
}

extension BusProtocolExt on BusProtocol {
  String get label {
    switch (this) {
      case BusProtocol.can2A: return 'CAN 2.0A';
      case BusProtocol.can2B: return 'CAN 2.0B';
      case BusProtocol.canFD: return 'CAN FD';
      case BusProtocol.lin: return 'LIN';
      case BusProtocol.flexRay: return 'FlexRay';
      case BusProtocol.ethernet: return 'Ethernet';
      case BusProtocol.analog: return 'Analog';
      case BusProtocol.digitalIO: return 'Digital I/O';
      case BusProtocol.gpsGnss: return 'GPS/GNSS';
      case BusProtocol.imu: return 'IMU/INS';
      case BusProtocol.video: return 'Video';
      case BusProtocol.sent: return 'SENT';
    }
  }

  String get shortLabel {
    switch (this) {
      case BusProtocol.can2A: return 'CAN';
      case BusProtocol.can2B: return 'CAN';
      case BusProtocol.canFD: return 'FD';
      case BusProtocol.lin: return 'LIN';
      case BusProtocol.flexRay: return 'FR';
      case BusProtocol.ethernet: return 'ETH';
      case BusProtocol.analog: return 'ANA';
      case BusProtocol.digitalIO: return 'DIO';
      case BusProtocol.gpsGnss: return 'GPS';
      case BusProtocol.imu: return 'IMU';
      case BusProtocol.video: return 'VID';
      case BusProtocol.sent: return 'SENT';
    }
  }

  /// True for any CAN-family protocol (used for channel budgeting).
  bool get isCan =>
      this == BusProtocol.can2A ||
      this == BusProtocol.can2B ||
      this == BusProtocol.canFD;

  int get colorValue {
    switch (this) {
      case BusProtocol.can2A: return 0xFFFF4D4D;   // Red
      case BusProtocol.can2B: return 0xFFFF6B6B;   // Light red
      case BusProtocol.canFD: return 0xFF00F3FF;   // Teal
      case BusProtocol.lin: return 0xFFAA66FF;     // Purple
      case BusProtocol.flexRay: return 0xFFFFB547;  // Orange
      case BusProtocol.ethernet: return 0xFF4FC3F7; // Light blue
      case BusProtocol.analog: return 0xFF81C784;   // Green
      case BusProtocol.digitalIO: return 0xFFFFD54F;// Yellow
      case BusProtocol.gpsGnss: return 0xFF4CAF50;  // Green
      case BusProtocol.imu: return 0xFFFF8A65;      // Orange
      case BusProtocol.video: return 0xFFE040FB;    // Pink
      case BusProtocol.sent: return 0xFF80DEEA;     // Cyan
    }
  }
}


/// Parse a [BusProtocol] from its stored name (JSON); falls back to classic CAN.
BusProtocol busProtocolFromName(String? name) {
  if (name == null) return BusProtocol.can2A;
  return BusProtocol.values.firstWhere(
    (p) => p.name == name,
    orElse: () => BusProtocol.can2A,
  );
}

/// Parse an [InstrumentCategory] from its stored name (JSON).
InstrumentCategory instrumentCategoryFromName(String? name) {
  if (name == null) return InstrumentCategory.connector;
  return InstrumentCategory.values.firstWhere(
    (c) => c.name == name,
    orElse: () => InstrumentCategory.connector,
  );
}


// ─── Instrument Category ────────────────────────────────────────────────────
enum InstrumentCategory {
  logger,
  interfaceDevice,
  software,
  sensor,
  ecu,
  receiver,
  display,
  power,
  connector,
}

extension InstrumentCategoryExt on InstrumentCategory {
  String get label {
    switch (this) {
      case InstrumentCategory.logger: return 'Data Logger';
      case InstrumentCategory.interfaceDevice: return 'Interface';
      case InstrumentCategory.software: return 'Software';
      case InstrumentCategory.sensor: return 'Sensor';
      case InstrumentCategory.ecu: return 'ECU / Controller';
      case InstrumentCategory.receiver: return 'Receiver';
      case InstrumentCategory.display: return 'Display';
      case InstrumentCategory.power: return 'Power';
      case InstrumentCategory.connector: return 'Connector';
    }
  }

  String get icon {
    switch (this) {
      case InstrumentCategory.logger: return 'sd_storage';
      case InstrumentCategory.interfaceDevice: return 'usb';
      case InstrumentCategory.software: return 'computer';
      case InstrumentCategory.sensor: return 'sensors';
      case InstrumentCategory.ecu: return 'memory';
      case InstrumentCategory.receiver: return 'settings_input_antenna';
      case InstrumentCategory.display: return 'tablet_android';
      case InstrumentCategory.power: return 'power';
      case InstrumentCategory.connector: return 'cable';
    }
  }
}


// ─── Instrument Vertical (activity grouping) ────────────────────────────────
// The 3 verticals the engineer thinks in: Calibration / Validation / Data
// Collection. A tool can belong to several; Kvaser + Power are shared infra.
enum InstrumentVertical { calibration, validation, dataCollection }

extension InstrumentVerticalExt on InstrumentVertical {
  String get label {
    switch (this) {
      case InstrumentVertical.calibration: return 'Calibration';
      case InstrumentVertical.validation: return 'Validation';
      case InstrumentVertical.dataCollection: return 'Data Collection';
    }
  }
}

const Map<InstrumentVertical, Set<String>> verticalInstrumentIds = {
  // Calibration — Raptor is OPTIONAL here. Kvaser flashes the Raptor ECU firmware.
  InstrumentVertical.calibration: {'canape', 'kvaser', 'raptor_cal', 'power_breakout'},
  // Validation — Raptor is MANDATORY (runs the tire-intelligence models → Display).
  InstrumentVertical.validation: {
    'raptor_cal', 'display_uiux', 'gl2000', 'canoe',
    'vbox_3i_dual', 'imu', 'huf_receiver', 'power_breakout',
  },
  // Data Collection — the recording/sensing gear.
  InstrumentVertical.dataCollection: {
    'gl2000', 'huf_receiver', 'vbox_3i_dual', 'imu', 'display_uiux', 'power_breakout',
  },
};

/// Instruments in a given vertical (order follows the catalog).
List<Instrument> instrumentsForVertical(InstrumentVertical v) {
  final ids = verticalInstrumentIds[v] ?? const <String>{};
  return instrumentCatalog.where((i) => ids.contains(i.id)).toList();
}

/// Is the Raptor ECU mandatory for this vertical? (Validation: yes; Calibration: optional.)
bool raptorMandatoryFor(InstrumentVertical v) => v == InstrumentVertical.validation;


// ─── Tire Intelligence Models ───────────────────────────────────────────────
// The SightLine models validated on-vehicle. Path: Vehicle CAN → Raptor CAL
// (models run here) → Display. Raptor is REQUIRED for validation.
class TireModel {
  final String name;
  final String description;
  final String? sensor; // extra sensor this model relies on, if any
  const TireModel({required this.name, required this.description, this.sensor});
}

const List<TireModel> tireIntelligenceModels = [
  TireModel(
    name: 'AQD',
    description: 'Aquaplaning Detection — detects loss of tire–road contact on water film.',
  ),
  TireModel(
    name: 'Leak Detection',
    description: 'Detects tire pressure loss / slow leaks from sensor + CAN data.',
  ),
  TireModel(
    name: 'Dynamic Friction Estimate',
    description: 'Estimates available road–tire friction in real time.',
  ),
  TireModel(
    name: 'Dynamic Load Estimation',
    description: 'Estimates per-tire load using a tire-mounted sensor.',
    sensor: 'Tire-mounted sensor',
  ),
];


// ─── Instrument Status ──────────────────────────────────────────────────────
enum InstrumentStatus {
  available,
  inUse,
  underCalibration,
  faulty,
}

extension InstrumentStatusExt on InstrumentStatus {
  String get label {
    switch (this) {
      case InstrumentStatus.available: return 'Available';
      case InstrumentStatus.inUse: return 'In Use';
      case InstrumentStatus.underCalibration: return 'Calibrating';
      case InstrumentStatus.faulty: return 'Faulty';
    }
  }

  int get colorValue {
    switch (this) {
      case InstrumentStatus.available: return 0xFF4CAF50;
      case InstrumentStatus.inUse: return 0xFFFFB547;
      case InstrumentStatus.underCalibration: return 0xFF42A5F5;
      case InstrumentStatus.faulty: return 0xFFFF4D6A;
    }
  }
}


// ─── Instrument Model ───────────────────────────────────────────────────────
class Instrument {
  final String id;
  final String name;
  final String brand;
  final InstrumentCategory category;
  final Set<BusProtocol> supportedProtocols;
  final bool supportsCAnFD;
  final Map<BusProtocol, int> channelCount; // protocol → number of channels
  final String description;
  final InstrumentStatus status;
  final int quantity;
  final DateTime? calibrationDueDate;
  final String? notes;

  // ── Capability flags (drive the physics rules R1–R9) ──
  /// Software that cannot reach the vehicle bus on its own — needs a hardware
  /// interface (VN / Kvaser). E.g. CANoe, CANape. (Rule R2/R3)
  final bool requiresInterface;

  /// Part of the fixed backbone: every captured bus must reach this device.
  /// True for Raptor CAL and the GL2000. (Rule R8)
  final bool mustReceiveAllSignals;

  /// GNSS with dual antenna → true heading + slip angle + pitch/roll + yaw,
  /// valid even at rest. Single antenna cannot do slip/low-speed heading. (Rule R4)
  final bool dualAntenna;

  const Instrument({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    required this.supportedProtocols,
    required this.supportsCAnFD,
    required this.channelCount,
    required this.description,
    this.status = InstrumentStatus.available,
    this.quantity = 1,
    this.calibrationDueDate,
    this.notes,
    this.requiresInterface = false,
    this.mustReceiveAllSignals = false,
    this.dualAntenna = false,
  });

  int get totalChannels =>
      channelCount.values.fold(0, (sum, c) => sum + c);

  /// CAN channels only (classic + FD) — used for channel budgeting (R5).
  int get canChannels => channelCount.entries
      .where((e) => e.key.isCan)
      .fold(0, (sum, e) => sum + e.value);

  /// True if this device is a hardware bus interface (Kvaser / VN) that
  /// software like CANoe/CANape can connect through. (R2)
  bool get isBusInterface => category == InstrumentCategory.interfaceDevice;
}


// ─── OBD Pin Definition ─────────────────────────────────────────────────────
class OBDPin {
  final int pinNumber;
  final String description;
  final BusProtocol? protocol;
  final bool isHighLine; // true = CANH, false = CANL
  final bool isPresent;

  const OBDPin({
    required this.pinNumber,
    required this.description,
    this.protocol,
    this.isHighLine = true,
    this.isPresent = true,
  });

  Map<String, dynamic> toJson() => {
        'pinNumber': pinNumber,
        'description': description,
        'protocol': protocol?.name,
        'isHighLine': isHighLine,
        'isPresent': isPresent,
      };

  factory OBDPin.fromJson(Map<String, dynamic> j) => OBDPin(
        pinNumber: (j['pinNumber'] as num?)?.toInt() ?? 0,
        description: j['description'] as String? ?? '',
        protocol: j['protocol'] == null
            ? null
            : busProtocolFromName(j['protocol'] as String?),
        isHighLine: j['isHighLine'] as bool? ?? true,
        isPresent: j['isPresent'] as bool? ?? true,
      );
}


// ─── Vehicle CAN Bus Definition ─────────────────────────────────────────────
class VehicleBus {
  final String id;
  final String name;
  final BusProtocol protocol;
  final int? obdPinHigh;
  final int? obdPinLow;
  final String? description;
  final String? dbcFile; // associated DBC (Phase 3)

  const VehicleBus({
    required this.id,
    required this.name,
    required this.protocol,
    this.obdPinHigh,
    this.obdPinLow,
    this.description,
    this.dbcFile,
  });

  bool get isCanFD => protocol == BusProtocol.canFD;

  VehicleBus copyWith({
    String? name,
    BusProtocol? protocol,
    int? obdPinHigh,
    int? obdPinLow,
    String? description,
    String? dbcFile,
    bool clearDbc = false,
  }) =>
      VehicleBus(
        id: id,
        name: name ?? this.name,
        protocol: protocol ?? this.protocol,
        obdPinHigh: obdPinHigh ?? this.obdPinHigh,
        obdPinLow: obdPinLow ?? this.obdPinLow,
        description: description ?? this.description,
        dbcFile: clearDbc ? null : (dbcFile ?? this.dbcFile),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'obdPinHigh': obdPinHigh,
        'obdPinLow': obdPinLow,
        'description': description,
        'dbcFile': dbcFile,
      };

  factory VehicleBus.fromJson(Map<String, dynamic> j) => VehicleBus(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        protocol: busProtocolFromName(j['protocol'] as String?),
        obdPinHigh: (j['obdPinHigh'] as num?)?.toInt(),
        obdPinLow: (j['obdPinLow'] as num?)?.toInt(),
        description: j['description'] as String?,
        dbcFile: j['dbcFile'] as String?,
      );
}


// ─── Schematic Node ─────────────────────────────────────────────────────────
class SchematicNode {
  final String id;
  final String label;
  final String? sublabel;
  final InstrumentCategory nodeType;
  final String? instrumentId; // links to Instrument.id if applicable
  double x; // position (fraction 0..1 of canvas width)
  double y; // position (fraction 0..1 of canvas height)

  SchematicNode({
    required this.id,
    required this.label,
    this.sublabel,
    required this.nodeType,
    this.instrumentId,
    required this.x,
    required this.y,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'sublabel': sublabel,
        'nodeType': nodeType.name,
        'instrumentId': instrumentId,
        'x': x,
        'y': y,
      };

  factory SchematicNode.fromJson(Map<String, dynamic> j) => SchematicNode(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        sublabel: j['sublabel'] as String?,
        nodeType: instrumentCategoryFromName(j['nodeType'] as String?),
        instrumentId: j['instrumentId'] as String?,
        x: (j['x'] as num?)?.toDouble() ?? 0.5,
        y: (j['y'] as num?)?.toDouble() ?? 0.5,
      );
}


// ─── Schematic Connection ───────────────────────────────────────────────────
class SchematicConnection {
  final String fromNodeId;
  final String toNodeId;
  final String label;
  final BusProtocol protocol;
  final int? busIndex; // e.g., CAN 1, CAN 2, CAN 3

  const SchematicConnection({
    required this.fromNodeId,
    required this.toNodeId,
    required this.label,
    required this.protocol,
    this.busIndex,
  });

  Map<String, dynamic> toJson() => {
        'fromNodeId': fromNodeId,
        'toNodeId': toNodeId,
        'label': label,
        'protocol': protocol.name,
        'busIndex': busIndex,
      };

  factory SchematicConnection.fromJson(Map<String, dynamic> j) =>
      SchematicConnection(
        fromNodeId: j['fromNodeId'] as String? ?? '',
        toNodeId: j['toNodeId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        protocol: busProtocolFromName(j['protocol'] as String?),
        busIndex: (j['busIndex'] as num?)?.toInt(),
      );
}


// ─── Vehicle Profile ────────────────────────────────────────────────────────
class VehicleProfile {
  final String id;
  final String name;
  final String manufacturer;
  final List<VehicleBus> buses;
  final List<OBDPin> obdPinout;
  final List<SchematicNode> schematicNodes;
  final List<SchematicConnection> schematicConnections;

  const VehicleProfile({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.buses,
    required this.obdPinout,
    required this.schematicNodes,
    required this.schematicConnections,
  });

  Set<BusProtocol> get requiredProtocols =>
      buses.map((b) => b.protocol).toSet();

  /// Vehicle CAN buses only — count drives the CAN channel budget (R5).
  List<VehicleBus> get canBuses =>
      buses.where((b) => b.protocol.isCan).toList();

  bool get hasCanFD => buses.any((b) => b.isCanFD);
}


// ═══════════════════════════════════════════════════════════════════════════
//  HARDCODED DATA — real owned inventory
// ═══════════════════════════════════════════════════════════════════════════

// ─── Instrument Catalog ─────────────────────────────────────────────────────
final List<Instrument> instrumentCatalog = [
  // ── Vector GL2000 — the primary standalone data logger (classic CAN ONLY) ──
  Instrument(
    id: 'gl2000',
    name: 'GL2000 ("GLM")',
    brand: 'Vector',
    category: InstrumentCategory.logger,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.lin},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 4, BusProtocol.lin: 2},
    description:
        'Primary standalone data logger. Classic CAN 2.0 + LIN, up to 4 CAN channels. '
        'NO CAN FD — this is the key limitation: on an FD bus the GL2000 cannot log.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    mustReceiveAllSignals: true,
    notes: 'Backbone: every captured bus must also reach the GL2000 (R8). '
        'Classic CAN only → FD buses must be logged elsewhere (CANoe/CANape/Raptor).',
  ),

  // ── Kvaser interface (PC bus access for CANoe/CANape) ──
  Instrument(
    id: 'kvaser',
    name: 'Kvaser Interface',
    brand: 'Kvaser',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 1},
    description:
        'USB CAN interface used to FLASH the Raptor ECUs — that is its one main function. '
        'Not part of the live vehicle capture path.',
    status: InstrumentStatus.available,
    quantity: 1,
    notes: 'Primary role: flashing Raptor ECU firmware (Calibration). ⚠ Confirm exact model.',
  ),

  // ── New Eagle Raptor CAL — rapid-proto controller (CAN + CAN FD) ──
  Instrument(
    id: 'raptor_cal',
    name: 'Raptor CAL (RCM80)',
    brand: 'New Eagle',
    category: InstrumentCategory.ecu,
    supportedProtocols: {
      BusProtocol.can2A,
      BusProtocol.can2B,
      BusProtocol.canFD,
      BusProtocol.analog,
      BusProtocol.digitalIO,
    },
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 4, BusProtocol.analog: 8, BusProtocol.digitalIO: 8},
    description:
        'Rapid-prototyping controller running the SightLine tire-intelligence models '
        '(AQD, Leak Detection, Dynamic Friction, Dynamic Load) → output to the Display. '
        'Vehicle CAN feeds it here. 4 CAN/CAN FD, 8 analog, 8 DIO.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    mustReceiveAllSignals: true,
    notes: 'MANDATORY for Validation (models run here → Display). OPTIONAL for Calibration. '
        'Flashed via Kvaser. Connector J2 (Black Key): 64319211.',
  ),

  // ── Vector CANoe — analysis/simulation software (needs interface) ──
  Instrument(
    id: 'canoe',
    name: 'CANoe',
    brand: 'Vector',
    category: InstrumentCategory.software,
    supportedProtocols: {
      BusProtocol.can2A,
      BusProtocol.can2B,
      BusProtocol.canFD,
      BusProtocol.lin,
      BusProtocol.flexRay,
      BusProtocol.ethernet,
    },
    supportsCAnFD: true,
    channelCount: {},
    description:
        'Bus simulation, analysis and test. Supports CAN FD — but only through an '
        'FD-capable hardware interface. Cannot touch the vehicle without an interface.',
    status: InstrumentStatus.available,
    quantity: 1,
    requiresInterface: true,
    notes: 'Needs a Vector VN (or Kvaser via CANlib) interface to reach the bus (R2/R3).',
  ),

  // ── Vector CANape — ECU measurement + calibration (needs interface) ──
  Instrument(
    id: 'canape',
    name: 'CANape',
    brand: 'Vector',
    category: InstrumentCategory.software,
    supportedProtocols: {
      BusProtocol.can2A,
      BusProtocol.can2B,
      BusProtocol.canFD,
      BusProtocol.lin,
      BusProtocol.flexRay,
      BusProtocol.ethernet,
    },
    supportsCAnFD: true,
    channelCount: {},
    description:
        'ECU measurement & calibration (XCP/CCP, A2L). Supports CAN FD; can run XCP on '
        'CAN FD with the same A2L (CANoe handles this differently).',
    status: InstrumentStatus.available,
    quantity: 1,
    requiresInterface: true,
    notes: 'Needs a Vector VN/VX (or Kvaser) interface to reach the bus (R2/R3).',
  ),

  // ── Racelogic VBOX 3i Dual Antenna — GNSS (slip angle, true heading) ──
  Instrument(
    id: 'vbox_3i_dual',
    name: 'VBOX 3i Dual Antenna',
    brand: 'Racelogic',
    category: InstrumentCategory.sensor,
    supportedProtocols: {BusProtocol.gpsGnss, BusProtocol.can2A, BusProtocol.analog},
    supportsCAnFD: false,
    channelCount: {BusProtocol.gpsGnss: 1, BusProtocol.can2A: 2, BusProtocol.analog: 4},
    description:
        '100 Hz GPS+GLONASS logger. Dual antenna → TRUE heading + slip angle + pitch/roll '
        '+ yaw rate, valid even at rest. CAN out to feed the logger/Raptor.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    dualAntenna: true,
    notes: 'Dual antenna is essential for vehicle-dynamics/tire work (slip angle).',
  ),

  // ── Racelogic IMU (integrated with VBOX 3i) ──
  Instrument(
    id: 'imu',
    name: 'IMU',
    brand: 'Racelogic',
    category: InstrumentCategory.sensor,
    supportedProtocols: {BusProtocol.imu, BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.imu: 1},
    description:
        'Inertial measurement unit, Kalman-fused with the VBOX 3i to improve slip/attitude '
        'accuracy and bridge GNSS dropouts.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: '⚠ Confirm model (e.g. Racelogic IMU04). Integrated with VBOX 3i.',
  ),

  // ── Setup components (vehicle-specific accessories) ──
  Instrument(
    id: 'huf_receiver',
    name: 'HUF Receiver',
    brand: 'HUF',
    category: InstrumentCategory.receiver,
    supportedProtocols: {BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 1},
    description: 'TPMS receiver → tire pressure/temperature over CAN (TMS_CAN).',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Tire-intelligence accessory. Typically feeds the Raptor CAL.',
  ),
  Instrument(
    id: 'display_uiux',
    name: 'Display UI/UX',
    brand: 'Custom',
    category: InstrumentCategory.display,
    supportedProtocols: {BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 1},
    description: 'Custom display for real-time visualization. Fed by the Raptor CAL.',
    status: InstrumentStatus.inUse,
    quantity: 1,
  ),
  Instrument(
    id: 'power_breakout',
    name: 'Power Breakout Bar',
    brand: 'Custom',
    category: InstrumentCategory.power,
    supportedProtocols: {},
    supportsCAnFD: false,
    channelCount: {},
    description: 'Fused power distribution for the instrumentation backbone.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Provides fused power to GL2000, Raptor CAL, HUF, Display, VBOX.',
  ),
];


// ─── Example Vehicle: TATA BETA (EV) ────────────────────────────────────────
// Demonstrates the fixed parallel backbone (every bus → GL2000 AND Raptor CAL)
// and an FD bus (CAN 3) that trips the R9 conflict against the classic-only GL2000.
const List<OBDPin> tataBetaOBDPinout = [
  OBDPin(pinNumber: 1,  description: 'Ignition'),
  OBDPin(pinNumber: 2,  description: 'ADAS CANH',        protocol: BusProtocol.canFD, isHighLine: true),
  OBDPin(pinNumber: 3,  description: 'EV CANH',          protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 4,  description: 'Chassis Ground'),
  OBDPin(pinNumber: 5,  description: 'Signal Ground'),
  OBDPin(pinNumber: 6,  description: 'Diagnostics CANH', protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 7,  description: 'PT_CAN H',         protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 8,  description: 'Body CANH',        protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 9,  description: 'Body CANL',        protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 10, description: 'ADAS CANL',        protocol: BusProtocol.canFD, isHighLine: false),
  OBDPin(pinNumber: 11, description: 'EV CANL',          protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 12, description: 'BCM LIN2 (Sunroof)', protocol: BusProtocol.lin),
  OBDPin(pinNumber: 13, description: 'BCM LIN1 (PDC)',   protocol: BusProtocol.lin),
  OBDPin(pinNumber: 14, description: 'Diagnostics CANL', protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 15, description: 'PT_CAN L',         protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 16, description: 'Battery Positive'),
];

final VehicleProfile tataBetaProfile = VehicleProfile(
  id: 'tata_beta',
  name: 'TATA BETA (EV)',
  manufacturer: 'Tata Motors',
  buses: const [
    VehicleBus(id: 'pt_can',   name: 'Vehicle CAN 1 · PT_CAN',   protocol: BusProtocol.can2A, obdPinHigh: 7, obdPinLow: 15, description: 'Powertrain'),
    VehicleBus(id: 'body_can', name: 'Vehicle CAN 2 · Body CAN', protocol: BusProtocol.can2A, obdPinHigh: 8, obdPinLow: 9,  description: 'Body electronics'),
    VehicleBus(id: 'adas_can', name: 'Vehicle CAN 3 · ADAS',     protocol: BusProtocol.canFD, obdPinHigh: 2, obdPinLow: 10, description: 'ADAS — CAN FD (GL2000 cannot log this!)'),
  ],
  obdPinout: tataBetaOBDPinout,
  schematicNodes: [
    // Vehicle source + buses (fan out)
    SchematicNode(id: 'obd_port', label: 'Vehicle OBD', sublabel: 'TATA BETA', nodeType: InstrumentCategory.connector, x: 0.06, y: 0.50),
    SchematicNode(id: 'can1_bus', label: 'CAN 1 · PT',  sublabel: 'CAN 2.0',  nodeType: InstrumentCategory.connector, x: 0.24, y: 0.22),
    SchematicNode(id: 'can2_bus', label: 'CAN 2 · Body', sublabel: 'CAN 2.0', nodeType: InstrumentCategory.connector, x: 0.24, y: 0.50),
    SchematicNode(id: 'can3_bus', label: 'CAN 3 · ADAS', sublabel: 'CAN FD',  nodeType: InstrumentCategory.connector, x: 0.24, y: 0.78),
    // Backbone: GL2000 + Raptor CAL (both receive all buses)
    SchematicNode(id: 'gl2000', label: 'GL2000', sublabel: 'Logger (no FD)', nodeType: InstrumentCategory.logger, instrumentId: 'gl2000', x: 0.52, y: 0.30),
    SchematicNode(id: 'raptor', label: 'Raptor CAL', sublabel: 'Controller', nodeType: InstrumentCategory.ecu, instrumentId: 'raptor_cal', x: 0.52, y: 0.68),
    // GNSS / inertial
    SchematicNode(id: 'vbox', label: 'VBOX 3i', sublabel: 'Dual Antenna', nodeType: InstrumentCategory.sensor, instrumentId: 'vbox_3i_dual', x: 0.80, y: 0.20),
    SchematicNode(id: 'imu', label: 'IMU', sublabel: 'Inertial', nodeType: InstrumentCategory.sensor, instrumentId: 'imu', x: 0.80, y: 0.42),
    // Downstream accessories
    SchematicNode(id: 'huf', label: 'HUF', sublabel: 'TPMS', nodeType: InstrumentCategory.receiver, instrumentId: 'huf_receiver', x: 0.80, y: 0.64),
    SchematicNode(id: 'display', label: 'Display', sublabel: 'UI/UX', nodeType: InstrumentCategory.display, instrumentId: 'display_uiux', x: 0.80, y: 0.86),
    // PC software + power
    SchematicNode(id: 'pc_sw', label: 'PC · CANoe/CANape', sublabel: 'via Kvaser', nodeType: InstrumentCategory.software, instrumentId: 'canoe', x: 0.52, y: 0.94),
    SchematicNode(id: 'power_bar', label: 'Power Breakout', sublabel: 'Distribution', nodeType: InstrumentCategory.power, instrumentId: 'power_breakout', x: 0.52, y: 0.04),
  ],
  schematicConnections: [
    // OBD → buses
    SchematicConnection(fromNodeId: 'obd_port', toNodeId: 'can1_bus', label: 'PT_CAN',  protocol: BusProtocol.can2A, busIndex: 1),
    SchematicConnection(fromNodeId: 'obd_port', toNodeId: 'can2_bus', label: 'Body',    protocol: BusProtocol.can2A, busIndex: 2),
    SchematicConnection(fromNodeId: 'obd_port', toNodeId: 'can3_bus', label: 'ADAS FD', protocol: BusProtocol.canFD, busIndex: 3),
    // Parallel backbone (R8): every bus → GL2000 AND Raptor CAL
    SchematicConnection(fromNodeId: 'can1_bus', toNodeId: 'gl2000', label: 'CAN 1', protocol: BusProtocol.can2A, busIndex: 1),
    SchematicConnection(fromNodeId: 'can1_bus', toNodeId: 'raptor', label: 'CAN 1', protocol: BusProtocol.can2A, busIndex: 1),
    SchematicConnection(fromNodeId: 'can2_bus', toNodeId: 'gl2000', label: 'CAN 2', protocol: BusProtocol.can2A, busIndex: 2),
    SchematicConnection(fromNodeId: 'can2_bus', toNodeId: 'raptor', label: 'CAN 2', protocol: BusProtocol.can2A, busIndex: 2),
    SchematicConnection(fromNodeId: 'can3_bus', toNodeId: 'gl2000', label: 'CAN 3 (FD!)', protocol: BusProtocol.canFD, busIndex: 3),
    SchematicConnection(fromNodeId: 'can3_bus', toNodeId: 'raptor', label: 'CAN 3', protocol: BusProtocol.canFD, busIndex: 3),
    // Raptor → accessories
    SchematicConnection(fromNodeId: 'raptor', toNodeId: 'huf',     label: 'TMS_CAN', protocol: BusProtocol.can2A),
    SchematicConnection(fromNodeId: 'raptor', toNodeId: 'display', label: 'Display', protocol: BusProtocol.can2A),
    // GNSS / inertial → backbone
    SchematicConnection(fromNodeId: 'imu',  toNodeId: 'vbox',   label: 'IMU fuse', protocol: BusProtocol.imu),
    SchematicConnection(fromNodeId: 'vbox', toNodeId: 'raptor', label: 'GPS CAN',  protocol: BusProtocol.can2A),
    SchematicConnection(fromNodeId: 'vbox', toNodeId: 'gl2000', label: 'GPS CAN',  protocol: BusProtocol.can2A),
    // PC software (via interface)
    SchematicConnection(fromNodeId: 'can3_bus', toNodeId: 'pc_sw', label: 'FD via Kvaser', protocol: BusProtocol.canFD, busIndex: 3),
    // Power
    SchematicConnection(fromNodeId: 'power_bar', toNodeId: 'gl2000', label: 'Power', protocol: BusProtocol.analog),
    SchematicConnection(fromNodeId: 'power_bar', toNodeId: 'raptor', label: 'Power', protocol: BusProtocol.analog),
  ],
);


// ─── All Vehicle Profiles ───────────────────────────────────────────────────
final List<VehicleProfile> allVehicleProfiles = [
  tataBetaProfile,
];

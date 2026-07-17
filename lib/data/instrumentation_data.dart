/// TrackLog — Instrumentation Intelligence Data Layer
/// Hardcoded catalog of instruments, vehicle profiles, and OBD pinouts.

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
      case InstrumentCategory.ecu: return 'ECU';
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
  });

  int get totalChannels =>
      channelCount.values.fold(0, (sum, c) => sum + c);
}


// ─── OBD Pin Definition ─────────────────────────────────────────────────────
class OBDPin {
  final int pinNumber;
  final String description;
  final BusProtocol? protocol;
  final bool isHighLine; // true = CANH, false = CANL, null for non-CAN
  final bool isPresent;

  const OBDPin({
    required this.pinNumber,
    required this.description,
    this.protocol,
    this.isHighLine = true,
    this.isPresent = true,
  });
}


// ─── Vehicle CAN Bus Definition ─────────────────────────────────────────────
class VehicleBus {
  final String id;
  final String name;
  final BusProtocol protocol;
  final int? obdPinHigh;
  final int? obdPinLow;
  final String? description;

  const VehicleBus({
    required this.id,
    required this.name,
    required this.protocol,
    this.obdPinHigh,
    this.obdPinLow,
    this.description,
  });
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
}


// ═══════════════════════════════════════════════════════════════════════════
//  HARDCODED DATA
// ═══════════════════════════════════════════════════════════════════════════

// ─── Instrument Catalog ─────────────────────────────────────────────────────
final List<Instrument> instrumentCatalog = [
  // ── Vector GL Series ──
  Instrument(
    id: 'gl1000',
    name: 'GL1000',
    brand: 'Vector',
    category: InstrumentCategory.logger,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 2},
    description: 'Compact 2-channel CAN data logger. No CAN FD support.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Currently deployed in TATA BETA vehicle setup. Connected to Vehicle CAN 1 & CAN 2.',
  ),
  Instrument(
    id: 'gl2000',
    name: 'GL2000',
    brand: 'Vector',
    category: InstrumentCategory.logger,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 4},
    description: '4-channel CAN data logger. No CAN FD. DB9 connectors.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),
  Instrument(
    id: 'gl3000',
    name: 'GL3000',
    brand: 'Vector',
    category: InstrumentCategory.logger,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 4, BusProtocol.lin: 2},
    description: 'Mid-range logger with CAN FD and LIN support. 4 CAN/FD + 2 LIN channels.',
    status: InstrumentStatus.available,
    quantity: 0,
    notes: 'Not currently in inventory. Recommended upgrade for CAN FD vehicles.',
  ),
  Instrument(
    id: 'gl4000',
    name: 'GL4000',
    brand: 'Vector',
    category: InstrumentCategory.logger,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin, BusProtocol.ethernet},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 6, BusProtocol.lin: 4, BusProtocol.ethernet: 2},
    description: 'Top-tier logger. CAN FD, LIN, Automotive Ethernet. Full protocol coverage.',
    status: InstrumentStatus.available,
    quantity: 0,
    notes: 'Not currently in inventory. Premium option for full vehicle network capture.',
  ),

  // ── Vector VN Series ──
  Instrument(
    id: 'vn1610',
    name: 'VN1610',
    brand: 'Vector',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 2},
    description: 'USB CAN interface. 2 CAN channels. No CAN FD.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),
  Instrument(
    id: 'vn1630',
    name: 'VN1630',
    brand: 'Vector',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 2, BusProtocol.lin: 2},
    description: 'USB CAN FD + LIN interface. Compact and FD-capable.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),
  Instrument(
    id: 'vn5610',
    name: 'VN5610',
    brand: 'Vector',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.ethernet},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 2, BusProtocol.ethernet: 1},
    description: 'CAN FD + Automotive Ethernet interface.',
    status: InstrumentStatus.available,
    quantity: 0,
  ),
  Instrument(
    id: 'vn7640',
    name: 'VN7640',
    brand: 'Vector',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin, BusProtocol.flexRay, BusProtocol.ethernet},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 4, BusProtocol.lin: 4, BusProtocol.flexRay: 2, BusProtocol.ethernet: 2},
    description: 'Full protocol coverage: CAN FD, LIN, FlexRay, Ethernet.',
    status: InstrumentStatus.available,
    quantity: 0,
  ),

  // ── Vector Software ──
  Instrument(
    id: 'canalyzer',
    name: 'CANalyzer',
    brand: 'Vector',
    category: InstrumentCategory.software,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin, BusProtocol.ethernet},
    supportsCAnFD: true,
    channelCount: {},
    description: 'CAN/LIN/Ethernet analysis software. CAN FD support with FD license.',
    status: InstrumentStatus.available,
    quantity: 1,
    notes: 'Requires Vector hardware interface (VN series) to connect to vehicle.',
  ),
  Instrument(
    id: 'canoe',
    name: 'CANoe',
    brand: 'Vector',
    category: InstrumentCategory.software,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin, BusProtocol.flexRay, BusProtocol.ethernet},
    supportsCAnFD: true,
    channelCount: {},
    description: 'Full simulation and analysis environment. All protocols.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),

  // ── Kvaser ──
  Instrument(
    id: 'kvaser_leaf_v2',
    name: 'Leaf Light v2',
    brand: 'Kvaser',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 1},
    description: 'Budget single-channel CAN interface. No CAN FD.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),
  Instrument(
    id: 'kvaser_u100',
    name: 'U100',
    brand: 'Kvaser',
    category: InstrumentCategory.interfaceDevice,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 1},
    description: 'Compact single-channel CAN FD interface.',
    status: InstrumentStatus.available,
    quantity: 0,
  ),

  // ── Racelogic ──
  Instrument(
    id: 'vbox_3i',
    name: 'VBOX 3i',
    brand: 'Racelogic',
    category: InstrumentCategory.sensor,
    supportedProtocols: {BusProtocol.gpsGnss, BusProtocol.analog, BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.gpsGnss: 1, BusProtocol.can2A: 2, BusProtocol.analog: 4},
    description: '20 Hz GPS data logger with 2 CAN + 4 analog inputs.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),
  Instrument(
    id: 'vbox_touch',
    name: 'VBOX Touch',
    brand: 'Racelogic',
    category: InstrumentCategory.sensor,
    supportedProtocols: {BusProtocol.gpsGnss, BusProtocol.can2A, BusProtocol.video},
    supportsCAnFD: false,
    channelCount: {BusProtocol.gpsGnss: 1, BusProtocol.can2A: 2, BusProtocol.video: 2},
    description: 'Touchscreen GPS logger with 2 CAN + 2 camera inputs.',
    status: InstrumentStatus.available,
    quantity: 0,
  ),

  // ── dSPACE ──
  Instrument(
    id: 'microautobox_ii',
    name: 'MicroAutoBox II',
    brand: 'dSPACE',
    category: InstrumentCategory.ecu,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.lin, BusProtocol.ethernet},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 6, BusProtocol.lin: 4},
    description: 'Rapid prototyping ECU. CAN FD, LIN, Ethernet. Real-time.',
    status: InstrumentStatus.available,
    quantity: 0,
  ),

  // ── Oxford / GeneSys ──
  Instrument(
    id: 'rt3000',
    name: 'RT3000',
    brand: 'Oxford Technical Solutions',
    category: InstrumentCategory.sensor,
    supportedProtocols: {BusProtocol.gpsGnss, BusProtocol.imu, BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.gpsGnss: 1, BusProtocol.imu: 1, BusProtocol.can2A: 1},
    description: '100 Hz high-precision INS/IMU + GPS. CAN output only.',
    status: InstrumentStatus.available,
    quantity: 1,
  ),
  Instrument(
    id: 'adma',
    name: 'ADMA',
    brand: 'GeneSys',
    category: InstrumentCategory.sensor,
    supportedProtocols: {BusProtocol.gpsGnss, BusProtocol.imu, BusProtocol.can2A, BusProtocol.ethernet},
    supportsCAnFD: false,
    channelCount: {BusProtocol.gpsGnss: 1, BusProtocol.imu: 1, BusProtocol.can2A: 1, BusProtocol.ethernet: 1},
    description: '200+ Hz premium INS. CAN + Ethernet output.',
    status: InstrumentStatus.available,
    quantity: 0,
  ),

  // ── TATA Setup Specific ──
  Instrument(
    id: 'raptor_rcm80',
    name: 'Raptor RCM80',
    brand: 'New Eagle',
    category: InstrumentCategory.ecu,
    supportedProtocols: {BusProtocol.can2A, BusProtocol.can2B, BusProtocol.canFD, BusProtocol.analog, BusProtocol.digitalIO},
    supportsCAnFD: true,
    channelCount: {BusProtocol.canFD: 4, BusProtocol.analog: 8, BusProtocol.digitalIO: 8},
    description: 'Rapid prototyping controller. 4 CAN/FD, 8 analog, 8 DIO. Connector J2 (Black Key): 64319211.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Deployed in TATA BETA setup. Connected to Vehicle CAN 3, HUF Receiver (TMS_CAN), and Display.',
  ),
  Instrument(
    id: 'huf_receiver',
    name: 'HUF Receiver',
    brand: 'HUF',
    category: InstrumentCategory.receiver,
    supportedProtocols: {BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 1},
    description: 'TPMS receiver for tire pressure monitoring. CAN 2.0 output (TMS_CAN).',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Connected to Raptor RCM80 via TMS_CAN_1.',
  ),
  Instrument(
    id: 'display_uiux',
    name: 'Display UI/UX',
    brand: 'Custom',
    category: InstrumentCategory.display,
    supportedProtocols: {BusProtocol.can2A},
    supportsCAnFD: false,
    channelCount: {BusProtocol.can2A: 1},
    description: 'Custom display for real-time visualization.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Connected to Raptor RCM80.',
  ),
  Instrument(
    id: 'power_breakout',
    name: 'Power Breakout Bar',
    brand: 'Custom',
    category: InstrumentCategory.power,
    supportedProtocols: {},
    supportsCAnFD: false,
    channelCount: {},
    description: 'Power distribution unit for vehicle instrumentation.',
    status: InstrumentStatus.inUse,
    quantity: 1,
    notes: 'Provides fused power to GL1000, Raptor, HUF, and Display.',
  ),
];


// ─── TATA BETA OBD Pinout ───────────────────────────────────────────────────
const List<OBDPin> tataBetaOBDPinout = [
  OBDPin(pinNumber: 1,  description: 'Ignition'),
  OBDPin(pinNumber: 2,  description: 'ADAS CANH',        protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 3,  description: 'EV CANH',          protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 4,  description: 'Chassis Ground'),
  OBDPin(pinNumber: 5,  description: 'Signal Ground'),
  OBDPin(pinNumber: 6,  description: 'Diagnostics CANH', protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 7,  description: 'PT_CAN H',         protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 8,  description: 'Body CANH',        protocol: BusProtocol.can2A, isHighLine: true),
  OBDPin(pinNumber: 9,  description: 'Body CANL',        protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 10, description: 'ADAS CANL',        protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 11, description: 'EV CAN',           protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 12, description: 'BCM LIN2 (Sunroof)', protocol: BusProtocol.lin),
  OBDPin(pinNumber: 13, description: 'BCM LIN1 (Front + Rear PDC)', protocol: BusProtocol.lin),
  OBDPin(pinNumber: 14, description: 'Diagnostics CANL', protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 15, description: 'PT_CAN L',         protocol: BusProtocol.can2A, isHighLine: false),
  OBDPin(pinNumber: 16, description: 'Battery Positive'),
];


// ─── TATA BETA Vehicle Profile ──────────────────────────────────────────────
final VehicleProfile tataBetaProfile = VehicleProfile(
  id: 'tata_beta',
  name: 'TATA BETA (EV)',
  manufacturer: 'Tata Motors',
  buses: const [
    VehicleBus(id: 'adas_can',  name: 'ADAS CAN',        protocol: BusProtocol.can2A, obdPinHigh: 2,  obdPinLow: 10, description: 'Advanced Driver Assistance System'),
    VehicleBus(id: 'ev_can',    name: 'EV CAN',          protocol: BusProtocol.can2A, obdPinHigh: 3,  obdPinLow: 11, description: 'Electric Vehicle powertrain'),
    VehicleBus(id: 'diag_can',  name: 'Diagnostics CAN', protocol: BusProtocol.can2A, obdPinHigh: 6,  obdPinLow: 14, description: 'OBD-II diagnostics'),
    VehicleBus(id: 'pt_can',    name: 'PT_CAN',          protocol: BusProtocol.can2A, obdPinHigh: 7,  obdPinLow: 15, description: 'Powertrain CAN bus'),
    VehicleBus(id: 'body_can',  name: 'Body CAN',        protocol: BusProtocol.can2A, obdPinHigh: 8,  obdPinLow: 9,  description: 'Body electronics'),
    VehicleBus(id: 'lin1',      name: 'BCM LIN1',        protocol: BusProtocol.lin,   obdPinHigh: 13, description: 'Front + Rear PDC'),
    VehicleBus(id: 'lin2',      name: 'BCM LIN2',        protocol: BusProtocol.lin,   obdPinHigh: 12, description: 'Sunroof'),
  ],
  obdPinout: tataBetaOBDPinout,
  schematicNodes: [
    // Vehicle source
    SchematicNode(id: 'obd_port',       label: 'Vehicle OBD',    sublabel: 'TATA BETA',     nodeType: InstrumentCategory.connector, x: 0.08, y: 0.45),
    // CAN buses (fan out)
    SchematicNode(id: 'can1_bus',       label: 'Vehicle CAN 1',  sublabel: 'PT_CAN',        nodeType: InstrumentCategory.connector, x: 0.28, y: 0.15),
    SchematicNode(id: 'can2_bus',       label: 'Vehicle CAN 2',  sublabel: 'Body CAN',      nodeType: InstrumentCategory.connector, x: 0.28, y: 0.45),
    SchematicNode(id: 'can3_bus',       label: 'Vehicle CAN 3',  sublabel: 'ADAS CAN',      nodeType: InstrumentCategory.connector, x: 0.28, y: 0.75),
    // Instruments
    SchematicNode(id: 'gl1000',         label: 'Vector GL1000',  sublabel: 'Data Logger',    nodeType: InstrumentCategory.logger, instrumentId: 'gl1000', x: 0.52, y: 0.22),
    SchematicNode(id: 'raptor',         label: 'Raptor RCM80',   sublabel: 'ECU',            nodeType: InstrumentCategory.ecu, instrumentId: 'raptor_rcm80', x: 0.52, y: 0.65),
    // Downstream
    SchematicNode(id: 'huf',            label: 'HUF Receiver',   sublabel: 'TPMS',           nodeType: InstrumentCategory.receiver, instrumentId: 'huf_receiver', x: 0.75, y: 0.50),
    SchematicNode(id: 'display',        label: 'Display UI/UX',  sublabel: 'Visualization',  nodeType: InstrumentCategory.display, instrumentId: 'display_uiux', x: 0.75, y: 0.80),
    // Power
    SchematicNode(id: 'power_bar',      label: 'Power Breakout', sublabel: 'Distribution',   nodeType: InstrumentCategory.power, instrumentId: 'power_breakout', x: 0.52, y: 0.02),
    // Software / PC
    SchematicNode(id: 'pc_sw',          label: 'PC / CANalyzer', sublabel: 'Analysis',       nodeType: InstrumentCategory.software, instrumentId: 'canalyzer', x: 0.92, y: 0.22),
  ],
  schematicConnections: [
    // OBD to CAN buses
    SchematicConnection(fromNodeId: 'obd_port', toNodeId: 'can1_bus', label: 'PT_CAN',   protocol: BusProtocol.can2A, busIndex: 1),
    SchematicConnection(fromNodeId: 'obd_port', toNodeId: 'can2_bus', label: 'Body CAN',  protocol: BusProtocol.can2A, busIndex: 2),
    SchematicConnection(fromNodeId: 'obd_port', toNodeId: 'can3_bus', label: 'ADAS CAN',  protocol: BusProtocol.can2A, busIndex: 3),
    // CAN 1 & 2 → GL1000
    SchematicConnection(fromNodeId: 'can1_bus',  toNodeId: 'gl1000',  label: 'Vehicle CAN 1', protocol: BusProtocol.can2A, busIndex: 1),
    SchematicConnection(fromNodeId: 'can2_bus',  toNodeId: 'gl1000',  label: 'Vehicle CAN 2', protocol: BusProtocol.can2A, busIndex: 2),
    // CAN 3 → Raptor
    SchematicConnection(fromNodeId: 'can3_bus',  toNodeId: 'raptor',  label: 'Vehicle CAN 3', protocol: BusProtocol.can2A, busIndex: 3),
    // Raptor → HUF (TMS_CAN)
    SchematicConnection(fromNodeId: 'raptor',    toNodeId: 'huf',     label: 'TMS_CAN_1',     protocol: BusProtocol.can2A),
    // Raptor → Display
    SchematicConnection(fromNodeId: 'raptor',    toNodeId: 'display', label: 'Display CAN',   protocol: BusProtocol.can2A),
    // GL1000 → PC
    SchematicConnection(fromNodeId: 'gl1000',    toNodeId: 'pc_sw',   label: 'USB / SD',      protocol: BusProtocol.can2A),
    // Power connections (shown as lines but no data protocol)
    SchematicConnection(fromNodeId: 'power_bar', toNodeId: 'gl1000',  label: 'Power',          protocol: BusProtocol.analog),
    SchematicConnection(fromNodeId: 'power_bar', toNodeId: 'raptor',  label: 'Power',          protocol: BusProtocol.analog),
  ],
);


// ─── All Vehicle Profiles ───────────────────────────────────────────────────
final List<VehicleProfile> allVehicleProfiles = [
  tataBetaProfile,
];

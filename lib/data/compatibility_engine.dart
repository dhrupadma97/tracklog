/// TrackLog — Compatibility Engine
/// Validates instrument setups against vehicle protocol requirements.

import 'instrumentation_data.dart';

// ─── Warning Severity ───────────────────────────────────────────────────────
enum WarningSeverity {
  error,   // Hard incompatibility — will NOT work
  warning, // Partial mismatch — may work with limitations
  info,    // Recommendation / optimization
  success, // Fully compatible
}

extension WarningSeverityExt on WarningSeverity {
  String get label {
    switch (this) {
      case WarningSeverity.error: return 'ERROR';
      case WarningSeverity.warning: return 'WARNING';
      case WarningSeverity.info: return 'INFO';
      case WarningSeverity.success: return 'OK';
    }
  }

  int get colorValue {
    switch (this) {
      case WarningSeverity.error: return 0xFFFF4D6A;
      case WarningSeverity.warning: return 0xFFFFB547;
      case WarningSeverity.info: return 0xFF42A5F5;
      case WarningSeverity.success: return 0xFF4CAF50;
    }
  }

  String get iconName {
    switch (this) {
      case WarningSeverity.error: return 'error';
      case WarningSeverity.warning: return 'warning';
      case WarningSeverity.info: return 'info';
      case WarningSeverity.success: return 'check_circle';
    }
  }
}


// ─── Compatibility Result ───────────────────────────────────────────────────
class CompatibilityResult {
  final WarningSeverity severity;
  final String title;
  final String message;
  final String? instrumentId;
  final BusProtocol? relatedProtocol;
  final String? recommendation;

  const CompatibilityResult({
    required this.severity,
    required this.title,
    required this.message,
    this.instrumentId,
    this.relatedProtocol,
    this.recommendation,
  });
}


// ─── Validation Report ──────────────────────────────────────────────────────
class ValidationReport {
  final List<CompatibilityResult> results;
  final int errorCount;
  final int warningCount;
  final int infoCount;
  final int successCount;

  ValidationReport(this.results)
      : errorCount = results.where((r) => r.severity == WarningSeverity.error).length,
        warningCount = results.where((r) => r.severity == WarningSeverity.warning).length,
        infoCount = results.where((r) => r.severity == WarningSeverity.info).length,
        successCount = results.where((r) => r.severity == WarningSeverity.success).length;

  bool get isFullyCompatible => errorCount == 0 && warningCount == 0;
  bool get hasErrors => errorCount > 0;

  WarningSeverity get overallSeverity {
    if (errorCount > 0) return WarningSeverity.error;
    if (warningCount > 0) return WarningSeverity.warning;
    return WarningSeverity.success;
  }
}


// ═══════════════════════════════════════════════════════════════════════════
//  COMPATIBILITY ENGINE
// ═══════════════════════════════════════════════════════════════════════════

class CompatibilityEngine {
  /// Validate a set of instruments against the vehicle's required protocols.
  static ValidationReport validateSetup({
    required Set<BusProtocol> vehicleProtocols,
    required List<Instrument> selectedInstruments,
    int requiredCANChannels = 3,
    bool requiresSlipAngle = false,
  }) {
    final results = <CompatibilityResult>[];

    // ── 1. Check each instrument against each required protocol ──
    for (final instrument in selectedInstruments) {
      // Skip software — it depends on hardware
      if (instrument.category == InstrumentCategory.software) continue;

      for (final protocol in vehicleProtocols) {
        if (protocol == BusProtocol.can2A || protocol == BusProtocol.can2B) {
          // Basic CAN — almost all instruments support this
          if (!instrument.supportedProtocols.contains(BusProtocol.can2A) &&
              !instrument.supportedProtocols.contains(BusProtocol.can2B)) {
            results.add(CompatibilityResult(
              severity: WarningSeverity.error,
              title: '${instrument.brand} ${instrument.name} — No CAN Support',
              message: 'This instrument does not support CAN 2.0 at all.',
              instrumentId: instrument.id,
              relatedProtocol: protocol,
            ));
          }
        } else if (protocol == BusProtocol.canFD) {
          if (!instrument.supportsCAnFD) {
            // Determine if this is an error or warning based on role
            final isLogger = instrument.category == InstrumentCategory.logger;
            final isInterface = instrument.category == InstrumentCategory.interfaceDevice;

            if (isLogger || isInterface) {
              results.add(CompatibilityResult(
                severity: WarningSeverity.error,
                title: '${instrument.brand} ${instrument.name} — No CAN FD',
                message: 'Vehicle outputs CAN FD but ${instrument.name} does NOT support CAN FD. '
                    'CAN FD frames will be lost or cause bus errors.',
                instrumentId: instrument.id,
                relatedProtocol: BusProtocol.canFD,
                recommendation: _recommendFDUpgrade(instrument),
              ));
            } else {
              results.add(CompatibilityResult(
                severity: WarningSeverity.warning,
                title: '${instrument.brand} ${instrument.name} — No CAN FD',
                message: '${instrument.name} does not support CAN FD. '
                    'It may still work on classic CAN frames if the bus is mixed.',
                instrumentId: instrument.id,
                relatedProtocol: BusProtocol.canFD,
              ));
            }
          } else {
            results.add(CompatibilityResult(
              severity: WarningSeverity.success,
              title: '${instrument.brand} ${instrument.name} — CAN FD OK',
              message: '${instrument.name} fully supports CAN FD.',
              instrumentId: instrument.id,
              relatedProtocol: BusProtocol.canFD,
            ));
          }
        } else if (protocol == BusProtocol.lin) {
          if (!instrument.supportedProtocols.contains(BusProtocol.lin)) {
            // LIN is usually optional, not an error
            results.add(CompatibilityResult(
              severity: WarningSeverity.info,
              title: '${instrument.brand} ${instrument.name} — No LIN',
              message: '${instrument.name} does not capture LIN. '
                  'LIN buses (PDC, Sunroof) will not be logged.',
              instrumentId: instrument.id,
              relatedProtocol: BusProtocol.lin,
            ));
          }
        } else if (protocol == BusProtocol.ethernet) {
          if (!instrument.supportedProtocols.contains(BusProtocol.ethernet)) {
            results.add(CompatibilityResult(
              severity: WarningSeverity.error,
              title: '${instrument.brand} ${instrument.name} — No Ethernet',
              message: 'Vehicle has Automotive Ethernet but ${instrument.name} cannot capture it.',
              instrumentId: instrument.id,
              relatedProtocol: BusProtocol.ethernet,
              recommendation: 'Add VN5610 or GL4000 for Ethernet capture.',
            ));
          }
        }
      }
    }

    // ── 2. Check total CAN channel count ──
    int totalCANChannels = 0;
    for (final instrument in selectedInstruments) {
      if (instrument.category == InstrumentCategory.software) continue;
      for (final entry in instrument.channelCount.entries) {
        if (entry.key == BusProtocol.can2A ||
            entry.key == BusProtocol.can2B ||
            entry.key == BusProtocol.canFD) {
          totalCANChannels += entry.value;
        }
      }
    }

    if (totalCANChannels < requiredCANChannels) {
      results.add(CompatibilityResult(
        severity: WarningSeverity.warning,
        title: 'Insufficient CAN Channels',
        message: 'Vehicle has $requiredCANChannels CAN buses but selected instruments '
            'only provide $totalCANChannels CAN channels total.',
        recommendation: 'Add another CAN interface or upgrade to a logger with more channels.',
      ));
    } else {
      results.add(CompatibilityResult(
        severity: WarningSeverity.success,
        title: 'CAN Channel Count OK',
        message: '$totalCANChannels channels available for $requiredCANChannels vehicle CAN buses.',
      ));
    }

    // ── 3. Check for instruments with status issues ──
    for (final instrument in selectedInstruments) {
      if (instrument.status == InstrumentStatus.faulty) {
        results.add(CompatibilityResult(
          severity: WarningSeverity.error,
          title: '${instrument.brand} ${instrument.name} — FAULTY',
          message: 'This instrument is marked as faulty and should not be used.',
          instrumentId: instrument.id,
        ));
      } else if (instrument.status == InstrumentStatus.underCalibration) {
        results.add(CompatibilityResult(
          severity: WarningSeverity.warning,
          title: '${instrument.brand} ${instrument.name} — Under Calibration',
          message: 'This instrument is currently being calibrated and may not be available.',
          instrumentId: instrument.id,
        ));
      }
      if (instrument.quantity == 0) {
        results.add(CompatibilityResult(
          severity: WarningSeverity.warning,
          title: '${instrument.brand} ${instrument.name} — Not in Inventory',
          message: 'This instrument is not currently available in your inventory (qty: 0).',
          instrumentId: instrument.id,
          recommendation: 'Consider procuring this instrument.',
        ));
      }
    }

    // ── R2. Software needs a hardware interface to reach the bus ──
    final software =
        selectedInstruments.where((i) => i.requiresInterface).toList();
    final hasInterface =
        selectedInstruments.any((i) => i.isBusInterface);
    if (software.isNotEmpty && !hasInterface) {
      for (final s in software) {
        results.add(CompatibilityResult(
          severity: WarningSeverity.error,
          title: '${s.name} — No Hardware Interface',
          message:
              '${s.name} is software and cannot reach the vehicle bus on its own. '
              'It needs a hardware interface (Kvaser / Vector VN).',
          instrumentId: s.id,
          recommendation: 'Add a Kvaser or Vector VN interface to the setup.',
        ));
      }
    }

    // ── R8. Parallel backbone: every signal must reach Raptor CAL AND the GL2000 ──
    if (vehicleProtocols.isNotEmpty) {
      final backbone =
          selectedInstruments.where((i) => i.mustReceiveAllSignals).toList();
      final hasLogger =
          backbone.any((i) => i.category == InstrumentCategory.logger);
      final hasController =
          backbone.any((i) => i.category == InstrumentCategory.ecu);
      if (!hasLogger) {
        results.add(const CompatibilityResult(
          severity: WarningSeverity.warning,
          title: 'No Primary Logger (GL2000)',
          message:
              'The backbone rule says every signal is logged on the GL2000, '
              'but no data logger is selected — signals would not be recorded.',
          recommendation: 'Add the GL2000 data logger.',
        ));
      }
      if (!hasController) {
        results.add(const CompatibilityResult(
          severity: WarningSeverity.warning,
          title: 'No Raptor CAL Controller',
          message:
              'The backbone rule says every signal also feeds the Raptor CAL, '
              'but no controller is selected — real-time / calibration path is missing.',
          recommendation: 'Add the Raptor CAL (RCM80).',
        ));
      }
    }

    // ── R4. Slip angle / low-speed heading requires a dual-antenna GNSS ──
    if (requiresSlipAngle) {
      final hasDual = selectedInstruments.any((i) => i.dualAntenna);
      if (!hasDual) {
        results.add(const CompatibilityResult(
          severity: WarningSeverity.error,
          title: 'Slip Angle — No Dual-Antenna GNSS',
          message:
              'Slip angle and low/zero-speed true heading need a dual-antenna GNSS. '
              'A single-antenna receiver only derives heading from motion.',
          relatedProtocol: BusProtocol.gpsGnss,
          recommendation: 'Add the VBOX 3i Dual Antenna (with IMU).',
        ));
      }
    }

    // ── 4. Overall compatibility check ──
    if (results.every((r) => r.severity == WarningSeverity.success || r.severity == WarningSeverity.info)) {
      results.insert(0, const CompatibilityResult(
        severity: WarningSeverity.success,
        title: 'Setup Fully Compatible',
        message: 'All selected instruments are compatible with the vehicle protocols.',
      ));
    }

    return ValidationReport(results);
  }

  /// Recommend how to handle a CAN FD bus given a device that can't do FD.
  /// (No FD logger exists in inventory — the GL2000 is classic-CAN only.)
  static String _recommendFDUpgrade(Instrument instrument) {
    if (instrument.category == InstrumentCategory.logger) {
      return 'The GL2000 is classic-CAN only. Log the CAN FD bus via the Raptor CAL '
          '(FD-capable) or CANoe/CANape with an FD-capable interface instead.';
    }
    if (instrument.category == InstrumentCategory.interfaceDevice) {
      return 'This interface is classic-CAN only. Use an FD-capable interface '
          '(e.g. Kvaser U-series / Vector VN16xx) for the CAN FD bus.';
    }
    return 'Route the CAN FD bus through an FD-capable device '
        '(Raptor CAL, or CANoe/CANape + FD interface).';
  }

  /// Quick check: does a single instrument support a given protocol?
  static bool instrumentSupportsProtocol(Instrument instrument, BusProtocol protocol) {
    if (protocol == BusProtocol.canFD) return instrument.supportsCAnFD;
    return instrument.supportedProtocols.contains(protocol);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PER-VEHICLE VALIDATION — the interactive planner engine
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validate a full per-vehicle setup. Unlike [validateSetup] (which reasons over
  /// a flat set of protocols), this evaluates each vehicle bus individually:
  ///  • R8 — every bus must reach both the logger (GL2000) and controller (Raptor CAL)
  ///  • R9 — a CAN FD bus cannot be logged by the classic-only GL2000
  ///  • R5 — CAN channel budget vs number of buses
  ///  • R2 — software needs a hardware interface
  ///  • R4 — slip angle needs a dual-antenna GNSS
  static ValidationReport validateVehicle({
    required VehicleProfile vehicle,
    required List<Instrument> selectedInstruments,
    bool requiresSlipAngle = false,
  }) {
    final results = <CompatibilityResult>[];

    final backbone =
        selectedInstruments.where((i) => i.mustReceiveAllSignals).toList();
    final loggers = backbone
        .where((i) => i.category == InstrumentCategory.logger)
        .toList();
    final controllers = backbone
        .where((i) => i.category == InstrumentCategory.ecu)
        .toList();
    final classicOnlyLoggers =
        loggers.where((l) => !l.supportsCAnFD).toList();

    // ── Per-bus: R8 reachability + R9 FD conflict ──
    for (final bus in vehicle.canBuses) {
      if (bus.isCanFD && classicOnlyLoggers.isNotEmpty) {
        for (final l in classicOnlyLoggers) {
          results.add(CompatibilityResult(
            severity: WarningSeverity.error,
            title: '${bus.name} — ${l.name} cannot log CAN FD',
            message:
                '${bus.name} is CAN FD, but ${l.name} is classic-CAN only. Under the '
                '"all signals to the logger" backbone rule this bus cannot reach it.',
            instrumentId: l.id,
            relatedProtocol: BusProtocol.canFD,
            recommendation:
                'Log this FD bus via the Raptor CAL, or CANoe/CANape + an FD interface.',
          ));
        }
      } else {
        results.add(CompatibilityResult(
          severity: WarningSeverity.success,
          title: '${bus.name} — OK',
          message: '${bus.name} (${bus.protocol.label}) reaches the backbone.',
        ));
      }
    }

    // ── R8: backbone presence ──
    if (loggers.isEmpty) {
      results.add(const CompatibilityResult(
        severity: WarningSeverity.warning,
        title: 'No Primary Logger (GL2000)',
        message: 'No data logger selected — signals would not be recorded.',
        recommendation: 'Add the GL2000 data logger.',
      ));
    }
    if (controllers.isEmpty) {
      results.add(const CompatibilityResult(
        severity: WarningSeverity.warning,
        title: 'No Raptor CAL Controller',
        message: 'No controller selected — real-time / calibration path is missing.',
        recommendation: 'Add the Raptor CAL (RCM80).',
      ));
    }

    // ── R5: CAN channel budget ──
    final busCount = vehicle.canBuses.length;
    final availableChannels = selectedInstruments
        .where((i) => i.mustReceiveAllSignals || i.isBusInterface)
        .fold<int>(0, (sum, i) => sum + i.canChannels);
    if (busCount > 0 && availableChannels < busCount) {
      results.add(CompatibilityResult(
        severity: WarningSeverity.warning,
        title: 'Insufficient CAN Channels',
        message: 'Vehicle has $busCount CAN bus(es) but the backbone provides only '
            '$availableChannels CAN channel(s).',
        recommendation: 'Add an interface or use a logger/controller with more channels.',
      ));
    } else if (busCount > 0) {
      results.add(CompatibilityResult(
        severity: WarningSeverity.success,
        title: 'CAN Channel Budget OK',
        message: '$availableChannels channel(s) available for $busCount bus(es).',
      ));
    }

    // ── R2: software needs a hardware interface ──
    final software =
        selectedInstruments.where((i) => i.requiresInterface).toList();
    final hasInterface = selectedInstruments.any((i) => i.isBusInterface);
    if (software.isNotEmpty && !hasInterface) {
      for (final s in software) {
        results.add(CompatibilityResult(
          severity: WarningSeverity.error,
          title: '${s.name} — No Hardware Interface',
          message: '${s.name} cannot reach the bus without a hardware interface.',
          instrumentId: s.id,
          recommendation: 'Add a Kvaser or Vector VN interface.',
        ));
      }
    }

    // ── R4: slip angle needs a dual-antenna GNSS ──
    if (requiresSlipAngle && !selectedInstruments.any((i) => i.dualAntenna)) {
      results.add(const CompatibilityResult(
        severity: WarningSeverity.error,
        title: 'Slip Angle — No Dual-Antenna GNSS',
        message:
            'Slip angle / low-speed heading needs a dual-antenna GNSS (single antenna '
            'only derives heading from motion).',
        relatedProtocol: BusProtocol.gpsGnss,
        recommendation: 'Add the VBOX 3i Dual Antenna (with IMU).',
      ));
    }

    return ValidationReport(results);
  }
}

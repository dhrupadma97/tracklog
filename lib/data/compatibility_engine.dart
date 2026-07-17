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

  /// Recommend an FD-capable replacement for a given instrument
  static String _recommendFDUpgrade(Instrument instrument) {
    if (instrument.category == InstrumentCategory.logger) {
      switch (instrument.id) {
        case 'gl1000':
        case 'gl2000':
          return 'Upgrade to Vector GL3000 (CAN FD + LIN) or GL4000 (full protocol).';
        default:
          return 'Use a CAN FD capable logger (GL3000+).';
      }
    }
    if (instrument.category == InstrumentCategory.interfaceDevice) {
      switch (instrument.id) {
        case 'vn1610':
          return 'Upgrade to Vector VN1630 (CAN FD + LIN) or VN5610 (CAN FD + Ethernet).';
        case 'kvaser_leaf_v2':
          return 'Upgrade to Kvaser U100 (CAN FD) or Vector VN1630.';
        default:
          return 'Use a CAN FD capable interface (VN1630+).';
      }
    }
    return 'Use an instrument that supports CAN FD.';
  }

  /// Quick check: does a single instrument support a given protocol?
  static bool instrumentSupportsProtocol(Instrument instrument, BusProtocol protocol) {
    if (protocol == BusProtocol.canFD) return instrument.supportsCAnFD;
    return instrument.supportedProtocols.contains(protocol);
  }
}

/// TrackLog — Minimal DBC parser (Phase 3)
/// Extracts messages (BO_) and their signals (SG_) from a Vector DBC file.
/// Enough for browsing what a bus carries — not a full DBC toolchain.

import 'dart:convert';

class DbcMessage {
  final int canId;
  final String name;
  final int dlc;
  final String transmitter;
  final List<String> signals;

  DbcMessage({
    required this.canId,
    required this.name,
    required this.dlc,
    required this.transmitter,
    required this.signals,
  });

  /// 29-bit extended IDs have the high bit set in DBC files.
  bool get isExtended => canId > 0x7FF && (canId & 0x80000000) != 0;

  String get idHex =>
      '0x${(canId & 0x1FFFFFFF).toRadixString(16).toUpperCase()}';
}

/// Parse a DBC file's messages + signal names.
/// `BO_ <id> <Name>: <dlc> <Transmitter>` followed by indented ` SG_ <name> ...`
List<DbcMessage> parseDbc(String content) {
  final messages = <DbcMessage>[];
  final boRe = RegExp(r'^BO_\s+(\d+)\s+([A-Za-z0-9_]+)\s*:\s*(\d+)\s+(\S+)');
  final sgRe = RegExp(r'^\s+SG_\s+([A-Za-z0-9_]+)');
  DbcMessage? current;

  for (final raw in const LineSplitter().convert(content)) {
    final bo = boRe.firstMatch(raw);
    if (bo != null) {
      current = DbcMessage(
        canId: int.tryParse(bo.group(1)!) ?? 0,
        name: bo.group(2)!,
        dlc: int.tryParse(bo.group(3)!) ?? 0,
        transmitter: bo.group(4)!,
        signals: [],
      );
      messages.add(current);
      continue;
    }
    final sg = sgRe.firstMatch(raw);
    if (sg != null && current != null) {
      current.signals.add(sg.group(1)!);
    } else if (raw.trim().isEmpty) {
      current = null; // blank line ends a message block
    }
  }
  return messages;
}

/// Total signal count across parsed messages.
int dbcSignalCount(List<DbcMessage> messages) =>
    messages.fold(0, (sum, m) => sum + m.signals.length);

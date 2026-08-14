import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pulls the text layer out of a PDF in pure Dart, so it works on Flutter web.
///
/// This is deliberately not a full PDF parser. It walks the raw bytes for
/// `stream … endstream` pairs, inflates the FlateDecode ones, and reads the
/// text-showing operators out of the page content. That covers the digitally
/// generated invoices NATRAX sends (Tally e-invoices), which is all we need.
///
/// A scanned invoice has no text layer at all — [extractText] returns an empty
/// string for those, and the caller is expected to say so rather than guess.
class PdfTextExtractor {
  const PdfTextExtractor._();

  /// Latin-1 keeps every byte round-trippable, which matters because we are
  /// treating binary PDF content as a searchable string.
  static const _latin1 = Latin1Codec(allowInvalid: true);

  /// Returns the document's visible text, one logical line per text-positioning
  /// operator. Empty when the PDF carries no text layer.
  static String extractText(Uint8List bytes) {
    final raw = _latin1.decode(bytes);
    final buffer = StringBuffer();

    // Composite (Type0) fonts encode text as glyph ids, so the raw bytes are
    // meaningless without the font's /ToUnicode map. Tally invoices carry no
    // such map and their literals are already readable; others (MOICARS) are
    // pure gibberish until decoded. Build the maps up front when present.
    final fontMaps = _toUnicodeMaps(bytes, raw);

    for (final stream in _inflatedStreams(bytes, raw)) {
      // Only content streams carry text operators; skip fonts, images, metadata.
      if (!stream.contains('Tj') && !stream.contains('TJ')) continue;
      buffer.writeln(_readTextOperators(stream, fontMaps));
    }

    return buffer
        .toString()
        .split('\n')
        .map(_clean)
        .where((l) => l.isNotEmpty)
        .join('\n');
  }

  /// Glyph-code to text, keyed by the font resource name used in the content
  /// stream (`/F1 Tf`). Empty when the document has no /ToUnicode maps.
  static Map<String, Map<int, String>> _toUnicodeMaps(
      Uint8List bytes, String raw) {
    if (!raw.contains('/ToUnicode')) return const {};

    // Object number -> byte offset of its body, so a /ToUnicode reference can
    // be followed to the CMap stream it points at.
    final objectAt = <int, int>{};
    for (final m
        in RegExp(r'(\d+)\s+\d+\s+obj').allMatches(raw)) {
      final id = int.tryParse(m.group(1)!);
      if (id != null) objectAt[id] = m.end;
    }

    // Font resource name -> object number, from the page /Font dictionaries.
    final fontObject = <String, int>{};
    for (final res in RegExp(r'/Font\s*<<(.*?)>>', dotAll: true)
        .allMatches(raw)) {
      for (final f in RegExp(r'/([A-Za-z0-9+._-]+)\s+(\d+)\s+\d+\s+R')
          .allMatches(res.group(1)!)) {
        fontObject[f.group(1)!] = int.parse(f.group(2)!);
      }
    }

    final maps = <String, Map<int, String>>{};
    for (final entry in fontObject.entries) {
      final start = objectAt[entry.value];
      if (start == null) continue;

      // The font object is small; look only at its own body.
      final end = raw.indexOf('endobj', start);
      final body = raw.substring(start, end < 0 ? raw.length : end);
      final ref = RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(body);
      if (ref == null) continue;

      final cmapStart = objectAt[int.parse(ref.group(1)!)];
      if (cmapStart == null) continue;
      final cmap = _inflateAt(bytes, raw, cmapStart);
      if (cmap == null) continue;

      final parsed = _parseCMap(cmap);
      if (parsed.isNotEmpty) maps[entry.key] = parsed;
    }

    // Resources are not always reachable by name — they can sit behind an
    // indirect /Resources reference, or in an object layout this deliberately
    // simple reader does not follow. Rather than fall back to raw bytes, which
    // decode to gibberish for a subset font, merge every CMap in the document
    // as a last resort. Subset fonts in a single invoice rarely disagree about
    // a code, and a near-right reading beats a certainly-wrong one.
    final merged = <int, String>{};
    for (final id in objectAt.keys) {
      final start = objectAt[id]!;
      final end = raw.indexOf('endobj', start);
      final body = raw.substring(start, end < 0 ? raw.length : end);
      if (!body.contains('/ToUnicode')) continue;
      final ref = RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(body);
      final target = ref == null ? null : objectAt[int.parse(ref.group(1)!)];
      if (target == null) continue;
      final cmap = _inflateAt(bytes, raw, target);
      if (cmap == null) continue;
      for (final e in _parseCMap(cmap).entries) {
        merged.putIfAbsent(e.key, () => e.value);
      }
    }
    if (merged.isNotEmpty) maps['*'] = merged;

    return maps;
  }

  /// Inflates the single stream that begins after [from].
  static String? _inflateAt(Uint8List bytes, String raw, int from) {
    final s = raw.indexOf('stream', from);
    if (s < 0) return null;
    var dataStart = s + 'stream'.length;
    if (dataStart < raw.length && raw.codeUnitAt(dataStart) == 0x0D) dataStart++;
    if (dataStart < raw.length && raw.codeUnitAt(dataStart) == 0x0A) dataStart++;
    final e = raw.indexOf('endstream', dataStart);
    if (e < 0 || e - dataStart <= 2) return null;

    // Not every stream is compressed — CMaps are routinely stored plain, with
    // a dictionary carrying only /Length. Inflate returns an empty result for
    // those rather than throwing, so an exception handler alone would silently
    // yield nothing; the emptiness itself has to be treated as the signal.
    try {
      final out = Inflate(bytes.sublist(dataStart + 2, e)).getBytes();
      if (out.isNotEmpty) return _latin1.decode(Uint8List.fromList(out));
    } catch (_) {
      // fall through to reading it as-is
    }
    return raw.substring(dataStart, e);
  }

  /// Reads `beginbfchar` / `beginbfrange` sections into a code -> text map.
  static Map<int, String> _parseCMap(String cmap) {
    final map = <int, String>{};

    for (final block in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true)
        .allMatches(cmap)) {
      for (final pair in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(block.group(1)!)) {
        final code = int.tryParse(pair.group(1)!, radix: 16);
        if (code == null) continue;
        map[code] = _utf16BeHex(pair.group(2)!);
      }
    }

    for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true)
        .allMatches(cmap)) {
      final body = block.group(1)!;

      // <lo> <hi> <dstStart>  — consecutive codes map to consecutive scalars.
      for (final r in RegExp(
              r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(body)) {
        final lo = int.tryParse(r.group(1)!, radix: 16);
        final hi = int.tryParse(r.group(2)!, radix: 16);
        final dst = int.tryParse(r.group(3)!, radix: 16);
        if (lo == null || hi == null || dst == null) continue;
        if (hi - lo > 65535) continue; // malformed; do not blow up
        for (var c = lo; c <= hi; c++) {
          map[c] = String.fromCharCode(dst + (c - lo));
        }
      }

      // <lo> <hi> [<d1> <d2> …] — each code maps to its own string.
      for (final r in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]',
              dotAll: true)
          .allMatches(body)) {
        final lo = int.tryParse(r.group(1)!, radix: 16);
        if (lo == null) continue;
        var i = 0;
        for (final d
            in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(r.group(3)!)) {
          map[lo + i] = _utf16BeHex(d.group(1)!);
          i++;
        }
      }
    }
    return map;
  }

  /// CMap destinations are UTF-16BE hex, sometimes several units long.
  static String _utf16BeHex(String hex) {
    final units = <int>[];
    for (var i = 0; i + 4 <= hex.length; i += 4) {
      final u = int.tryParse(hex.substring(i, i + 4), radix: 16);
      if (u != null) units.add(u);
    }
    if (units.isEmpty) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? '' : String.fromCharCode(v);
    }
    return String.fromCharCodes(units);
  }

  /// Custom-encoded PDF fonts leave stray control bytes in the decoded text —
  /// the NATRAX invoices carry a 0x02 between "Total" and its figure, which is
  /// enough to stop a field pattern anchoring. Fold every control character and
  /// exotic space into a plain space, then collapse runs.
  static String _clean(String line) {
    final out = StringBuffer();
    for (final unit in line.codeUnits) {
      final isControl = unit < 0x20 || unit == 0x7F;
      final isExoticSpace = unit == 0xA0 || // no-break space
          (unit >= 0x2000 && unit <= 0x200D) || // en quad … zero-width joiner
          unit == 0x202F ||
          unit == 0x205F ||
          unit == 0x3000 ||
          unit == 0xFEFF;
      out.writeCharCode(isControl || isExoticSpace ? 0x20 : unit);
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Inflates every deflate-compressed stream in the document.
  static Iterable<String> _inflatedStreams(Uint8List bytes, String raw) sync* {
    var cursor = 0;
    while (true) {
      final start = raw.indexOf('stream', cursor);
      if (start < 0) break;

      var dataStart = start + 'stream'.length;
      // The keyword is followed by CRLF or LF before the payload begins.
      if (dataStart < raw.length && raw.codeUnitAt(dataStart) == 0x0D) {
        dataStart++;
      }
      if (dataStart < raw.length && raw.codeUnitAt(dataStart) == 0x0A) {
        dataStart++;
      }

      final end = raw.indexOf('endstream', dataStart);
      if (end < 0) break;
      cursor = end + 'endstream'.length;

      final length = end - dataStart;
      // Two bytes is not even a zlib header, let alone a payload.
      if (length <= 2) continue;

      try {
        // Skip the 2-byte zlib header and inflate the raw deflate payload.
        final payload = bytes.sublist(dataStart + 2, dataStart + length);
        final out = Inflate(payload).getBytes();
        if (out.isEmpty) {
          // Uncompressed stream — read it as it stands.
          yield raw.substring(dataStart, dataStart + length);
          continue;
        }
        yield _latin1.decode(Uint8List.fromList(out));
      } catch (_) {
        // Not a deflate stream (image data, already-plain content, a stream
        // whose /Length disagrees with the delimiters). Nothing to read.
        continue;
      }
    }
  }

  /// Reads `(literal) Tj` and `[(a) -250 (b)] TJ` sequences out of a content
  /// stream, treating the positioning operators as line breaks.
  static String _readTextOperators(
      String content, Map<String, Map<int, String>> fontMaps) {
    final lines = <String>[];
    final current = StringBuffer();
    Map<int, String>? activeMap;

    // A parenthesised literal, a hex string, a font selection, or one of the
    // operators that ends a run of text.
    final token = RegExp(
        r'\((?:\\.|[^\\()])*\)|<[0-9A-Fa-f\s]*>|/([A-Za-z0-9+._-]+)\s+[\d.]+\s+Tf'
        r'|Td|TD|T\*|ET|Tj|TJ');

    for (final match in token.allMatches(content)) {
      final value = match.group(0)!;

      if (value.endsWith('Tf')) {
        // Switch decoders with the font; a document mixes several. Fall back
        // to the merged map when this font could not be resolved by name.
        activeMap = fontMaps[match.group(1)] ?? fontMaps['*'];
        continue;
      }

      if (value.startsWith('(')) {
        final literal = _unescape(value.substring(1, value.length - 1));
        current.write(
            activeMap == null ? literal : _decode(literal, activeMap));
      } else if (value.startsWith('<')) {
        current.write(_decodeHex(value, activeMap));
      } else if (value == 'Td' ||
          value == 'TD' ||
          value == 'T*' ||
          value == 'ET') {
        if (current.isNotEmpty) {
          lines.add(current.toString());
          current.clear();
        }
      }
    }
    if (current.isNotEmpty) lines.add(current.toString());

    return lines.join('\n');
  }

  /// Composite fonts use two-byte glyph codes, so the literal's bytes are read
  /// in pairs and looked up rather than taken as characters.
  static String _decode(String literal, Map<int, String> map) {
    final units = literal.codeUnits;

    // Composite fonts use two-byte glyph codes; simple subset fonts use one.
    // Which applies is not knowable from the literal alone, so decode both
    // ways and keep whichever the map actually recognised.
    final wide = StringBuffer();
    var wideHits = 0;
    for (var i = 0; i + 1 < units.length; i += 2) {
      final v = map[(units[i] << 8) | units[i + 1]];
      if (v != null) wideHits++;
      wide.write(v ?? '');
    }

    final narrow = StringBuffer();
    var narrowHits = 0;
    for (final u in units) {
      final v = map[u];
      if (v != null) narrowHits++;
      narrow.write(v ?? '');
    }

    if (narrowHits == 0 && wideHits == 0) return literal;
    return narrowHits >= wideHits ? narrow.toString() : wide.toString();
  }

  static String _decodeHex(String token, Map<int, String>? map) {
    final hex = token.substring(1, token.length - 1).replaceAll(RegExp(r'\s'), '');
    if (hex.isEmpty) return '';
    final out = StringBuffer();
    if (map == null) {
      // No CMap: hex pairs are plain bytes.
      for (var i = 0; i + 2 <= hex.length; i += 2) {
        final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
        if (b != null) out.writeCharCode(b);
      }
      return out.toString();
    }
    for (var i = 0; i + 4 <= hex.length; i += 4) {
      final code = int.tryParse(hex.substring(i, i + 4), radix: 16);
      if (code != null) out.write(map[code] ?? '');
    }
    return out.toString();
  }

  /// Resolves the PDF string escapes that matter for invoice text.
  static String _unescape(String literal) {
    final out = StringBuffer();
    for (var i = 0; i < literal.length; i++) {
      final ch = literal[i];
      if (ch != r'\' || i + 1 >= literal.length) {
        out.write(ch);
        continue;
      }
      final next = literal[i + 1];
      i++;
      switch (next) {
        case 'n':
          out.write('\n');
        case 'r':
          out.write('\r');
        case 't':
          out.write('\t');
        case 'b':
        case 'f':
          out.write(' ');
        case '(':
          out.write('(');
        case ')':
          out.write(')');
        case r'\':
          out.write(r'\');
        default:
          // \ddd octal character code
          if (RegExp(r'[0-7]').hasMatch(next)) {
            final octal = StringBuffer(next);
            while (octal.length < 3 &&
                i + 1 < literal.length &&
                RegExp(r'[0-7]').hasMatch(literal[i + 1])) {
              octal.write(literal[i + 1]);
              i++;
            }
            out.writeCharCode(int.parse(octal.toString(), radix: 8));
          } else {
            out.write(next);
          }
      }
    }
    return out.toString();
  }
}

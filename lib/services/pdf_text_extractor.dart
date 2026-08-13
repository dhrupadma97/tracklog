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

    for (final stream in _inflatedStreams(bytes, raw)) {
      // Only content streams carry text operators; skip fonts, images, metadata.
      if (!stream.contains('Tj') && !stream.contains('TJ')) continue;
      buffer.writeln(_readTextOperators(stream));
    }

    return buffer
        .toString()
        .split('\n')
        .map(_clean)
        .where((l) => l.isNotEmpty)
        .join('\n');
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
        if (out.isEmpty) continue;
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
  static String _readTextOperators(String content) {
    final lines = <String>[];
    final current = StringBuffer();

    // Either a parenthesised literal (honouring backslash escapes) or one of
    // the operators that ends a run of text.
    final token = RegExp(r'\((?:\\.|[^\\()])*\)|Td|TD|T\*|ET|Tj|TJ');

    for (final match in token.allMatches(content)) {
      final value = match.group(0)!;
      if (value.startsWith('(')) {
        current.write(_unescape(value.substring(1, value.length - 1)));
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

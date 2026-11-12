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
  /// Largest PDF this will try to read.
  ///
  /// This was 2 MB, on the theory that big files froze the app. They did not:
  /// the freeze came from handing a stream that was never compressed to the
  /// inflater — an embedded font in INV/26-27/205, a 53 KB file, took 102
  /// seconds and ran out of memory. Size was a coincidence. The limit let that
  /// file through and turned away INV/26-27/802 (2.7 MB, mostly a background
  /// image), which reads in about a second once images and fonts are skipped
  /// unread — see [_useFor].
  ///
  /// A ceiling stays, because extraction is synchronous and Flutter web has no
  /// isolates to move it to, but it is set well above any e-invoice NATRAX or
  /// MOICARS send. Above it the text layer is not read and the caller takes
  /// the figures by hand, as before.
  static const int maxBytes = 25 * 1024 * 1024;

  static String extractText(Uint8List bytes) => extract(bytes).text;

  /// The text layer twice over, from one pass: [text] one logical line per
  /// positioning operator, exactly as [extractText] has always returned it,
  /// and [rows] — the same words regrouped by where they sit on the page, top
  /// to bottom and left to right, one row per visual line.
  ///
  /// The rows exist because an invoice line is a ROW, and the text is not.
  /// Tally positions every cell separately, so "Braking Track Testing - WET",
  /// "998346", "28 Hrs." and "5,88,000.00" each arrive on their own line, and
  /// a reader expecting a line item on one line found none — on every real
  /// invoice, while the hand-typed test text passed. Grouping by position
  /// puts the cells of a row back together. [text] is left alone because the
  /// header fields are read from it and are known to work.
  static ({String text, List<String> rows}) extract(Uint8List bytes) {
    if (bytes.length > maxBytes) return (text: '', rows: const <String>[]);
    final raw = _latin1.decode(bytes);
    final buffer = StringBuffer();
    final rows = <String>[];

    // Composite (Type0) fonts encode text as glyph ids, so the raw bytes are
    // meaningless without the font's /ToUnicode map. Tally invoices carry no
    // such map and their literals are already readable; others (MOICARS) are
    // pure gibberish until decoded. Build the maps up front when present.
    final fontMaps = _toUnicodeMaps(bytes, raw);

    // Fragments are gathered per PAGE, not per stream: a page drawn from
    // several streams has its table rows spread across them. Each page keeps
    // its own coordinates, so two pages' rows at one height never merge.
    final pageOf = _pageOfStream(raw);
    final byPage = <String, List<_Fragment>>{};
    final pageOrder = <String>[];

    for (final s in _streams(bytes, raw)) {
      final stream = s.content;
      // Only content streams carry text operators; skip fonts, images, metadata.
      if (!stream.contains('Tj') && !stream.contains('TJ')) continue;
      buffer.writeln(_readTextOperators(stream, fontMaps));

      final page = pageOf.isEmpty
          ? 'page:0'
          : (pageOf[s.obj] != null ? 'page:${pageOf[s.obj]}' : 'obj:${s.obj}');
      if (!byPage.containsKey(page)) pageOrder.add(page);
      (byPage[page] ??= []).addAll(_readPositioned(stream, fontMaps));
    }
    for (final p in pageOrder) {
      rows.addAll(_rowsOf(byPage[p]!));
    }

    final text = buffer
        .toString()
        .split('\n')
        .map(_clean)
        .where((l) => l.isNotEmpty)
        .join('\n');
    return (
      text: text,
      rows: rows.map(_clean).where((r) => r.isNotEmpty).toList(),
    );
  }

  /// Every piece of shown text in a content stream, with where it lands.
  ///
  /// A small interpreter for the operators that move the pen: the text matrix
  /// (Tm, Td, TD, T*, TL, ' and ") and the graphics matrix around it (cm, q,
  /// Q). It does not know glyph widths, so it records where each run STARTS;
  /// consecutive runs with no move between them are joined, since they are
  /// written one after the other.
  static List<_Fragment> _readPositioned(
      String content, Map<String, Map<int, String>> fontMaps) {
    final token = RegExp(
      r'\((?:\\.|[^\\()])*\)' // literal string
      r'|<[0-9A-Fa-f\s]*>' // hex string
      r'|/[^\s/\[\]()<>{}%]+' // name
      r'|[+-]?(?:\d+\.?\d*|\.\d+)' // number
      r'|\[|\]' // array brackets
      "|[A-Za-z'\"*]+", // operator
    );

    List<double> identity() => [1, 0, 0, 1, 0, 0];
    List<double> mul(List<double> m, List<double> n) => [
          m[0] * n[0] + m[1] * n[2],
          m[0] * n[1] + m[1] * n[3],
          m[2] * n[0] + m[3] * n[2],
          m[2] * n[1] + m[3] * n[3],
          m[4] * n[0] + m[5] * n[2] + n[4],
          m[4] * n[1] + m[5] * n[3] + n[5],
        ];

    var ctm = identity();
    final saved = <List<double>>[];
    var tm = identity();
    var tlm = identity();
    var leading = 0.0;
    Map<int, String>? activeMap;
    final operands = <Object>[];
    List<Object>? array;
    final out = <_Fragment>[];
    var moved = true;

    double num0(int fromEnd) {
      final i = operands.length - fromEnd;
      if (i < 0) return 0;
      final v = operands[i];
      return v is double ? v : 0;
    }

    void moveText(double tx, double ty) {
      tlm = mul([1, 0, 0, 1, tx, ty], tlm);
      tm = List.of(tlm);
      moved = true;
    }

    String decodeString(String tok) {
      if (tok.startsWith('(')) {
        final literal = _unescape(tok.substring(1, tok.length - 1));
        final map = activeMap;
        return map == null ? literal : _decode(literal, map);
      }
      return _decodeHex(tok, activeMap);
    }

    void show(String text) {
      if (text.isEmpty) return;
      final p = mul(tm, ctm);
      if (!moved && out.isNotEmpty) {
        out.last.text.write(text);
      } else {
        out.add(_Fragment(p[4], p[5])..text.write(text));
      }
      moved = false;
    }

    for (final m in token.allMatches(content)) {
      final t = m.group(0)!;
      final c = t.codeUnitAt(0);

      if (t == '[') {
        array = <Object>[];
        continue;
      }
      if (t == ']') {
        if (array != null) operands.add(array);
        array = null;
        continue;
      }
      // Strings and numbers are operands, inside an array or out of one.
      if (c == 0x28 /* ( */ || c == 0x3C /* < */) {
        (array ?? operands).add(t);
        continue;
      }
      if ((c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2D || c == 0x2E) {
        (array ?? operands).add(double.tryParse(t) ?? 0.0);
        continue;
      }
      if (c == 0x2F /* / */) {
        operands.add(t);
        continue;
      }

      switch (t) {
        case 'q':
          saved.add(List.of(ctm));
        case 'Q':
          if (saved.isNotEmpty) ctm = saved.removeLast();
        case 'cm':
          ctm = mul([num0(6), num0(5), num0(4), num0(3), num0(2), num0(1)], ctm);
        case 'BT':
          tm = identity();
          tlm = identity();
          moved = true;
        case 'Tm':
          tlm = [num0(6), num0(5), num0(4), num0(3), num0(2), num0(1)];
          tm = List.of(tlm);
          moved = true;
        case 'Td':
          moveText(num0(2), num0(1));
        case 'TD':
          leading = -num0(1);
          moveText(num0(2), num0(1));
        case 'TL':
          leading = num0(1);
        case 'T*':
          moveText(0, -leading);
        case 'Tf':
          final name = operands.length >= 2 ? operands[operands.length - 2] : null;
          if (name is String && name.startsWith('/')) {
            activeMap = fontMaps[name.substring(1)] ?? fontMaps['*'];
          }
        case 'Tj':
          final s = operands.isEmpty ? null : operands.last;
          if (s is String) show(decodeString(s));
        case "'":
          moveText(0, -leading);
          final s = operands.isEmpty ? null : operands.last;
          if (s is String) show(decodeString(s));
        case '"':
          moveText(0, -leading);
          final s = operands.isEmpty ? null : operands.last;
          if (s is String) show(decodeString(s));
        case 'TJ':
          final arr = operands.isEmpty ? null : operands.last;
          if (arr is List<Object>) {
            final sb = StringBuffer();
            for (final part in arr) {
              if (part is String) {
                sb.write(decodeString(part));
              } else if (part is double && part <= -200) {
                // A kern this wide is a word gap, not letter spacing.
                sb.write(' ');
              }
            }
            show(sb.toString());
          }
      }
      operands.clear();
    }
    return out;
  }

  /// The object number of the stream whose `stream` keyword is at [keyword],
  /// read from its `N G obj` header. Null when the header cannot be found.
  static int? _objectNumber(String raw, int keyword) {
    final obj = raw.lastIndexOf('obj', keyword);
    if (obj < 0) return null;
    final head = raw.substring((obj - 24).clamp(0, obj), obj);
    final m = RegExp(r'(\d+)\s+\d+\s+$').firstMatch(head);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Which page draws each content stream, from the pages' /Contents.
  ///
  /// A page's content is often split across several streams — INV/26-27/205
  /// and INV/26-27/802 each draw one page from eight. Grouping text by stream
  /// rather than by page split every table row whose cells landed in
  /// different streams, so "High Speed Track ... 75,000.00" and its own
  /// "998346 3 Hrs. 25,000.00" came out as two rows and neither was a line.
  ///
  /// Pages are numbered in the order they appear in the file. A document whose
  /// page objects sit inside a compressed object stream has none visible here;
  /// the caller then treats every content stream as one page, which is right
  /// for the one-page invoices this reads.
  static Map<int, int> _pageOfStream(String raw) {
    final out = <int, int>{};
    var page = 0;
    final contents = RegExp(
        r'/Contents\s*(?:\[([^\]]*)\]|(\d+)\s+\d+\s+R)');
    final ref = RegExp(r'(\d+)\s+\d+\s+R');
    for (final m in contents.allMatches(raw)) {
      final refs = m.group(1) != null
          ? ref.allMatches(m.group(1)!).map((r) => int.parse(r.group(1)!))
          : [int.parse(m.group(2)!)];
      for (final id in refs) {
        out.putIfAbsent(id, () => page);
      }
      page++;
    }
    return out;
  }

  /// Every positioned run in the document, per content stream — for tests and
  /// for tuning the row grouping against real layouts.
  static List<List<({double x, double y, String text})>> fragments(
      Uint8List bytes) {
    if (bytes.length > maxBytes) return const [];
    final raw = _latin1.decode(bytes);
    final fontMaps = _toUnicodeMaps(bytes, raw);
    final out = <List<({double x, double y, String text})>>[];
    for (final stream in _inflatedStreams(bytes, raw)) {
      if (!stream.contains('Tj') && !stream.contains('TJ')) continue;
      out.add([
        for (final f in _readPositioned(stream, fontMaps))
          (x: f.x, y: f.y, text: f.text.toString()),
      ]);
    }
    return out;
  }

  /// Fragments regrouped into visual rows, top of the page first.
  ///
  /// Two fragments share a row when their baselines are within a couple of
  /// points; within a row they run left to right. The tolerance is tight on
  /// purpose — an address block beside a header field must not fuse into it.
  static List<String> _rowsOf(List<_Fragment> frags) {
    if (frags.isEmpty) return const [];
    final sorted = List.of(frags)
      ..sort((a, b) {
        final dy = b.y.compareTo(a.y);
        return dy != 0 ? dy : a.x.compareTo(b.x);
      });
    const tolerance = 2.0;
    final rows = <List<_Fragment>>[];
    for (final f in sorted) {
      if (rows.isNotEmpty && (rows.last.first.y - f.y).abs() <= tolerance) {
        rows.last.add(f);
      } else {
        rows.add([f]);
      }
    }
    return rows.map((r) {
      r.sort((a, b) => a.x.compareTo(b.x));
      return _withoutTilePieces(r.map((f) => f.text.toString().trim()))
          .join(' ');
    }).toList();
  }

  /// One row's runs with the clipping-tile copies taken out.
  ///
  /// Some invoice PDFs (388, 467, 802) draw a background pattern as thousands
  /// of clip tiles and redraw the page's text once per tile, each time showing
  /// only the characters inside it. On screen it looks normal; to a reader it
  /// is "Braking Track Testing (GVW < 3.5T) - WET .5T) 5T 5T) - WE W WE 998 998"
  /// — the real cell followed by dozens of its own fragments. Every such piece
  /// is a substring of the full run it was cut from, so a run contained in a
  /// longer run of the same row is dropped, as is a second identical run.
  ///
  /// What that also drops is harmless by construction: a per-unit column
  /// ("Hrs.") inside its quantity ("28 Hrs."), a serial "1" inside "1,800.00".
  /// A row's description, quantity and final amount are never substrings of
  /// anything longer on the same row.
  ///
  /// Except a bare unit — "Hrs.", "Nos", "Unt", "days". That is the "per"
  /// column, a cell in its own right, and its position matters: a rate is
  /// followed by its unit while an amount ends the row, which is how a row
  /// whose amount never reached the text layer is told apart from one whose
  /// amount is the rate. Dropping it as a piece of "34 Hrs." turned 205's
  /// 7,14,000 wet line back into a 21,000 one.
  static final _unitCell =
      RegExp(r'^(?:Hrs?\.?|Nos?\.?|Unt\.?|Units?|Days?)$', caseSensitive: false);

  static List<String> _withoutTilePieces(Iterable<String> runs) {
    final texts = runs.where((t) => t.isNotEmpty).toList();
    final kept = <String>[];
    for (var i = 0; i < texts.length; i++) {
      final t = texts[i];
      if (_unitCell.hasMatch(t)) {
        kept.add(t);
        continue;
      }
      var inside = false;
      for (var j = 0; j < texts.length && !inside; j++) {
        if (j != i && texts[j].length > t.length && texts[j].contains(t)) {
          inside = true;
        }
      }
      if (inside || kept.contains(t)) continue;
      kept.add(t);
    }
    return kept;
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

    // Same rule as _inflatedStreams: decide from the dictionary first. A
    // plain CMap handed to the inflater can hang it the same way the plain
    // font in INV/26-27/205 did.
    final use = _useFor(raw.substring(from, s));
    if (use == _StreamUse.skip) return null;
    if (use == _StreamUse.plain) return raw.substring(dataStart, e);

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

  /// The dictionary of the stream whose `stream` keyword sits at [keyword].
  ///
  /// Read back to the object header, which is where every stream dictionary
  /// in a PDF begins. Left exactly as written: squeezing the whitespace out
  /// turns `/Length 1753` into `/Length1753`, which then looks like the
  /// `/Length1` key of an embedded font — and every content stream whose
  /// length began with 1, 2 or 3 was skipped as a font.
  static String _dictBefore(String raw, int keyword) {
    final obj = raw.lastIndexOf('obj', keyword);
    final from = obj < 0 ? (keyword - 600).clamp(0, keyword) : obj;
    return raw.substring(from, keyword);
  }

  static final _image = RegExp(r'/Subtype\s*/Image\b');
  static final _fontFile =
      RegExp(r'/Subtype\s*/(?:Type1C|CIDFontType0C|OpenType)\b');
  // A PDF name ends at whitespace or a delimiter, so `/Length1 5000` (a font
  // program's clear-text length) can never be confused with `/Length 1753`
  // once the original spacing is kept. The lookahead keeps `/Length10` from
  // matching, for completeness.
  static final _fontProgram = RegExp(r'/Length[123](?![0-9A-Za-z])');
  static final _notText =
      RegExp(r'/Type\s*/(?:Metadata|XRef|EmbeddedFile|ObjStm)\b');

  /// What to do with a stream, decided from its dictionary BEFORE touching it.
  ///
  /// Every stream used to be handed to the inflater, and only afterwards
  /// checked for text. That is not merely slow. An embedded font stored
  /// uncompressed — `<</Length 612/Subtype/Type1C>>` in INV/26-27/205, a
  /// 53 KB file — is not deflate data at all, and the inflater span on it
  /// for 102 seconds before running out of memory. In the browser that is a
  /// frozen tab. The 2 MB size limit that was added for "big files" never
  /// touched the cause: it waved this file through and blocked big ones,
  /// like INV/26-27/802, that would have read in a second.
  ///
  /// Fonts, images, metadata and cross-reference streams never carry text
  /// operators, so they are skipped unread. Only a stream that declares
  /// /FlateDecode is inflated; one with no /Filter is read as it stands; any
  /// other filter is one this reader cannot decode, so it is skipped too.
  static _StreamUse _useFor(String dict) {
    if (_image.hasMatch(dict) ||
        _fontFile.hasMatch(dict) ||
        _fontProgram.hasMatch(dict) ||
        _notText.hasMatch(dict)) {
      return _StreamUse.skip;
    }
    if (dict.contains('/FlateDecode')) return _StreamUse.inflate;
    if (dict.contains('/Filter')) return _StreamUse.skip;
    return _StreamUse.plain;
  }

  /// Inflates every deflate-compressed stream in the document.
  static Iterable<String> _inflatedStreams(Uint8List bytes, String raw) =>
      _streams(bytes, raw).map((s) => s.content);

  /// Every readable stream with the object number it belongs to, so a
  /// content stream can be tied back to the page that draws it.
  static Iterable<({int? obj, String content})> _streams(
      Uint8List bytes, String raw) sync* {
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

      final use = _useFor(_dictBefore(raw, start));
      if (use == _StreamUse.skip) continue;
      final obj = _objectNumber(raw, start);
      if (use == _StreamUse.plain) {
        yield (obj: obj, content: raw.substring(dataStart, dataStart + length));
        continue;
      }

      try {
        // Skip the 2-byte zlib header and inflate the raw deflate payload.
        final payload = bytes.sublist(dataStart + 2, dataStart + length);
        final out = Inflate(payload).getBytes();
        if (out.isEmpty) {
          // Uncompressed stream — read it as it stands.
          yield (
            obj: obj,
            content: raw.substring(dataStart, dataStart + length),
          );
          continue;
        }
        yield (obj: obj, content: _latin1.decode(Uint8List.fromList(out)));
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

/// What [PdfTextExtractor] does with one stream, decided before reading it.
enum _StreamUse { inflate, plain, skip }

/// One run of shown text and where its first glyph sits on the page.
class _Fragment {
  final double x;
  final double y;
  final StringBuffer text = StringBuffer();
  _Fragment(this.x, this.y);
}

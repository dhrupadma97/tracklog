import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/pdf_text_extractor.dart';

/// A minimal PDF, assembled in memory, carrying exactly the shapes that broke
/// the reader on real invoices — so the fixes are pinned without shipping
/// those invoices into the repo.
Uint8List _pdf(List<({int id, String dict, List<int> body})> objects,
    {required String page}) {
  const latin1 = Latin1Codec();
  final out = BytesBuilder()..add(latin1.encode('%PDF-1.4\n'));
  out.add(latin1.encode('1 0 obj\n$page\nendobj\n'));
  for (final o in objects) {
    out.add(latin1.encode('${o.id} 0 obj\n${o.dict}\nstream\n'));
    out.add(o.body);
    out.add(latin1.encode('\nendstream\nendobj\n'));
  }
  out.add(latin1.encode('%%EOF\n'));
  return out.toBytes();
}

List<int> _flate(String s) => ZLibEncoder().encode(latin1.encode(s));

void main() {
  group('streams are judged before they are read', () {
    test('an uncompressed embedded font is skipped, not inflated', () {
      // INV/26-27/205 carries <</Length 612/Subtype/Type1C>> with no filter.
      // Handed to the inflater it span for 102 seconds and ran out of memory;
      // in the browser, a frozen tab. It is now never touched.
      final font = List<int>.generate(612, (i) => (i * 37 + 11) % 256);
      final content = _flate('BT 1 0 0 1 50 700 Tm (INV/26-27/205) Tj ET');
      final bytes = _pdf([
        (id: 2, dict: '<</Length ${content.length}/Filter/FlateDecode>>',
            body: content),
        (id: 3, dict: '<</Length 612/Subtype/Type1C>>', body: font),
      ], page: '<</Type/Page/Contents 2 0 R>>');

      final sw = Stopwatch()..start();
      final text = PdfTextExtractor.extractText(bytes);
      sw.stop();
      expect(text, contains('INV/26-27/205'));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('a length that starts with 1 is not mistaken for a font program', () {
      // Squeezing whitespace once turned "/Length 1753" into "/Length1753",
      // which matched the /Length1 key of an embedded font and threw away
      // the very content streams that carry the invoice.
      final content = _flate('BT 1 0 0 1 50 700 Tm (Braking Track) Tj ET'
          '${' ' * 1700}');
      final bytes = _pdf([
        (id: 2, dict: '<</Length ${content.length} /Filter /FlateDecode>>',
            body: content),
      ], page: '<</Type/Page/Contents 2 0 R>>');
      expect(PdfTextExtractor.extractText(bytes), contains('Braking Track'));
    });
  });

  group('rows', () {
    test('cells drawn by different streams of one page join one row', () {
      // 205 and 802 each draw one page from eight content streams. Grouping
      // by stream split every row whose cells fell in different streams.
      final left = _flate(
          'BT 1 0 0 1 76 380 Tm (Braking Track Testing - WET) Tj ET');
      final right = _flate('BT 1 0 0 1 300 381 Tm (998346) Tj ET '
          'BT 1 0 0 1 361 380 Tm (34 Hrs.) Tj ET '
          'BT 1 0 0 1 490 380 Tm (7,14,000.00) Tj ET');
      final bytes = _pdf([
        (id: 2, dict: '<</Length ${left.length}/Filter/FlateDecode>>',
            body: left),
        (id: 3, dict: '<</Length ${right.length}/Filter/FlateDecode>>',
            body: right),
      ], page: '<</Type/Page/Contents[2 0 R 3 0 R]>>');

      final rows = PdfTextExtractor.extract(bytes).rows;
      expect(rows,
          contains('Braking Track Testing - WET 998346 34 Hrs. 7,14,000.00'));
    });

    test('clip-tile copies of a cell are dropped, its unit cell is kept', () {
      // 802 redraws its text once per clip tile of a background pattern,
      // each copy showing only part of the run.
      final c = _flate(
          'BT 1 0 0 1 76 380 Tm (Braking Track Testing - WET) Tj ET '
          'BT 1 0 0 1 90 380 Tm (Track) Tj ET '
          'BT 1 0 0 1 150 380 Tm (WE) Tj ET '
          'BT 1 0 0 1 300 380 Tm (998346) Tj ET '
          'BT 1 0 0 1 305 380 Tm (998) Tj ET '
          'BT 1 0 0 1 361 380 Tm (28 Hrs.) Tj ET '
          'BT 1 0 0 1 402 380 Tm (21,000.00) Tj ET '
          'BT 1 0 0 1 446 380 Tm (Hrs.) Tj ET '
          'BT 1 0 0 1 482 380 Tm (5,88,000.00) Tj ET');
      final bytes = _pdf([
        (id: 2, dict: '<</Length ${c.length}/Filter/FlateDecode>>', body: c),
      ], page: '<</Type/Page/Contents 2 0 R>>');

      expect(PdfTextExtractor.extract(bytes).rows.single,
          'Braking Track Testing - WET 998346 28 Hrs. 21,000.00 Hrs. '
          '5,88,000.00');
    });

    test('rows a few points apart stay separate rows', () {
      final c = _flate('BT 1 0 0 1 76 391 Tm (Dynamic Platform) Tj ET '
          'BT 1 0 0 1 76 380 Tm (Braking Track) Tj ET');
      final bytes = _pdf([
        (id: 2, dict: '<</Length ${c.length}/Filter/FlateDecode>>', body: c),
      ], page: '<</Type/Page/Contents 2 0 R>>');
      expect(PdfTextExtractor.extract(bytes).rows,
          ['Dynamic Platform', 'Braking Track']);
    });
  });
}

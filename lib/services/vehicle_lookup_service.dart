import 'package:dio/dio.dart';

/// What could be found about a vehicle online.
class VehicleFacts {
  final String title;
  final String description;
  final String summary;
  final String? imageUrl;
  final String? sourceUrl;
  final String vehicleType;

  /// 'bev' or 'ice'.
  final String powertrain;

  /// Up to three short chips for the card.
  final List<String> specs;

  /// Longer facts, one per line, for the card's hover panel.
  final List<String> details;

  const VehicleFacts({
    required this.title,
    required this.description,
    required this.summary,
    required this.vehicleType,
    required this.powertrain,
    this.imageUrl,
    this.sourceUrl,
    this.specs = const [],
    this.details = const [],
  });
}

/// Looks a vehicle up on Wikipedia: its summary, picture and the facts in
/// its infobox — engine or battery, transmission, power, layout.
///
/// Wikipedia because its API answers a browser directly (CORS, no key) and
/// its car articles carry a structured infobox. What comes back is a
/// starting point, shown in the form to be checked and edited before it is
/// saved — not a source of record. Only the vehicle's name is sent.
class VehicleLookupService {
  const VehicleLookupService._();

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static const _api = 'https://en.wikipedia.org/w/api.php';

  /// Null when nothing usable was found.
  static Future<VehicleFacts?> lookup(String vehicle) async {
    final q = vehicle.trim();
    if (q.isEmpty) return null;
    final title = await _bestTitle(q);
    if (title == null) return null;

    final summary = await _dio.get<Map<String, dynamic>>(
      'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
    );
    final s = summary.data ?? const {};

    String wikitext = '';
    try {
      final parse = await _dio.get<Map<String, dynamic>>(_api, queryParameters: {
        'action': 'parse',
        'page': title,
        'prop': 'wikitext',
        'section': '0',
        'redirects': '1',
        'format': 'json',
        'origin': '*',
      });
      wikitext = (((parse.data?['parse'] as Map?)?['wikitext'] as Map?)?['*'] as String?) ?? '';
    } catch (_) {
      // The summary alone is still worth having.
    }

    return build(
      title: (s['title'] as String?) ?? title,
      description: (s['description'] as String?) ?? '',
      extract: (s['extract'] as String?) ?? '',
      imageUrl: ((s['originalimage'] as Map?)?['source'] as String?) ??
          ((s['thumbnail'] as Map?)?['source'] as String?),
      sourceUrl: (((s['content_urls'] as Map?)?['desktop'] as Map?)?['page'] as String?),
      infobox: infobox(wikitext),
    );
  }

  /// The search result that best matches [q] — preferring a title that
  /// contains every word of it, so "Kia Sonet" finds the car and not a list.
  static Future<String?> _bestTitle(String q) async {
    final r = await _dio.get<Map<String, dynamic>>(_api, queryParameters: {
      'action': 'query',
      'list': 'search',
      'srsearch': '$q car',
      'srlimit': '8',
      'format': 'json',
      'origin': '*',
    });
    final hits = [
      for (final h in ((((r.data?['query'] as Map?)?['search']) as List?) ?? const []))
        ((h as Map)['title'] as String?) ?? '',
    ].where((t) => t.isNotEmpty).toList();
    if (hits.isEmpty) return null;
    return pickTitle(q, hits);
  }

  /// Exposed for tests: the hit whose title holds the most words of [q],
  /// avoiding lists and disambiguation pages.
  static String pickTitle(String q, List<String> hits) {
    final words = q
        .toLowerCase()
        .split(RegExp(r'[\s.\-]+'))
        .where((w) => w.length > 1)
        .toList();
    int score(String t) {
      final l = t.toLowerCase();
      var s = words.where(l.contains).length * 10;
      if (l.startsWith('list of') || l.contains('disambiguation')) s -= 50;
      s -= t.length ~/ 20;
      return s;
    }

    final sorted = List<String>.from(hits)
      ..sort((a, b) => score(b).compareTo(score(a)));
    return sorted.first;
  }

  /// The `{{Infobox automobile …}}` fields, as plain text.
  static Map<String, String> infobox(String wikitext) {
    final start = wikitext.toLowerCase().indexOf('{{infobox');
    if (start < 0) return const {};
    // Walk to the matching close of the infobox template.
    var depth = 0, end = wikitext.length;
    for (var i = start; i < wikitext.length - 1; i++) {
      if (wikitext.startsWith('{{', i)) {
        depth++;
        i++;
      } else if (wikitext.startsWith('}}', i)) {
        depth--;
        i++;
        if (depth == 0) {
          end = i + 1;
          break;
        }
      }
    }
    final body = wikitext.substring(start, end);
    final out = <String, String>{};
    // Split on top-level pipes only.
    final parts = <String>[];
    var buf = StringBuffer();
    var d = 0;
    for (var i = 2; i < body.length - 2; i++) {
      final two = body.substring(i, i + 2 > body.length ? body.length : i + 2);
      if (two == '{{' || two == '[[') {
        d++;
        buf.write(two);
        i++;
        continue;
      }
      if (two == '}}' || two == ']]') {
        d--;
        buf.write(two);
        i++;
        continue;
      }
      if (body[i] == '|' && d == 0) {
        parts.add(buf.toString());
        buf = StringBuffer();
        continue;
      }
      buf.write(body[i]);
    }
    parts.add(buf.toString());
    for (final p in parts) {
      final eq = p.indexOf('=');
      if (eq <= 0) continue;
      final k = p.substring(0, eq).trim().toLowerCase();
      final v = plain(p.substring(eq + 1));
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    }
    return out;
  }

  /// Wiki markup to plain text: links, conversions, lists and references.
  static String plain(String s) {
    var t = s
        .replaceAll(RegExp(r'<ref[^>]*/>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<ref[^>]*>.*?</ref>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ', ')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    // Links first, so the pipes inside them cannot split a list:
    // [[a|b]] -> b ; [[a]] -> a.
    t = t.replaceAllMapped(RegExp(r'\[\[(?:[^\]|]*\|)?([^\]]*)\]\]'), (m) => m[1]!);
    // Spacing templates, which would otherwise close a list early.
    t = t.replaceAll(RegExp(r'\{\{\s*(?:nbh|nbsp|nowrap\s*\|?|thinsp)\s*\}\}', caseSensitive: false), ' ');
    t = t.replaceAllMapped(RegExp(r'\{\{\s*nowrap\s*\|([^{}]*)\}\}', caseSensitive: false), (m) => m[1]!);
    // {{convert|1497|cc|...}} -> 1497 cc ; {{cvt|...}} likewise.
    t = t.replaceAllMapped(
        RegExp(r'\{\{\s*(?:convert|cvt)\s*\|([^|}]+)\|([^|}]+)[^}]*\}\}', caseSensitive: false),
        (m) => '${m[1]!.trim()} ${m[2]!.trim()}');
    // {{ubl|a|b}} / {{plainlist|...}} / {{hlist|a|b}} -> a, b
    t = t.replaceAllMapped(
        RegExp(r'\{\{\s*(?:ubl|unbulleted list|hlist|flatlist|plainlist)\s*\|([^{}]*)\}\}',
            caseSensitive: false, dotAll: true),
        (m) => m[1]!.split(RegExp(r'[|\n]')).map((x) => x.replaceAll('*', '').trim()).where((x) => x.isNotEmpty).join(', '));
    // Any other template: drop it.
    for (var i = 0; i < 4; i++) {
      t = t.replaceAll(RegExp(r'\{\{[^{}]*\}\}'), '');
    }
    t = t.replaceAll("'''", '').replaceAll("''", '');
    t = t.replaceAll(RegExp(r'^\s*\*\s*', multiLine: true), '');
    t = t.replaceAll(RegExp(r'\s*\n\s*'), ', ');
    t = t.replaceAll(RegExp(r'\s{2,}'), ' ').replaceAll(RegExp(r'(,\s*)+'), ', ');
    return t.trim().replaceAll(RegExp(r'^,\s*|,\s*$'), '');
  }

  /// First real item of a comma list, trimmed to a chip — skipping headings
  /// such as "Petrol:" and preferring one with a figure in it ("1.0 L …").
  static String _first(String v, [int max = 34]) {
    final items = v
        .split(',')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty && !x.endsWith(':'))
        .toList();
    if (items.isEmpty) return '';
    final f = items.firstWhere((x) => RegExp(r'\d').hasMatch(x), orElse: () => items.first);
    return f.length <= max ? f : '${f.substring(0, max - 1)}…';
  }

  /// Exposed for tests: facts from what was fetched.
  static VehicleFacts build({
    required String title,
    required String description,
    required String extract,
    required Map<String, String> infobox,
    String? imageUrl,
    String? sourceUrl,
  }) {
    String? f(List<String> keys) {
      for (final k in keys) {
        final v = infobox[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final engine = f(['engine']);
    final motor = f(['motor', 'electric motor']);
    final battery = f(['battery']);
    final transmission = f(['transmission']);
    final power = f(['power', 'power output']);
    final layout = f(['layout', 'drive']);
    final klass = f(['class']);
    final body = f(['body_style', 'body style']);
    final range = f(['electric_range', 'range']);
    final production = f(['production']);
    final manufacturer = f(['manufacturer']);
    final platform = f(['platform']);

    final text = '$description $extract ${klass ?? ''}'.toLowerCase();
    final electric = battery != null ||
        motor != null ||
        (text.contains('electric') && !text.contains('hybrid') && engine == null);
    final powertrain = electric ? 'bev' : 'ice';

    final type = [
      if (klass != null) _first(klass, 40),
      if (klass == null && body != null) _first(body, 40),
    ].join();
    final vehicleType = type.isNotEmpty
        ? '${electric ? 'Battery Electric ' : ''}$type'
        : (description.isNotEmpty ? description : (electric ? 'Battery Electric Vehicle' : 'Passenger vehicle'));

    final specs = <String>[
      if (electric && battery != null) _first(battery) else if (engine != null) _first(engine),
      if (transmission != null) _first(transmission) else if (motor != null) _first(motor),
      if (layout != null) _first(layout) else if (power != null) _first(power),
    ].where((s) => s.isNotEmpty).take(3).toList();

    final details = <String>[
      if (manufacturer != null) 'Manufacturer: ${_first(manufacturer, 60)}',
      if (klass != null || body != null) 'Class: ${_first(klass ?? body!, 60)}',
      if (platform != null) 'Platform: ${_first(platform, 60)}',
      if (engine != null) 'Engine: ${_first(engine, 60)}',
      if (motor != null) 'Motor: ${_first(motor, 60)}',
      if (battery != null) 'Battery: ${_first(battery, 60)}',
      if (transmission != null) 'Transmission: ${_first(transmission, 60)}',
      if (power != null) 'Power: ${_first(power, 60)}',
      if (range != null) 'Range: ${_first(range, 60)}',
      if (layout != null) 'Layout: ${_first(layout, 60)}',
      if (production != null) 'Production: ${_first(production, 60)}',
    ].take(6).toList();

    return VehicleFacts(
      title: title,
      description: description,
      summary: extract,
      imageUrl: imageUrl,
      sourceUrl: sourceUrl,
      vehicleType: vehicleType,
      powertrain: powertrain,
      specs: specs,
      details: details,
    );
  }
}

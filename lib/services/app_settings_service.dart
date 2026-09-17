import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

/// Settings that change with the business rather than with the code.
///
/// The workshop accrual dates used to be `static final DateTime` constants.
/// Moving a settled date forward each time NATRAX invoiced a month therefore
/// meant editing Dart and redeploying — a monthly chore nobody owned, and
/// forgetting it made the manager's report ask twice for money already paid.
///
/// Values live in `public.app_settings`; the Dart defaults below survive only
/// as the fallback for a client that has not loaded yet, or is running against
/// a database where the migration has not been applied.
class AppSettingsService {
  static AppSettingsService? _instance;
  static AppSettingsService get instance =>
      _instance ??= AppSettingsService._();
  AppSettingsService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Keys are namespaced by area so the table stays readable as it grows.
  static const String kWorkshopSettledTo = 'workshop.settled_to';
  static const String kWorkshopResumedOn = 'workshop.resumed_on';
  static const String kWorkshopReleasedOn = 'workshop.released_on';

  final Map<String, String?> _values = {};
  bool _loaded = false;

  /// True once a read has come back — successfully or not. Callers that must
  /// show a real figure check this rather than assuming the cache is fresh.
  bool get isLoaded => _loaded;

  /// Reads every setting once and caches it.
  ///
  /// Silent on failure by design: an unreadable settings table must degrade to
  /// the built-in defaults, not take down the report that reads them.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final rows = await _client.from('app_settings').select('key, value');
      _values
        ..clear()
        ..addEntries((rows as List).cast<Map<String, dynamic>>().map(
            (r) => MapEntry(r['key'] as String, r['value'] as String?)));
    } catch (_) {
      // Leave whatever is cached. A failed refresh must not wipe good values.
    }
    _loaded = true;
  }

  /// Loads on first use. Cheap to call from anywhere that needs a value.
  Future<void> ensureLoaded() => load();

  /// A stored date, or null when unset or unreadable.
  ///
  /// Null is meaningful for some keys — an empty `workshop.released_on` means
  /// the bay is still held — so it is never conflated with "missing".
  DateTime? getDate(String key) {
    final raw = _values[key];
    if (raw == null || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return null;
    // Dates are day-precision. Stripping any time keeps day arithmetic exact
    // whatever the column ends up holding.
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// Writes a date, or clears it when [value] is null.
  ///
  /// Throws on failure so the caller can say the save did not happen — a
  /// setting that silently fails to save is worse than one that cannot be
  /// edited at all.
  Future<void> setDate(String key, DateTime? value) async {
    final text = value == null
        ? null
        : '${value.year.toString().padLeft(4, '0')}-'
            '${value.month.toString().padLeft(2, '0')}-'
            '${value.day.toString().padLeft(2, '0')}';
    await _client
        .from('app_settings')
        .upsert({'key': key, 'value': text}, onConflict: 'key');
    _values[key] = text;
  }

  /// Test seam: seeds the cache without a database round trip, so the accrual
  /// arithmetic can be exercised against dates other than the seeded ones.
  @visibleForTesting
  void setLocalForTest(String key, String? value) {
    _values[key] = value;
    _loaded = true;
  }

  /// Drops the cache so the next read hits the database. Used on sign-out and
  /// account switch, where the previous user's values must not carry over.
  void clear() {
    _values.clear();
    _loaded = false;
  }
}

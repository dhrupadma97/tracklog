import 'package:flutter/foundation.dart';

import 'track_venue_catalog.dart';

/// Global testing-venue context, alongside [ProjectManager].
///
/// Deliberately separate from the project rather than a field on it: a single
/// programme can run at more than one proving ground, and a venue outlives any
/// one programme. Keeping them independent means picking a venue does not
/// silently re-scope which project a session is billed to, and vice versa.
///
/// Defaults to NATRAX, which is where every session recorded so far ran.
class VenueManager extends ChangeNotifier {
  static final VenueManager _instance = VenueManager._();
  static VenueManager get instance => _instance;
  VenueManager._();

  String _activeKey = TrackVenueCatalog.defaultVenueKey;

  String get activeKey => _activeKey;

  TrackVenue get active => TrackVenueCatalog.resolve(_activeKey);

  /// The value written to `engineer_sessions.venue`.
  String get dbValue => active.dbValue;

  /// True where the active venue has no rate card, so anything logged against
  /// it will carry no cost. Screens use this to say so rather than print a
  /// confident zero.
  bool get ratesPending => active.ratesPending;

  void setVenue(String key) {
    final resolved = TrackVenueCatalog.byKey(key);
    // An unknown key is ignored rather than silently reverting to NATRAX: a
    // typo would otherwise look like a successful switch back to the default.
    if (resolved == null || resolved.key == _activeKey) return;
    _activeKey = resolved.key;
    notifyListeners();
  }

  void reset() => setVenue(TrackVenueCatalog.defaultVenueKey);
}

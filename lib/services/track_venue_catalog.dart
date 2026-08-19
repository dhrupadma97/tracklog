/// The proving grounds SightLine testing can run at.
///
/// NATRAX is the only venue with a loaded rate card, and stays the default:
/// every session recorded before this file existed was run there, which is why
/// the `venue` column on `track_rates` and `engineer_sessions` defaults to
/// 'NATRAX' rather than being nullable. A null would have been indistinguishable
/// from "venue not yet known".
///
/// The other two are declared ahead of use so a session can be attributed the
/// day testing moves, without a schema change at short notice. Neither has a
/// rate card yet, and neither invents one — see [ratesPending].
library;

/// One layout at a venue.
///
/// [detail] carries whatever the source document actually states, so the picker
/// can show why one layout differs from another. It is descriptive only; nothing
/// bills off it.
class VenueTrack {
  final String code;
  final String name;
  final String? detail;

  const VenueTrack(this.code, this.name, {this.detail});
}

class TrackVenue {
  /// Lower-case key. Matches the `venue` column, upper-cased.
  final String key;
  final String displayName;

  /// What the venue is called in a heading, where the full name is too long.
  final String shortName;
  final String location;

  /// Layouts known from the venue's own documentation. Empty where no document
  /// has been supplied — an empty list is honest, an invented one is not.
  final List<VenueTrack> tracks;

  /// True where the venue is usable but no rate card has been recorded, so a
  /// session logged against it carries no cost. The entry form says so rather
  /// than printing a confident zero.
  final bool ratesPending;

  /// Optional logo asset. NATRAX has one; the others do not yet.
  final String? logoAsset;

  const TrackVenue({
    required this.key,
    required this.displayName,
    required this.shortName,
    required this.location,
    this.tracks = const [],
    this.ratesPending = false,
    this.logoAsset,
  });

  /// The `venue` column value.
  String get dbValue => key.toUpperCase();

  /// True where no layouts are known yet, so the venue can be seen but not
  /// booked against.
  bool get tracksPending => tracks.isEmpty;
}

class TrackVenueCatalog {
  const TrackVenueCatalog._();

  /// Where sessions run before a venue was ever asked for. Do not change this
  /// without a migration: it is the default on both `track_rates.venue` and
  /// `engineer_sessions.venue`.
  static const String defaultVenueKey = 'natrax';

  static const List<TrackVenue> all = [
    TrackVenue(
      key: 'natrax',
      displayName: 'NATRAX Proving Ground',
      shortName: 'NATRAX',
      location: 'Pithampur, Indore, Madhya Pradesh',
      logoAsset: 'assets/images/NATRAX LOGO.png',
      // NATRAX layouts are not listed here. They live in `track_rates`, which
      // carries their rates too, and has done since the first migration -
      // duplicating T1..T13 into code would give two lists to keep in step.
    ),
    TrackVenue(
      key: 'coastt',
      displayName: 'CoASTT High Performance Centre',
      shortName: 'CoASTT',
      location: 'Coimbatore, Tamil Nadu',
      ratesPending: true,
      // From "CoASTT High Performance Centre - Coimbatore.pptx", slides 6, 7
      // and 9. Figures are the deck's own; no rate card was included with it.
      tracks: [
        VenueTrack('CO-INT', 'International Circuit',
            detail: '3.80 km · 14 corners · 527 m start straight · '
                'lap 1:14 · avg 177 kph, max 278 kph'),
        VenueTrack('CO-NAT', 'National Circuit',
            detail: '2.02 km · 7 corners · 527 m start straight · '
                'lap 41 s · avg 176 kph, max 278 kph'),
        VenueTrack('CO-HND', 'Handling Circuit',
            detail: '1.58 km · 8 corners · 317 m start straight · '
                'lap 34 s · avg 163 kph, max 246 kph'),
        VenueTrack('CO-EV', 'EV Testing Track',
            detail: 'Over 1 km · flood-lit for night running · '
                'home of the NK Academy'),
      ],
    ),
    TrackVenue(
      key: 'mspt',
      displayName: 'Mahindra SUV Proving Track',
      shortName: 'MSPT',
      location: 'Mahindra Research Valley, Chennai',
      ratesPending: true,
      // No document supplied. Declared so a session can be attributed the day
      // testing moves there; the layouts go in when a track list arrives.
    ),
  ];

  static TrackVenue get defaultVenue => byKey(defaultVenueKey)!;

  static TrackVenue? byKey(String? raw) {
    final k = (raw ?? '').trim().toLowerCase();
    if (k.isEmpty) return byKey(defaultVenueKey);
    for (final v in all) {
      if (v.key == k) return v;
    }
    return null;
  }

  /// Resolves the `venue` column, falling back to NATRAX.
  ///
  /// Sessions written before the column existed carry the default, and anything
  /// unrecognised is treated the same way rather than being dropped from a
  /// report for naming a venue this build has not heard of.
  static TrackVenue resolve(String? raw) =>
      byKey(raw) ?? byKey(defaultVenueKey)!;

  static List<String> get displayNames =>
      all.map((v) => v.displayName).toList();

  /// Venues a session can actually be booked against — a venue with no known
  /// layouts has nothing to select.
  static List<TrackVenue> get bookable =>
      all.where((v) => v.key == defaultVenueKey || !v.tracksPending).toList();
}

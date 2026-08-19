/// The PoC programmes running at NATRAX, as the billing layer needs them.
///
/// The project selection screen holds a richer record of the same programmes —
/// hero images, accent colours, vehicle specs — but that lives in the
/// presentation layer and a service must not reach into it. This holds only
/// what reporting needs: the key sessions and invoices are filed under, the
/// name to print, the vehicle, and whether the programme is still running.
///
/// If a programme's status changes, change it here; the selection screen
/// should be pointed at this catalogue rather than keeping its own copy.
library;

enum ProgrammeStatus { active, upcoming, completed }

extension ProgrammeStatusLabel on ProgrammeStatus {
  String get label => switch (this) {
        ProgrammeStatus.active => 'Active',
        ProgrammeStatus.upcoming => 'Upcoming',
        ProgrammeStatus.completed => 'Closed',
      };

  /// Closed programmes still carry spend and still draw on the shared PO pool,
  /// so they are reported — just not counted as ongoing commitment.
  bool get isClosed => this == ProgrammeStatus.completed;
}

/// Whether the test vehicle is battery-electric or combustion.
///
/// Screens key an icon and a short label off this rather than matching on the
/// vehicle name, which stops being reliable as soon as there is more than one
/// EV in the list.
enum Powertrain { bev, ice }

extension PowertrainLabel on Powertrain {
  String get label => switch (this) {
        Powertrain.bev => 'BEV',
        Powertrain.ice => 'ICE SUV',
      };

  bool get isIce => this == Powertrain.ice;
}

class Programme {
  /// Lower-case key that `project_name` is matched on.
  final String key;
  final String displayName;
  final String vehicle;
  final Powertrain powertrain;
  final ProgrammeStatus status;

  const Programme({
    required this.key,
    required this.displayName,
    required this.vehicle,
    required this.powertrain,
    required this.status,
  });
}

class ProjectCatalog {
  const ProjectCatalog._();

  static const List<Programme> all = [
    Programme(
      key: 'mahindra ev poc',
      displayName: 'Mahindra EV PoC',
      vehicle: 'Mahindra XEV 9e',
      powertrain: Powertrain.bev,
      status: ProgrammeStatus.completed,
    ),
    Programme(
      key: 'mahindra ice poc',
      displayName: 'Mahindra ICE PoC',
      vehicle: 'Mahindra XUV 7XO',
      powertrain: Powertrain.ice,
      status: ProgrammeStatus.active,
    ),
    Programme(
      key: 'kia sonet poc',
      displayName: 'Kia Sonet PoC',
      vehicle: 'Kia Sonet',
      powertrain: Powertrain.ice,
      status: ProgrammeStatus.upcoming,
    ),
    Programme(
      key: 'tata harrier ev poc',
      displayName: 'Tata Harrier EV PoC',
      vehicle: 'Tata Harrier.ev QWD',
      powertrain: Powertrain.bev,
      status: ProgrammeStatus.active,
    ),
  ];

  /// The display names every project picker should offer, in one order.
  ///
  /// Five screens each held their own copy of this list, so adding a programme
  /// meant editing all five and noticing all five. They read it from here now.
  static List<String> get displayNames =>
      all.map((p) => p.displayName).toList();

  /// An empty or 'general' `project_name` means Mahindra EV PoC — that
  /// programme predates the field being filled in reliably.
  static String normaliseKey(String? raw) {
    final k = (raw ?? '').trim().toLowerCase();
    return (k.isEmpty || k == 'general') ? 'mahindra ev poc' : k;
  }

  static Programme? byKey(String? raw) {
    final k = normaliseKey(raw);
    for (final p in all) {
      if (p.key == k) return p;
    }
    return null;
  }

  static String displayName(String? raw) =>
      byKey(raw)?.displayName ?? (raw ?? '').trim();
}

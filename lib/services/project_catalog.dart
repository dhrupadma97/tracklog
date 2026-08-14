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

class Programme {
  /// Lower-case key that `project_name` is matched on.
  final String key;
  final String displayName;
  final String vehicle;
  final ProgrammeStatus status;

  const Programme({
    required this.key,
    required this.displayName,
    required this.vehicle,
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
      status: ProgrammeStatus.completed,
    ),
    Programme(
      key: 'mahindra ice poc',
      displayName: 'Mahindra ICE PoC',
      vehicle: 'Mahindra XUV 7XO',
      status: ProgrammeStatus.active,
    ),
    Programme(
      key: 'hyundai poc',
      displayName: 'Hyundai PoC',
      vehicle: 'Hyundai CRETA EV',
      status: ProgrammeStatus.upcoming,
    ),
  ];

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

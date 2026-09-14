import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'engineer_auth_service.dart';
import 'supabase_service.dart';

/// Why a day carries no track session.
///
/// A category rather than free text alone, so gaps can be counted across
/// months — "we lost nine days to vehicle downtime this quarter" is a
/// different conversation from nine separate sentences nobody reads.
enum DayNoteReason {
  vehicleDowntime,
  trackUnavailable,
  weather,
  instrumentation,
  noTestingPlanned,
  notLogged,
  other,
}

extension DayNoteReasonX on DayNoteReason {
  /// Must match the check constraint on day_notes.reason.
  String get dbValue => switch (this) {
        DayNoteReason.vehicleDowntime => 'vehicle_downtime',
        DayNoteReason.trackUnavailable => 'track_unavailable',
        DayNoteReason.weather => 'weather',
        DayNoteReason.instrumentation => 'instrumentation',
        DayNoteReason.noTestingPlanned => 'no_testing_planned',
        DayNoteReason.notLogged => 'not_logged',
        DayNoteReason.other => 'other',
      };

  String get label => switch (this) {
        DayNoteReason.vehicleDowntime => 'Vehicle downtime',
        DayNoteReason.trackUnavailable => 'Track unavailable',
        DayNoteReason.weather => 'Weather',
        DayNoteReason.instrumentation => 'Instrumentation',
        DayNoteReason.noTestingPlanned => 'No testing planned',
        DayNoteReason.notLogged => 'Testing ran — not logged',
        DayNoteReason.other => 'Other',
      };

  /// The one reason that means the register is wrong rather than the day was
  /// quiet. Worth separating: it is the only one that implies an entry is
  /// still owed, and therefore billable time that has not been claimed.
  bool get meansEntryMissing => this == DayNoteReason.notLogged;

  static DayNoteReason parse(String? raw) {
    final v = (raw ?? '').trim();
    for (final r in DayNoteReason.values) {
      if (r.dbValue == v) return r;
    }
    return DayNoteReason.other;
  }
}

/// One day's explanation, for one programme.
class DayNote {
  final String? id;
  final DateTime date;
  final String projectName;
  final DayNoteReason reason;
  final String? comment;

  const DayNote({
    this.id,
    required this.date,
    required this.projectName,
    required this.reason,
    this.comment,
  });

  String get dateKey => date.toIso8601String().split('T').first;

  factory DayNote.fromJson(Map<String, dynamic> j) => DayNote(
        id: j['id'] as String?,
        date: DateTime.parse(j['note_date'] as String),
        projectName: j['project_name'] as String? ?? '',
        reason: DayNoteReasonX.parse(j['reason'] as String?),
        comment: j['comment'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'note_date': dateKey,
        'project_name': projectName,
        'reason': reason.dbValue,
        'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
      };
}

/// Reads and writes the day notes.
///
/// A [ChangeNotifier] for the same reason [MusterService] is: answering "why
/// was there no testing on the 3rd" changes what the history shows, and the
/// screen that asked the question is rarely the only one displaying it.
class DayNoteService extends ChangeNotifier {
  DayNoteService._();
  static DayNoteService? _instance;
  static DayNoteService get instance => _instance ??= DayNoteService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Notes keyed 'YYYY-MM-DD|project', the shape a day lookup needs.
  ///
  /// Returns empty rather than throwing when the table is not there yet: the
  /// migration is applied by hand, so a build can reach users before the table
  /// does, and a missing explanation must not take the history down with it.
  Future<Map<String, DayNote>> byDay() async {
    try {
      final rows = await _client.from('day_notes').select();
      final out = <String, DayNote>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final n = DayNote.fromJson(r);
        out['${n.dateKey}|${n.projectName.toLowerCase().trim()}'] = n;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Upserts on (note_date, project_name), so answering again corrects the
  /// record instead of leaving two explanations for one day.
  Future<void> save(DayNote note) async {
    final payload = note.toJson();
    final user = EngineerAuthService.instance.currentUser;
    if (user != null) payload['recorded_by'] = user.id;
    await _client
        .from('day_notes')
        .upsert(payload, onConflict: 'note_date,project_name');
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _client.from('day_notes').delete().eq('id', id);
    notifyListeners();
  }
}

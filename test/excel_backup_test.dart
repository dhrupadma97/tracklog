import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/excel_backup_service.dart';

/// The backup is only worth having if it round-trips: every test here writes a
/// real .xlsx and reads it back with the same library Excel would, rather than
/// asserting on the in-memory structures that produced it.
void main() {
  final at = DateTime(2026, 8, 19, 14, 30);

  Map<String, dynamic> session({
    String started = '2026-05-20T09:15:00Z',
    String? ended = '2026-05-20T11:15:00Z',
    String venue = 'NATRAX',
    String code = 'T3W',
    num rate = 21000,
    num cost = 42000,
    int minutes = 120,
  }) =>
      {
        'started_at': started,
        'ended_at': ended,
        'venue': venue,
        'track_code': code,
        'track_name': 'T3 Wet Braking Track',
        'project_name': 'Mahindra EV PoC',
        'duration_minutes': minutes,
        'hourly_rate': rate,
        'total_cost': cost,
        'session_status': 'completed',
        'notes': 'Manual entry',
      };

  BackupData buildData({
    List<Map<String, dynamic>>? sessions,
    List<Map<String, dynamic>>? services,
    List<Map<String, dynamic>>? muster,
  }) =>
      BackupData.fromRows(
        sessionRows: sessions ?? [session()],
        serviceRows: services ?? const [],
        musterRows: muster ?? const [],
        generatedAt: at,
      );

  Excel reopen(BackupData d) => Excel.decodeBytes(ExcelBackupService.build(d));

  /// The excel package normalises a whole number to IntCellValue and keeps
  /// a fractional one as DoubleCellValue. Both are numeric cells in Excel -
  /// which is the property that matters, since text would not sum - so read
  /// either rather than pinning the test to one representation.
  num numOf(CellValue? v) {
    if (v is IntCellValue) return v.value;
    if (v is DoubleCellValue) return v.value;
    fail('expected a numeric cell, got ${v.runtimeType}: $v');
  }

  group('workbook structure', () {
    test('opens, and carries exactly the four expected sheets', () {
      final book = reopen(buildData());
      expect(
        book.sheets.keys.toSet(),
        {
          ExcelBackupService.sheetSessions,
          ExcelBackupService.sheetServices,
          ExcelBackupService.sheetMuster,
          ExcelBackupService.sheetSummary,
        },
      );
    });

    test('the default Sheet1 is gone', () {
      expect(reopen(buildData()).sheets.keys, isNot(contains('Sheet1')));
    });

    test('headers survive the round trip in order', () {
      final sheet = reopen(buildData())[ExcelBackupService.sheetSessions];
      final header =
          sheet.rows.first.map((c) => c?.value?.toString() ?? '').toList();
      expect(header, BackupData.sessionHeaders);
    });

    test('an entirely empty database still produces a valid workbook', () {
      // The failure that matters: a brand new project, or the very first
      // backup, must not throw.
      final book = reopen(BackupData.fromRows(
        sessionRows: const [],
        serviceRows: const [],
        musterRows: const [],
        generatedAt: at,
      ));
      final sheet = book[ExcelBackupService.sheetSessions];
      expect(sheet.rows.length, 1, reason: 'header only');
    });
  });

  group('values', () {
    test('numbers stay numbers, not text', () {
      final sheet = reopen(buildData())[ExcelBackupService.sheetSessions];
      final row = sheet.rows[1];
      expect(numOf(row[7]?.value), 120, reason: 'duration');
      expect(numOf(row[8]?.value), 21000, reason: 'hourly rate');
      expect(numOf(row[9]?.value), 42000, reason: 'total cost');
      // Text would not sum in Excel, which is the whole point.
      expect(row[9]?.value, isNot(isA<TextCellValue>()));
    });

    test('money is rounded to paise', () {
      final d = buildData(sessions: [session(cost: 42000.005999)]);
      final v = reopen(d)[ExcelBackupService.sheetSessions].rows[1][9]!.value;
      expect(numOf(v), 42000.01);
    });

    test('a running session with no end time does not break the row', () {
      final d = buildData(sessions: [session(ended: null)]);
      final row = reopen(d)[ExcelBackupService.sheetSessions].rows[1];
      expect(row[6]?.value?.toString() ?? '', '');
      expect(row[3]?.value.toString(), 'T3 Wet Braking Track');
    });

    test('nulls the schema allows are tolerated', () {
      final d = BackupData.fromRows(
        sessionRows: [
          {'started_at': '2026-05-20T09:00:00Z'} // every other column absent
        ],
        serviceRows: const [],
        musterRows: const [],
        generatedAt: at,
      );
      final row = reopen(d)[ExcelBackupService.sheetSessions].rows[1];
      expect(row[1]?.value.toString(), 'NATRAX',
          reason: 'venue defaults for rows predating the column');
      expect(numOf(row[9]!.value), 0);
    });

    test('venue is carried through', () {
      final d = buildData(sessions: [session(venue: 'COASTT')]);
      final row = reopen(d)[ExcelBackupService.sheetSessions].rows[1];
      expect(row[1]?.value.toString(), 'COASTT');
    });
  });

  group('services', () {
    // session_additional_services carries neither a date nor a project of its
    // own; both live on the parent session and arrive nested under the table
    // name. If that embed is ever dropped from the query these two go blank,
    // which is exactly what this pins.
    test('date and project are read from the embedded session', () {
      final d = BackupData.fromRows(
        sessionRows: const [],
        serviceRows: [
          {
            'service_name': 'Sand bags 20/50kg',
            'quantity': 75,
            'rate': 150,
            'total_cost': 11250,
            'engineer_sessions': {
              'started_at': '2026-04-17T08:00:00Z',
              'project_name': 'Mahindra EV PoC',
            },
          }
        ],
        musterRows: const [],
        generatedAt: at,
      );
      final row = reopen(d)[ExcelBackupService.sheetServices].rows[1];
      expect(row[0]?.value.toString(), '17-Apr-2026');
      expect(row[1]?.value.toString(), 'Mahindra EV PoC');
      expect(row[2]?.value.toString(), 'Sand bags 20/50kg');
      expect(numOf(row[4]?.value), 150, reason: 'rate, not unit_rate');
      expect(numOf(row[5]?.value), 11250);
    });

    test('a service whose parent session was not embedded still writes', () {
      final d = BackupData.fromRows(
        sessionRows: const [],
        serviceRows: [
          {'service_name': 'Electricity', 'quantity': 1, 'rate': 3225,
           'total_cost': 3225}
        ],
        musterRows: const [],
        generatedAt: at,
      );
      final row = reopen(d)[ExcelBackupService.sheetServices].rows[1];
      expect(row[0]?.value?.toString() ?? '', '');
      expect(numOf(row[5]?.value), 3225);
    });
  });

  group('summary', () {
    test('row counts and totals match the detail sheets', () {
      final d = buildData(sessions: [
        session(cost: 42000),
        session(cost: 15000),
        session(cost: 9000),
      ]);
      final book = reopen(d);
      final summary = book[ExcelBackupService.sheetSummary];
      final sessionsRow = summary.rows.firstWhere(
          (r) => r.first?.value.toString() == ExcelBackupService.sheetSessions);

      expect(numOf(sessionsRow[1]!.value), 3);
      expect(numOf(sessionsRow[2]!.value), 66000);

      // And the detail sheet genuinely holds those three rows.
      expect(book[ExcelBackupService.sheetSessions].rows.length, 4);
    });

    test('totals survive many rows without drifting', () {
      final rows = List.generate(500, (_) => session(cost: 1234.56));
      final d = buildData(sessions: rows);
      final summary = reopen(d)[ExcelBackupService.sheetSummary];
      final sessionsRow = summary.rows.firstWhere(
          (r) => r.first?.value.toString() == ExcelBackupService.sheetSessions);
      expect(numOf(sessionsRow[2]!.value), 617280.0);
    });
  });

  group('filename', () {
    test('is sortable and carries the timestamp', () {
      expect(ExcelBackupService.fileName(at),
          'TrackLog_Backup_2026-08-19_1430.xlsx');
    });
  });
}

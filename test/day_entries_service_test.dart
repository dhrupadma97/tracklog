import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/day_entries_service.dart';
import 'package:tracklog/services/natrax_rate_card.dart';

DayEntry _run(String id, String code, String start, int minutes,
    {double cost = 0, String notes = ''}) {
  final p = start.split(':');
  return DayEntry(
    id: id,
    code: code,
    name: code,
    start: DateTime(2026, 10, 7, int.parse(p[0]), int.parse(p[1])),
    minutes: minutes,
    cost: cost,
    project: 'Mahindra ICE PoC',
    notes: notes,
  );
}

double _sum(Map<String, double> m) => m.values.fold(0.0, (a, b) => a + b);

void main() {
  group('pricing a day again', () {
    test('runs on one track share its whole hours, and add up exactly', () {
      // 158 + 22 + 45 = 225 min → 4 h on T16.
      final priced = DayEntriesService.priceDay([
        _run('a', 'T16', '12:13', 158),
        _run('b', 'T16', '15:38', 22),
        _run('c', 'T16', '16:49', 45),
      ]);
      expect(_sum(priced), 4 * NatraxRateCard.rateFor('T16'));
      // The longest run carries the rounding; the rest are by minutes.
      expect(priced['b'], (4 * NatraxRateCard.rateFor('T16') * 22 / 225).roundToDouble());
    });

    test('T3 Wet and Dry share one two-hour floor, not one each', () {
      // 30 min wet + 20 min dry: an hour each, which already meets the
      // shared floor. Pricing them one after another, as Manual Entry
      // does, charges the first one the whole floor and bills three hours.
      final priced = DayEntriesService.priceDay([
        _run('w', 'T3W', '09:00', 30),
        _run('d', 'T3D', '11:00', 20),
      ]);
      expect(priced['w'], NatraxRateCard.rateFor('T3W'));
      expect(priced['d'], NatraxRateCard.rateFor('T3D'));
    });

    test('a short run on a two-hour track is billed the floor', () {
      final priced = DayEntriesService.priceDay([_run('a', 'T1', '12:31', 28)]);
      expect(priced['a'], 2 * NatraxRateCard.rateFor('T1'));
    });

    test('exclusive is whole blocks', () {
      final priced = DayEntriesService.priceDay([_run('x', 'T1X', '08:25', 26)]);
      expect(priced['x'], NatraxRateCard.rateFor('T1X'));
    });

    test('a code the card does not know keeps its own cost', () {
      final priced = DayEntriesService.priceDay([
        _run('a', 'CO-INT', '10:00', 60, cost: 0),
        _run('b', 'T16', '10:00', 60),
      ]);
      expect(priced.containsKey('a'), isFalse);
      expect(priced['b'], NatraxRateCard.rateFor('T16'));
    });
  });

  group('comments', () {
    test('Manual Entry\'s prefix is hidden when reading', () {
      expect(DayEntriesService.commentOf('Manual entry — brake test, wet'),
          'brake test, wet');
      expect(DayEntriesService.commentOf('Manual entry'), '');
      expect(DayEntriesService.commentOf('logged live'), 'logged live');
      expect(DayEntriesService.commentOf(null), '');
    });

    test('and kept when writing, so Manual Entry can still find the row', () {
      expect(DayEntriesService.notesWith('Manual entry — old', 'new note'),
          'Manual entry — new note');
      expect(DayEntriesService.notesWith('Manual entry — old', '  '),
          'Manual entry');
      expect(DayEntriesService.notesWith('', 'note'), 'note');
    });
  });

  test('clock times wrap past midnight', () {
    final e = _run('a', 'T16', '23:30', 45);
    expect(e.timeLabel, '23:30–00:15');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/muster_service.dart';

/// "Other" muster entries: the office, the conference hall, food coupons.
/// A record of the day — they must never draw a PO or count as a man-day.
void main() {
  MusterDay entry({double qty = 1, double? rate, String po = ''}) => MusterDay(
        date: DateTime(2026, 10, 21),
        headCount: 0,
        poNumber: po,
        projectName: 'Mahindra ICE PoC',
        notes: 'with NATRAX',
        kind: MusterKind.other,
        item: '  Conference hall ',
        quantity: qty,
        rate: rate,
      );

  test('an other entry draws no PO and consumes no days', () {
    expect(MusterKind.other.poCategory, '');
    expect(MusterKind.other.isHeadCounted, isFalse);
    expect(entry().daysConsumed, 0);
  });

  test('amount is quantity times rate, and unknown without a rate', () {
    expect(entry(qty: 26, rate: 125).amount, 3250);
    expect(entry(qty: 26).amount, isNull);
  });

  test('it round-trips through muster_entries', () {
    final json = entry(qty: 2, rate: 11000).toEntryJson();
    expect(json['entry_date'], '2026-10-21');
    expect(json['item'], 'Conference hall');
    expect(json['po_number'], isNull, reason: 'no PO is stored as null');
    final back = MusterDay.fromEntryJson({...json, 'id': 'x'});
    expect(back.kind, MusterKind.other);
    expect(back.item, 'Conference hall');
    expect(back.quantity, 2);
    expect(back.rate, 11000);
    expect(back.amount, 22000);
    expect(back.projectName, 'Mahindra ICE PoC');
  });

  test('the kind parses from its name', () {
    expect(MusterKindX.parse('other'), MusterKind.other);
    expect(MusterKind.other.label, 'Other');
  });
}

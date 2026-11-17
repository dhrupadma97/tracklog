import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/muster_service.dart';
import 'package:tracklog/services/spend_breakdown_service.dart';

Map<String, dynamic> _s(String id, String project, String code, double cost,
        String start, {String status = 'completed'}) =>
    {
      'id': id,
      'project_name': project,
      'track_code': code,
      'total_cost': cost,
      'started_at': start,
      'session_status': status,
    };

Map<String, dynamic> _svc(String sid, String name, double qty, double cost) =>
    {'session_id': sid, 'service_name': name, 'quantity': qty, 'total_cost': cost};

void main() {
  test('Mahindra EV is pinned to its invoices: 17,32,719 with its 12,72,500 of track', () {
    final b = SpendBreakdown.build(
      sessions: [
        _s('e1', 'General', 'T3W', 1272500, '2026-04-10T10:00:00'),
      ],
      // Inside an invoiced month: already inside the pinned 2,15,219.
      services: [_svc('e1', 'Vbox 3i Hiring /day', 6, 162000)],
      charges: const {},
    );
    final ev = b.rowFor('Mahindra EV PoC')!;
    expect(ev.pinned, isTrue);
    expect(ev.track, 1272500);
    expect(ev.services, 215219);
    expect(ev.workshop, 245000);
    expect(ev.total, 1732719);
    // Vehicle validation, instrumentation and Vbox hire are listed, not added.
    expect(b.outside.map((x) => x.label),
        isNot(contains(startsWith('Workshop'))));
    expect(b.outside, isNotEmpty);
  });

  test('other programmes add the muster, before GST, nothing grossed up', () {
    final b = SpendBreakdown.build(
      sessions: [
        _s('i1', 'Mahindra ICE PoC', 'T16', 36000, '2026-10-07T12:13:00'),
        _s('i2', 'Mahindra ICE PoC', 'MISC', 0, '2026-10-08T08:00:00'),
        _s('x', 'Mahindra ICE PoC', 'T1', 50000, '2026-10-09T08:00:00',
            status: 'cancelled'),
      ],
      services: [
        _svc('i2', 'Refreshment / Lunch', 10, 1250),
        _svc('i2', 'Universal EV Charger', 46, 1150),
        _svc('x', 'Refreshment / Lunch', 99, 9999), // on a cancelled session
      ],
      charges: {
        'Mahindra ICE PoC': const ProjectCharges(
          manpowerCost: 66600,
          manDays: 37,
          workshopCost: 95000,
          workshopDays: 19,
          workshopByMonth: {'2026-10': 95000},
          deadWeightCost: 7200,
          deadWeightDays: 16,
        ),
      },
    );
    final ice = b.rowFor('Mahindra ICE PoC')!;
    expect(ice.track, 36000);
    expect(ice.sessions, 1, reason: 'the services container is not a run');
    expect(ice.services, 1250);
    expect(ice.ev, 1150);
    expect(ice.workshop, 95000);
    expect(ice.workshopDays, 19);
    expect(ice.manpower, 66600);
    expect(ice.deadWeight, 7200);
    expect(ice.total, 36000 + 1250 + 1150 + 95000 + 66600 + 7200);
  });

  test('workshop logged as a service line is not counted again from the muster', () {
    final b = SpendBreakdown.build(
      sessions: [_s('h', 'Tata Harrier EV PoC', 'MISC', 0, '2026-10-01T08:00:00')],
      services: [_svc('h', 'Porta Cabin (Per Day)', 13, 65000)],
      charges: {
        'Tata Harrier EV PoC': const ProjectCharges(
          workshopCost: 65000,
          workshopByMonth: {'2026-10': 65000},
        ),
      },
    );
    expect(b.rowFor('Tata Harrier EV PoC')!.workshop, 65000);
  });
}

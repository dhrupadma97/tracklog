import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/project_catalog.dart';
import 'package:tracklog/services/project_registry.dart';
import 'package:tracklog/services/vehicle_lookup_service.dart';

/// The vehicle lookup reads Wikipedia's infobox. These samples follow the
/// shape of the real Kia Sonet and Mahindra XEV 9e articles (19 Nov 2026).
const _sonet = r"""
{{Short description|Subcompact crossover SUV}}
{{Infobox automobile
| name = Kia Sonet
| image = 2020 Kia Sonet.jpg
| manufacturer = [[Kia]]
| production = August 2020 – present
| class = [[Subcompact crossover SUV]]
| body_style = 5-door [[Sport utility vehicle|SUV]]
| layout = [[Front-engine, front-wheel-drive layout|Front-engine, front-wheel-drive]]
| platform = Hyundai-Kia K2
| engine = {{ubl
  | '''[[Petrol engine|Petrol]]:'''
  | 1.0 L [[Hyundai Kappa engine#G3LC|''Kappa II'']] [[Turbocharger|T]]{{nbh}}[[Gasoline direct injection|GDi]] [[Straight-three engine|I3]]
  | 1.2 L [[Hyundai Smartstream engine|Smartstream G1.2]] MPi I4
  }}
| transmission = {{ubl
  | 5-speed [[Manual transmission|manual]]
  | 7-speed [[Dual-clutch transmission|DCT]]
  }}
| wheelbase = {{convert|2500|mm|in|1|abbr=on}}
}}
The '''Kia Sonet''' is a subcompact crossover SUV.<ref>{{cite web|url=x}}</ref>
""";

const _xev = r"""
{{Infobox automobile
| manufacturer = [[Mahindra & Mahindra]]
| class = [[Mid-size car|Mid-size]] [[crossover SUV]]
| platform = INGLO
| motor = [[Permanent magnet synchronous]]
| battery = 59 kWh [[BYD Blade battery|Blade]] [[LFP battery|LFP]]<ref>a</ref>
| electric_range = 542–656 km (MIDC)
| layout = Rear-motor
}}
""";

void main() {
  test('an ICE car: engine with a figure, transmission, layout', () {
    final f = VehicleLookupService.build(
      title: 'Kia Sonet',
      description: 'subcompact crossover SUV',
      extract: 'The Kia Sonet is a subcompact crossover SUV.',
      infobox: VehicleLookupService.infobox(_sonet),
    );
    expect(f.powertrain, 'ice');
    expect(f.vehicleType, 'Subcompact crossover SUV');
    // The heading "Petrol:" is skipped for the first item with a figure.
    expect(f.specs.first, startsWith('1.0 L Kappa II'));
    expect(f.specs[1], '5-speed manual');
    expect(f.details, contains('Manufacturer: Kia'));
    expect(f.details, contains('Platform: Hyundai-Kia K2'));
  });

  test('an electric car is recognised from its battery and motor', () {
    final f = VehicleLookupService.build(
      title: 'Mahindra XEV 9e',
      description: '',
      extract: '',
      infobox: VehicleLookupService.infobox(_xev),
    );
    expect(f.powertrain, 'bev');
    expect(f.vehicleType, startsWith('Battery Electric'));
    expect(f.specs.first, '59 kWh Blade LFP');
    expect(f.details.any((d) => d.startsWith('Range: 542')), isTrue);
  });

  test('no infobox still gives a usable result', () {
    final f = VehicleLookupService.build(
        title: 'X', description: 'electric SUV', extract: '', infobox: const {});
    expect(f.powertrain, 'bev');
    expect(f.specs, isEmpty);
    expect(f.vehicleType, 'electric SUV');
  });

  test('the best search hit is the car, not a list', () {
    expect(
        VehicleLookupService.pickTitle(
            'Hyundai Creta', ['List of Hyundai vehicles', 'Hyundai Creta', 'Hyundai']),
        'Hyundai Creta');
  });

  test('wiki markup comes out as plain text', () {
    expect(VehicleLookupService.plain("[[Turbocharger|T]]{{nbh}}[[GDi]] '''bold'''<ref>x</ref>"),
        'T GDi bold');
    expect(VehicleLookupService.plain('{{convert|2500|mm|in}}'), '2500 mm');
  });

  test('a programme added from the app joins the catalog, never replacing a built-in', () {
    const added = ProgrammeProfile(
        key: 'hyundai creta poc', displayName: 'Hyundai Creta PoC', vehicle: 'Hyundai Creta');
    const clash = ProgrammeProfile(
        key: 'kia sonet poc', displayName: 'Kia Sonet PoC', vehicle: 'Something else');
    ProjectCatalog.setAdded([
      added.toProgramme(ProgrammeStatus.upcoming),
      clash.toProgramme(ProgrammeStatus.active),
    ]);
    expect(ProjectCatalog.displayNames, contains('Hyundai Creta PoC'));
    expect(ProjectCatalog.byKey('kia sonet poc')!.vehicle, 'Kia Sonet');
    expect(ProjectCatalog.displayName('hyundai creta poc'), 'Hyundai Creta PoC');
    ProjectCatalog.setAdded(const []);
    expect(ProjectCatalog.displayNames, isNot(contains('Hyundai Creta PoC')));
  });

  test('a profile round-trips through public.projects', () {
    const p = ProgrammeProfile(
      key: 'hyundai creta poc',
      displayName: ' Hyundai Creta PoC ',
      vehicle: 'Hyundai Creta',
      powertrain: 'ice',
      specs: ['1.5 L turbo', '', '7-speed DCT'],
      details: ['Engine: 1.5 L', ''],
      imageUrl: '',
    );
    final j = p.toJson();
    expect(j['display_name'], 'Hyundai Creta PoC');
    expect(j['specs'], ['1.5 L turbo', '7-speed DCT']);
    expect(j['image_url'], isNull);
    final back = ProgrammeProfile.fromJson(j);
    expect(back.specs, ['1.5 L turbo', '7-speed DCT']);
    expect(back.details, ['Engine: 1.5 L']);
  });
}

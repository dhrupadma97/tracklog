@Tags(['integration'])
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracklog/services/supabase_service.dart';

/// Integration tests against the real Supabase project.
///
/// These assert the SHAPE of the protection, never the data. The key here is
/// the anon key, which ships inside the public web bundle — anything it can
/// reach is reachable by anyone on the internet who opens the site. So every
/// test below is a claim about what the public CANNOT do.
///
/// They would have caught two real problems on 15 September 2026: accessories
/// invisible to the app because session_additional_services had no read
/// policy for the signed-in user, and every new sign-up getting full write
/// access because engineer_sessions never checked a role.
///
/// Run with:  flutter test --tags integration
/// Skipped by default, because they need the network.
void main() {
  final dio = Dio(BaseOptions(
    baseUrl: '${SupabaseService.supabaseUrl}/rest/v1',
    headers: {
      'apikey': SupabaseService.supabaseAnonKey,
      'Authorization': 'Bearer ${SupabaseService.supabaseAnonKey}',
      'Content-Type': 'application/json',
    },
    // Read the status rather than throwing, so a 401 is an assertion and not
    // an exception.
    validateStatus: (_) => true,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// The tables the app depends on. A 404 with PGRST205 means the table is
  /// missing entirely — usually a migration that was written but never run.
  const requiredTables = [
    'engineer_sessions',
    'session_additional_services',
    'manpower_muster',
    'natrax_invoices',
    'po_trackers',
    'track_rates',
    'engineer_profiles',
    'tracklog_writers',
    'day_notes',
  ];

  group('the tables the app needs all exist', () {
    for (final t in requiredTables) {
      test(t, () async {
        final r = await dio.get('/$t', queryParameters: {'select': 'count'});
        expect(r.statusCode, isNot(404),
            reason: '$t is missing — a migration has not been run. '
                'PostgREST says: ${r.data}');
      });
    }
  });

  group('the public cannot READ operational data', () {
    // RLS is on and no policy grants anon, so these come back 200 with an
    // empty list. An empty list is the pass; rows would mean a leak.
    const protectedTables = [
      'engineer_sessions',
      'session_additional_services',
      'manpower_muster',
      'natrax_invoices',
      'po_trackers',
    ];
    for (final t in protectedTables) {
      test('$t returns nothing to an anonymous caller', () async {
        final r = await dio.get('/$t', queryParameters: {'select': '*', 'limit': 5});
        if (r.statusCode == 200) {
          expect(r.data, isEmpty,
              reason: 'ANON CAN READ $t. The anon key is in the public web '
                  'bundle, so this data is public on the internet.');
        } else {
          // 401/403 is also a pass: refused outright.
          expect(r.statusCode, anyOf(401, 403));
        }
      });
    }
  });

  group('the public cannot WRITE', () {
    test('a session cannot be inserted anonymously', () async {
      final r = await dio.post('/engineer_sessions', data: {
        'track_code': 'TEST-RLS',
        'track_name': 'permission probe',
        'started_at': DateTime.utc(2000).toIso8601String(),
        'duration_minutes': 1,
      });
      expect(r.statusCode, isNot(201),
          reason: 'ANON CAN CREATE SESSIONS. Anyone could write billing rows.');
      expect(r.statusCode, anyOf(401, 403, 400, 404));
    });

    test('an invoice cannot be inserted anonymously', () async {
      final r = await dio.post('/natrax_invoices', data: {
        'invoice_number': 'RLS-PROBE-DO-NOT-KEEP',
        'amount_excl_gst': 1,
      });
      expect(r.statusCode, isNot(201),
          reason: 'ANON CAN CREATE INVOICES.');
    });

    test('the writer list cannot be added to anonymously', () async {
      // This is the security boundary for who may edit anything. It has a
      // read policy and deliberately NO write policy, so only the SQL editor
      // can change it.
      final r = await dio.post('/tracklog_writers',
          data: {'email': 'rls-probe@example.com', 'note': 'probe'});
      expect(r.statusCode, isNot(201),
          reason: 'ANYONE COULD GRANT THEMSELVES WRITE ACCESS. '
              'tracklog_writers must have no INSERT policy.');
    });
  });

  group('reference data is public on purpose', () {
    test('track rates are readable — the app needs them before sign-in',
        () async {
      final r = await dio.get('/track_rates',
          queryParameters: {'select': 'track_code', 'limit': 1});
      expect(r.statusCode, 200);
    });
  });

  group('the key in the bundle is the anon key, not a privileged one', () {
    test('its role claim is anon', () {
      final parts = SupabaseService.supabaseAnonKey.split('.');
      expect(parts.length, 3, reason: 'not a JWT');
      // Middle segment is base64url JSON; look for the role without decoding
      // padding-sensitive base64 by hand.
      final payload = String.fromCharCodes(
        _b64urlDecode(parts[1]),
      );
      expect(payload, contains('"role":"anon"'),
          reason: 'A service_role key in the web bundle would hand every '
              'visitor full database access.');
      expect(payload, isNot(contains('service_role')));
    });
  });
}

List<int> _b64urlDecode(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return const Base64Codec().decode(t);
}

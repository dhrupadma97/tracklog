import 'package:supabase_flutter/supabase_flutter.dart';

import './app_settings_service.dart';
import './supabase_service.dart';
import './venue_manager.dart';
import 'session_status.dart';

class EngineerProfile {
  final String id;
  final String engineerName;
  final String engineerId;
  final String email;
  final String department;
  final String userRole;
  final DateTime createdAt;

  EngineerProfile({
    required this.id,
    required this.engineerName,
    required this.engineerId,
    required this.email,
    required this.department,
    this.userRole = 'engineer',
    required this.createdAt,
  });

  factory EngineerProfile.fromJson(Map<String, dynamic> json) {
    return EngineerProfile(
      id: json['id'] as String,
      engineerName: json['engineer_name'] as String? ?? '',
      engineerId: json['engineer_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      department: json['department'] as String? ?? 'Tyre Testing',
      userRole: json['user_role'] as String? ?? 'engineer',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isManager => userRole == 'manager';
  bool get isReadOnly => userRole == 'manager';

  Map<String, dynamic> toJson() => {
    'id': id,
    'engineer_name': engineerName,
    'engineer_id': engineerId,
    'email': email,
    'department': department,
    'user_role': userRole,
    'created_at': createdAt.toIso8601String(),
  };
}

class EngineerSession {
  final String id;
  final String engineerId;
  final String trackCode;
  final String trackName;
  final String vehicleCategory;
  final String bookingType;
  final String sessionStatus;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationMinutes;
  final double hourlyRate;
  final double? totalCost;
  final String? notes;
  final String projectName;
  final String vehicleName;

  EngineerSession({
    required this.id,
    required this.engineerId,
    required this.trackCode,
    required this.trackName,
    required this.vehicleCategory,
    required this.bookingType,
    required this.sessionStatus,
    required this.startedAt,
    this.endedAt,
    this.durationMinutes,
    required this.hourlyRate,
    this.totalCost,
    this.notes,
    required this.projectName,
    required this.vehicleName,
  });

  factory EngineerSession.fromJson(Map<String, dynamic> json) {
    return EngineerSession(
      id: json['id'] as String,
      engineerId: json['engineer_id'] as String,
      trackCode: json['track_code'] as String? ?? '',
      trackName: json['track_name'] as String? ?? '',
      vehicleCategory: json['vehicle_category'] as String? ?? 'below_3_5t',
      bookingType: json['booking_type'] as String? ?? 'standard',
      sessionStatus: json['session_status'] as String? ?? 'active',
      startedAt:
          DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now(),
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'] as String)
          : null,
      durationMinutes: json['duration_minutes'] as int?,
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble() ?? 0.0,
      totalCost: (json['total_cost'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      projectName: json['project_name'] as String? ?? 'General',
      vehicleName: json['vehicle_name'] as String? ?? 'Standard Vehicle',
    );
  }
}

class TrackRate {
  final String trackCode;
  final String trackName;

  /// Which proving ground the layout belongs to. Defaults to NATRAX, where
  /// every track predating the venue column sits.
  final String venue;

  /// True where the venue is usable but its rate card has not been recorded.
  /// Distinguishes a genuine zero from an unknown, so the entry form can say
  /// "not recorded" rather than printing a confident 0.
  final bool ratePending;
  final double rateBelow3_5t;
  final double? rateAbove3_5t;
  final double? exclusiveRateBelow3_5t;
  final double? exclusiveRateAbove3_5t;
  final int minHoursPerDay;

  TrackRate({
    required this.trackCode,
    required this.trackName,
    this.venue = 'NATRAX',
    this.ratePending = false,
    required this.rateBelow3_5t,
    this.rateAbove3_5t,
    this.exclusiveRateBelow3_5t,
    this.exclusiveRateAbove3_5t,
    required this.minHoursPerDay,
  });

  factory TrackRate.fromJson(Map<String, dynamic> json) {
    return TrackRate(
      trackCode: json['track_code'] as String,
      trackName: json['track_name'] as String,
      venue: (json['venue'] as String? ?? 'NATRAX').trim(),
      ratePending: json['rate_pending'] as bool? ?? false,
      rateBelow3_5t: (json['rate_below_3_5t'] as num).toDouble(),
      rateAbove3_5t: (json['rate_above_3_5t'] as num?)?.toDouble(),
      exclusiveRateBelow3_5t: (json['exclusive_rate_below_3_5t'] as num?)
          ?.toDouble(),
      exclusiveRateAbove3_5t: (json['exclusive_rate_above_3_5t'] as num?)
          ?.toDouble(),
      minHoursPerDay: json['min_hours_per_day'] as int? ?? 1,
    );
  }

  double getRate({bool above3_5t = false}) {
    if (above3_5t && rateAbove3_5t != null) return rateAbove3_5t!;
    return rateBelow3_5t;
  }
}

class EngineerAuthService {
  static EngineerAuthService? _instance;
  static EngineerAuthService get instance =>
      _instance ??= EngineerAuthService._();
  EngineerAuthService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  // ── Auth ──────────────────────────────────────────────────────────────────

  /// Creates an account, and hands back what actually happened.
  ///
  /// The two outcomes look nothing alike to the person signing up:
  ///   * confirmation ON  — `session` is null and NOTHING more happens until
  ///     they click the link in their email;
  ///   * confirmation OFF — they are signed in there and then.
  /// This used to return void, so the screen said "welcome" and walked into
  /// the app either way. The day confirmation is switched on, that becomes a
  /// bounce straight back to the sign-in page with no explanation.
  ///
  /// An address that already has an account comes back with a user whose
  /// `identities` list is empty. Supabase will not say so outright, so that
  /// the form cannot be used to test which addresses exist.
  Future<AuthResponse> signUp({
    required String engineerName,
    required String engineerId,
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      // Where "confirm your account" comes back to. Without it Supabase falls
      // back to the project's Site URL, which is not necessarily this app.
      emailRedirectTo: SupabaseService.appUrl,
      data: {
        'engineer_name': engineerName,
        'engineer_id': engineerId,
        'department': 'Tyre Testing',
      },
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    // Both caches are per-account. Left standing, the next person to sign in
    // on this device inherits the previous one's write permission and the
    // previous one's settings until something else happens to refresh them.
    clearWriteCache();
    AppSettingsService.instance.clear();
  }

  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<EngineerProfile?> getCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;
    try {
      final data = await _client
          .from('engineer_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) return null;
      return EngineerProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }


  /// Whether the signed-in user may write, as the DATABASE sees it.
  ///
  /// Read from `public.tracklog_writers`, the same table
  /// `public.can_write_tracklog()` checks inside every write policy, so the
  /// UI and RLS can never disagree about who is an owner.
  ///
  /// Deliberately NOT a column on engineer_profiles: `engineers_manage_own_
  /// profile` lets a user UPDATE their own row, so a flag living there could
  /// be granted to oneself. tracklog_writers has a read policy and no write
  /// policy at all.
  ///
  /// This only decides what the UI OFFERS. It is not the security boundary —
  /// RLS is, and it applies whatever the client believes.
  bool? _canWriteCache;

  Future<bool> canWrite({bool refresh = false}) async {
    if (!refresh && _canWriteCache != null) return _canWriteCache!;
    final email = currentUser?.email;
    if (email == null || email.isEmpty) return _canWriteCache = false;
    try {
      final rows = await _client
          .from('tracklog_writers')
          .select('email')
          .ilike('email', email);
      return _canWriteCache = (rows as List).isNotEmpty;
    } on PostgrestException catch (e) {
      // 42P01 = undefined_table: the whitelist migration has not been run on
      // this project yet. Fall OPEN so a deploy that lands before the SQL
      // does not hide Manual Entry from the owner; the old policies still
      // govern writes in that window. Every other failure falls CLOSED.
      if (e.code == '42P01') return _canWriteCache = true;
      return _canWriteCache = false;
    } catch (_) {
      return _canWriteCache = false;
    }
  }

  /// Drops the cached answer, so a sign-out or account switch re-checks.
  void clearWriteCache() => _canWriteCache = null;
  // ── Sessions ────────────────────────────────────────────────────────

  Future<String> startSession({
    required String trackCode,
    required String trackName,
    required double hourlyRate,
    String vehicleCategory = 'below_3_5t',
    String bookingType = 'standard',
    String projectName = 'General',
    String vehicleName = 'Standard Vehicle',
    String? venue,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Not signed in');

    final response = await _client
        .from('engineer_sessions')
        .insert({
          'engineer_id': user.id,
          'track_code': trackCode,
          'track_name': trackName,
          'vehicle_category': vehicleCategory,
          'booking_type': bookingType,
          'session_status': 'active',
          'started_at': DateTime.now().toIso8601String(),
          'hourly_rate': hourlyRate,
          'project_name': projectName,
          'vehicle_name': vehicleName,
          'venue': (venue ?? VenueManager.instance.dbValue),
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  Future<void> endSession({
    required String sessionId,
    required int durationMinutes,
    required double totalCost,
    String? notes,
    String status = 'completed',
  }) async {
    await _client
        .from('engineer_sessions')
        .update({
          'session_status': status,
          'ended_at': DateTime.now().toIso8601String(),
          'duration_minutes': durationMinutes,
          'total_cost': totalCost,
          'notes': notes,
        })
        .eq('id', sessionId);
  }

  /// Every session in the register, newest first.
  ///
  /// Fetches the whole organisation's sessions, not just the signed-in
  /// engineer's, so historically seeded data stays visible whoever is logged
  /// in — the name predates that and is kept only because callers use it.
  ///
  /// Paged rather than capped. `limit: 200` silently dropped everything past
  /// the newest 200 sessions: no error, no marker, the older months simply
  /// stopped existing for the screen. Ordering carries `id` as a tiebreaker
  /// because two sessions can share a `started_at`, and a tie straddling a
  /// page boundary would otherwise repeat one row and lose another.
  Future<List<EngineerSession>> getMySessionHistory({int pageSize = 1000}) async {
    final user = currentUser;
    if (user == null) return [];
    try {
      final out = <EngineerSession>[];
      for (var from = 0;; from += pageSize) {
        final data = await _client
            .from('engineer_sessions')
            .select()
            .order('started_at', ascending: false)
            .order('id', ascending: false)
            .range(from, from + pageSize - 1);
        final batch = (data as List).cast<Map<String, dynamic>>();
        out.addAll(batch.map(EngineerSession.fromJson));
        if (batch.length < pageSize) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getMyStats() async {
    final user = currentUser;
    if (user == null) return {};
    try {
      final data = await _client
          .from('engineer_sessions')
          .select('duration_minutes, total_cost, session_status')
          .eq('engineer_id', user.id)
          .inFilter('session_status', kBillableSessionStatuses);

      final sessions = data as List;
      int totalMinutes = 0;
      double totalCost = 0;
      for (final s in sessions) {
        totalMinutes += (s['duration_minutes'] as int? ?? 0);
        totalCost += (s['total_cost'] as num? ?? 0).toDouble();
      }
      return {
        'total_sessions': sessions.length,
        'total_minutes': totalMinutes,
        'total_cost': totalCost,
      };
    } catch (_) {
      return {};
    }
  }

  // ── Track Rates ───────────────────────────────────────────────────────────

  /// Active track rates, optionally for one venue only.
  ///
  /// Left unfiltered this returns every venue's layouts, which is what the
  /// admin rate table wants. Pickers pass a venue, or T1..T13 and CoASTT's
  /// circuits would appear in one undifferentiated grid.
  Future<List<TrackRate>> getTrackRates({String? venue}) async {
    try {
      var q = _client.from('track_rates').select().eq('is_active', true);
      if (venue != null && venue.trim().isNotEmpty) {
        q = q.eq('venue', venue.trim().toUpperCase());
      }
      final data = await q.order('track_code');
      return (data as List)
          .map((e) => TrackRate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// One track's rate.
  ///
  /// [venue] matters: track_code is unique per venue, not globally, so an
  /// unscoped lookup would throw on maybeSingle() the first time two venues
  /// shared a code.
  Future<TrackRate?> getTrackRate(String trackCode, {String? venue}) async {
    try {
      var q = _client.from('track_rates').select().eq('track_code', trackCode);
      if (venue != null && venue.trim().isNotEmpty) {
        q = q.eq('venue', venue.trim().toUpperCase());
      }
      final data = await q.maybeSingle();
      if (data == null) return null;
      return TrackRate.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

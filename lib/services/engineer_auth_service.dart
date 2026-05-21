import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

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
    );
  }
}

class TrackRate {
  final String trackCode;
  final String trackName;
  final double rateBelow3_5t;
  final double? rateAbove3_5t;
  final double? exclusiveRateBelow3_5t;
  final double? exclusiveRateAbove3_5t;
  final int minHoursPerDay;

  TrackRate({
    required this.trackCode,
    required this.trackName,
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

  Future<void> signUp({
    required String engineerName,
    required String engineerId,
    required String email,
    required String password,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
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

  // ── Sessions ──────────────────────────────────────────────────────────────

  Future<String> startSession({
    required String trackCode,
    required String trackName,
    required double hourlyRate,
    String vehicleCategory = 'below_3_5t',
    String bookingType = 'standard',
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

  Future<List<EngineerSession>> getMySessionHistory({int limit = 200}) async {
    final user = currentUser;
    if (user == null) return [];
    try {
      // Fetch all sessions for the organisation (not just current user)
      // so that historically seeded data is always visible regardless of
      // which engineer account is logged in.
      final data = await _client
          .from('engineer_sessions')
          .select()
          .order('started_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((e) => EngineerSession.fromJson(e as Map<String, dynamic>))
          .toList();
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
          .eq('session_status', 'completed');

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

  Future<List<TrackRate>> getTrackRates() async {
    try {
      final data = await _client
          .from('track_rates')
          .select()
          .eq('is_active', true)
          .order('track_code');
      return (data as List)
          .map((e) => TrackRate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<TrackRate?> getTrackRate(String trackCode) async {
    try {
      final data = await _client
          .from('track_rates')
          .select()
          .eq('track_code', trackCode)
          .maybeSingle();
      if (data == null) return null;
      return TrackRate.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import './supabase_service.dart';

class SandBagRental {
  final String id;
  final String engineerId;
  final String? sessionId;
  final int bagQuantity;
  final double dailyRate;
  final DateTime takenDate;
  final DateTime? returnDate;
  final bool isReturned;
  final double accruedCost;
  final DateTime createdAt;

  SandBagRental({
    required this.id,
    required this.engineerId,
    this.sessionId,
    required this.bagQuantity,
    required this.dailyRate,
    required this.takenDate,
    this.returnDate,
    required this.isReturned,
    required this.accruedCost,
    required this.createdAt,
  });

  factory SandBagRental.fromJson(Map<String, dynamic> json) {
    return SandBagRental(
      id: json['id'] as String,
      engineerId: json['engineer_id'] as String,
      sessionId: json['session_id'] as String?,
      bagQuantity: json['bag_quantity'] as int? ?? 0,
      dailyRate: (json['daily_rate'] as num?)?.toDouble() ?? 150.0,
      takenDate:
          DateTime.tryParse(json['taken_date'] as String? ?? '') ??
          DateTime.now(),
      returnDate: json['return_date'] != null
          ? DateTime.tryParse(json['return_date'] as String)
          : null,
      isReturned: json['is_returned'] as bool? ?? false,
      accruedCost: (json['accrued_cost'] as num?)?.toDouble() ?? 0.0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  int get daysElapsed {
    final end = returnDate ?? DateTime.now();
    return end.difference(takenDate).inDays;
  }

  double get liveCost => bagQuantity * dailyRate * daysElapsed;
}

class RentalInstrument {
  final String id;
  final String engineerId;
  final String? sessionId;
  final String instrumentName;
  final double dailyRate;
  final DateTime takenDate;
  final DateTime? returnDate;
  final bool isReturned;
  final double accruedCost;
  final DateTime createdAt;

  RentalInstrument({
    required this.id,
    required this.engineerId,
    this.sessionId,
    required this.instrumentName,
    required this.dailyRate,
    required this.takenDate,
    this.returnDate,
    required this.isReturned,
    required this.accruedCost,
    required this.createdAt,
  });

  factory RentalInstrument.fromJson(Map<String, dynamic> json) {
    return RentalInstrument(
      id: json['id'] as String,
      engineerId: json['engineer_id'] as String,
      sessionId: json['session_id'] as String?,
      instrumentName: json['instrument_name'] as String? ?? '',
      dailyRate: (json['daily_rate'] as num?)?.toDouble() ?? 0.0,
      takenDate:
          DateTime.tryParse(json['taken_date'] as String? ?? '') ??
          DateTime.now(),
      returnDate: json['return_date'] != null
          ? DateTime.tryParse(json['return_date'] as String)
          : null,
      isReturned: json['is_returned'] as bool? ?? false,
      accruedCost: (json['accrued_cost'] as num?)?.toDouble() ?? 0.0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  int get daysElapsed {
    final end = returnDate ?? DateTime.now();
    return end.difference(takenDate).inDays;
  }

  double get liveCost => dailyRate * daysElapsed;
}

class RentalService {
  static RentalService? _instance;
  static RentalService get instance => _instance ??= RentalService._();
  RentalService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  String? get _currentUserId => _client.auth.currentUser?.id;

  // ── Sand Bag Rentals ──────────────────────────────────────────────────────

  Future<String?> createSandBagRental({
    required int bagQuantity,
    required DateTime takenDate,
    String? sessionId,
    double dailyRate = 150.0,
  }) async {
    final userId = _currentUserId;
    if (userId == null) return null;
    try {
      final response = await _client
          .from('sand_bag_rentals')
          .insert({
            'engineer_id': userId,
            'session_id': sessionId,
            'bag_quantity': bagQuantity,
            'daily_rate': dailyRate,
            'taken_date': takenDate.toIso8601String().split('T').first,
            'is_returned': false,
            'accrued_cost': 0,
          })
          .select('id')
          .single();
      return response['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<List<SandBagRental>> getActiveSandBagRentals() async {
    final userId = _currentUserId;
    if (userId == null) return [];
    try {
      // Refresh costs first
      await _client.rpc('update_all_rental_costs');
      final data = await _client
          .from('sand_bag_rentals')
          .select()
          .eq('engineer_id', userId)
          .eq('is_returned', false)
          .order('taken_date', ascending: true);
      return (data as List)
          .map((e) => SandBagRental.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> returnSandBagRental(String rentalId) async {
    final userId = _currentUserId;
    if (userId == null) return false;
    try {
      final result = await _client.rpc(
        'return_sand_bag_rental',
        params: {'p_rental_id': rentalId, 'p_engineer_id': userId},
      );
      return (result as Map<String, dynamic>?)?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Rental Instruments ────────────────────────────────────────────────────

  Future<String?> createRentalInstrument({
    required String instrumentName,
    required double dailyRate,
    required DateTime takenDate,
    String? sessionId,
  }) async {
    final userId = _currentUserId;
    if (userId == null) return null;
    try {
      final response = await _client
          .from('rental_instruments')
          .insert({
            'engineer_id': userId,
            'session_id': sessionId,
            'instrument_name': instrumentName,
            'daily_rate': dailyRate,
            'taken_date': takenDate.toIso8601String().split('T').first,
            'is_returned': false,
            'accrued_cost': 0,
          })
          .select('id')
          .single();
      return response['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<List<RentalInstrument>> getActiveRentalInstruments() async {
    final userId = _currentUserId;
    if (userId == null) return [];
    try {
      final data = await _client
          .from('rental_instruments')
          .select()
          .eq('engineer_id', userId)
          .eq('is_returned', false)
          .order('taken_date', ascending: true);
      return (data as List)
          .map((e) => RentalInstrument.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> returnRentalInstrument(String rentalId) async {
    final userId = _currentUserId;
    if (userId == null) return false;
    try {
      final result = await _client.rpc(
        'return_instrument_rental',
        params: {'p_rental_id': rentalId, 'p_engineer_id': userId},
      );
      return (result as Map<String, dynamic>?)?['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Combined pending returns ──────────────────────────────────────────────

  Future<Map<String, dynamic>> getPendingReturns() async {
    final sandBags = await getActiveSandBagRentals();
    final instruments = await getActiveRentalInstruments();
    return {
      'sand_bags': sandBags,
      'instruments': instruments,
      'total_items': sandBags.length + instruments.length,
    };
  }
}

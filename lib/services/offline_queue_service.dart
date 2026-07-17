import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './supabase_service.dart';

/// Represents a single queued manual entry waiting to be synced.
class QueuedEntry {
  final String id;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  int retryCount;

  QueuedEntry({
    required this.id,
    required this.payload,
    required this.queuedAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'payload': payload,
    'queued_at': queuedAt.toIso8601String(),
    'retry_count': retryCount,
  };

  factory QueuedEntry.fromJson(Map<String, dynamic> json) => QueuedEntry(
    id: json['id'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    queuedAt: DateTime.parse(json['queued_at'] as String),
    retryCount: (json['retry_count'] as int?) ?? 0,
  );
}

/// Manages offline queuing and automatic sync of manual entries.
class OfflineQueueService {
  static OfflineQueueService? _instance;
  static OfflineQueueService get instance =>
      _instance ??= OfflineQueueService._();

  OfflineQueueService._();

  static const String _queueKey = 'offline_manual_entry_queue';
  static const int _maxRetries = 5;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;
  bool _isOnline = true;

  // Notifier so UI can react to queue changes
  final StreamController<List<QueuedEntry>> _queueController =
      StreamController<List<QueuedEntry>>.broadcast();

  Stream<List<QueuedEntry>> get queueStream => _queueController.stream;

  /// Call once at app startup (or when ManualEntryScreen is first opened).
  Future<void> initialize() async {
    // Determine initial connectivity
    final result = await Connectivity().checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    // Listen for connectivity changes
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      final wasOffline = !_isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);
      if (wasOffline && _isOnline) {
        // Just came back online — attempt sync
        syncPendingEntries();
      }
    });

    // Attempt sync on init in case we're already online with queued items
    if (_isOnline) {
      await syncPendingEntries();
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
    _queueController.close();
  }

  bool get isOnline => _isOnline;

  /// Returns all currently queued entries.
  Future<List<QueuedEntry>> getPendingEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => QueuedEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persists the queue list to SharedPreferences.
  Future<void> _saveQueue(List<QueuedEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _queueKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    _queueController.add(entries);
  }

  /// Adds a new entry to the offline queue.
  Future<void> enqueue(Map<String, dynamic> payload) async {
    final entries = await getPendingEntries();
    entries.add(
      QueuedEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        payload: payload,
        queuedAt: DateTime.now(),
      ),
    );
    await _saveQueue(entries);
  }

  /// Removes a specific entry from the queue by id.
  Future<void> _removeEntry(String id) async {
    final entries = await getPendingEntries();
    entries.removeWhere((e) => e.id == id);
    await _saveQueue(entries);
  }

  /// Attempts to sync all pending entries to Supabase.
  /// Safe to call multiple times — guards against concurrent runs.
  Future<SyncResult> syncPendingEntries() async {
    if (_isSyncing) return SyncResult(synced: 0, failed: 0);
    _isSyncing = true;

    int synced = 0;
    int failed = 0;

    try {
      final entries = await getPendingEntries();
      if (entries.isEmpty) return SyncResult(synced: 0, failed: 0);

      for (final entry in List<QueuedEntry>.from(entries)) {
        try {
          await SupabaseService.instance.client
              .from('engineer_sessions')
              .insert(entry.payload);
          await _removeEntry(entry.id);
          synced++;
        } catch (_) {
          entry.retryCount++;
          if (entry.retryCount >= _maxRetries) {
            // Give up after max retries — remove to avoid infinite loop
            await _removeEntry(entry.id);
          } else {
            // Update retry count in storage
            final current = await getPendingEntries();
            final idx = current.indexWhere((e) => e.id == entry.id);
            if (idx != -1) {
              current[idx] = entry;
              await _saveQueue(current);
            }
          }
          failed++;
        }
      }
    } finally {
      _isSyncing = false;
    }

    return SyncResult(synced: synced, failed: failed);
  }

  /// Returns the count of pending entries.
  Future<int> getPendingCount() async {
    final entries = await getPendingEntries();
    return entries.length;
  }
}

class SyncResult {
  final int synced;
  final int failed;
  SyncResult({required this.synced, required this.failed});
}

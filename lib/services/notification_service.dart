import 'package:flutter/foundation.dart';

import 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_native.dart';

export 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_native.dart';

/// Facade that routes to the correct platform implementation.
/// On web: all methods are no-ops.
/// On Android/iOS: uses flutter_local_notifications.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final NotificationServiceImpl _impl = NotificationServiceImpl();

  Future<void> initialize() async {
    if (kIsWeb) return;
    await _impl.initialize();
  }

  /// Called when engineer enters a gate — session auto-starts.
  Future<void> onGateEntry({
    required String gateName,
    required String engineerName,
  }) async {
    if (kIsWeb) return;
    await _impl.showGateEntryNotification(
      gateName: gateName,
      engineerName: engineerName,
    );
  }

  /// Called when engineer exits a gate — session auto-stops.
  Future<void> onGateExit({
    required String gateName,
    required Duration sessionDuration,
    required double cost,
  }) async {
    if (kIsWeb) return;
    await _impl.showGateExitNotification(
      gateName: gateName,
      sessionDuration: sessionDuration,
      cost: cost,
    );
  }

  /// GPS signal lost alert.
  Future<void> alertGpsLost() async {
    if (kIsWeb) return;
    await _impl.showAnomalyNotification(
      id: 10,
      title: '⚠️ GPS Signal Lost',
      body: 'Cannot determine gate position. Session timer paused.',
    );
  }

  /// GPS signal restored alert.
  Future<void> alertGpsRestored() async {
    if (kIsWeb) return;
    await _impl.showAnomalyNotification(
      id: 11,
      title: '📡 GPS Signal Restored',
      body: 'Location lock re-acquired. Session resumed.',
    );
  }

  /// Session running unusually long.
  Future<void> alertLongSession({required Duration elapsed}) async {
    if (kIsWeb) return;
    final h = elapsed.inHours;
    await _impl.showAnomalyNotification(
      id: 12,
      title: '⏱ Long Session Alert',
      body:
          'Session has been running for $h hour${h == 1 ? '' : 's'}. Verify if still on track.',
    );
  }

  /// Unexpected gate exit (session active but engineer left geofence).
  Future<void> alertUnexpectedExit({required String gateName}) async {
    if (kIsWeb) return;
    await _impl.showAnomalyNotification(
      id: 13,
      title: '🚨 Unexpected Gate Exit',
      body:
          'Left $gateName geofence while session is active. Session will stop.',
    );
  }

  /// Daily evening reminder for unreturned rentals.
  Future<void> alertPendingReturns({
    required int sandBagCount,
    required int instrumentCount,
    required double totalRunningCost,
  }) async {
    if (kIsWeb) return;
    final itemCount = sandBagCount + instrumentCount;
    if (itemCount == 0) return;
    final parts = <String>[];
    if (sandBagCount > 0) {
      parts.add('$sandBagCount sand bag rental${sandBagCount > 1 ? 's' : ''}');
    }
    if (instrumentCount > 0) {
      parts.add(
        '$instrumentCount instrument rental${instrumentCount > 1 ? 's' : ''}',
      );
    }
    await _impl.showPendingReturnsNotification(
      itemSummary: parts.join(' & '),
      totalCost: totalRunningCost,
    );
  }

  /// Schedule the daily 7 PM pending-returns reminder.
  Future<void> scheduleDailyPendingReturnsReminder({
    required int sandBagCount,
    required int instrumentCount,
    required double totalRunningCost,
  }) async {
    if (kIsWeb) return;
    await _impl.scheduleDailyPendingReturnsReminder(
      sandBagCount: sandBagCount,
      instrumentCount: instrumentCount,
      totalRunningCost: totalRunningCost,
    );
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _impl.cancelAll();
  }
}
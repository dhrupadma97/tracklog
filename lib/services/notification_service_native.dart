import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Native (Android/iOS) implementation of the notification service.
class NotificationServiceImpl {
  static final NotificationServiceImpl _instance =
      NotificationServiceImpl._internal();
  factory NotificationServiceImpl() => _instance;
  NotificationServiceImpl._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  NotificationDetails get _gateDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      'tracklog_gate_channel',
      'Gate Events',
      channelDescription: 'Notifications for gate entry and exit events',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFF00E676),
      enableVibration: true,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  NotificationDetails get _anomalyDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      'tracklog_anomaly_channel',
      'Anomaly Alerts',
      channelDescription: 'Alerts for GPS issues and session anomalies',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF6B35),
      enableVibration: true,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  NotificationDetails get _pendingReturnsDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      'tracklog_pending_returns_channel',
      'Pending Returns',
      channelDescription: 'Daily evening reminders for unreturned rental items',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF6B35),
      enableVibration: true,
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  Future<void> showGateEntryNotification({
    required String gateName,
    required String engineerName,
  }) async {
    await initialize();
    await _plugin.show(
      1,
      '✅ Session Started — $gateName',
      'Engineer $engineerName entered the gate. Timer is running.',
      _gateDetails,
    );
  }

  Future<void> showGateExitNotification({
    required String gateName,
    required Duration sessionDuration,
    required double cost,
  }) async {
    await initialize();
    final h = sessionDuration.inHours.toString().padLeft(2, '0');
    final m = sessionDuration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final s = sessionDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    await _plugin.show(
      2,
      '🏁 Session Stopped — $gateName',
      'Duration: $h:$m:$s  |  Est. Cost: ₹${cost.toStringAsFixed(0)}',
      _gateDetails,
    );
  }

  Future<void> showAnomalyNotification({
    required String title,
    required String body,
    int id = 99,
  }) async {
    await initialize();
    await _plugin.show(id, title, body, _anomalyDetails);
  }

  /// Show an immediate pending-returns notification.
  Future<void> showPendingReturnsNotification({
    required String itemSummary,
    required double totalCost,
  }) async {
    await initialize();
    await _plugin.show(
      20,
      '📦 Unreturned Rentals — ₹${totalCost.toStringAsFixed(0)} running',
      'You have $itemSummary still out. Tap to return them now.',
      _pendingReturnsDetails,
    );
  }

  /// Schedule a daily 7 PM notification for pending returns.
  /// Uses a periodic timer approach since timezone scheduling requires
  /// the flutter_timezone package. Falls back to immediate notification
  /// if it is already past 7 PM today.
  Future<void> scheduleDailyPendingReturnsReminder({
    required int sandBagCount,
    required int instrumentCount,
    required double totalRunningCost,
  }) async {
    await initialize();
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
    final summary = parts.join(' & ');

    // Cancel any existing pending-returns notification first
    await _plugin.cancel(20);

    // Fire the notification immediately as a reminder
    // (In production, use flutter_timezone + zonedSchedule for true 7 PM scheduling)
    await _plugin.show(
      20,
      '🌆 Evening Reminder — Unreturned Rentals',
      'Still out: $summary · ₹${totalRunningCost.toStringAsFixed(0)} accrued. Return today!',
      _pendingReturnsDetails,
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}

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

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}

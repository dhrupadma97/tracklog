/// Stub implementation for web platform — notifications are no-ops on web.
class NotificationServiceImpl {
  Future<void> initialize() async {}

  Future<void> showGateEntryNotification({
    required String gateName,
    required String engineerName,
  }) async {}

  Future<void> showGateExitNotification({
    required String gateName,
    required Duration sessionDuration,
    required double cost,
  }) async {}

  Future<void> showAnomalyNotification({
    required String title,
    required String body,
    int id = 99,
  }) async {}

  Future<void> showPendingReturnsNotification({
    required String itemSummary,
    required double totalCost,
  }) async {}

  Future<void> scheduleDailyPendingReturnsReminder({
    required int sandBagCount,
    required int instrumentCount,
    required double totalRunningCost,
  }) async {}

  Future<void> cancelAll() async {}
}

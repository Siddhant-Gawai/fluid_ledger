import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:intl/intl.dart';
import '../settings/notification_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _schedulingAvailable = true;

  // Channel IDs
  static const _spendingChannel = 'spending_alerts';
  static const _syncChannel = 'sync_updates';
  static const _reminderChannel = 'daily_reminders';

  /// Initialize the notification service — call once in main.dart
  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    await _configureLocalTimezone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(initSettings);

    // Create notification channels
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _spendingChannel,
          'Spending Alerts',
          description: 'Alerts when spending crosses thresholds',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _syncChannel,
          'Sync Updates',
          description: 'Updates after SMS sync',
          importance: Importance.defaultImportance,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannel,
          'Daily Reminders',
          description: 'Daily spending summary and reminders',
          importance: Importance.defaultImportance,
        ),
      );
    }

    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Instant notifications
  // ---------------------------------------------------------------------------

  /// Show after SMS sync completes
  Future<void> showSyncComplete({
    required int added,
    required int skipped,
    required double totalAmount,
  }) async {
    if (!await NotificationPreferences.instance.syncAlertsEnabled()) return;
    final fmt = NumberFormat('#,##,###', 'en_IN');
    await _show(
      id: 1,
      channel: _syncChannel,
      title: '✅ Sync Complete',
      body:
          '$added transactions added (₹${fmt.format(totalAmount.round())})'
          '${skipped > 0 ? ' · $skipped duplicates skipped' : ''}',
    );
  }

  /// Show when monthly spending crosses a threshold
  Future<void> showSpendingAlert({
    required double totalSpent,
    required double threshold,
  }) async {
    if (!await NotificationPreferences.instance.insightsEnabled()) return;
    final fmt = NumberFormat('#,##,###', 'en_IN');
    final pct = ((totalSpent / threshold) * 100).round();
    await _show(
      id: 2,
      channel: _spendingChannel,
      title: '⚠️ Spending Alert',
      body:
          'You\'ve spent ₹${fmt.format(totalSpent.round())} this month ($pct% of ₹${fmt.format(threshold.round())} budget)',
    );
  }

  /// Show after manual expense is added
  Future<void> showExpenseAdded({
    required double amount,
    required String category,
    required String emoji,
  }) async {
    if (!await NotificationPreferences.instance.syncAlertsEnabled()) return;
    final fmt = NumberFormat('#,##,###', 'en_IN');
    await _show(
      id: 3,
      channel: _syncChannel,
      title: '$emoji Expense Logged',
      body: '₹${fmt.format(amount.round())} added to $category',
    );
  }

  /// Generic info notification
  Future<void> showInfo({required String title, required String body}) async {
    if (!await NotificationPreferences.instance.remindersEnabled()) return;
    await _show(id: 10, channel: _reminderChannel, title: title, body: body);
  }

  // ---------------------------------------------------------------------------
  // Scheduled notifications
  // ---------------------------------------------------------------------------

  /// Schedule daily spending reminder at 9 PM
  Future<void> scheduleDailyReminder() async {
    if (!_schedulingAvailable) return;
    if (!await NotificationPreferences.instance.remindersEnabled()) {
      await _plugin.cancel(100);
      return;
    }
    await _plugin.zonedSchedule(
      100,
      '📊 Daily Check-in',
      'How was your spending today? Tap to review.',
      _nextInstanceOfTime(21, 0), // 9:00 PM
      NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannel,
          'Daily Reminders',
          channelDescription: 'Daily spending summary and reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repeats daily
    );
  }

  /// Schedule weekly summary on Sunday at 10 AM
  Future<void> scheduleWeeklySummary() async {
    if (!_schedulingAvailable) return;
    if (!await NotificationPreferences.instance.insightsEnabled()) {
      await _plugin.cancel(101);
      return;
    }
    await _plugin.zonedSchedule(
      101,
      '📈 Weekly Summary Ready',
      'Your weekly spending report is waiting. Tap to see insights.',
      _nextInstanceOfDayAndTime(DateTime.sunday, 10, 0),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannel,
          'Daily Reminders',
          channelDescription: 'Daily spending summary and reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      _schedulingAvailable = false;
    }
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Cancel a specific notification
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _show({
    required int id,
    required String channel,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          channel == _spendingChannel
              ? 'Spending Alerts'
              : channel == _syncChannel
              ? 'Sync Updates'
              : 'Daily Reminders',
          importance: channel == _spendingChannel
              ? Importance.high
              : Importance.defaultImportance,
          priority: channel == _spendingChannel
              ? Priority.high
              : Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfDayAndTime(int dayOfWeek, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != dayOfWeek) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}

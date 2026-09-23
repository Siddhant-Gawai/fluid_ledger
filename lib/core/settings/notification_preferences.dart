import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferences {
  NotificationPreferences._();
  static final NotificationPreferences instance = NotificationPreferences._();

  static const _kReminders = 'notif_reminders_enabled';
  static const _kInsights = 'notif_insights_enabled';
  static const _kSyncAlerts = 'notif_sync_enabled';

  Future<bool> remindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kReminders) ?? true;
  }

  Future<bool> insightsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kInsights) ?? true;
  }

  Future<bool> syncAlertsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSyncAlerts) ?? true;
  }

  Future<void> setRemindersEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReminders, value);
  }

  Future<void> setInsightsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kInsights, value);
  }

  Future<void> setSyncAlertsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSyncAlerts, value);
  }
}

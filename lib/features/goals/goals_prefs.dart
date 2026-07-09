import 'package:shared_preferences/shared_preferences.dart';

// Device-local settings for the practice goals & reminder feature.
class GoalsPrefs {
  static const _kWeeklyGoal = 'goals_weekly_target';
  static const _kReminderOn = 'goals_reminder_enabled';
  static const _kReminderHour = 'goals_reminder_hour';
  static const _kReminderMinute = 'goals_reminder_minute';

  int weeklyGoal;
  bool reminderEnabled;
  int reminderHour;
  int reminderMinute;

  GoalsPrefs({
    required this.weeklyGoal,
    required this.reminderEnabled,
    required this.reminderHour,
    required this.reminderMinute,
  });

  static Future<GoalsPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return GoalsPrefs(
      weeklyGoal: p.getInt(_kWeeklyGoal) ?? 5,
      reminderEnabled: p.getBool(_kReminderOn) ?? false,
      reminderHour: p.getInt(_kReminderHour) ?? 19,
      reminderMinute: p.getInt(_kReminderMinute) ?? 0,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kWeeklyGoal, weeklyGoal);
    await p.setBool(_kReminderOn, reminderEnabled);
    await p.setInt(_kReminderHour, reminderHour);
    await p.setInt(_kReminderMinute, reminderMinute);
  }
}

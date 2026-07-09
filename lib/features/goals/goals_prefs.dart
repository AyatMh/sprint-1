import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// A single practice reminder: fires weekly on [weekday] at [hour]:[minute].
class PracticeReminder {
  final int weekday; // 1 = Monday … 7 = Sunday (matches DateTime.weekday)
  final int hour;
  final int minute;

  const PracticeReminder({
    required this.weekday,
    required this.hour,
    required this.minute,
  });

  Map<String, dynamic> toMap() =>
      {'weekday': weekday, 'hour': hour, 'minute': minute};

  factory PracticeReminder.fromMap(Map<String, dynamic> m) => PracticeReminder(
        weekday: (m['weekday'] ?? 1) as int,
        hour: (m['hour'] ?? 19) as int,
        minute: (m['minute'] ?? 0) as int,
      );
}

// Device-local settings for the practice goals & reminders feature.
class GoalsPrefs {
  static const _kWeeklyGoal = 'goals_weekly_target';
  static const _kReminders = 'goals_reminders_json';

  int weeklyGoal;
  List<PracticeReminder> reminders;

  GoalsPrefs({required this.weeklyGoal, required this.reminders});

  static Future<GoalsPrefs> load() async {
    final p = await SharedPreferences.getInstance();

    final reminders = <PracticeReminder>[];
    final raw = p.getString(_kReminders);
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List) {
          reminders.add(PracticeReminder.fromMap(Map<String, dynamic>.from(e)));
        }
      } catch (_) {
        // Corrupt/older value — start with no reminders.
      }
    }

    return GoalsPrefs(
      weeklyGoal: p.getInt(_kWeeklyGoal) ?? 5,
      reminders: reminders,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kWeeklyGoal, weeklyGoal);
    await p.setString(
      _kReminders,
      jsonEncode(reminders.map((r) => r.toMap()).toList()),
    );
  }
}

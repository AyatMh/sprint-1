import 'package:flutter/material.dart';
import '../../data/models/recording.dart';

// Practice habit metrics derived from a user's recordings: streak, whether
// they've practiced today, and how many sessions this week.
class GoalsStats {
  final int currentStreak; // consecutive days ending today/yesterday
  final bool practicedToday;
  final int thisWeekCount; // sessions in the last 7 days (incl. today)
  final int totalCount;

  const GoalsStats({
    required this.currentStreak,
    required this.practicedToday,
    required this.thisWeekCount,
    required this.totalCount,
  });

  factory GoalsStats.fromRecordings(List<Recording> recordings, DateTime now) {
    final today = DateUtils.dateOnly(now);
    final days = recordings
        .map((r) => DateUtils.dateOnly(r.createdAt))
        .toSet();

    final practicedToday = days.contains(today);

    // Count back from today (or yesterday, so a fresh morning doesn't reset
    // the streak) while each consecutive day has a session.
    var cursor = practicedToday
        ? today
        : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final weekStart = today.subtract(const Duration(days: 6));
    final thisWeek = recordings
        .where((r) => !DateUtils.dateOnly(r.createdAt).isBefore(weekStart))
        .length;

    return GoalsStats(
      currentStreak: streak,
      practicedToday: practicedToday,
      thisWeekCount: thisWeek,
      totalCount: recordings.length,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/recording.dart';
import '../../data/repositories/recording_repository.dart';
import '../../data/services/notification_service.dart';
import '../../shared/widgets/glass.dart';
import '../auth/providers/auth_provider.dart';
import 'goals_prefs.dart';
import 'goals_stats.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  GoalsPrefs? _prefs;

  @override
  void initState() {
    super.initState();
    GoalsPrefs.load().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  Future<void> _setGoal(int value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() => prefs.weeklyGoal = value.clamp(1, 14));
    await prefs.save();
  }

  Future<void> _toggleReminder(bool on) async {
    final prefs = _prefs;
    if (prefs == null) return;

    if (on) {
      final granted = await NotificationService.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Notifications are turned off for InterviewPro. Enable them in system settings.'),
            ),
          );
        }
        return;
      }
      await NotificationService.scheduleDailyReminder(
        hour: prefs.reminderHour,
        minute: prefs.reminderMinute,
      );
    } else {
      await NotificationService.cancelReminder();
    }

    setState(() => prefs.reminderEnabled = on);
    await prefs.save();
  }

  Future<void> _pickTime() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: prefs.reminderHour, minute: prefs.reminderMinute),
    );
    if (picked == null) return;
    setState(() {
      prefs.reminderHour = picked.hour;
      prefs.reminderMinute = picked.minute;
    });
    await prefs.save();
    if (prefs.reminderEnabled) {
      await NotificationService.scheduleDailyReminder(
        hour: picked.hour,
        minute: picked.minute,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            bottom: false,
            child: (userId == null || _prefs == null)
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<Recording>>(
                    stream: RecordingRepository().watchRecordings(userId),
                    builder: (context, snapshot) {
                      final recordings = snapshot.data ?? [];
                      final stats = GoalsStats.fromRecordings(
                        recordings,
                        DateTime.now(),
                      );
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
                        children: [
                          _topBar(context),
                          const SizedBox(height: 18),
                          _streakCard(stats),
                          const SizedBox(height: 14),
                          _weeklyGoalCard(stats),
                          const SizedBox(height: 14),
                          _reminderCard(),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: AppColors.wine),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 12),
        const Text(
          'Practice goals',
          style: TextStyle(
            color: AppColors.wine,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _streakCard(GoalsStats stats) {
    final n = stats.currentStreak;
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF7A00).withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
              ],
            ),
            child: const Icon(Icons.local_fire_department_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n == 0 ? 'No streak yet' : '$n day${n == 1 ? '' : 's'} streak',
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stats.practicedToday
                      ? 'You practiced today 🎉'
                      : 'Practice today to keep it going.',
                  style: const TextStyle(
                    color: AppColors.midMauve,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyGoalCard(GoalsStats stats) {
    final goal = _prefs!.weeklyGoal;
    final done = stats.thisWeekCount;
    final progress = goal > 0 ? (done / goal).clamp(0.0, 1.0) : 0.0;
    final reached = done >= goal;

    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded,
                  size: 18, color: AppColors.deepMauve),
              const SizedBox(width: 8),
              const Text(
                'Weekly goal',
                style: TextStyle(
                  color: AppColors.wine,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$done / $goal',
                style: TextStyle(
                  color: reached ? AppColors.success : AppColors.wine,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.paleMauve,
              valueColor: AlwaysStoppedAnimation(
                reached ? AppColors.success : AppColors.deepMauve,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                reached
                    ? 'Goal reached — great week! 🎯'
                    : '${goal - done} more session${goal - done == 1 ? '' : 's'} to go this week.',
                style: const TextStyle(
                  color: AppColors.midMauve,
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              _stepButton(Icons.remove_rounded,
                  onTap: goal > 1 ? () => _setGoal(goal - 1) : null),
              const SizedBox(width: 10),
              _stepButton(Icons.add_rounded,
                  onTap: goal < 14 ? () => _setGoal(goal + 1) : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.paleMauve : AppColors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.8),
        ),
        child: Icon(icon,
            size: 18,
            color: onTap == null ? AppColors.softMauve : AppColors.deepMauve),
      ),
    );
  }

  Widget _reminderCard() {
    final prefs = _prefs!;
    final time = TimeOfDay(hour: prefs.reminderHour, minute: prefs.reminderMinute);
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  size: 18, color: AppColors.deepMauve),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Daily reminder',
                  style: TextStyle(
                    color: AppColors.wine,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: prefs.reminderEnabled,
                onChanged: _toggleReminder,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Get a gentle nudge to practice at the same time every day.',
            style: TextStyle(
              color: AppColors.midMauve,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (prefs.reminderEnabled) ...[
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 18, color: AppColors.midMauve),
                    const SizedBox(width: 10),
                    const Text(
                      'Reminder time',
                      style: TextStyle(
                        color: AppColors.wine,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      time.format(context),
                      style: const TextStyle(
                        color: AppColors.deepMauve,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.softMauve, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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

  static const List<String> _dayNames = [
    '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    'Saturday', 'Sunday',
  ];

  Future<void> _setGoal(int value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() => prefs.weeklyGoal = value.clamp(1, 99));
    await prefs.save();
  }

  // Lets the user type an exact weekly goal instead of tapping +/-.
  Future<void> _editGoalDialog() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final controller = TextEditingController(text: '${prefs.weeklyGoal}');
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Weekly goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Recordings per week',
            suffixText: 'sessions',
          ),
          onSubmitted: (s) => Navigator.of(ctx).pop(int.tryParse(s.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && value > 0) await _setGoal(value);
  }

  // Reschedules every reminder in the current list (or clears them all).
  Future<void> _reschedule() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await NotificationService.scheduleReminders(
      prefs.reminders
          .map((r) => (weekday: r.weekday, hour: r.hour, minute: r.minute))
          .toList(),
    );
  }

  Future<void> _addReminder() async {
    final prefs = _prefs;
    if (prefs == null) return;

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
    if (!mounted) return;

    final weekday = await _pickWeekday(DateTime.now().weekday);
    if (weekday == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (time == null) return;

    setState(() => prefs.reminders.add(PracticeReminder(
          weekday: weekday,
          hour: time.hour,
          minute: time.minute,
        )));
    await prefs.save();
    await _reschedule();
  }

  Future<void> _editReminder(int index) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final current = prefs.reminders[index];

    final weekday = await _pickWeekday(current.weekday);
    if (weekday == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time == null) return;

    setState(() => prefs.reminders[index] = PracticeReminder(
          weekday: weekday,
          hour: time.hour,
          minute: time.minute,
        ));
    await prefs.save();
    await _reschedule();
  }

  Future<void> _deleteReminder(int index) async {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() => prefs.reminders.removeAt(index));
    await prefs.save();
    await _reschedule();
  }

  // Simple day-of-week chooser. Returns 1 (Mon) … 7 (Sun) or null.
  Future<int?> _pickWeekday(int initial) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Which day?'),
        children: [
          for (var d = 1; d <= 7; d++)
            ListTile(
              title: Text(_dayNames[d]),
              trailing: d == initial
                  ? const Icon(Icons.check_rounded, color: AppColors.deepMauve)
                  : null,
              onTap: () => Navigator.of(ctx).pop(d),
            ),
        ],
      ),
    );
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
              // Tap the number to type an exact goal.
              InkWell(
                onTap: _editGoalDialog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '$done / $goal',
                        style: TextStyle(
                          color: reached ? AppColors.success : AppColors.wine,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined,
                          size: 14, color: AppColors.midMauve),
                    ],
                  ),
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
                  onTap: goal < 99 ? () => _setGoal(goal + 1) : null),
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
    final reminders = _prefs!.reminders;
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.notifications_active_rounded,
                  size: 18, color: AppColors.deepMauve),
              SizedBox(width: 8),
              Text(
                'Reminders',
                style: TextStyle(
                  color: AppColors.wine,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick the day and time for each reminder. Each one repeats weekly.',
            style: TextStyle(
              color: AppColors.midMauve,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),

          if (reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No reminders yet.',
                style: TextStyle(color: AppColors.softMauve, fontSize: 13),
              ),
            )
          else
            for (var i = 0; i < reminders.length; i++) ...[
              _reminderRow(i, reminders[i]),
              const SizedBox(height: 8),
            ],

          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addReminder,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add reminder'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reminderRow(int index, PracticeReminder r) {
    final time = TimeOfDay(hour: r.hour, minute: r.minute);
    return InkWell(
      onTap: () => _editReminder(index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            Expanded(
              child: Text(
                '${_dayNames[r.weekday]} · ${time.format(context)}',
                style: const TextStyle(
                  color: AppColors.wine,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AppColors.midMauve,
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteReminder(index),
            ),
          ],
        ),
      ),
    );
  }
}

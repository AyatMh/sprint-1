import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum RecordingMode { regular, withQuestions }

// Lets the user choose between a plain recording and one where the AI coach
// asks questions from their question bank. Only shown when the picked
// category actually has saved questions — otherwise recording starts as
// "regular" immediately, with no extra friction.
Future<RecordingMode?> showRecordingModeSheet(
  BuildContext context, {
  required int questionCount,
}) {
  return showModalBottomSheet<RecordingMode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecordingModeSheet(questionCount: questionCount),
  );
}

class _RecordingModeSheet extends StatelessWidget {
  final int questionCount;
  const _RecordingModeSheet({required this.questionCount});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: size.height * 0.8),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: (size.width * 0.06).clamp(16.0, 32.0),
            vertical: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.paleMauve,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'How do you want to practice?',
                style: TextStyle(
                  color: AppColors.wine,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Record freely, or have the AI coach ask you questions one by one.',
                style: TextStyle(
                  color: AppColors.midMauve,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _ModeCard(
                icon: Icons.videocam_rounded,
                title: 'Regular recording',
                subtitle: 'Record freely, no prompts.',
                colors: const [Color(0xFF64708B), Color(0xFF8C99B3)],
                onTap: () => Navigator.of(context).pop(RecordingMode.regular),
              ),
              const SizedBox(height: 12),
              _ModeCard(
                icon: Icons.auto_awesome_rounded,
                title: 'With AI coach questions',
                subtitle: questionCount == 0
                    ? 'No questions saved yet for this category — you can add some next.'
                    : '$questionCount question${questionCount == 1 ? '' : 's'} available in this category — choose which to use.',
                colors: const [Color(0xFF5E6AD2), Color(0xFF8C99F0)],
                onTap: () =>
                    Navigator.of(context).pop(RecordingMode.withQuestions),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paleMauve,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.wine,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.midMauve,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.softMauve, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/interview_question.dart';
import '../../data/repositories/question_repository.dart';
import '../../data/repositories/recording_repository.dart';
import '../../live_simulation_screen.dart';
import '../auth/providers/auth_provider.dart';
import '../questions/screens/question_bank_screen.dart';
import 'providers/recording_provider.dart';
import 'widgets/category_picker_dialog.dart';
import 'widgets/question_picker_sheet.dart';
import 'widgets/recording_mode_sheet.dart';

// Fetches the questions saved for [category], if any. Failures are treated
// as "no questions" — the AI coach step is simply skipped.
Future<List<InterviewQuestion>> _questionsForCategory(
  String userId,
  String category,
) async {
  try {
    final all = await QuestionRepository().watchQuestions(userId).first;
    return all.where((q) => q.categories.contains(category)).toList();
  } catch (_) {
    return [];
  }
}

// Offers to add questions right now when the picked category doesn't have
// any yet, instead of silently skipping the AI coach for a category the
// user may simply not have gotten around to filling in. Returns true if the
// user went to add questions (caller should re-check for new ones).
Future<bool> _offerToAddQuestions(BuildContext context, String category) async {
  final wantsToAdd = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.auto_awesome_rounded,
          color: AppColors.deepMauve, size: 32),
      title: Text('No questions yet for "$category"'),
      content: const Text(
        'Add a few and the AI coach can ask them during this recording. '
        'You can always add more later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add questions'),
        ),
      ],
    ),
  );

  if (wantsToAdd != true || !context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => QuestionBankScreen(filterCategory: category),
    ),
  );
  return true;
}

// Shared entry point for starting a practice session: collects the user's
// own categories, lets them pick (or create) one, then opens the live
// simulation screen. Used by the Home hero CTA and the Recordings "+".
Future<void> startPracticeSession(BuildContext context) async {
  final userId = context.read<AuthProvider>().user?.uid;

  // Load the user's previously used categories lazily so the picker opens
  // instantly instead of waiting on a Firestore round-trip first.
  Future<List<String>> loadCategories() async {
    if (userId == null) return [];
    final recordings =
        await RecordingRepository().watchRecordings(userId).first;
    final used = <String>{};
    for (final r in recordings) {
      if (r.category.trim().isNotEmpty) {
        used.add(r.category.trim());
      }
    }
    return used.toList()..sort();
  }

  final selectedCategory = await showCategoryPicker(
    context,
    categoriesFuture: loadCategories(),
  );
  if (selectedCategory == null) return;

  // Always let the user choose between a regular recording and one where the
  // AI coach asks questions — even when this category has none yet. Only if
  // they pick "with questions" do we then either let them choose which ones
  // (if some exist) or offer to add some on the spot (if none do).
  List<InterviewQuestion> questionsToUse = [];
  if (userId != null) {
    var categoryQuestions = await _questionsForCategory(userId, selectedCategory);

    if (!context.mounted) return;
    final mode = await showRecordingModeSheet(
      context,
      questionCount: categoryQuestions.length,
    );
    if (mode == null) return; // backed out of the sheet

    if (mode == RecordingMode.withQuestions) {
      if (categoryQuestions.isEmpty) {
        if (!context.mounted) return;
        final wentToAdd = await _offerToAddQuestions(context, selectedCategory);
        if (wentToAdd) {
          if (!context.mounted) return;
          categoryQuestions =
              await _questionsForCategory(userId, selectedCategory);
        }
      }

      if (categoryQuestions.isNotEmpty) {
        if (!context.mounted) return;
        final picked = await showQuestionPickerSheet(
          context,
          questions: categoryQuestions,
        );
        if (picked == null) return; // backed out of picking questions
        questionsToUse = picked;
      }
      // Otherwise still no questions after being offered — fall back to a
      // regular recording (questionsToUse stays empty).
    }
  }

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => RecordingProvider(),
        child: LiveSimulationScreen(
          initialCategory: selectedCategory,
          questions: questionsToUse,
        ),
      ),
    ),
  );
}

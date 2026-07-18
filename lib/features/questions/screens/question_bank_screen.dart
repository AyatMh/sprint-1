import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/interview_question.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../../shared/widgets/glass.dart';
import '../../auth/providers/auth_provider.dart';

// Label used for questions saved without any category.
const String _kUncategorized = 'General';

// The user's personal interview-question bank. A question can belong to more
// than one category. These are the questions the AI coach asks (one at a
// time, as text on screen) during a recording whose category matches.
//
// When [filterCategory] is given, the screen is scoped to just that
// category's questions (used when opening this from inside a category, e.g.
// from the Recordings screen) instead of showing every category grouped.
class QuestionBankScreen extends StatefulWidget {
  final String? filterCategory;

  const QuestionBankScreen({super.key, this.filterCategory});

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  final _repo = QuestionRepository();

  // Existing category names, pooled from both saved questions and past
  // recordings, so the add dialog can suggest a consistent set.
  Future<List<String>> _loadCategorySuggestions(
    String userId,
    List<InterviewQuestion> questions,
  ) async {
    final cats = <String>{for (final q in questions) ...q.categories}
      ..removeWhere((c) => c.isEmpty || c == _kUncategorized);
    try {
      final recordings =
          await RecordingRepository().watchRecordings(userId).first;
      for (final r in recordings) {
        if (r.category.trim().isNotEmpty) cats.add(r.category.trim());
      }
    } catch (_) {
      // Suggestions are a nice-to-have; ignore failures.
    }
    return cats.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // Adding supports queuing up several questions in one go — type one, tap +
  // (or press enter) to add it to the list below, and keep going — then tag
  // all of them with the same categories in a single save. Mirrors the
  // category chip-adder just below it. Editing stays scoped to the one
  // existing question.
  Future<void> _addOrEditQuestion(
    String userId, {
    InterviewQuestion? existing,
    required List<String> categorySuggestions,
    String? presetCategory,
  }) async {
    final isBulkAdd = existing == null;
    final textController = TextEditingController(text: existing?.text ?? '');
    final newCatController = TextEditingController();
    final pendingQuestions = <String>[];
    final selected = <String>{
      ...?existing?.categories,
      if (existing == null && presetCategory != null) presetCategory,
    };

    final result =
        await showDialog<({List<String> texts, List<String> categories})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          void addCategory(String raw) {
            final c = raw.trim();
            if (c.isEmpty) return;
            setLocalState(() => selected.add(c));
            newCatController.clear();
          }

          void addQuestionText(String raw) {
            final t = raw.trim();
            if (t.isEmpty) return;
            setLocalState(() => pendingQuestions.add(t));
            textController.clear();
          }

          final suggestions =
              categorySuggestions.where((c) => !selected.contains(c)).toList();
          final leftover = textController.text.trim();
          final totalCount = pendingQuestions.length + (leftover.isEmpty ? 0 : 1);
          final canSave = isBulkAdd ? totalCount > 0 : leftover.isNotEmpty;

          return AlertDialog(
            title: Text(isBulkAdd ? 'Add questions' : 'Edit question'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBulkAdd) ...[
                    const Text(
                      'Type a question, tap + to add it, then keep going.',
                      style: TextStyle(
                        color: AppColors.midMauve,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: textController,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: isBulkAdd ? (_) => setLocalState(() {}) : null,
                    onSubmitted: isBulkAdd ? addQuestionText : null,
                    decoration: InputDecoration(
                      labelText: 'Question',
                      hintText:
                          'e.g. Tell me about a time you handled conflict.',
                      suffixIcon: isBulkAdd
                          ? IconButton(
                              icon: const Icon(Icons.add_circle_rounded),
                              color: AppColors.deepMauve,
                              tooltip: 'Add question',
                              onPressed: () =>
                                  addQuestionText(textController.text),
                            )
                          : null,
                    ),
                  ),
                  if (isBulkAdd && pendingQuestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${pendingQuestions.length} question'
                      '${pendingQuestions.length == 1 ? '' : 's'} added',
                      style: const TextStyle(
                        color: AppColors.midMauve,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (var i = 0; i < pendingQuestions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.paleMauve,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: AppColors.deepMauve,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pendingQuestions[i],
                                  style: const TextStyle(
                                    color: AppColors.wine,
                                    fontSize: 13.5,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => setLocalState(
                                    () => pendingQuestions.removeAt(i)),
                                child: const Padding(
                                  padding: EdgeInsets.only(left: 6, top: 1),
                                  child: Icon(Icons.close_rounded,
                                      size: 18, color: AppColors.midMauve),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Categories',
                    style: TextStyle(
                      color: AppColors.midMauve,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isBulkAdd
                        ? 'Applied to every question above. A question can '
                            'belong to more than one category.'
                        : 'A question can belong to more than one category.',
                    style: const TextStyle(
                        color: AppColors.softMauve, fontSize: 11.5),
                  ),
                  const SizedBox(height: 8),
                  if (selected.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in selected)
                          Chip(
                            label: Text(c),
                            onDeleted: () =>
                                setLocalState(() => selected.remove(c)),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: newCatController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Add a category',
                      prefixIcon: const Icon(Icons.folder_open_rounded),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () => addCategory(newCatController.text),
                      ),
                    ),
                    onSubmitted: addCategory,
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in suggestions)
                          ActionChip(
                            label: Text(c),
                            onPressed: () => addCategory(c),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: canSave
                    ? () {
                        final cats = selected.isEmpty
                            ? [_kUncategorized]
                            : selected.toList();
                        final texts = isBulkAdd
                            ? [...pendingQuestions, if (leftover.isNotEmpty) leftover]
                            : [leftover];
                        Navigator.of(ctx).pop((texts: texts, categories: cats));
                      }
                    : null,
                child: Text(
                  isBulkAdd
                      ? 'Add $totalCount question${totalCount == 1 ? '' : 's'}'
                      : 'Save',
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    if (existing == null) {
      await Future.wait(result.texts.map((text) => _repo.addQuestion(
            userId: userId,
            text: text,
            categories: result.categories,
          )));
    } else {
      await _repo.updateQuestion(
        userId: userId,
        questionId: existing.id,
        text: result.texts.first,
        categories: result.categories,
      );
    }
  }

  Future<void> _confirmDelete(String userId, InterviewQuestion q) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete question?'),
        content: Text('"${q.text}" will be removed from your question bank.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _repo.deleteQuestion(userId, q.id);
  }

  Future<void> _openAddDialog(
    String userId,
    List<InterviewQuestion> questions,
  ) async {
    final suggestions = await _loadCategorySuggestions(userId, questions);
    if (!mounted) return;
    await _addOrEditQuestion(
      userId,
      categorySuggestions: suggestions,
      presetCategory: widget.filterCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    final filterCategory = widget.filterCategory;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            bottom: false,
            child: StreamBuilder<List<InterviewQuestion>>(
              stream: _repo.watchQuestions(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final questions = snapshot.data ?? [];
                final relevant = filterCategory == null
                    ? questions
                    : questions
                        .where((q) => q.categories.contains(filterCategory))
                        .toList();

                // Grouped-by-category view is only used when not scoped to a
                // single category; a question with several categories is
                // listed once under each of them.
                final groups = <String, List<InterviewQuestion>>{};
                if (filterCategory == null) {
                  for (final q in questions) {
                    final cats =
                        q.categories.isEmpty ? [_kUncategorized] : q.categories;
                    for (final cat in cats) {
                      groups.putIfAbsent(cat, () => []).add(q);
                    }
                  }
                }
                final categoryHeaders = groups.keys.toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back,
                                color: AppColors.wine),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              filterCategory == null
                                  ? 'Interview questions'
                                  : '$filterCategory questions',
                              style: const TextStyle(
                                color: AppColors.wine,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(42, 6, 4, 18),
                      child: Text(
                        filterCategory == null
                            ? 'Add questions per category. The AI coach will '
                                'ask them one by one while you record a '
                                'session in that category.'
                            : 'Questions the AI coach can ask during a '
                                '"$filterCategory" recording. A question can '
                                'also be shared with other categories.',
                        style: const TextStyle(
                          color: AppColors.midMauve,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (relevant.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: _EmptyState(
                          icon: Icons.quiz_outlined,
                          title: filterCategory == null
                              ? 'No questions yet'
                              : 'No questions for $filterCategory yet',
                          message: filterCategory == null
                              ? 'Add a few questions and the AI coach will '
                                  'ask them during your next recording.'
                              : 'Add one and the AI coach can ask it during '
                                  'recordings in this category.',
                        ),
                      )
                    else if (filterCategory != null)
                      GlassCard(
                        radius: 20,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < relevant.length; i++) ...[
                              _questionRow(userId, relevant[i], questions),
                              if (i < relevant.length - 1)
                                const Divider(
                                  height: 1,
                                  thickness: 0.5,
                                  indent: 16,
                                  color: AppColors.separator,
                                ),
                            ],
                          ],
                        ),
                      )
                    else
                      for (final cat in categoryHeaders) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                          child: Text(
                            cat,
                            style: const TextStyle(
                              color: AppColors.wine,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        GlassCard(
                          radius: 20,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            children: [
                              for (var i = 0; i < groups[cat]!.length; i++) ...[
                                _questionRow(
                                    userId, groups[cat]![i], questions),
                                if (i < groups[cat]!.length - 1)
                                  const Divider(
                                    height: 1,
                                    thickness: 0.5,
                                    indent: 16,
                                    color: AppColors.separator,
                                  ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: StreamBuilder<List<InterviewQuestion>>(
        stream: _repo.watchQuestions(userId),
        builder: (context, snapshot) {
          final questions = snapshot.data ?? [];
          return FloatingActionButton(
            onPressed: () => _openAddDialog(userId, questions),
            backgroundColor: AppColors.wine,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add_rounded),
          );
        },
      ),
    );
  }

  Widget _questionRow(
    String userId,
    InterviewQuestion q,
    List<InterviewQuestion> allQuestions,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.chat_bubble_outline_rounded,
                size: 18, color: AppColors.deepMauve),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  q.text,
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
                // Shows every category this question belongs to, so it's
                // clear at a glance when a question is shared across more
                // than one category.
                if (q.categories.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    q.categories.join(' · '),
                    style: const TextStyle(
                      color: AppColors.softMauve,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 19),
            color: AppColors.midMauve,
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final suggestions =
                  await _loadCategorySuggestions(userId, allQuestions);
              if (!mounted) return;
              await _addOrEditQuestion(
                userId,
                existing: q,
                categorySuggestions: suggestions,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 19),
            color: AppColors.midMauve,
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmDelete(userId, q),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: AppColors.softMauve),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.midMauve),
            ),
          ],
        ),
      ),
    );
  }
}

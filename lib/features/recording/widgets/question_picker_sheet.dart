import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/interview_question.dart';

// Lets the user pick which of this category's saved questions the AI coach
// should ask during the recording, and in what order (the order they're
// tapped in). Returns the selected questions, or null if cancelled.
Future<List<InterviewQuestion>?> showQuestionPickerSheet(
  BuildContext context, {
  required List<InterviewQuestion> questions,
}) {
  return showModalBottomSheet<List<InterviewQuestion>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuestionPickerSheet(questions: questions),
  );
}

class _QuestionPickerSheet extends StatefulWidget {
  final List<InterviewQuestion> questions;
  const _QuestionPickerSheet({required this.questions});

  @override
  State<_QuestionPickerSheet> createState() => _QuestionPickerSheetState();
}

class _QuestionPickerSheetState extends State<_QuestionPickerSheet> {
  // Selected ids, in the order tapped — that order is what the AI coach
  // asks them in during the recording.
  final List<String> _selectedIds = [];

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == widget.questions.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.questions.map((q) => q.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hPad = (size.width * 0.06).clamp(16.0, 32.0);
    final allSelected = _selectedIds.length == widget.questions.length;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
              child: Column(
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
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Choose questions',
                          style: TextStyle(
                            color: AppColors.wine,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleSelectAll,
                        child:
                            Text(allSelected ? 'Deselect all' : 'Select all'),
                      ),
                    ],
                  ),
                  const Text(
                    'Tap the questions you want this session, in the order '
                    'you\'d like to be asked them.',
                    style: TextStyle(
                      color: AppColors.midMauve,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: hPad),
                itemCount: widget.questions.length,
                itemBuilder: (context, i) {
                  final q = widget.questions[i];
                  final order = _selectedIds.indexOf(q.id);
                  final selected = order != -1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color:
                          selected ? AppColors.paleMauve : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _toggle(q.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (selected)
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: AppColors.deepMauve,
                                  child: Text(
                                    '${order + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                const Icon(Icons.circle_outlined,
                                    size: 22, color: AppColors.softMauve),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  q.text,
                                  style: const TextStyle(
                                    color: AppColors.wine,
                                    fontSize: 14.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 12),
              child: FilledButton.icon(
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () {
                        final ordered = _selectedIds
                            .map((id) => widget.questions
                                .firstWhere((q) => q.id == id))
                            .toList();
                        Navigator.of(context).pop(ordered);
                      },
                icon: const Icon(Icons.fiber_manual_record_rounded, size: 18),
                label: Text(
                  _selectedIds.isEmpty
                      ? 'Select at least one question'
                      : 'Start with ${_selectedIds.length} question${_selectedIds.length == 1 ? '' : 's'}',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

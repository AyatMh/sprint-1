import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// Opens a modern bottom sheet letting the user pick a category for their
// practice session. There are no built-in presets: the list contains only
// categories the user created in past sessions. The first time around the
// sheet guides them to create their first category. Returns the chosen
// category, or null if the sheet was dismissed.
//
// [categoriesFuture] is loaded *after* the sheet is shown so the popup opens
// instantly instead of waiting on a network round-trip.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required Future<List<String>> categoriesFuture,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        CategoryPickerSheet(categoriesFuture: categoriesFuture),
  );
}

class CategoryPickerSheet extends StatefulWidget {
  final Future<List<String>> categoriesFuture;
  const CategoryPickerSheet({super.key, required this.categoriesFuture});

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final _newCategoryController = TextEditingController();
  bool _creating = false;

  // null while the categories are still loading.
  List<String>? _categories;

  bool get _loading => _categories == null;
  bool get _hasCategories => _categories?.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    widget.categoriesFuture.then((cats) {
      if (!mounted) return;
      setState(() {
        _categories = cats;
        // With no categories yet, jump straight into creation mode.
        _creating = cats.isEmpty;
      });
    });
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  void _submitNewCategory() {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // Keeps the sheet above the keyboard when typing a new category.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: size.height * 0.8),
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: (size.width * 0.06).clamp(16.0, 32.0),
              vertical: 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== Drag handle =====
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
                Text(
                  _hasCategories ? 'Choose a Category' : 'Create a Category',
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _hasCategories
                      ? 'Pick one of your categories, or create a new one.'
                      : 'Categories help you organize your sessions — for example "Behavioral" or "System Design". Create your first one to get started.',
                  style: const TextStyle(
                    color: AppColors.midMauve,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),

                // ===== Language notice =====
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.paleMauve,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.translate_rounded,
                          size: 18, color: AppColors.deepMauve),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Just a heads-up: speech analysis is currently available in English only, so record your session in English for the most accurate feedback.',
                          style: TextStyle(
                            color: AppColors.midMauve,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ===== Loading the user's saved categories =====
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),

                // ===== The user's own categories =====
                if (_hasCategories) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < _categories!.length; i++)
                        _AnimatedCategoryChip(
                          label: _categories![i],
                          index: i,
                          onTap: () =>
                              Navigator.of(context).pop(_categories![i]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // ===== Create a new category =====
                if (!_loading)
                  AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _creating
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _newCategoryController,
                              autofocus: true,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Category name',
                                hintText: 'e.g. Behavioral',
                                prefixIcon: Icon(Icons.folder_open_rounded),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submitNewCategory(),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed:
                                  _newCategoryController.text.trim().isEmpty
                                      ? null
                                      : _submitNewCategory,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Create & Use'),
                            ),
                          ],
                        )
                      : OutlinedButton.icon(
                          onPressed: () => setState(() => _creating = true),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('New category'),
                        ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// A category chip that fades and slides in with a slight stagger.
class _AnimatedCategoryChip extends StatelessWidget {
  final String label;
  final int index;
  final VoidCallback onTap;

  const _AnimatedCategoryChip({
    required this.label,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + index * 50),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Material(
        color: AppColors.paleMauve,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_rounded,
                    size: 16, color: AppColors.deepMauve),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/recording.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/session_stats.dart';
import '../../auth/providers/auth_provider.dart';
import '../../recording/screens/replay_screen.dart';
import '../../recording/start_practice_session.dart';
import '../../analysis/screens/analysis_screen.dart';
import '../../analysis/screens/compare_screen.dart';

// Label used for recordings saved without a category.
const String _kUncategorized = 'Uncategorized';

String _formatDuration(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDate(DateTime dt) {
  return DateFormat('MMM d, y · HH:mm').format(dt);
}

String _categoryOf(Recording r) =>
    r.category.trim().isEmpty ? _kUncategorized : r.category.trim();

// Folder gradient pairs, cycled by index (mock's blue/teal/indigo).
const List<List<Color>> _tileGradients = [
  [Color(0xFF0A84FF), Color(0xFF54B8FF)],
  [Color(0xFF0AB8C8), Color(0xFF4ADDE0)],
  [Color(0xFF5E6AD2), Color(0xFF8C99B3)],
];

// ============================================================================
// Recordings: search + category folders + recent sessions
// ============================================================================
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  // Android-style contextual editing for the category folders: long-press a
  // folder to enter, then rename (single) or delete (one or more) from the top.
  bool _editing = false;
  final Set<String> _selectedCategories = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _enterCategoryEditing(String category) {
    setState(() {
      _editing = true;
      _selectedCategories
        ..clear()
        ..add(category);
    });
  }

  void _exitCategoryEditing() {
    setState(() {
      _editing = false;
      _selectedCategories.clear();
    });
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  // Renames the single selected category by re-tagging every recording in it.
  Future<void> _renameCategory(
    String userId,
    RecordingRepository repo,
    Map<String, List<Recording>> groups,
  ) async {
    if (_selectedCategories.length != 1) return;
    final category = _selectedCategories.first;
    final controller = TextEditingController(text: category);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Category name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == category) return;
    final ids = (groups[category] ?? []).map((r) => r.id).toList();
    await repo.setCategoryForRecordings(userId, ids, newName);
    if (mounted) _exitCategoryEditing();
  }

  // Merges the selected categories into one: every recording across them is
  // re-tagged to a single target name (kept from the selection, or a new one).
  Future<void> _mergeCategories(
    String userId,
    RecordingRepository repo,
    Map<String, List<Recording>> groups,
  ) async {
    if (_selectedCategories.length < 2) return;
    final cats = _selectedCategories.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final controller = TextEditingController(text: cats.first);
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Merge ${cats.length} categories'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All recordings from ${cats.join(', ')} will be combined into '
              'one category.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Merged category name'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (target == null || target.isEmpty) return;
    final ids = <String>[
      for (final c in cats) ...(groups[c] ?? []).map((r) => r.id),
    ];
    await repo.setCategoryForRecordings(userId, ids, target);
    if (!mounted) return;
    _exitCategoryEditing();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Merged ${cats.length} categories into "$target"'),
      ),
    );
  }

  // Deletes every selected category: removes all their recordings (local
  // files, Storage copies, and Firestore docs).
  Future<void> _deleteCategories(
    String userId,
    RecordingRepository repo,
    Map<String, List<Recording>> groups,
  ) async {
    if (_selectedCategories.isEmpty) return;
    final cats = _selectedCategories.toList();
    final toDelete = <Recording>[
      for (final c in cats) ...(groups[c] ?? []),
    ];
    final catCount = cats.length;
    final recCount = toDelete.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete $catCount categor${catCount == 1 ? 'y' : 'ies'}?',
        ),
        content: Text(
          'This will permanently delete all $recCount recording'
          '${recCount == 1 ? '' : 's'} in '
          '${catCount == 1 ? 'this category' : 'these categories'}, including '
          'their video files. This cannot be undone.',
        ),
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
    if (confirmed != true) return;

    for (final r in toDelete) {
      try {
        final file = File(r.localPath);
        if (await file.exists()) await file.delete();
        final storagePath = r.storagePath;
        if (storagePath != null && storagePath.isNotEmpty) {
          try {
            await FirebaseStorage.instance.ref(storagePath).delete();
          } catch (_) {
            // Already gone or never finished uploading — nothing to clean.
          }
        }
        await repo.deleteRecording(userId, r.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
    if (mounted) _exitCategoryEditing();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    final repo = RecordingRepository();

    if (userId == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('Not logged in')),
      );
    }

    return PopScope(
      // While editing categories, the Android back button exits editing
      // instead of leaving the Recordings tab.
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitCategoryEditing();
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      // Android-style FAB, lifted above the floating tab bar.
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: FloatingActionButton(
          onPressed: () => startPracticeSession(context),
          backgroundColor: AppColors.wine,
          foregroundColor: Colors.white,
          elevation: 4,
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<Recording>>(
          stream: repo.watchRecordings(userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load recordings:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final recordings = snapshot.data ?? [];

            // Group into category folders, newest-first preserved.
            final groups = <String, List<Recording>>{};
            for (final r in recordings) {
              groups.putIfAbsent(_categoryOf(r), () => []).add(r);
            }
            final q = _query.trim().toLowerCase();
            // A category matches if its own name matches, or if any recording
            // inside it is named like the query.
            bool matchesQuery(String cat) {
              if (q.isEmpty) return true;
              if (cat.toLowerCase().contains(q)) return true;
              return groups[cat]!.any((r) {
                final name = r.name.trim().isNotEmpty
                    ? r.name
                    : _formatDate(r.createdAt);
                return name.toLowerCase().contains(q);
              });
            }

            final categories = groups.keys.where(matchesQuery).toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 140),
              children: [
                // ===== Header (contextual action bar while editing) =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: _editing
                      ? Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: AppColors.wine),
                              tooltip: 'Done',
                              onPressed: _exitCategoryEditing,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _selectedCategories.isEmpty
                                    ? 'Select categories'
                                    : '${_selectedCategories.length} selected',
                                style: const TextStyle(
                                  color: AppColors.wine,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppColors.wine),
                              tooltip: 'Rename category',
                              onPressed: _selectedCategories.length == 1
                                  ? () => _renameCategory(userId, repo, groups)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.merge_type_rounded,
                                  color: AppColors.wine),
                              tooltip: 'Merge categories',
                              onPressed: _selectedCategories.length >= 2
                                  ? () => _mergeCategories(userId, repo, groups)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.wine),
                              tooltip: 'Delete',
                              onPressed: _selectedCategories.isEmpty
                                  ? null
                                  : () =>
                                      _deleteCategories(userId, repo, groups),
                            ),
                          ],
                        )
                      : const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Recordings',
                                style: TextStyle(
                                  color: AppColors.wine,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),

                // ===== Search (hidden while editing categories) =====
                if (!_editing)
                  GlassCard(
                    radius: 23,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              size: 20, color: AppColors.midMauve),
                          const SizedBox(width: 9),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) => setState(() => _query = v),
                              decoration: const InputDecoration(
                                hintText: 'Search categories',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isCollapsed: true,
                              ),
                              style: const TextStyle(
                                color: AppColors.wine,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() {
                                _query = '';
                                _searchController.clear();
                              }),
                              child: const Icon(Icons.close_rounded,
                                  size: 20, color: AppColors.midMauve),
                            ),
                        ],
                      ),
                    ),
                  ),

                if (recordings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: _EmptyState(
                      icon: Icons.videocam_off_outlined,
                      title: 'No recordings yet',
                      message:
                          'Tap "Start practicing" on the home screen to create your first session. Your takes will be organized here by category.',
                    ),
                  )
                else ...[
                  // ===== Analyze / Compare actions (hidden while editing) =====
                  if (!_editing) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _TopAction(
                            icon: Icons.analytics_rounded,
                            label: 'Analyze',
                            colors: const [
                              Color(0xFF0A84FF),
                              Color(0xFF0E60C8)
                            ],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AnalyzeScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TopAction(
                            icon: Icons.compare_arrows_rounded,
                            label: 'Compare',
                            colors: const [
                              Color(0xFF5E6AD2),
                              Color(0xFF3B43A0)
                            ],
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CompareSelectScreen(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ===== Folders =====
                  const SizedBox(height: 16),
                  if (categories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: _EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching categories',
                        message:
                            'No category or recording matches your search.',
                      ),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.18,
                      children: [
                        for (var i = 0; i < categories.length; i++)
                          _FolderCard(
                            category: categories[i],
                            count: groups[categories[i]]!.length,
                            colors: _tileGradients[i % _tileGradients.length],
                            selected: _editing &&
                                _selectedCategories.contains(categories[i]),
                            onTap: () {
                              // In editing mode a tap toggles selection;
                              // otherwise it opens the category.
                              if (_editing) {
                                _toggleCategory(categories[i]);
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CategoryRecordingsScreen(
                                      category: categories[i],
                                    ),
                                  ),
                                );
                              }
                            },
                            // Long-press a folder to enter Android-style
                            // editing for the categories, selecting this one.
                            onLongPress: _editing
                                ? null
                                : () => _enterCategoryEditing(categories[i]),
                          ),
                      ],
                    ),
                ],
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String category;
  final int count;
  final List<Color> colors;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  const _FolderCard({
    required this.category,
    required this.count,
    required this.colors,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: colors.first.withValues(alpha: 0.55),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: const Icon(Icons.folder_rounded,
                    color: Colors.white, size: 26),
              ),
              const Spacer(),
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.wine,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count session${count == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: AppColors.midMauve,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          // Selection badge shown while editing categories.
          if (selected)
            const Positioned(
              top: 0,
              right: 0,
              child: Icon(Icons.check_circle_rounded,
                  color: AppColors.wine, size: 24),
            ),
        ],
      ),
    );
  }
}

// A solid gradient pill action button (Analyze / Compare). Deliberately
// styled as a horizontal CTA so it doesn't look like a category folder tile.
class _TopAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  const _TopAction({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colors.first.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bottom sheet that lists the user's categories so they can pick one to
// analyze. Returns the chosen category name, or null if dismissed.
class _CategoryChooserSheet extends StatelessWidget {
  final List<String> categories;
  final Map<String, int> counts;

  const _CategoryChooserSheet({
    required this.categories,
    required this.counts,
  });

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.separator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Choose a category',
                style: TextStyle(
                  color: AppColors.wine,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (final c in categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: AppColors.paleMauve,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_rounded,
                                color: AppColors.deepMauve, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.wine,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${counts[c] ?? 0}',
                              style: const TextStyle(
                                color: AppColors.midMauve,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppColors.softMauve, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Multi-select category picker. Returns the chosen category names, or null if
// cancelled. Used by Analyze to average several categories together.
class _CategoryMultiSelectSheet extends StatefulWidget {
  final List<String> categories;
  final Map<String, int> counts;

  const _CategoryMultiSelectSheet({
    required this.categories,
    required this.counts,
  });

  @override
  State<_CategoryMultiSelectSheet> createState() =>
      _CategoryMultiSelectSheetState();
}

class _CategoryMultiSelectSheetState extends State<_CategoryMultiSelectSheet> {
  final Set<String> _selected = {};

  void _toggle(String c) {
    setState(() {
      if (_selected.contains(c)) {
        _selected.remove(c);
      } else {
        _selected.add(c);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final n = _selected.length;
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.separator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Choose categories to average',
                style: TextStyle(
                  color: AppColors.wine,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final c in widget.categories)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: AppColors.paleMauve,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _toggle(c),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                child: Row(
                                  children: [
                                    Icon(
                                      _selected.contains(c)
                                          ? Icons.check_box_rounded
                                          : Icons.check_box_outline_blank_rounded,
                                      color: AppColors.deepMauve,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        c,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.wine,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${widget.counts[c] ?? 0}',
                                      style: const TextStyle(
                                        color: AppColors.midMauve,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: n == 0
                    ? null
                    : () => Navigator.of(context).pop(_selected.toList()),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  n == 0
                      ? 'Select categories'
                      : 'Add ${n == 1 ? '1 category' : '$n categories'}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Inside a folder: stats summary + the recordings of one category.
// ============================================================================

// Shows the recordings inside one category. Recording-level editing (rename /
// move / delete / average) starts by long-pressing a recording; category-level
// rename and delete live on the Recordings screen instead.
class CategoryRecordingsScreen extends StatefulWidget {
  final String category;

  const CategoryRecordingsScreen({
    super.key,
    required this.category,
  });

  @override
  State<CategoryRecordingsScreen> createState() =>
      _CategoryRecordingsScreenState();
}

class _CategoryRecordingsScreenState extends State<CategoryRecordingsScreen> {
  // Android-style contextual editing mode: long-press a recording to enter,
  // then multi-select to move / delete / average, or tap a card's pencil to
  // rename that single recording.
  bool _editing = false;
  final Set<String> _selectedIds = {};

  // Android-style in-app-bar search over recording names.
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  // The folder's category. Renaming now happens from the Recordings screen.
  late final String _category = widget.category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // The label a recording is searched/shown by (its name, or its date).
  String _displayName(Recording r) =>
      r.name.trim().isNotEmpty ? r.name : _formatDate(r.createdAt);

  void _enterSearch() => setState(() => _searching = true);

  void _exitSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // Enters editing mode, optionally pre-selecting the long-pressed recording.
  void _enterEditing({String? select}) {
    setState(() {
      _editing = true;
      _selectedIds.clear();
      if (select != null) _selectedIds.add(select);
    });
  }

  void _exitEditing() {
    setState(() {
      _editing = false;
      _selectedIds.clear();
    });
  }

  // Title shown in the app bar while editing.
  String _editingTitle() =>
      _selectedIds.isEmpty ? 'Select recordings' : '${_selectedIds.length} selected';

  // Selects (or clears) every recording in this category. Used by the multi
  // select purposes (move / average / delete).
  Widget _selectAllAction(String userId, RecordingRepository repo) {
    return TextButton(
      child: const Text('Select all'),
      onPressed: () async {
        final all = await repo.watchRecordings(userId).first;
        if (!mounted) return;
        final ids = all
            .where((r) => _categoryOf(r) == _category)
            .map((r) => r.id)
            .toList();
        setState(() {
          // Toggle: if everything is already picked, clear; otherwise pick all.
          if (ids.isNotEmpty && _selectedIds.length == ids.length) {
            _selectedIds.clear();
          } else {
            _selectedIds
              ..clear()
              ..addAll(ids);
          }
        });
      },
    );
  }

  // Contextual action-bar buttons shown at the top while editing. Every
  // action works on the current multi-selection (disabled when nothing is
  // picked), matching Android's "select then act" pattern.
  List<Widget> _editingActions(String userId, RecordingRepository repo) {
    final hasSelection = _selectedIds.isNotEmpty;
    return [
      _selectAllAction(userId, repo),
      IconButton(
        icon: const Icon(Icons.drive_file_move_outline),
        tooltip: 'Move to another category',
        onPressed: hasSelection ? () => _moveSelected(userId, repo) : null,
      ),
      IconButton(
        icon: const Icon(Icons.bar_chart_rounded),
        tooltip: 'Average selected',
        onPressed: hasSelection
            ? () async {
                final all = await repo.watchRecordings(userId).first;
                if (!mounted) return;
                final recordings =
                    all.where((r) => _categoryOf(r) == _category).toList();
                _showCombinedStats(recordings);
              }
            : null,
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete selected',
        onPressed: hasSelection
            ? () async {
                final recordings = await repo.watchRecordings(userId).first;
                if (!mounted) return;
                await _confirmDeleteSelected(
                  context,
                  userId,
                  repo,
                  recordings,
                );
              }
            : null,
      ),
    ];
  }

  // Simple single-field text dialog used for renaming.
  Future<String?> _promptText({
    required String title,
    required String label,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameRecording(Recording r) async {
    final userId = context.read<AuthProvider>().user?.uid;
    if (userId == null) return;
    final newName = await _promptText(
      title: 'Rename recording',
      label: 'Recording name',
      initial: r.name,
    );
    if (newName == null || newName.isEmpty || newName == r.name) return;
    await RecordingRepository().renameRecording(userId, r.id, newName);
  }

  // Moves every selected recording to another (existing or new) category.
  Future<void> _moveSelected(String userId, RecordingRepository repo) async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();

    final all = await repo.watchRecordings(userId).first;
    if (!mounted) return;
    final categories = all
        .map(_categoryOf)
        .toSet()
        .where((c) => c != _category)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final target = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoveCategorySheet(categories: categories),
    );
    if (target == null || target.isEmpty || !mounted) return;
    await repo.setCategoryForRecordings(userId, ids, target);
    if (!mounted) return;
    final n = ids.length;
    _exitEditing();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved $n recording${n == 1 ? '' : 's'} to "$target"'),
      ),
    );
  }

  // Shows the combined averages of the selected recordings in a bottom sheet.
  void _showCombinedStats(List<Recording> all) {
    final selected = all.where((r) => _selectedIds.contains(r.id)).toList();
    if (selected.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: size.height * 0.8),
          decoration: const BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: AppColors.separator,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SessionStatsCard(
                    recordings: selected,
                    title:
                        'Combined averages · ${selected.length} session${selected.length == 1 ? '' : 's'}',
                    framed: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSelected(
    BuildContext context,
    String userId,
    RecordingRepository repo,
    List<Recording> recordings,
  ) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count recording${count == 1 ? '' : 's'}?'),
        content: const Text(
          'This will remove the selected recordings from your history. The local video files will also be deleted.',
        ),
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

    if (confirmed != true) return;

    final toDelete =
        recordings.where((r) => _selectedIds.contains(r.id)).toList();

    await _deleteRecordings(userId, repo, toDelete);

    if (mounted) _exitEditing();
  }

  // Permanently deletes the given recordings: local file, Firebase Storage
  // copy, and the Firestore document. Shared by selection-delete and
  // category-delete.
  Future<void> _deleteRecordings(
    String userId,
    RecordingRepository repo,
    List<Recording> toDelete,
  ) async {
    for (final r in toDelete) {
      try {
        final file = File(r.localPath);
        if (await file.exists()) {
          await file.delete();
        }
        // Also remove the uploaded copy from Firebase Storage so deleted
        // recordings don't leave orphaned files behind.
        final storagePath = r.storagePath;
        if (storagePath != null && storagePath.isNotEmpty) {
          try {
            await FirebaseStorage.instance.ref(storagePath).delete();
          } catch (_) {
            // Already gone or never finished uploading — nothing to clean.
          }
        }
        await repo.deleteRecording(userId, r.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    final repo = RecordingRepository();

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _editing
            ? Text(_editingTitle())
            : _searching
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search recordings',
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    style: const TextStyle(
                      color: AppColors.wine,
                      fontSize: 18,
                    ),
                  )
                : Text(_category),
        leading: _editing
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Done',
                onPressed: _exitEditing,
              )
            : _searching
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Close search',
                    onPressed: _exitSearch,
                  )
                : null,
        actions: _editing
            ? _editingActions(userId, repo)
            : _searching
                ? [
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear',
                        onPressed: () => setState(() {
                          _query = '';
                          _searchController.clear();
                        }),
                      ),
                  ]
                : [
                    // Renaming / deleting the category itself now lives on the
                    // Recordings screen (long-press a folder). Here we only
                    // search, and editing recordings starts with a long-press.
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Search recordings',
                      onPressed: _enterSearch,
                    ),
                  ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          StreamBuilder<List<Recording>>(
            stream: repo.watchRecordings(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to load recordings:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final all = (snapshot.data ?? [])
                  .where((r) => _categoryOf(r) == _category)
                  .toList();
              if (all.isEmpty) {
                return const _EmptyState(
                  icon: Icons.folder_off_outlined,
                  title: 'Nothing here anymore',
                  message: 'All recordings in this category were deleted.',
                );
              }

              // While searching, filter by name and drop the stats header so
              // only the matching recordings show.
              final q = _query.trim().toLowerCase();
              final searchActive = _searching && q.isNotEmpty;
              final recordings = searchActive
                  ? all
                      .where(
                          (r) => _displayName(r).toLowerCase().contains(q))
                      .toList()
                  : all;

              if (searchActive && recordings.isEmpty) {
                return _EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  message: 'No recordings named like "$q" in this category.',
                );
              }

              // Show the per-category stats summary first, but not while
              // searching or editing recordings (keeps edit mode focused).
              final showStats = !searchActive && !_editing;
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                itemCount: recordings.length + (showStats ? 1 : 0),
                separatorBuilder: (_, i) =>
                    SizedBox(height: showStats && i == 0 ? 18 : 10),
                itemBuilder: (context, i) {
                  if (showStats && i == 0) {
                    return SessionStatsCard(
                      recordings: recordings,
                      title: 'Category Averages',
                    );
                  }
                  final index = showStats ? i - 1 : i;
                  return _buildRecordingCard(context, recordings[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingCard(BuildContext context, Recording r) {
    final selected = _selectedIds.contains(r.id);
    final title = r.name.trim().isNotEmpty ? r.name : _formatDate(r.createdAt);

    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(12),
      onTap: () {
        if (_editing) {
          _toggleSelected(r.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReplayScreen(recording: r)),
          );
        }
      },
      // Long-press starts Android-style editing and selects this recording.
      onLongPress: _editing ? null : () => _enterEditing(select: r.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Checkbox(
                value: selected,
                onChanged: (_) => _toggleSelected(r.id),
              ),
            )
          else
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A84FF), Color(0xFF0E2A55)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 24),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDate(r.createdAt)} · ${_formatDuration(r.durationMs)} · ${_formatSize(r.fileSizeBytes)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.midMauve,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AnalysisScreen(recording: r),
                        ),
                      );
                    },
                    icon: Icon(
                      r.hasTranscript
                          ? Icons.analytics_outlined
                          : Icons.auto_awesome,
                      size: 18,
                    ),
                    label: Text(
                      r.hasTranscript ? 'View Analysis' : 'Analyze',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // In editing mode, a pencil next to each recording renames just it.
          if (_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Rename recording',
              color: AppColors.wine,
              onPressed: () => _renameRecording(r),
            ),
        ],
      ),
    );
  }
}

// Shared two-step picker: choose a category, then a recording inside it.
// Returns the chosen recording id, or null if cancelled. [disabledIds] are
// shown as already-added and can't be re-picked.
Future<String?> pickRecordingViaCategory(
  BuildContext context,
  List<Recording> all, {
  required Set<String> disabledIds,
}) async {
  final groups = <String, List<Recording>>{};
  for (final r in all) {
    groups.putIfAbsent(_categoryOf(r), () => []).add(r);
  }
  final categories = groups.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (categories.isEmpty) return null;
  final counts = {for (final c in categories) c: groups[c]!.length};

  final cat = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _CategoryChooserSheet(categories: categories, counts: counts),
  );
  if (cat == null || !context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RecordingChooserSheet(
      category: cat,
      recordings: groups[cat] ?? [],
      disabledIds: disabledIds,
    ),
  );
}

// ============================================================================
// Analyze: build a set of recordings (each picked via category → recording)
// then view one or average several.
// ============================================================================
class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  // Picked recordings, by id, in the order they were added.
  final List<String> _pickedIds = [];

  // Adds a recording via the shared category → recording picker flow.
  Future<void> _addRecording(List<Recording> all) async {
    final recId = await pickRecordingViaCategory(
      context,
      all,
      disabledIds: _pickedIds.toSet(),
    );
    if (recId == null || !mounted) return;
    if (!_pickedIds.contains(recId)) {
      setState(() => _pickedIds.add(recId));
    }
  }

  // Adds every recording from one or more chosen categories, so several
  // categories can be averaged together.
  Future<void> _addCategories(List<Recording> all) async {
    final groups = <String, List<Recording>>{};
    for (final r in all) {
      groups.putIfAbsent(_categoryOf(r), () => []).add(r);
    }
    final categories = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (categories.isEmpty) return;
    final counts = {for (final c in categories) c: groups[c]!.length};

    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryMultiSelectSheet(
        categories: categories,
        counts: counts,
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() {
      for (final c in chosen) {
        for (final r in groups[c] ?? const <Recording>[]) {
          if (!_pickedIds.contains(r.id)) _pickedIds.add(r.id);
        }
      }
    });
  }

  void _showAverage(List<Recording> picked) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: size.height * 0.8),
          decoration: const BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: AppColors.separator,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SessionStatsCard(
                    recordings: picked,
                    title:
                        'Average · ${picked.length} recording${picked.length == 1 ? '' : 's'}',
                    includeCategories: true,
                    framed: false,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }
    final repo = RecordingRepository();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('Analyze')),
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          StreamBuilder<List<Recording>>(
            stream: repo.watchRecordings(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data ?? [];
              final byId = {for (final r in all) r.id: r};
              final picked = _pickedIds
                  .map((id) => byId[id])
                  .whereType<Recording>()
                  .toList();

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      const Text(
                        'Pick a recording to analyze, or add several '
                        'recordings or whole categories to see their average.',
                        style: TextStyle(
                          color: AppColors.midMauve,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (picked.isEmpty)
                        const _EmptyState(
                          icon: Icons.add_chart_rounded,
                          title: 'Nothing selected yet',
                          message:
                              'Add a single recording, or pick whole categories to average them.',
                        )
                      else
                        for (final r in picked)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _pickedCard(context, r),
                          ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _addRecording(all),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add recording'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.cardBg,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _addCategories(all),
                              icon: const Icon(Icons.folder_rounded),
                              label: const Text('Add categories'),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: AppColors.cardBg,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (picked.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: FilledButton.icon(
                        onPressed: picked.length == 1
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AnalysisScreen(recording: picked.first),
                                  ),
                                )
                            : () => _showAverage(picked),
                        icon: Icon(picked.length == 1
                            ? Icons.analytics_rounded
                            : Icons.bar_chart_rounded),
                        label: Text(
                          picked.length == 1
                              ? 'View analysis'
                              : 'Average analysis (${picked.length})',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pickedCard(BuildContext context, Recording r) {
    final title = r.name.trim().isNotEmpty ? r.name : _formatDate(r.createdAt);
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_categoryOf(r)} · ${_formatDate(r.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.midMauve,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.midMauve),
            tooltip: 'Remove',
            onPressed: () => setState(() => _pickedIds.remove(r.id)),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Compare: pick exactly two recordings (each via category → recording), then
// open the side-by-side comparison.
// ============================================================================
class CompareSelectScreen extends StatefulWidget {
  const CompareSelectScreen({super.key});

  @override
  State<CompareSelectScreen> createState() => _CompareSelectScreenState();
}

class _CompareSelectScreenState extends State<CompareSelectScreen> {
  final List<String> _pickedIds = [];
  static const int _maxPicks = 2;

  Future<void> _addRecording(List<Recording> all) async {
    final recId = await pickRecordingViaCategory(
      context,
      all,
      disabledIds: _pickedIds.toSet(),
    );
    if (recId == null || !mounted) return;
    if (!_pickedIds.contains(recId) && _pickedIds.length < _maxPicks) {
      setState(() => _pickedIds.add(recId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }
    final repo = RecordingRepository();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('Compare')),
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          StreamBuilder<List<Recording>>(
            stream: repo.watchRecordings(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data ?? [];
              final byId = {for (final r in all) r.id: r};
              final picked = _pickedIds
                  .map((id) => byId[id])
                  .whereType<Recording>()
                  .toList();
              final canCompare = picked.length == 2;

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      const Text(
                        'Pick two recordings to compare side by side, or '
                        'compare two whole categories by their averages.',
                        style: TextStyle(
                          color: AppColors.midMauve,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (picked.isEmpty)
                        const _EmptyState(
                          icon: Icons.compare_arrows_rounded,
                          title: 'Nothing selected yet',
                          message:
                              'Tap "Add recording" to choose two sessions to compare.',
                        )
                      else
                        for (final r in picked)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _pickedCard(context, r),
                          ),
                      const SizedBox(height: 6),
                      if (picked.length < _maxPicks)
                        OutlinedButton.icon(
                          onPressed: () => _addRecording(all),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add recording'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.cardBg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CompareCategoriesScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.folder_copy_outlined),
                        label: const Text('Compare two categories'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.cardBg,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 24,
                    child: FilledButton.icon(
                      onPressed: canCompare
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CompareScreen(
                                    initialLeftId: picked[0].id,
                                    initialRightId: picked[1].id,
                                  ),
                                ),
                              )
                          : null,
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: Text(
                        canCompare
                            ? 'Compare'
                            : 'Pick ${_maxPicks - picked.length} more',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pickedCard(BuildContext context, Recording r) {
    final title = r.name.trim().isNotEmpty ? r.name : _formatDate(r.createdAt);
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.wine,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_categoryOf(r)} · ${_formatDate(r.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.midMauve,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.midMauve),
            tooltip: 'Remove',
            onPressed: () => setState(() => _pickedIds.remove(r.id)),
          ),
        ],
      ),
    );
  }
}

// Bottom sheet listing the recordings inside a category. Returns the chosen
// recording id, or null if dismissed. Already-picked recordings are disabled.
class _RecordingChooserSheet extends StatelessWidget {
  final String category;
  final List<Recording> recordings;
  final Set<String> disabledIds;

  const _RecordingChooserSheet({
    required this.category,
    required this.recordings,
    required this.disabledIds,
  });

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.separator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                category,
                style: const TextStyle(
                  color: AppColors.wine,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (final r in recordings)
                _recordingTile(context, r, disabledIds.contains(r.id)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordingTile(BuildContext context, Recording r, bool disabled) {
    final title = r.name.trim().isNotEmpty ? r.name : _formatDate(r.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.paleMauve.withValues(alpha: disabled ? 0.4 : 1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled ? null : () => Navigator.of(context).pop(r.id),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: disabled ? AppColors.midMauve : AppColors.wine,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatDate(r.createdAt)} · ${_formatDuration(r.durationMs)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.midMauve,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (disabled)
                  const Text(
                    'Added',
                    style: TextStyle(
                      color: AppColors.midMauve,
                      fontSize: 12.5,
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

// Bottom sheet for moving a recording: pick an existing category or create a
// new one. Returns the chosen/typed category name, or null if dismissed.
class _MoveCategorySheet extends StatefulWidget {
  final List<String> categories;
  const _MoveCategorySheet({required this.categories});

  @override
  State<_MoveCategorySheet> createState() => _MoveCategorySheetState();
}

class _MoveCategorySheetState extends State<_MoveCategorySheet> {
  final _controller = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitNew() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.separator,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Move to category',
                  style: TextStyle(
                    color: AppColors.wine,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                for (final c in widget.categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppColors.paleMauve,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).pop(c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_rounded,
                                  color: AppColors.deepMauve, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.wine,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                if (_creating) ...[
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'New category name',
                      hintText: 'e.g. Behavioral',
                      prefixIcon: Icon(Icons.create_new_folder_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submitNew(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed:
                        _controller.text.trim().isEmpty ? null : _submitNew,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Move here'),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _creating = true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New category'),
                  ),
              ],
            ),
          ),
        ),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/recording_repository.dart';
import '../../live_simulation_screen.dart';
import '../auth/providers/auth_provider.dart';
import 'providers/recording_provider.dart';
import 'widgets/category_picker_dialog.dart';

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

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => RecordingProvider(),
        child: LiveSimulationScreen(initialCategory: selectedCategory),
      ),
    ),
  );
}

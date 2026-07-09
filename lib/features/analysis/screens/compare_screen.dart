import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../data/models/recording.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../auth/providers/auth_provider.dart';

class CompareScreen extends StatefulWidget {
  // Optional sessions to pre-select (e.g. when launched from a multi-select
  // on the All sessions screen). Fall back to the two most recent otherwise.
  final String? initialLeftId;
  final String? initialRightId;

  const CompareScreen({super.key, this.initialLeftId, this.initialRightId});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  // Selections are tracked by document ID: the Firestore stream emits new
  // Recording instances on every snapshot, so holding instances would leave
  // the dropdowns pointing at values that no longer exist in their items.
  String? _leftId;
  String? _rightId;

  @override
  void initState() {
    super.initState();
    _leftId = widget.initialLeftId;
    _rightId = widget.initialRightId;
  }

  String _formatDate(DateTime dt) => DateFormat('MMM d, HH:mm').format(dt);

  String _formatSeconds(double s) {
    if (s < 60) return '${s.toStringAsFixed(1)}s';
    final m = (s / 60).floor();
    final rem = (s - m * 60).toStringAsFixed(0);
    return '${m}m ${rem}s';
  }

  double _fillerRate(Recording r) {
    final min = r.durationMs / 60000;
    return min > 0 ? (r.fillerWordCount ?? 0) / min : 0;
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    final repo = RecordingRepository();

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Sessions'),
      ),
      body: StreamBuilder<List<Recording>>(
        stream: repo.watchRecordings(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final analyzed = (snapshot.data ?? []).toList();

          if (analyzed.length < 2) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.compare_arrows,
                        size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'Need at least 2 recordings',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You currently have ${analyzed.length}. Record more sessions to compare your progress.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // Reset selections that point at recordings no longer available
          // (e.g. deleted while this screen is open), then default: newest
          // as right (latest), 2nd newest as left.
          final ids = analyzed.map((r) => r.id).toSet();
          if (_leftId != null && !ids.contains(_leftId)) _leftId = null;
          if (_rightId != null && !ids.contains(_rightId)) _rightId = null;
          _leftId ??= analyzed[1].id;
          _rightId ??= analyzed[0].id;

          final left = analyzed.firstWhere((r) => r.id == _leftId);
          final right = analyzed.firstWhere((r) => r.id == _rightId);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPickers(analyzed),
                const SizedBox(height: 16),
                _buildComparison(left, right),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPickers(List<Recording> analyzed) {
    return Row(
      children: [
        Expanded(
          child: _buildDropdown(
            label: 'Session A',
            selectedId: _leftId,
            items: analyzed,
            onChanged: (id) => setState(() => _leftId = id),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.compare_arrows),
        ),
        Expanded(
          child: _buildDropdown(
            label: 'Session B',
            selectedId: _rightId,
            items: analyzed,
            onChanged: (id) => setState(() => _rightId = id),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? selectedId,
    required List<Recording> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          // Recreate the field when the selection is reset externally, so
          // its internal state never holds an id missing from the items.
          key: ValueKey('$label-$selectedId'),
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: items
              .map((r) => DropdownMenuItem(
                    value: r.id,
                    child: Text(
                      r.name.trim().isNotEmpty
                          ? r.name
                          : _formatDate(r.createdAt),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildComparison(Recording a, Recording b) {
    return Column(
      children: [
        _metricRow(
          'Confidence',
          a.averageConfidencePercentage != null
              ? '${a.averageConfidencePercentage!.toStringAsFixed(0)}%'
              : '—',
          b.averageConfidencePercentage != null
              ? '${b.averageConfidencePercentage!.toStringAsFixed(0)}%'
              : '—',
          aVal: a.averageConfidencePercentage ?? 0,
          bVal: b.averageConfidencePercentage ?? 0,
          lowerIsBetter: false,
        ),
        _metricRow(
          'Posture',
          a.averagePostureStability != null
              ? '${a.averagePostureStability!.toStringAsFixed(0)}%'
              : '—',
          b.averagePostureStability != null
              ? '${b.averagePostureStability!.toStringAsFixed(0)}%'
              : '—',
          aVal: a.averagePostureStability ?? 0,
          bVal: b.averagePostureStability ?? 0,
          lowerIsBetter: false,
        ),
        _metricRow(
          'Look-aways',
          '${a.lookingAwayCount ?? 0}',
          '${b.lookingAwayCount ?? 0}',
          aVal: (a.lookingAwayCount ?? 0).toDouble(),
          bVal: (b.lookingAwayCount ?? 0).toDouble(),
          lowerIsBetter: true,
        ),
        _metricRow(
          'Filler words',
          '${a.fillerWordCount ?? 0}',
          '${b.fillerWordCount ?? 0}',
          aVal: (a.fillerWordCount ?? 0).toDouble(),
          bVal: (b.fillerWordCount ?? 0).toDouble(),
          lowerIsBetter: true,
        ),
        _metricRow(
          'Fillers / min',
          _fillerRate(a).toStringAsFixed(1),
          _fillerRate(b).toStringAsFixed(1),
          aVal: _fillerRate(a),
          bVal: _fillerRate(b),
          lowerIsBetter: true,
        ),
        _metricRow(
          'Vocabulary diversity',
          '${((a.lexicalDiversity ?? 0) * 100).toStringAsFixed(0)}%',
          '${((b.lexicalDiversity ?? 0) * 100).toStringAsFixed(0)}%',
          aVal: a.lexicalDiversity ?? 0,
          bVal: b.lexicalDiversity ?? 0,
          lowerIsBetter: false,
        ),
        _metricRow(
          'Total words',
          '${a.totalWords ?? 0}',
          '${b.totalWords ?? 0}',
          aVal: (a.totalWords ?? 0).toDouble(),
          bVal: (b.totalWords ?? 0).toDouble(),
          lowerIsBetter: false,
        ),
        _metricRow(
          'Silences',
          '${a.silenceCount ?? 0}',
          '${b.silenceCount ?? 0}',
          aVal: (a.silenceCount ?? 0).toDouble(),
          bVal: (b.silenceCount ?? 0).toDouble(),
          lowerIsBetter: true,
        ),
        _metricRow(
          'Longest pause',
          _formatSeconds(a.longestSilenceSeconds ?? 0),
          _formatSeconds(b.longestSilenceSeconds ?? 0),
          aVal: a.longestSilenceSeconds ?? 0,
          bVal: b.longestSilenceSeconds ?? 0,
          lowerIsBetter: true,
        ),
      ],
    );
  }

  Widget _metricRow(
    String label,
    String aText,
    String bText, {
    required double aVal,
    required double bVal,
    required bool lowerIsBetter,
  }) =>
      _comparisonMetricRow(
        label,
        aText,
        bText,
        aVal: aVal,
        bVal: bVal,
        lowerIsBetter: lowerIsBetter,
      );
}

// Shared metric row used by both session and category comparisons: two big
// numbers with the "better" side coloured green and the other red.
Widget _comparisonMetricRow(
  String label,
  String aText,
  String bText, {
  required double aVal,
  required double bVal,
  required bool lowerIsBetter,
}) {
  Color aColor = Colors.black87;
  Color bColor = Colors.black87;
  // Only colour a winner/loser when the two sides actually differ. Compare the
  // displayed text too, so values that round to the same number (e.g. 87.36 vs
  // 87.44 both shown as "87%") stay neutral instead of one red and one green.
  if (aVal != bVal && aText != bText) {
    final aBetter = lowerIsBetter ? aVal < bVal : aVal > bVal;
    aColor = aBetter ? Colors.green.shade700 : Colors.red.shade400;
    bColor = aBetter ? Colors.red.shade400 : Colors.green.shade700;
  }

  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  aText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: aColor,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: Colors.grey.shade300,
              ),
              Expanded(
                child: Text(
                  bText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: bColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _fmtSeconds(double s) {
  if (s < 60) return '${s.toStringAsFixed(1)}s';
  final m = (s / 60).floor();
  final rem = (s - m * 60).toStringAsFixed(0);
  return '${m}m ${rem}s';
}

// Label used for recordings saved without a category (mirrors history_screen).
const String _kUncategorized = 'Uncategorized';

String _categoryOf(Recording r) =>
    r.category.trim().isEmpty ? _kUncategorized : r.category.trim();

double _mean(Iterable<double?> values) {
  final present = values.whereType<double>().toList();
  if (present.isEmpty) return 0;
  return present.reduce((a, b) => a + b) / present.length;
}

// Averaged metrics for all recordings of one category.
class _CategoryAverages {
  final double confidence;
  final double posture;
  final double lookAways;
  final double fillerWords;
  final double fillersPerMin;
  final double lexicalDiversity;
  final double totalWords;
  final double silences;
  final double longestPause;
  final int sessions;

  _CategoryAverages._({
    required this.confidence,
    required this.posture,
    required this.lookAways,
    required this.fillerWords,
    required this.fillersPerMin,
    required this.lexicalDiversity,
    required this.totalWords,
    required this.silences,
    required this.longestPause,
    required this.sessions,
  });

  factory _CategoryAverages.from(List<Recording> recs) {
    double fillerRate(Recording r) {
      final min = r.durationMs / 60000;
      return min > 0 ? (r.fillerWordCount ?? 0) / min : 0;
    }

    return _CategoryAverages._(
      confidence: _mean(recs.map((r) => r.averageConfidencePercentage)),
      posture: _mean(recs.map((r) => r.averagePostureStability)),
      lookAways: _mean(recs.map((r) => r.lookingAwayCount?.toDouble())),
      fillerWords: _mean(recs.map((r) => r.fillerWordCount?.toDouble())),
      fillersPerMin: _mean(recs.map(fillerRate)),
      lexicalDiversity: _mean(recs.map((r) => r.lexicalDiversity)),
      totalWords: _mean(recs.map((r) => r.totalWords?.toDouble())),
      silences: _mean(recs.map((r) => r.silenceCount?.toDouble())),
      longestPause: _mean(recs.map((r) => r.longestSilenceSeconds)),
      sessions: recs.length,
    );
  }
}

// ============================================================================
// Compare two categories by the average of their recordings.
// ============================================================================
class CompareCategoriesScreen extends StatefulWidget {
  const CompareCategoriesScreen({super.key});

  @override
  State<CompareCategoriesScreen> createState() =>
      _CompareCategoriesScreenState();
}

class _CompareCategoriesScreenState extends State<CompareCategoriesScreen> {
  String? _left;
  String? _right;

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.uid;
    final repo = RecordingRepository();

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Compare Categories')),
      body: StreamBuilder<List<Recording>>(
        stream: repo.watchRecordings(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data ?? [];
          final groups = <String, List<Recording>>{};
          for (final r in all) {
            groups.putIfAbsent(_categoryOf(r), () => []).add(r);
          }
          final categories = groups.keys.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          if (categories.length < 2) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.folder_copy_outlined,
                        size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'Need at least 2 categories',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Save recordings under different categories to compare '
                      'their averages.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // Drop selections that no longer exist, then default to the first
          // two categories.
          if (_left != null && !categories.contains(_left)) _left = null;
          if (_right != null && !categories.contains(_right)) _right = null;
          _left ??= categories[0];
          _right ??= categories[1];

          final leftAvg = _CategoryAverages.from(groups[_left] ?? const []);
          final rightAvg = _CategoryAverages.from(groups[_right] ?? const []);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPickers(categories, groups),
                const SizedBox(height: 16),
                _buildComparison(leftAvg, rightAvg),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPickers(
    List<String> categories,
    Map<String, List<Recording>> groups,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildDropdown(
            label: 'Category A',
            selected: _left,
            categories: categories,
            groups: groups,
            onChanged: (c) => setState(() => _left = c),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.compare_arrows),
        ),
        Expanded(
          child: _buildDropdown(
            label: 'Category B',
            selected: _right,
            categories: categories,
            groups: groups,
            onChanged: (c) => setState(() => _right = c),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? selected,
    required List<String> categories,
    required Map<String, List<Recording>> groups,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          key: ValueKey('$label-$selected'),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: categories
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(
                      '$c (${groups[c]?.length ?? 0})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildComparison(_CategoryAverages a, _CategoryAverages b) {
    return Column(
      children: [
        _comparisonMetricRow(
          'Sessions',
          '${a.sessions}',
          '${b.sessions}',
          aVal: a.sessions.toDouble(),
          bVal: b.sessions.toDouble(),
          lowerIsBetter: false,
        ),
        _comparisonMetricRow(
          'Confidence',
          '${a.confidence.toStringAsFixed(0)}%',
          '${b.confidence.toStringAsFixed(0)}%',
          aVal: a.confidence,
          bVal: b.confidence,
          lowerIsBetter: false,
        ),
        _comparisonMetricRow(
          'Posture',
          '${a.posture.toStringAsFixed(0)}%',
          '${b.posture.toStringAsFixed(0)}%',
          aVal: a.posture,
          bVal: b.posture,
          lowerIsBetter: false,
        ),
        _comparisonMetricRow(
          'Look-aways',
          a.lookAways.toStringAsFixed(1),
          b.lookAways.toStringAsFixed(1),
          aVal: a.lookAways,
          bVal: b.lookAways,
          lowerIsBetter: true,
        ),
        _comparisonMetricRow(
          'Filler words',
          a.fillerWords.toStringAsFixed(1),
          b.fillerWords.toStringAsFixed(1),
          aVal: a.fillerWords,
          bVal: b.fillerWords,
          lowerIsBetter: true,
        ),
        _comparisonMetricRow(
          'Fillers / min',
          a.fillersPerMin.toStringAsFixed(1),
          b.fillersPerMin.toStringAsFixed(1),
          aVal: a.fillersPerMin,
          bVal: b.fillersPerMin,
          lowerIsBetter: true,
        ),
        _comparisonMetricRow(
          'Vocabulary diversity',
          '${(a.lexicalDiversity * 100).toStringAsFixed(0)}%',
          '${(b.lexicalDiversity * 100).toStringAsFixed(0)}%',
          aVal: a.lexicalDiversity,
          bVal: b.lexicalDiversity,
          lowerIsBetter: false,
        ),
        _comparisonMetricRow(
          'Total words',
          a.totalWords.toStringAsFixed(0),
          b.totalWords.toStringAsFixed(0),
          aVal: a.totalWords,
          bVal: b.totalWords,
          lowerIsBetter: false,
        ),
        _comparisonMetricRow(
          'Silences',
          a.silences.toStringAsFixed(1),
          b.silences.toStringAsFixed(1),
          aVal: a.silences,
          bVal: b.silences,
          lowerIsBetter: true,
        ),
        _comparisonMetricRow(
          'Longest pause',
          _fmtSeconds(a.longestPause),
          _fmtSeconds(b.longestPause),
          aVal: a.longestPause,
          bVal: b.longestPause,
          lowerIsBetter: true,
        ),
      ],
    );
  }
}
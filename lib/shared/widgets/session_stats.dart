import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/recording.dart';
import 'glass.dart';

// Aggregate statistics computed across an arbitrary set of recordings.
// Reused for the Home "your averages" panel, per-category folders, and the
// combined averages of a multi-selected group on the All sessions screen.
class SessionStats {
  final int sessionCount;
  final int categoryCount;
  final int totalDurationMs;
  final double? avgConfidence;
  final double? avgPosture;
  final double? avgLookAways;
  final double? avgWpm;
  final double? avgFillerPerMin;

  const SessionStats({
    required this.sessionCount,
    required this.categoryCount,
    required this.totalDurationMs,
    this.avgConfidence,
    this.avgPosture,
    this.avgLookAways,
    this.avgWpm,
    this.avgFillerPerMin,
  });

  factory SessionStats.from(List<Recording> recordings) {
    double? avg(Iterable<double?> xs) {
      final vals = xs.whereType<double>().toList();
      if (vals.isEmpty) return null;
      return vals.reduce((a, b) => a + b) / vals.length;
    }

    final totalDuration =
        recordings.fold<int>(0, (sum, r) => sum + r.durationMs);

    final categories = recordings
        .map((r) => r.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet();

    final lookAwayVals =
        recordings.map((r) => r.lookingAwayCount).whereType<int>().toList();
    final avgLookAways = lookAwayVals.isEmpty
        ? null
        : lookAwayVals.reduce((a, b) => a + b) / lookAwayVals.length;

    // Speech averages only count recordings that were actually transcribed.
    final analyzed = recordings.where((r) => r.hasTranscript).toList();
    final wpms = <double>[];
    final fillerRates = <double>[];
    for (final r in analyzed) {
      final minutes = r.durationMs / 60000;
      if (minutes > 0) {
        wpms.add((r.totalWords ?? 0) / minutes);
        fillerRates.add((r.fillerWordCount ?? 0) / minutes);
      }
    }

    return SessionStats(
      sessionCount: recordings.length,
      categoryCount: categories.length,
      totalDurationMs: totalDuration,
      avgConfidence: avg(recordings.map((r) => r.averageConfidencePercentage)),
      avgPosture: avg(recordings.map((r) => r.averagePostureStability)),
      avgLookAways: avgLookAways,
      avgWpm: wpms.isEmpty ? null : wpms.reduce((a, b) => a + b) / wpms.length,
      avgFillerPerMin: fillerRates.isEmpty
          ? null
          : fillerRates.reduce((a, b) => a + b) / fillerRates.length,
    );
  }

  String get totalDurationLabel {
    final d = Duration(milliseconds: totalDurationMs);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// Renders a [SessionStats] as two confidence/posture gauges plus a grid of
// stat boxes. Pass [includeCategories] when the recordings can span more than
// one category (Home, combined selection); leave it off inside a single
// folder where the count would always be 1.
class SessionStatsCard extends StatelessWidget {
  final List<Recording> recordings;
  final String title;
  final bool includeCategories;
  final bool framed;
  final bool compact;

  const SessionStatsCard({
    super.key,
    required this.recordings,
    this.title = 'Averages',
    this.includeCategories = false,
    this.framed = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final stats = SessionStats.from(recordings);

    final items = <({String label, String value})>[
      (label: 'Sessions', value: '${stats.sessionCount}'),
      (label: 'Practice time', value: stats.totalDurationLabel),
      if (includeCategories)
        (label: 'Categories', value: '${stats.categoryCount}'),
      (
        label: 'Look-aways',
        value:
            stats.avgLookAways != null ? stats.avgLookAways!.toStringAsFixed(0) : '—',
      ),
      (
        label: 'Speech rate',
        value: stats.avgWpm != null ? '${stats.avgWpm!.toStringAsFixed(0)} WPM' : '—',
      ),
      (
        label: 'Filler / min',
        value: stats.avgFillerPerMin != null
            ? stats.avgFillerPerMin!.toStringAsFixed(1)
            : '—',
      ),
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.wine,
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _gauge('Confidence', stats.avgConfidence),
            _gauge('Posture', stats.avgPosture),
          ],
        ),
        SizedBox(height: compact ? 10 : 16),
        _statGrid(items),
      ],
    );

    if (!framed) return content;

    return GlassCard(
      radius: compact ? 22 : 26,
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: content,
    );
  }

  // Lays out the stat boxes two-per-row, padding the final row with an empty
  // slot when there is an odd number so widths stay aligned.
  Widget _statGrid(List<({String label, String value})> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final a = items[i];
      final b = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : (compact ? 6 : 8)),
          child: Row(
            children: [
              _statBox(a.label, a.value),
              if (b != null)
                _statBox(b.label, b.value)
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _gauge(String label, double? value) {
    final double pct = (value ?? 0).clamp(0, 100).toDouble();
    final double size = compact ? 66 : 84;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: pct / 100,
                  strokeWidth: compact ? 6 : 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.paleMauve,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.deepMauve),
                ),
              ),
              Text(
                value != null ? '${pct.toStringAsFixed(0)}%' : '—',
                style: TextStyle(
                  fontSize: compact ? 15 : 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.wine,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(
          label,
          style: TextStyle(
            color: AppColors.midMauve,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
        decoration: BoxDecoration(
          color: AppColors.paleMauve,
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: compact ? 15 : 17,
                fontWeight: FontWeight.w700,
                color: AppColors.tintDeep,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                  fontSize: compact ? 11 : 12, color: AppColors.midMauve),
            ),
          ],
        ),
      ),
    );
  }
}

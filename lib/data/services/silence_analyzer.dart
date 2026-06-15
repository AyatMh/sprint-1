import '../models/recording.dart';

class SilenceEvent {
  final double startSeconds;
  final double endSeconds;
  final double durationSeconds;

  SilenceEvent({
    required this.startSeconds,
    required this.endSeconds,
    required this.durationSeconds,
  });

  Map<String, dynamic> toMap() => {
        'start': startSeconds,
        'end': endSeconds,
        'duration': durationSeconds,
      };

  factory SilenceEvent.fromMap(Map<String, dynamic> map) => SilenceEvent(
        startSeconds: (map['start'] ?? 0).toDouble(),
        endSeconds: (map['end'] ?? 0).toDouble(),
        durationSeconds: (map['duration'] ?? 0).toDouble(),
      );
}

class SilenceResult {
  final int count;
  final double totalSilenceSeconds;
  final double longestSilenceSeconds;
  final double averageSilenceSeconds;
  final List<SilenceEvent> events;

  SilenceResult({
    required this.count,
    required this.totalSilenceSeconds,
    required this.longestSilenceSeconds,
    required this.averageSilenceSeconds,
    required this.events,
  });
}

class SilenceAnalyzer {
  static const double silenceThresholdSeconds = 2.0;
  static const double minRecordingSeconds = 3.0;

  static SilenceResult analyze({
    required List<TranscriptSegment> segments,
    required double totalDurationSeconds,
  }) {
    if (segments.isEmpty || totalDurationSeconds < minRecordingSeconds) {
      return SilenceResult(
        count: 0,
        totalSilenceSeconds: 0,
        longestSilenceSeconds: 0,
        averageSilenceSeconds: 0,
        events: [],
      );
    }

    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    final events = <SilenceEvent>[];

    if (sorted.first.start >= silenceThresholdSeconds) {
      events.add(SilenceEvent(
        startSeconds: 0,
        endSeconds: sorted.first.start,
        durationSeconds: sorted.first.start,
      ));
    }

    for (int i = 0; i < sorted.length - 1; i++) {
      final gap = sorted[i + 1].start - sorted[i].end;
      if (gap >= silenceThresholdSeconds) {
        events.add(SilenceEvent(
          startSeconds: sorted[i].end,
          endSeconds: sorted[i + 1].start,
          durationSeconds: gap,
        ));
      }
    }

    final trailingGap = totalDurationSeconds - sorted.last.end;
    if (trailingGap >= silenceThresholdSeconds) {
      events.add(SilenceEvent(
        startSeconds: sorted.last.end,
        endSeconds: totalDurationSeconds,
        durationSeconds: trailingGap,
      ));
    }

    if (events.isEmpty) {
      return SilenceResult(
        count: 0,
        totalSilenceSeconds: 0,
        longestSilenceSeconds: 0,
        averageSilenceSeconds: 0,
        events: [],
      );
    }

    final total = events.fold<double>(0, (sum, e) => sum + e.durationSeconds);
    final longest = events
        .map((e) => e.durationSeconds)
        .reduce((a, b) => a > b ? a : b);
    final average = total / events.length;

    return SilenceResult(
      count: events.length,
      totalSilenceSeconds: total,
      longestSilenceSeconds: longest,
      averageSilenceSeconds: average,
      events: events,
    );
  }
}
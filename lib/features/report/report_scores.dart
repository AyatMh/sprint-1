import '../../data/models/recording.dart';

// One labelled skill dimension shown on the report (and in the PDF).
class SkillScore {
  final String label;
  final int value; // 0-100
  const SkillScore(this.label, this.value);
}

// Derives all the 0-100 scores a performance report shows from a recording's
// raw metrics. Shared by the report screen and the PDF export so they never
// drift apart.
class ReportScores {
  final Recording recording;
  ReportScores(this.recording);

  double get _durationMin => recording.durationMs / 60000;

  int get filler {
    // Fewer fillers per minute = higher. 0/min = 100, 10+/min = 0.
    final rate =
        _durationMin > 0 ? (recording.fillerWordCount ?? 0) / _durationMin : 0;
    return (100 - rate * 10).clamp(0, 100).round();
  }

  int get diversity =>
      ((recording.lexicalDiversity ?? 0) * 100).clamp(0, 100).round();

  int get silence {
    final total = recording.totalSilenceSeconds ?? 0;
    return (100 - total * 5).clamp(0, 100).round();
  }

  // Body-language scores — null when the recording predates these metrics.
  int? get confidence =>
      recording.averageConfidencePercentage?.clamp(0, 100).round();

  int? get posture =>
      recording.averagePostureStability?.clamp(0, 100).round();

  int? get eyeContact {
    final lookAways = recording.lookingAwayCount;
    if (lookAways == null) return null;
    final rate =
        _durationMin > 0 ? lookAways / _durationMin : lookAways.toDouble();
    return (100 - rate * 8).clamp(0, 100).round();
  }

  // Speech first, then body language when available. Drives both the bars and
  // the overall score, so the overall reflects speech AND body language.
  List<SkillScore> get skills => [
        SkillScore('Fluency', filler),
        SkillScore('Clarity', diversity),
        SkillScore('Pacing', silence),
        if (confidence != null) SkillScore('Confidence', confidence!),
        if (eyeContact != null) SkillScore('Eye contact', eyeContact!),
        if (posture != null) SkillScore('Posture', posture!),
      ];

  int get overall {
    final values = skills.map((s) => s.value).toList();
    return values.isEmpty
        ? 0
        : (values.reduce((a, b) => a + b) / values.length).round();
  }

  static String label(int score) => score >= 75
      ? 'Excellent'
      : score >= 50
          ? 'Good'
          : 'Keep practicing';
}

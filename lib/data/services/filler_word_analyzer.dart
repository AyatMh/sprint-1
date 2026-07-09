class FillerWordResult {
  final int total;
  final Map<String, int> breakdown;

  FillerWordResult({required this.total, required this.breakdown});
}

class FillerWordAnalyzer {
  // English filler words and phrases (case-insensitive matching)
  static const List<String> englishFillers = [
    'um',
    'umm',
    'uh',
    'uhh',
    'er',
    'ah',
    'like',
    'you know',
    'i mean',
    'actually',
    'basically',
    'literally',
    'sort of',
    'kind of',
    // NOTE: standalone words like "right" and "okay" are intentionally NOT
    // counted — they're legitimate vocabulary far more often than fillers
    // ("that's right", "okay, next topic") and skewed the counts.
  ];

  static FillerWordResult analyze(String transcript, {String language = 'en'}) {
    if (transcript.trim().isEmpty) {
      return FillerWordResult(total: 0, breakdown: {});
    }

    final fillers = englishFillers;
    final lower = transcript.toLowerCase();
    final breakdown = <String, int>{};
    int total = 0;

    for (final filler in fillers) {
      // Match whole words/phrases only (word boundaries)
      final pattern = RegExp(
        r'\b' + RegExp.escape(filler) + r'\b',
        caseSensitive: false,
      );
      final matches = pattern.allMatches(lower);
      final count = matches.length;
      if (count > 0) {
        breakdown[filler] = count;
        total += count;
      }
    }

    return FillerWordResult(total: total, breakdown: breakdown);
  }
}
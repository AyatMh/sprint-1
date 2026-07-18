class VocabularyResult {
  final int totalWords;
  final int uniqueWords;
  final double lexicalDiversity; // unique / total (0-1, higher = richer vocab)
  final List<WordFrequency> topWords; // sorted by count, top N
  final List<WordFrequency> overusedWords; // appeared > threshold

  VocabularyResult({
    required this.totalWords,
    required this.uniqueWords,
    required this.lexicalDiversity,
    required this.topWords,
    required this.overusedWords,
  });
}

class WordFrequency {
  final String word;
  final int count;

  WordFrequency({required this.word, required this.count});

  Map<String, dynamic> toMap() => {'word': word, 'count': count};

  factory WordFrequency.fromMap(Map<String, dynamic> map) =>
      WordFrequency(word: map['word'] ?? '', count: map['count'] ?? 0);
}

class VocabularyAnalyzer {
  // Common English stop-words to ignore (not meaningful vocabulary)
  static const Set<String> englishStopWords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'so', 'because', 'as',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
    'have', 'has', 'had', 'having',
    'do', 'does', 'did', 'doing',
    'i', 'me', 'my', 'mine', 'myself',
    'you', 'your', 'yours', 'yourself', 'yourselves',
    'he', 'him', 'his', 'himself',
    'she', 'her', 'hers', 'herself',
    'it', 'its', 'itself',
    'we', 'us', 'our', 'ours', 'ourselves',
    'they', 'them', 'their', 'theirs', 'themselves',
    'this', 'that', 'these', 'those',
    'what', 'which', 'who', 'whom', 'whose',
    'where', 'when', 'why', 'how',
    'in', 'on', 'at', 'by', 'for', 'with', 'about', 'against',
    'between', 'into', 'through', 'during', 'before', 'after',
    'above', 'below', 'from', 'up', 'down', 'out', 'off', 'over', 'under',
    'to', 'of', 'than', 'then',
    'too', 'very', 'just', 'only', 'also', 'yet', 'still',
    'no', 'not', 'nor', 'don', 'didn', 'won', 'can', 'cannot',
    'will', 'would', 'should', 'could', 'may', 'might', 'must', 'shall',
    'all', 'any', 'some', 'each', 'every', 'few', 'more', 'most', 'other',
    'such', 'own', 'same', 'one', 'two', 'first', 'last',
    'there', 'here', 'now',
    'go', 'going', 'went', 'get', 'got', 'getting',
    'say', 'said', 'says', 'saying',
    // Common filler-adjacent (already counted as fillers, exclude from vocab)
    'um', 'umm', 'uh', 'er', 'ah', 'like', 'okay', 'right',
  };

  // Words appearing more than this count are "overused"
  static const int overusedThreshold = 4;
  // Show top N most-used words
  static const int topWordsLimit = 8;

  static VocabularyResult analyze(String transcript) {
    if (transcript.trim().isEmpty) {
      return VocabularyResult(
        totalWords: 0,
        uniqueWords: 0,
        lexicalDiversity: 0,
        topWords: [],
        overusedWords: [],
      );
    }

    // Lowercase, strip punctuation, split on whitespace
    final cleaned = transcript
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final allWords = cleaned.split(' ').where((w) => w.isNotEmpty).toList();

    final meaningfulWords = allWords
        .where((w) => w.length >= 3 && !englishStopWords.contains(w))
        .toList();

    final counts = <String, int>{};
    for (final w in meaningfulWords) {
      counts[w] = (counts[w] ?? 0) + 1;
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topWords = entries
        .take(topWordsLimit)
        .map((e) => WordFrequency(word: e.key, count: e.value))
        .toList();

    final overusedWords = entries
        .where((e) => e.value >= overusedThreshold)
        .map((e) => WordFrequency(word: e.key, count: e.value))
        .toList();

    final total = allWords.length;
    final unique = counts.length;
    // Diversity must compare unique meaningful words against the *same*
    // population (meaningful word occurrences), not every word spoken —
    // dividing by allWords.length here previously mixed the two universes,
    // which silently deflated the score by the stop-word share of any
    // normal sentence (articles, pronouns, etc. never counted toward
    // "unique" but always inflated the denominator).
    final diversity =
        meaningfulWords.isNotEmpty ? unique / meaningfulWords.length : 0.0;

    return VocabularyResult(
      totalWords: total,
      uniqueWords: unique,
      lexicalDiversity: diversity,
      topWords: topWords,
      overusedWords: overusedWords,
    );
  }
}
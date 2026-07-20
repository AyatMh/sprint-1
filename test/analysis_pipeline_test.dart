// Verifies the speech-analysis pipeline interprets a known answer correctly.
//
// We feed a fixed interview answer (and fixed transcript segments) through the
// exact analyzer classes the app uses, and assert the numbers against values
// computed by hand from the script. This proves that, given a transcript, the
// app reports filler words, vocabulary and silences correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:interviewpro/data/models/recording.dart';
import 'package:interviewpro/data/services/filler_word_analyzer.dart';
import 'package:interviewpro/data/services/vocabulary_analyzer.dart';
import 'package:interviewpro/data/services/silence_analyzer.dart';

void main() {
  // A realistic spoken answer with deliberately placed fillers and a repeated
  // word ("project" x4), so every metric has a known expected value.
  const answer =
      'So um I led a project where we basically rebuilt the payment system. '
      'You know the old project was slow, uh, and the team was, like, frustrated. '
      'I mean we actually shipped the new project in three months. '
      'Honestly the project taught me a lot about teamwork.';

  group('FillerWordAnalyzer', () {
    final result = FillerWordAnalyzer.analyze(answer);

    test('counts each filler phrase correctly', () {
      // By hand from the script:
      //   um=1, uh=1, like=1, you know=1, i mean=1, basically=1, actually=1
      expect(result.breakdown['um'], 1);
      expect(result.breakdown['uh'], 1);
      expect(result.breakdown['like'], 1);
      expect(result.breakdown['you know'], 1);
      expect(result.breakdown['i mean'], 1);
      expect(result.breakdown['basically'], 1);
      expect(result.breakdown['actually'], 1);
      expect(result.total, 7);
    });

    test('does not count "right"/"okay" (removed from filler list)', () {
      final r = FillerWordAnalyzer.analyze("That's right, okay, let's move on.");
      expect(r.total, 0);
    });

    test('uses word boundaries (does not match inside words)', () {
      // "drumming" contains "um", "alike" contains "like" — must NOT count.
      final r = FillerWordAnalyzer.analyze('I was drumming, we are alike.');
      expect(r.total, 0);
    });
  });

  group('VocabularyAnalyzer', () {
    final result = VocabularyAnalyzer.analyze(answer);

    test('total words counts every token', () {
      final expectedTotal = answer
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s']"), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      expect(result.totalWords, expectedTotal);
    });

    test('flags the most-repeated meaningful word', () {
      // "project" appears 4 times and is the clear top word.
      expect(result.topWords.first.word, 'project');
      expect(result.topWords.first.count, 4);
    });

    test('marks "project" as overused (>= 4 occurrences)', () {
      expect(result.overusedWords.any((w) => w.word == 'project'), isTrue);
    });

    test('lexical diversity is unique/total within (0,1]', () {
      expect(result.lexicalDiversity, greaterThan(0));
      expect(result.lexicalDiversity, lessThanOrEqualTo(1));
    });
  });

  group('SilenceAnalyzer', () {
    test('detects a single mid-answer gap longer than 7s', () {
      // Three spoken segments with an 8.0s gap between #2 and #3.
      final segments = [
        TranscriptSegment(start: 0.0, end: 4.0, text: 'first part'),
        TranscriptSegment(start: 4.5, end: 8.0, text: 'second part'),
        TranscriptSegment(start: 16.0, end: 20.0, text: 'third part'),
      ];
      final result = SilenceAnalyzer.analyze(
        segments: segments,
        totalDurationSeconds: 20.0,
      );
      expect(result.count, 1); // the 0.5s gap is ignored, the 8.0s gap counts
      expect(result.longestSilenceSeconds, closeTo(8.0, 0.001));
      expect(result.totalSilenceSeconds, closeTo(8.0, 0.001));
    });

    test('detects a long pause before the speaker starts', () {
      final segments = [
        TranscriptSegment(start: 8.0, end: 12.0, text: 'late start'),
      ];
      final result = SilenceAnalyzer.analyze(
        segments: segments,
        totalDurationSeconds: 12.0,
      );
      expect(result.count, 1);
      expect(result.longestSilenceSeconds, closeTo(8.0, 0.001));
    });

    test('reports no silences for continuous speech', () {
      final segments = [
        TranscriptSegment(start: 0.0, end: 4.0, text: 'a'),
        TranscriptSegment(start: 4.2, end: 8.0, text: 'b'),
      ];
      final result = SilenceAnalyzer.analyze(
        segments: segments,
        totalDurationSeconds: 8.0,
      );
      expect(result.count, 0);
    });
  });

  group('Recording.copyWith', () {
    test('preserves body-language metrics while updating analysis', () {
      final original = Recording(
        id: 'r1',
        userId: 'u1',
        localPath: '/tmp/x.mp4',
        durationMs: 60000,
        fileSizeBytes: 1000,
        createdAt: DateTime(2026, 1, 1),
        name: 'My Session',
        category: 'Behavioral',
        averageConfidencePercentage: 72.5,
        lookingAwayCount: 3,
        averagePostureStability: 88.0,
      );

      final updated = original.copyWith(
        transcript: 'hello world',
        totalWords: 2,
      );

      // Analysis fields updated...
      expect(updated.transcript, 'hello world');
      expect(updated.totalWords, 2);
      // ...while name, category and live metrics are preserved.
      expect(updated.name, 'My Session');
      expect(updated.category, 'Behavioral');
      expect(updated.averageConfidencePercentage, 72.5);
      expect(updated.lookingAwayCount, 3);
      expect(updated.averagePostureStability, 88.0);
    });
  });
}

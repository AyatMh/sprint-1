// Real end-to-end proof, run ON the emulator/device (real network + plugins):
//   flutter test integration_test/whisper_real_test.dart -d emulator-5554
//
// Transcribes a known spoken answer through the app's actual TranscriptionService
// (real Whisper call) and runs the real analyzers, printing the results. This is
// the authoritative check that recorded audio is interpreted correctly — unlike
// `flutter test`, the integration_test binding allows real network requests.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:interviewpro/data/services/transcription_service.dart';
import 'package:interviewpro/data/services/filler_word_analyzer.dart';
import 'package:interviewpro/data/services/vocabulary_analyzer.dart';
import 'package:interviewpro/data/services/silence_analyzer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real audio -> transcript -> analysis (on device)',
      (tester) async {
    await dotenv.load(fileName: '.env');

    // Write the bundled known-speech WAV to a real file on the device.
    final bytes = await rootBundle.load('test_assets/known_answer.wav');
    final dir = await getTemporaryDirectory();
    final wavPath = '${dir.path}/known_answer.wav';
    await File(wavPath).writeAsBytes(bytes.buffer.asUint8List());

    // 1) Real transcription via the app's service.
    final result = await TranscriptionService().transcribe(
      filePath: wavPath,
      language: 'en',
    );

    // 2) Real analyzers on the returned transcript.
    final fillers = FillerWordAnalyzer.analyze(result.text);
    final vocab = VocabularyAnalyzer.analyze(result.text);
    final silence = SilenceAnalyzer.analyze(
      segments: result.segments,
      totalDurationSeconds: result.duration,
    );

    // ignore: avoid_print
    print('\n================ REAL WHISPER ROUND-TRIP ================');
    // ignore: avoid_print
    print('TRANSCRIPT (${result.language}, '
        '${result.duration.toStringAsFixed(1)}s):\n${result.text}');
    // ignore: avoid_print
    print('\nFiller words: ${fillers.total} -> ${fillers.breakdown}');
    // ignore: avoid_print
    print('Vocabulary: ${vocab.totalWords} words, ${vocab.uniqueWords} unique, '
        '${(vocab.lexicalDiversity * 100).toStringAsFixed(0)}% diversity');
    // ignore: avoid_print
    print('Top words: '
        '${vocab.topWords.map((w) => '${w.word}x${w.count}').join(', ')}');
    // ignore: avoid_print
    print('Silences: ${silence.count}, longest '
        '${silence.longestSilenceSeconds.toStringAsFixed(1)}s');
    // ignore: avoid_print
    print('========================================================\n');

    expect(result.text.trim().length, greaterThan(40));
    expect(result.text.toLowerCase(), contains('project'));
    expect(vocab.totalWords, greaterThan(20));
    expect(fillers.total, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

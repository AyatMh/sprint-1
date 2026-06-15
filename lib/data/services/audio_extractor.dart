import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

// Pulls the audio track out of a recorded MP4 into a small .m4a file using
// the platform's native demuxer (no re-encoding). Whisper only needs the
// audio, and the full video easily exceeds its 25 MB upload limit.
class AudioExtractor {
  static const MethodChannel _channel =
      MethodChannel('interviewpro/audio_extractor');

  /// Returns the path of the extracted .m4a, or null if extraction isn't
  /// available on this platform or failed (callers fall back to the video).
  static Future<String?> extractAudio(String videoPath) async {
    if (!Platform.isAndroid) return null;
    try {
      final tmpDir = await getTemporaryDirectory();
      final outputPath =
          '${tmpDir.path}/whisper_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final result = await _channel.invokeMethod<String>('extractAudio', {
        'inputPath': videoPath,
        'outputPath': outputPath,
      });
      if (result == null) return null;
      final out = File(result);
      if (!await out.exists() || await out.length() == 0) return null;
      return result;
    } catch (_) {
      return null;
    }
  }
}

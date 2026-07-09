import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/recording.dart';
import 'audio_extractor.dart';

class TranscriptionResult {
  final String text;
  final List<TranscriptSegment> segments;
  final String language;
  final double duration;

  TranscriptionResult({
    required this.text,
    required this.segments,
    required this.language,
    required this.duration,
  });
}

class TranscriptionService {
  final Dio _dio = Dio();
  static const String _endpoint =
      'https://api.openai.com/v1/audio/transcriptions';

  // Whisper rejects uploads above 25 MB; leave a little headroom.
  static const int _maxUploadBytes = 24 * 1024 * 1024;

  Future<TranscriptionResult> transcribe({
    required String filePath,
    String language = 'en',
  }) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY missing in .env file');
    }

    if (!await File(filePath).exists()) {
      throw Exception(
        'Recording file not found on this device. It may have been moved or deleted.',
      );
    }

    // Whisper only needs the audio: extract it from the video so even long
    // sessions stay well under the 25 MB upload limit. Falls back to the
    // original file when extraction isn't available.
    String uploadPath = filePath;
    String? extractedPath;
    extractedPath = await AudioExtractor.extractAudio(filePath);
    if (extractedPath != null) {
      uploadPath = extractedPath;
    }

    final uploadSize = await File(uploadPath).length();
    if (uploadSize > _maxUploadBytes) {
      if (extractedPath != null) {
        await File(extractedPath).delete().catchError((_) => File(''));
      }
      throw Exception(
        'This recording is too large to transcribe (${(uploadSize / (1024 * 1024)).toStringAsFixed(0)} MB; Whisper accepts up to 25 MB).',
      );
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(uploadPath),
      'model': 'whisper-1',
      'response_format': 'verbose_json',
      'language': language,
      // By default Whisper "cleans" disfluencies (um, uh, like, you know) out
      // of the transcript, so the filler-word analyzer never sees them. A
      // prompt full of fillers nudges Whisper to keep them verbatim, and
      // temperature 0 keeps the output deterministic.
      'prompt':
          'Um, uh, er, ah, hmm. Well, so, like, you know, I mean, actually, '
              'basically, literally, sort of, kind of.',
      'temperature': '0',
    });

    try {
      final response = await _dio.post(
        _endpoint,
        data: formData,
        options: Options(
          // Only set Authorization. Do NOT set Content-Type here: dio derives
          // 'multipart/form-data; boundary=...' from the FormData, and setting
          // it manually drops the boundary, which makes the API reject the
          // request with a 400 (this previously broke all transcriptions).
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final segmentsRaw = data['segments'] as List? ?? [];
      final segments = segmentsRaw
          .map((s) => TranscriptSegment(
                start: (s['start'] ?? 0).toDouble(),
                end: (s['end'] ?? 0).toDouble(),
                text: (s['text'] ?? '').toString().trim(),
              ))
          .toList();

      return TranscriptionResult(
        text: data['text'] ?? '',
        segments: segments,
        language: data['language'] ?? language,
        duration: (data['duration'] ?? 0).toDouble(),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      if (code == 401) {
        throw Exception('Invalid OpenAI API key. Check your .env file.');
      } else if (code == 429) {
        throw Exception('Rate limited. Wait a minute and try again.');
      } else if (code == 413) {
        throw Exception('File too large (max 25 MB for Whisper).');
      }
      throw Exception('Whisper API error ($code): $body');
    } finally {
      // The extracted audio is a temp artifact — clean it up either way.
      if (extractedPath != null) {
        await File(extractedPath).delete().catchError((_) => File(''));
      }
    }
  }
}
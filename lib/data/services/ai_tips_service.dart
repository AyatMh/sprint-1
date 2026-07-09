import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/recording.dart';

// Structured AI coaching feedback for a single recording.
class AiTipsResult {
  final String summary;
  final List<String> strengths;
  final List<String> improvements;
  final List<String> tips;

  AiTipsResult({
    required this.summary,
    required this.strengths,
    required this.improvements,
    required this.tips,
  });

  Map<String, dynamic> toMap() => {
        'summary': summary,
        'strengths': strengths,
        'improvements': improvements,
        'tips': tips,
      };

  factory AiTipsResult.fromMap(Map<String, dynamic> map) => AiTipsResult(
        summary: (map['summary'] ?? '').toString(),
        strengths: _stringList(map['strengths']),
        improvements: _stringList(map['improvements']),
        tips: _stringList(map['tips']),
      );

  static List<String> _stringList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];
}

// Sends a recording's analysis to an LLM and gets back actionable interview
// coaching tips. Reuses the same OpenAI key as the transcription service.
class AiTipsService {
  final Dio _dio = Dio();
  static const String _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const String _model = 'gpt-4o-mini';

  Future<AiTipsResult> generateTips(Recording recording) async {
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OPENAI_API_KEY missing in .env file');
    }

    final metrics = _buildMetricsSummary(recording);

    const systemPrompt =
        'You are an expert interview and public-speaking coach. You are given '
        'objective metrics (and, when available, a transcript) from a practice '
        'interview answer. Give specific, encouraging and actionable feedback '
        'the candidate can act on next time. Base every point strictly on the '
        'data provided and never invent numbers. Respond ONLY with JSON of the '
        'shape: {"summary": string, "strengths": string[], '
        '"improvements": string[], "tips": string[]}. "summary" is one or two '
        'sentences. Each list item is one concise sentence. Provide 2-4 items '
        'per list.';

    final transcriptBlock = recording.hasTranscript
        ? 'Transcript:\n"""\n${_truncate(recording.transcript!, 6000)}\n"""'
        : 'No transcript is available for this recording.';

    final userPrompt = 'Practice session data:\n\n$metrics\n\n$transcriptBlock';

    try {
      final response = await _dio.post(
        _endpoint,
        data: {
          'model': _model,
          'temperature': 0.5,
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final content =
          data['choices']?[0]?['message']?['content'] as String? ?? '';
      if (content.isEmpty) {
        throw Exception('The AI returned an empty response. Try again.');
      }
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      return AiTipsResult.fromMap(parsed);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        throw Exception('Invalid OpenAI API key. Check your .env file.');
      } else if (code == 429) {
        throw Exception('Rate limited. Wait a minute and try again.');
      }
      throw Exception('AI tips error ($code): ${e.response?.data ?? e.message}');
    }
  }

  // Renders the recording's metrics as a compact, human-readable block the
  // model can reason over. Only includes fields that were actually measured.
  String _buildMetricsSummary(Recording r) {
    final b = StringBuffer();
    final durationMin = r.durationMs / 60000;
    b.writeln('Duration: ${durationMin.toStringAsFixed(1)} min');

    if (r.averageConfidencePercentage != null) {
      b.writeln(
          'Facial confidence: ${r.averageConfidencePercentage!.toStringAsFixed(0)}% (higher is more confident)');
    }
    if (r.lookingAwayCount != null) {
      b.writeln('Broke eye contact: ${r.lookingAwayCount} time(s)');
    }
    if (r.averagePostureStability != null) {
      b.writeln(
          'Posture stability: ${r.averagePostureStability!.toStringAsFixed(0)}% (higher is steadier)');
    }
    if (r.fillerWordCount != null) {
      final rate = durationMin > 0 ? r.fillerWordCount! / durationMin : 0;
      b.writeln(
          'Filler words: ${r.fillerWordCount} total (${rate.toStringAsFixed(1)} per minute)');
      final breakdown = r.fillerWordBreakdown;
      if (breakdown != null && breakdown.isNotEmpty) {
        final parts =
            breakdown.entries.map((e) => '${e.key}×${e.value}').join(', ');
        b.writeln('Filler breakdown: $parts');
      }
    }
    if (r.totalWords != null) {
      b.writeln('Words spoken: ${r.totalWords} (${r.uniqueWords ?? '-'} unique)');
    }
    if (r.lexicalDiversity != null) {
      b.writeln(
          'Lexical diversity: ${(r.lexicalDiversity! * 100).toStringAsFixed(0)}%');
    }
    final overused = r.overusedWords;
    if (overused != null && overused.isNotEmpty) {
      final parts = overused
          .take(6)
          .map((w) => '${w['word']}×${w['count']}')
          .join(', ');
      b.writeln('Overused words: $parts');
    }
    if (r.silenceCount != null) {
      b.writeln(
          'Long pauses: ${r.silenceCount} (total ${r.totalSilenceSeconds?.toStringAsFixed(0) ?? '-'}s, '
          'longest ${r.longestSilenceSeconds?.toStringAsFixed(1) ?? '-'}s)');
    }
    return b.toString();
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

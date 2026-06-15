import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/recording.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../../data/services/filler_word_analyzer.dart';
import '../../../data/services/silence_analyzer.dart';
import '../../../data/services/transcription_service.dart';
import '../../../data/services/vocabulary_analyzer.dart';
import '../../auth/providers/auth_provider.dart';
import '../../report/screens/performance_report_screen.dart';
import '../../../core/theme/app_theme.dart';

class AnalysisScreen extends StatefulWidget {
  final Recording recording;
  const AnalysisScreen({super.key, required this.recording});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _loading = false;
  String _statusMessage = '';
  late Recording _recording;

  @override
  void initState() {
    super.initState();
    _recording = widget.recording;
  }

  Future<void> _transcribe() async {
    final userId = context.read<AuthProvider>().user?.uid;
    if (userId == null) return;

    setState(() {
      _loading = true;
      _statusMessage = 'Sending audio to Whisper... (this can take 30-90s)';
    });

    try {
      final service = TranscriptionService();
      final result = await service.transcribe(
        filePath: _recording.localPath,
        language: 'en',
      );

      setState(() => _statusMessage = 'Analyzing speech patterns...');

      final fillers = FillerWordAnalyzer.analyze(
        result.text,
        language: result.language,
      );
      final vocab = VocabularyAnalyzer.analyze(result.text);
      final silence = SilenceAnalyzer.analyze(
        segments: result.segments,
        totalDurationSeconds: result.duration > 0
            ? result.duration
            : _recording.durationMs / 1000,
      );

      final repo = RecordingRepository();
      await repo.updateAnalysis(
        userId: userId,
        recordingId: _recording.id,
        transcript: result.text,
        segments: result.segments,
        language: result.language,
        fillerWordCount: fillers.total,
        fillerWordBreakdown: fillers.breakdown,
        totalWords: vocab.totalWords,
        uniqueWords: vocab.uniqueWords,
        lexicalDiversity: vocab.lexicalDiversity,
        topWords: vocab.topWords.map((w) => w.toMap()).toList(),
        overusedWords: vocab.overusedWords.map((w) => w.toMap()).toList(),
        silenceCount: silence.count,
        totalSilenceSeconds: silence.totalSilenceSeconds,
        longestSilenceSeconds: silence.longestSilenceSeconds,
        averageSilenceSeconds: silence.averageSilenceSeconds,
        silenceEvents: silence.events.map((e) => e.toMap()).toList(),
      );

      setState(() {
        // copyWith keeps name, category and the live body-language metrics.
        _recording = _recording.copyWith(
          transcript: result.text,
          transcriptSegments: result.segments,
          transcribedAt: DateTime.now(),
          language: result.language,
          fillerWordCount: fillers.total,
          fillerWordBreakdown: fillers.breakdown,
          totalWords: vocab.totalWords,
          uniqueWords: vocab.uniqueWords,
          lexicalDiversity: vocab.lexicalDiversity,
          topWords: vocab.topWords.map((w) => w.toMap()).toList(),
          overusedWords: vocab.overusedWords.map((w) => w.toMap()).toList(),
          silenceCount: silence.count,
          totalSilenceSeconds: silence.totalSilenceSeconds,
          longestSilenceSeconds: silence.longestSilenceSeconds,
          averageSilenceSeconds: silence.averageSilenceSeconds,
          silenceEvents: silence.events.map((e) => e.toMap()).toList(),
        );
        _loading = false;
        _statusMessage = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Analysis complete')),
        );
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _statusMessage = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildBodyLanguageCard(),
            Expanded(
              child: _recording.hasTranscript
                  ? _buildAnalysisView()
                  : _buildEmptyView(),
            ),
          ],
        ),
      ),
    );
  }

  // ============ BODY LANGUAGE CARD (live metrics, shown always) ============
  Widget _buildBodyLanguageCard() {
    final confidence = _recording.averageConfidencePercentage;
    final posture = _recording.averagePostureStability;
    final lookAways = _recording.lookingAwayCount;

    // Older recordings (before this feature) have no body-language data.
    if (confidence == null && posture == null && lookAways == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.face_retouching_natural,
                      color: AppColors.deepMauve),
                  const SizedBox(width: 8),
                  Text(
                    'Body language',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  const Text(
                    'Live',
                    style: TextStyle(
                      color: AppColors.midMauve,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statBox(
                    confidence != null
                        ? '${confidence.toStringAsFixed(0)}%'
                        : '—',
                    'Confidence',
                  ),
                  _statBox(
                    lookAways != null ? '$lookAways' : '—',
                    'Look-aways',
                  ),
                  _statBox(
                    posture != null ? '${posture.toStringAsFixed(0)}%' : '—',
                    'Posture',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.transcribe, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No analysis yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Generate a transcript and full analysis (filler words, vocabulary, silences). English only for now.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(_statusMessage, textAlign: TextAlign.center),
            ] else
              FilledButton.icon(
                onPressed: _transcribe,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyze recording'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatSeconds(double s) {
    if (s < 60) return '${s.toStringAsFixed(1)}s';
    final m = (s / 60).floor();
    final rem = (s - m * 60).toStringAsFixed(0);
    return '${m}m ${rem}s';
  }

  Widget _buildAnalysisView() {
    final fillerCount = _recording.fillerWordCount ?? 0;
    final breakdown = _recording.fillerWordBreakdown ?? {};
    final durationMin = _recording.durationMs / 60000;
    final fillerRate = durationMin > 0 ? fillerCount / durationMin : 0;

    final silenceCount = _recording.silenceCount ?? 0;
    final totalSilence = _recording.totalSilenceSeconds ?? 0;
    final longestSilence = _recording.longestSilenceSeconds ?? 0;
    final averageSilence = _recording.averageSilenceSeconds ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ============ PERFORMANCE REPORT CTA ============
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PerformanceReportScreen(recording: _recording),
                ),
              );
            },
            icon: const Icon(Icons.insights),
            label: const Text('View performance report'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),

          // ============ FILLER WORDS CARD ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'Filler words',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statBox('$fillerCount', 'Total'),
                      _statBox(
                        fillerRate.toStringAsFixed(1),
                        'Per minute',
                      ),
                    ],
                  ),
                  if (breakdown.isNotEmpty) ...[
                    const Divider(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: breakdown.entries
                          .map((e) => Chip(
                                label: Text('${e.key} × ${e.value}'),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ============ VOCABULARY CARD ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.menu_book, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Text(
                        'Vocabulary',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statBox(
                        '${_recording.totalWords ?? 0}',
                        'Words',
                      ),
                      _statBox(
                        '${_recording.uniqueWords ?? 0}',
                        'Unique',
                      ),
                      _statBox(
                        '${((_recording.lexicalDiversity ?? 0) * 100).toStringAsFixed(0)}%',
                        'Diversity',
                      ),
                    ],
                  ),
                  if ((_recording.topWords ?? []).isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      'Most used words',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_recording.topWords ?? [])
                          .map((w) => Chip(
                                label: Text('${w['word']} × ${w['count']}'),
                              ))
                          .toList(),
                    ),
                  ],
                  if ((_recording.overusedWords ?? []).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You used ${(_recording.overusedWords ?? []).length} word(s) more than 4 times. Consider varying your vocabulary.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ============ SILENCES CARD ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pause_circle_outline,
                          color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Text(
                        'Silences (gaps > 2s)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statBox('$silenceCount', 'Count'),
                      _statBox(_formatSeconds(totalSilence), 'Total'),
                      _statBox(_formatSeconds(longestSilence), 'Longest'),
                    ],
                  ),
                  if (silenceCount > 0) ...[
                    const Divider(height: 24),
                    Text(
                      'Average pause: ${_formatSeconds(averageSilence)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (longestSilence >= 5)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(
                                  color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'A ${_formatSeconds(longestSilence)} pause is unusually long. Practice transitions to keep your flow.',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ============ TRANSCRIPT CARD ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.article_outlined),
                      const SizedBox(width: 8),
                      Text(
                        'Transcript',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        _recording.language?.toUpperCase() ?? 'EN',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _recording.transcript ?? '',
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
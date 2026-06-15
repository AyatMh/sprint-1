import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/recording.dart';
import '../../../shared/widgets/score_ring.dart';
import '../../../shared/widgets/metric_widgets.dart';

class PerformanceReportScreen extends StatelessWidget {
  final Recording recording;
  const PerformanceReportScreen({super.key, required this.recording});

  // ---- derived scores (0-100) from real metrics ----

  double get _durationMin => recording.durationMs / 60000;

  int get _fillerScore {
    // Fewer fillers per minute = higher score. 0/min = 100, 10+/min = 0
    final rate = _durationMin > 0
        ? (recording.fillerWordCount ?? 0) / _durationMin
        : 0;
    final s = (100 - rate * 10).clamp(0, 100);
    return s.round();
  }

  int get _diversityScore {
    // Lexical diversity 0-1 mapped to 0-100, capped sensibly
    final d = (recording.lexicalDiversity ?? 0) * 100;
    return d.clamp(0, 100).round();
  }

  int get _silenceScore {
    // Fewer/shorter silences = higher. Penalize total silence seconds.
    final total = recording.totalSilenceSeconds ?? 0;
    final s = (100 - total * 5).clamp(0, 100);
    return s.round();
  }

  int get _overallScore =>
      ((_fillerScore + _diversityScore + _silenceScore) / 3).round();

  String _fmtDuration() {
    final d = Duration(milliseconds: recording.durationMs);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m min $s sec';
  }

  List<FlSpot> get _paceSpots {
    // Build a pace-over-time line from segment word counts
    final segs = recording.transcriptSegments ?? [];
    if (segs.isEmpty) return [const FlSpot(0, 0)];
    final spots = <FlSpot>[];
    for (int i = 0; i < segs.length; i++) {
      final seg = segs[i];
      final dur = (seg.end - seg.start).clamp(0.1, 999);
      final words = seg.text.trim().split(RegExp(r'\s+')).length;
      final wpm = (words / dur) * 60;
      spots.add(FlSpot(i.toDouble(), wpm.clamp(0, 300)));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              _buildScoreSection(),
              _buildStatCards(),
              _buildPaceChart(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppColors.wine,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.softMauve, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Performance report',
                  style: TextStyle(
                      color: AppColors.softMauve,
                      fontSize: 13,
                      letterSpacing: 0.3)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM d, HH:mm').format(recording.createdAt),
                    style: const TextStyle(
                        color: AppColors.pageBg,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        height: 1.05),
                  ),
                  const SizedBox(height: 5),
                  Text(_fmtDuration(),
                      style: const TextStyle(
                          color: AppColors.softMauve, fontSize: 12)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.softMauve.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Score $_overallScore',
                    style: const TextStyle(
                        color: AppColors.paleMauve,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 6),
      child: Row(
        children: [
          ScoreRing(score: _overallScore),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                SkillBar(label: 'Clarity', percent: _diversityScore),
                const SizedBox(height: 13),
                SkillBar(
                    label: 'Pacing',
                    percent: _silenceScore,
                    barColor: AppColors.midMauve),
                const SizedBox(height: 13),
                SkillBar(label: 'Fluency', percent: _fillerScore),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    final fillerRate = _durationMin > 0
        ? ((recording.fillerWordCount ?? 0) / _durationMin)
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.chat_bubble_outline,
                  label: 'Filler words',
                  value: '${recording.fillerWordCount ?? 0}',
                  footnote: '${fillerRate.toStringAsFixed(1)} / min',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.pause_circle_outline,
                  label: 'Silences',
                  value: '${recording.silenceCount ?? 0}',
                  footnote: 'longest ${(recording.longestSilenceSeconds ?? 0).toStringAsFixed(1)}s',
                  footnoteColor: AppColors.midMauve,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.psychology_outlined,
                  label: 'Average Confidence',
                  value: recording.averageConfidencePercentage != null
                      ? '${recording.averageConfidencePercentage!.toStringAsFixed(0)}%'
                      : 'N/A',
                  footnote: 'AI Visual Metric',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  icon: Icons.remove_red_eye_outlined,
                  label: 'Distractions',
                  value: recording.lookingAwayCount != null
                      ? '${recording.lookingAwayCount}'
                      : 'N/A',
                  footnote: 'frames looking away',
                  footnoteColor: AppColors.midMauve,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaceChart() {
    final spots = _paceSpots;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.paleMauve, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Speaking pace over time',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.deepMauve)),
                Text('wpm',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.softMauve)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  minY: 0,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppColors.deepMauve,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.midMauve.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
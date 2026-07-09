import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/recording.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/score_ring.dart';
import '../../../shared/widgets/metric_widgets.dart';
import '../report_scores.dart';
import '../report_pdf.dart';

class PerformanceReportScreen extends StatelessWidget {
  final Recording recording;
  const PerformanceReportScreen({super.key, required this.recording});

  // All derived 0-100 scores live in ReportScores, shared with the PDF export.
  ReportScores get _scores => ReportScores(recording);
  int get _overallScore => _scores.overall;

  String _fmtDuration() {
    final d = Duration(milliseconds: recording.durationMs);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '$m min $s sec';
  }

  // Red / amber / green by score, matching the app's semantic accents.
  Color _scoreColor(int s) => s >= 75
      ? AppColors.success
      : s >= 50
          ? AppColors.gold
          : AppColors.danger;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context),
                  const SizedBox(height: 18),
                  _buildScoreCard(),
                  const SizedBox(height: 14),
                  _buildSkillsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: AppColors.wine),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 10),
            const Text(
              'Performance report',
              style: TextStyle(
                color: AppColors.midMauve,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => _shareReport(context),
              icon: const Icon(Icons.ios_share_rounded, color: AppColors.wine),
              tooltip: 'Share as PDF',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          DateFormat('MMM d, HH:mm').format(recording.createdAt),
          style: const TextStyle(
            color: AppColors.wine,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _fmtDuration(),
          style: const TextStyle(color: AppColors.midMauve, fontSize: 13),
        ),
      ],
    );
  }

  // Generates a PDF of this report and opens the system share sheet.
  Future<void> _shareReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReportPdf.share(recording);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create PDF: $e')),
      );
    }
  }

  Widget _buildScoreCard() {
    final color = _scoreColor(_overallScore);
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          ScoreRing(score: _overallScore, color: color, label: 'SCORE'),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ReportScores.label(_overallScore),
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Overall performance',
                  style: TextStyle(
                    color: AppColors.wine,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Combined from your speech and body language.',
                  style: TextStyle(
                    color: AppColors.midMauve,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsCard() {
    // One bar per available dimension — speech first, then body language when
    // the recording has it. Each bar is tinted by its own score.
    final bars = [
      for (final s in _scores.skills) _bar(s.label, s.value),
    ];

    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.equalizer_rounded, 'Skill breakdown'),
          const SizedBox(height: 18),
          for (var i = 0; i < bars.length; i++) ...[
            bars[i],
            if (i < bars.length - 1) const SizedBox(height: 15),
          ],
        ],
      ),
    );
  }

  Widget _bar(String label, int percent) =>
      SkillBar(label: label, percent: percent, barColor: _scoreColor(percent));

  Widget _cardTitle(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.deepMauve),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.wine,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}
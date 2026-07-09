import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/recording.dart';
import 'report_scores.dart';

// Builds a shareable PDF of a recording's performance report and opens the
// system share sheet. Kept self-contained so the screen just calls this.
class ReportPdf {
  static const PdfColor _ink = PdfColor.fromInt(0xFF0B0D12);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B6F7A);
  static const PdfColor _track = PdfColor.fromInt(0xFFE6E8EF);
  static const PdfColor _blue = PdfColor.fromInt(0xFF0A84FF);
  static const PdfColor _green = PdfColor.fromInt(0xFF30D158);
  static const PdfColor _gold = PdfColor.fromInt(0xFFFF9F0A);
  static const PdfColor _red = PdfColor.fromInt(0xFFFF453A);

  static PdfColor _scoreColor(int s) =>
      s >= 75 ? _green : (s >= 50 ? _gold : _red);

  static String _fmtDuration(Recording r) {
    final d = Duration(milliseconds: r.durationMs);
    return '${d.inMinutes} min ${d.inSeconds.remainder(60)} sec';
  }

  // Generates the document bytes so it can be shared, printed or saved.
  static Future<void> share(Recording recording) async {
    final scores = ReportScores(recording);
    final doc = pw.Document();

    final title = recording.name.trim().isNotEmpty
        ? recording.name.trim()
        : 'Practice session';

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        ),
        build: (context) => [
          _header(title, recording),
          pw.SizedBox(height: 24),
          _overall(scores),
          pw.SizedBox(height: 24),
          _skills(scores),
          if (recording.hasAiTips) ...[
            pw.SizedBox(height: 24),
            _aiTips(recording.aiTips!),
          ],
          pw.SizedBox(height: 28),
          _footer(),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'InterviewPro-report.pdf',
    );
  }

  static pw.Widget _header(String title, Recording r) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('INTERVIEWPRO · PERFORMANCE REPORT',
            style: pw.TextStyle(
                color: _blue, fontSize: 10, letterSpacing: 1.2)),
        pw.SizedBox(height: 8),
        pw.Text(title,
            style: pw.TextStyle(
                color: _ink, fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          '${DateFormat('MMM d, y · HH:mm').format(r.createdAt)}   ·   ${_fmtDuration(r)}'
          '${r.category.trim().isNotEmpty ? '   ·   ${r.category.trim()}' : ''}',
          style: pw.TextStyle(color: _muted, fontSize: 11),
        ),
        pw.SizedBox(height: 14),
        pw.Divider(color: _track, thickness: 1),
      ],
    );
  }

  static pw.Widget _overall(ReportScores s) {
    final color = _scoreColor(s.overall);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 96,
          height: 96,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: color, width: 6),
          ),
          child: pw.Text('${s.overall}',
              style: pw.TextStyle(
                  color: color, fontSize: 30, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(width: 22),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(ReportScores.label(s.overall),
                style: pw.TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Overall performance',
                style: pw.TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('Combined from your speech and body language.',
                style: pw.TextStyle(color: _muted, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _skills(ReportScores s) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Skill breakdown',
            style: pw.TextStyle(
                color: _ink, fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        for (final skill in s.skills) ...[
          _skillBar(skill.label, skill.value),
          pw.SizedBox(height: 10),
        ],
      ],
    );
  }

  static pw.Widget _skillBar(String label, int percent) {
    final color = _scoreColor(percent);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(color: _ink, fontSize: 11)),
            pw.Text('$percent%',
                style: pw.TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 4),
        // Proportional bar: the fill and remaining track share the width by
        // flex (pdf has no FractionallySizedBox).
        pw.Container(
          height: 7,
          decoration: pw.BoxDecoration(
            color: _track,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Row(
            children: [
              if (percent > 0)
                pw.Expanded(
                  flex: percent,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                  ),
                ),
              if (percent < 100) pw.Expanded(flex: 100 - percent, child: pw.SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _aiTips(Map<String, dynamic> tips) {
    List<String> list(dynamic v) =>
        (v as List?)?.map((e) => e.toString()).toList() ?? const [];

    pw.Widget section(String title, List<String> items) {
      if (items.isEmpty) return pw.SizedBox();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text(title,
              style: pw.TextStyle(
                  color: _ink, fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          for (final item in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3, left: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('•  ',
                      style: pw.TextStyle(color: _muted, fontSize: 11)),
                  pw.Expanded(
                    child: pw.Text(item,
                        style: pw.TextStyle(color: _ink, fontSize: 11)),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final summary = (tips['summary'] ?? '').toString();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF3F4F8),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('AI coaching tips',
              style: pw.TextStyle(
                  color: _ink, fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if (summary.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(summary,
                style: pw.TextStyle(color: _ink, fontSize: 11)),
          ],
          section('What went well', list(tips['strengths'])),
          section('What to work on', list(tips['improvements'])),
          section('Tips for next time', list(tips['tips'])),
        ],
      ),
    );
  }

  static pw.Widget _footer() {
    return pw.Text('Generated by InterviewPro',
        style: pw.TextStyle(color: _muted, fontSize: 9));
  }
}

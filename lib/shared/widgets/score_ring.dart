import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ScoreRing extends StatelessWidget {
  final int score; // 0-100
  final String label;
  final double size;
  final Color? color; // arc + number tint; defaults to the neutral mauve

  const ScoreRing({
    super.key,
    required this.score,
    this.label = 'OVERALL',
    this.size = 104,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.midMauve;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(score / 100, tint),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: tint,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  color: AppColors.midMauve,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress; // 0-1
  final Color tint;
  _RingPainter(this.progress, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 5;
    const stroke = 9.0;

    final track = Paint()
      ..color = AppColors.paleMauve
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final fill = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.tint != tint;
}
import 'dart:math';

import 'package:flutter/material.dart';

// Flutter port of the MagicUI "Particles" effect: a field of softly
// twinkling dots that drift across the background. Purely decorative —
// it ignores pointer events and repaints on its own ticker.
class ParticlesBackground extends StatefulWidget {
  final int quantity;
  final Color color;

  const ParticlesBackground({
    super.key,
    this.quantity = 100,
    this.color = Colors.black,
  });

  @override
  State<ParticlesBackground> createState() => _ParticlesBackgroundState();
}

class _ParticlesBackgroundState extends State<ParticlesBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_Particle> _particles = [];
  final Random _rng = Random();
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _controller.addListener(_tick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seedParticles(Size size) {
    _size = size;
    _particles
      ..clear()
      ..addAll(List.generate(widget.quantity, (_) => _spawn(size)));
  }

  _Particle _spawn(Size size) {
    return _Particle(
      x: _rng.nextDouble() * size.width,
      y: _rng.nextDouble() * size.height,
      dx: (_rng.nextDouble() - 0.5) * 0.3,
      dy: (_rng.nextDouble() - 0.5) * 0.3,
      size: 1.0 + _rng.nextDouble() * 2.0,
      alpha: 0,
      targetAlpha: 0.1 + _rng.nextDouble() * 0.45,
    );
  }

  void _tick() {
    if (_size == Size.zero) return;
    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.x += p.dx;
      p.y += p.dy;
      // Fade in toward the particle's own brightness, with a tiny flicker.
      p.alpha += (p.targetAlpha - p.alpha) * 0.02;
      if (_rng.nextDouble() < 0.002) {
        p.targetAlpha = 0.1 + _rng.nextDouble() * 0.45;
      }
      // Respawn particles that drift off-screen.
      if (p.x < -4 || p.x > _size.width + 4 || p.y < -4 || p.y > _size.height + 4) {
        _particles[i] = _spawn(_size)..alpha = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (size != _size) _seedParticles(size);
            return CustomPaint(
              size: size,
              painter: _ParticlesPainter(
                particles: _particles,
                color: widget.color,
                repaint: _controller,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Particle {
  double x, y, dx, dy, size, alpha, targetAlpha;

  _Particle({
    required this.x,
    required this.y,
    required this.dx,
    required this.dy,
    required this.size,
    required this.alpha,
    required this.targetAlpha,
  });
}

class _ParticlesPainter extends CustomPainter {
  final List<_Particle> particles;
  final Color color;

  _ParticlesPainter({
    required this.particles,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      paint.color = color.withValues(alpha: p.alpha.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(p.x, p.y), p.size / 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => true;
}

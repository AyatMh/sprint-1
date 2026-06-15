import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ============================================================================
// Liquid Glass primitives (iOS 26 design language)
// ============================================================================

// Frosted translucent card: white gradient over a backdrop blur, hairline
// white border, soft layered shadow.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: const [
          BoxShadow(
            color: Color(0x33121C3A),
            blurRadius: 32,
            offset: Offset(0, 12),
            spreadRadius: -14,
          ),
          BoxShadow(
            color: Color(0x0F121C3A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.74),
                      Colors.white.withValues(alpha: 0.52),
                    ],
                  ),
                  borderRadius: br,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Ambient wallpaper the glass refracts: a soft neutral base with three
// huge blurry colour orbs slowly drifting.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _orb({
    double? left,
    double? right,
    double? top,
    double? bottom,
    required double size,
    required Color color,
    required double alpha,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              Container(color: const Color(0xFFECEEF4)),
              _orb(
                left: -140 + 70 * t,
                top: -120 + 50 * t,
                size: 440,
                color: const Color(0xFFBCD6FF),
                alpha: 0.55,
              ),
              _orb(
                right: -150 - 60 * t,
                top: 200 + 70 * t,
                size: 400,
                color: const Color(0xFFD6F4E4),
                alpha: 0.5,
              ),
              _orb(
                left: -80 + 60 * t,
                bottom: -180 + 60 * t,
                size: 440,
                color: const Color(0xFFFFE6D8),
                alpha: 0.42,
              ),
            ],
          );
        },
      ),
    );
  }
}

// Small pill showing a session score (we use the live confidence average).
// Green for good takes, amber for mid ones.
class ScorePill extends StatelessWidget {
  final int? score;

  const ScorePill({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final good = (score ?? 0) >= 70;
    final fg = score == null
        ? AppColors.midMauve
        : good
            ? const Color(0xFF0E6B31)
            : const Color(0xFF8A5A00);
    final bg = score == null
        ? AppColors.paleMauve
        : good
            ? const Color(0xFF34C759).withValues(alpha: 0.18)
            : const Color(0xFFFFD60A).withValues(alpha: 0.22);
    final ring = score == null
        ? Colors.transparent
        : good
            ? const Color(0xFF34C759).withValues(alpha: 0.22)
            : const Color(0xFFFFD60A).withValues(alpha: 0.3);

    return Container(
      constraints: const BoxConstraints(minWidth: 44),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ring),
      ),
      child: Text(
        score?.toString() ?? '—',
        style: TextStyle(
          color: fg,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

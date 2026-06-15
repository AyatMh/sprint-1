import 'dart:math';

import 'package:flutter/material.dart';

// Liquid Glass CTA (from the iOS 26 mock): a dark glass capsule wrapped in a
// continuously rotating conic rainbow ring with a soft rainbow glow.
class RainbowButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double height;

  const RainbowButton({
    super.key,
    required this.child,
    this.onPressed,
    this.height = 54,
  });

  @override
  State<RainbowButton> createState() => _RainbowButtonState();
}

class _RainbowButtonState extends State<RainbowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Rainbow ring colors from the mock's conic gradient.
  static const List<Color> _rainbow = [
    Color(0xFF0A84FF),
    Color(0xFF64D2FF),
    Color(0xFF30D158),
    Color(0xFFFFD60A),
    Color(0xFFFF6482),
    Color(0xFFBF5AF2),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Samples the looping rainbow at position t (wraps around 0..1).
  Color _sample(double t) {
    final scaled = (t % 1) * _rainbow.length;
    final i = scaled.floor() % _rainbow.length;
    final f = scaled - scaled.floorToDouble();
    return Color.lerp(_rainbow[i], _rainbow[(i + 1) % _rainbow.length], f)!;
  }

  @override
  Widget build(BuildContext context) {
    final outer = BorderRadius.circular(widget.height / 2 + 2);
    final inner = BorderRadius.circular(widget.height / 2);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          height: widget.height + 4,
          decoration: BoxDecoration(
            borderRadius: outer,
            gradient: SweepGradient(
              colors: [..._rainbow, _rainbow.first],
              transform: GradientRotation(t * 2 * pi),
            ),
            boxShadow: [
              BoxShadow(
                color: _sample(t).withValues(alpha: 0.5),
                blurRadius: 22,
                offset: const Offset(-6, 8),
                spreadRadius: -6,
              ),
              BoxShadow(
                color: _sample(t + 0.33).withValues(alpha: 0.5),
                blurRadius: 22,
                offset: const Offset(0, 10),
                spreadRadius: -6,
              ),
              BoxShadow(
                color: _sample(t + 0.66).withValues(alpha: 0.5),
                blurRadius: 22,
                offset: const Offset(6, 8),
                spreadRadius: -6,
              ),
            ],
          ),
          padding: const EdgeInsets.all(2),
          child: Material(
            color: const Color(0xB80A0D12), // dark glass
            borderRadius: inner,
            child: InkWell(
              borderRadius: inner,
              onTap: widget.onPressed,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white, size: 20),
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

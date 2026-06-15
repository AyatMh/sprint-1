import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/app_theme.dart';

class AppDockItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  const AppDockItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
  });
}

// Flutter port of the MagicUI "Dock": a floating frosted-glass pill of
// icons with macOS-style magnification. Sizes are driven by a per-frame
// spring simulation (like framer-motion's useSpring), so icons glide
// continuously toward the pointer instead of stepping between targets.
class AppDock extends StatefulWidget {
  final List<AppDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  /// Resting icon-button diameter.
  final double baseSize;

  /// Extra diameter gained at the magnification peak.
  final double magnification;

  /// Horizontal distance (px) over which the magnification falls off.
  final double influenceRadius;

  const AppDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    this.baseSize = 46,
    this.magnification = 22,
    this.influenceRadius = 130,
  });

  @override
  State<AppDock> createState() => _AppDockState();
}

class _AppDockState extends State<AppDock>
    with SingleTickerProviderStateMixin {
  late final List<GlobalKey> _itemKeys =
      List.generate(widget.items.length, (_) => GlobalKey());

  // Current (animated) size of each icon; targets are derived from the
  // pointer position every frame and the sizes spring toward them.
  late final List<double> _sizes =
      List.filled(widget.items.length, widget.baseSize);

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Global pointer position while hovering / dragging over the dock.
  Offset? _pointer;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setPointer(Offset? position) {
    _pointer = position;
    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  double _targetFor(int index) {
    final pointer = _pointer;
    if (pointer == null) return widget.baseSize;

    final box =
        _itemKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return widget.baseSize;

    final center = box.localToGlobal(box.size.center(Offset.zero));
    final distance = (pointer.dx - center.dx).abs();
    if (distance >= widget.influenceRadius) return widget.baseSize;

    // Smooth cosine falloff: 1 at the pointer, 0 at the influence edge.
    final falloff = (cos(pi * distance / widget.influenceRadius) + 1) / 2;
    return widget.baseSize + widget.magnification * falloff;
  }

  void _onTick(Duration elapsed) {
    // Frame-rate independent critically-damped approach: each icon closes
    // a fixed fraction of the gap to its target per unit time.
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    final blend = 1 - exp(-18 * dt); // spring stiffness

    var settled = true;
    for (var i = 0; i < _sizes.length; i++) {
      final target = _targetFor(i);
      final diff = target - _sizes[i];
      if (diff.abs() < 0.05) {
        _sizes[i] = target;
      } else {
        _sizes[i] += diff * blend;
        settled = false;
      }
    }

    setState(() {});
    if (settled && _pointer == null) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final dockHeight = widget.baseSize + widget.magnification + 16;

    return MouseRegion(
      onHover: (e) => _setPointer(e.position),
      onExit: (_) => _setPointer(null),
      child: Listener(
        onPointerDown: (e) => _setPointer(e.position),
        onPointerMove: (e) => _setPointer(e.position),
        onPointerUp: (_) => _setPointer(null),
        onPointerCancel: (_) => _setPointer(null),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: dockHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBg.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.wine.withValues(alpha: 0.10),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                // Icons grow upward out of the bar, like the macOS dock.
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < widget.items.length; i++) _buildItem(i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int index) {
    final item = widget.items[index];
    final selected = index == widget.selectedIndex;
    final size = _sizes[index];

    return Padding(
      key: _itemKeys[index],
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: item.label,
        preferBelow: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onItemSelected(index),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.deepMauve : Colors.transparent,
            ),
            child: Icon(
              selected ? (item.selectedIcon ?? item.icon) : item.icon,
              size: size * 0.46,
              color: selected ? Colors.white : AppColors.midMauve,
            ),
          ),
        ),
      ),
    );
  }
}

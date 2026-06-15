import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class LiquidTabItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const LiquidTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

// iOS 26 Liquid Glass floating tab bar: a frosted pill with a bright glass
// "lens" that springs between tabs.
class LiquidTabBar extends StatelessWidget {
  final List<LiquidTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  static const double _tabWidth = 86;
  static const double _tabHeight = 56;

  // Overshooting spring, same as the mock's cubic-bezier(.34,1.36,.34,1).
  static const Curve _spring = Cubic(0.34, 1.36, 0.34, 1);

  const LiquidTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: const [
          BoxShadow(
            color: Color(0x660E1837),
            blurRadius: 44,
            offset: Offset(0, 22),
            spreadRadius: -16,
          ),
          BoxShadow(
            color: Color(0x140E1837),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.66),
                  Colors.white.withValues(alpha: 0.42),
                ],
              ),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
            ),
            child: SizedBox(
              width: _tabWidth * items.length,
              height: _tabHeight,
              child: Stack(
                children: [
                  // The bright glass lens behind the active tab.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 450),
                    curve: _spring,
                    left: selectedIndex * _tabWidth,
                    top: 0,
                    width: _tabWidth,
                    height: _tabHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.96),
                            Colors.white.withValues(alpha: 0.62),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(29),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x590E1837),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                            spreadRadius: -8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++) _buildTab(i),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    final item = items[index];
    final selected = index == selectedIndex;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onItemSelected(index),
      child: SizedBox(
        width: _tabWidth,
        height: _tabHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.0 : 0.96,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 23,
                color: selected ? AppColors.wine : AppColors.midMauve,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.wine : AppColors.midMauve,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

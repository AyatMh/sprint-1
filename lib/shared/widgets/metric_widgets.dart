import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SkillBar extends StatelessWidget {
  final String label;
  final int percent; // 0-100
  final Color? barColor;

  const SkillBar({
    super.key,
    required this.label,
    required this.percent,
    this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.deepMauve)),
            Text('$percent%',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.wine)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 6,
            backgroundColor: AppColors.paleMauve,
            valueColor: AlwaysStoppedAnimation(
              barColor ?? AppColors.deepMauve,
            ),
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? footnote;
  final Color? footnoteColor;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.footnote,
    this.footnoteColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.paleMauve, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.midMauve),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.midMauve)),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: AppColors.wine,
                  height: 1)),
          if (footnote != null) ...[
            const SizedBox(height: 7),
            Text(footnote!,
                style: TextStyle(
                    fontSize: 11,
                    color: footnoteColor ?? AppColors.deepMauve)),
          ],
        ],
      ),
    );
  }
}
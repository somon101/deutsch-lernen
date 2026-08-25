import 'package:flutter/material.dart';

import '../../data/profile_gamification_repository.dart';
import '../profile_tokens.dart';
import 'profile_card.dart';

class LevelCard extends StatelessWidget {
  const LevelCard({super.key, required this.level});

  final LevelProgress level;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final percent = level.percent.clamp(0, 100) / 100;
    return ProfileCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ваш уровень', style: ProfileTypography.caption(context)),
                const SizedBox(height: 4),
                Text('${level.code} — ${level.name}', style: ProfileTypography.sectionTitle(context)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(ProfileMetrics.progressBarRadius),
                  child: SizedBox(
                    height: ProfileMetrics.progressBarHeight,
                    child: Stack(
                      children: [
                        Container(color: c.border),
                        AnimatedFractionallySizedBox(
                          duration: ProfileMetrics.transition,
                          curve: ProfileMetrics.transitionCurve,
                          widthFactor: percent,
                          child: Container(color: c.accent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(level.hint, style: ProfileTypography.caption(context)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.auto_awesome, color: c.accent, size: 24),
          ),
        ],
      ),
    );
  }
}

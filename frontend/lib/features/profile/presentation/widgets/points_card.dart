import 'package:flutter/material.dart';

import '../profile_tokens.dart';
import 'profile_card.dart';

/// Total points (§ rating system, 2026-08-30) — replaces the old mock
/// "Ваш уровень" card. Same number the leaderboard/rank card already use
/// (10 per correctly-answered question + 50 per completed lesson, summed
/// across every language), just shown as a plain total here instead of a
/// rank.
class PointsCard extends StatelessWidget {
  const PointsCard({super.key, required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return ProfileCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Общее количество очков', style: ProfileTypography.caption(context)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('$points', maxLines: 1, style: ProfileTypography.bigNumber(context)),
                ),
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

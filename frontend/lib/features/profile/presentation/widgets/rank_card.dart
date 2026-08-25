import 'package:flutter/material.dart';

import '../../data/profile_gamification_repository.dart';
import '../profile_tokens.dart';
import 'profile_card.dart';

class RankCard extends StatelessWidget {
  const RankCard({super.key, required this.rank});

  final RankInfo rank;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return ProfileCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.emoji_events, color: c.accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ваш рейтинг', style: ProfileTypography.caption(context)),
                const SizedBox(height: 2),
                Text('#${rank.place}', style: ProfileTypography.bigNumber(context)),
              ],
            ),
          ),
          _RankFact(value: 'Топ ${rank.topPercent}%', label: rank.periodLabel),
          const SizedBox(width: 20),
          _RankFact(value: 'из ${rank.totalStudents}', label: 'Среди всех студентов'),
        ],
      ),
    );
  }
}

class _RankFact extends StatelessWidget {
  const _RankFact({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
        Text(label, style: ProfileTypography.caption(context)),
      ],
    );
  }
}

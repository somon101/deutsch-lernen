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
    final header = Row(
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
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('#${rank.place}', maxLines: 1, style: ProfileTypography.bigNumber(context)),
              ),
            ],
          ),
        ),
      ],
    );

    // A single Row cramming the header + both facts only has room on wide
    // screens — below 360px the trailing facts get squeezed to a sliver and
    // their text force-breaks mid-word. Stack the facts under the header
    // instead of beside it on narrow widths.
    return ProfileCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 16),
                Divider(height: 1, color: c.border),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RankFact(value: 'Топ ${rank.topPercent}%', label: rank.periodLabel, alignEnd: false),
                    _RankFact(value: 'из ${rank.totalStudents}', label: 'Среди всех студентов', alignEnd: true),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              _RankFact(value: 'Топ ${rank.topPercent}%', label: rank.periodLabel, alignEnd: true),
              const SizedBox(width: 20),
              _RankFact(value: 'из ${rank.totalStudents}', label: 'Среди всех студентов', alignEnd: true),
            ],
          );
        },
      ),
    );
  }
}

class _RankFact extends StatelessWidget {
  const _RankFact({required this.value, required this.label, required this.alignEnd});
  final String value;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
        Text(label, style: ProfileTypography.caption(context)),
      ],
    );
  }
}

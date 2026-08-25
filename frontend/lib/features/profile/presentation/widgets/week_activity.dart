import 'package:flutter/material.dart';

import '../../data/profile_gamification_repository.dart';
import '../profile_tokens.dart';
import 'profile_card.dart';

const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

class WeekActivityCard extends StatelessWidget {
  const WeekActivityCard({super.key, required this.activity});

  final WeeklyActivity activity;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Активность за неделю', style: ProfileTypography.sectionTitle(context)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++) _DayDot(label: _dayLabels[i], done: activity.days[i]),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${activity.avgHoursPerDay.toStringAsFixed(1)} ч/день', style: ProfileTypography.bigNumber(context)),
              Row(
                children: [
                  Icon(Icons.trending_up, size: 16, color: c.success),
                  const SizedBox(width: 4),
                  Text('${activity.trendPercent}%', style: ProfileTypography.body(context).copyWith(color: c.success)),
                ],
              ),
            ],
          ),
          Text('Средняя активность', style: ProfileTypography.caption(context)),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.label, required this.done});
  final String label;
  final bool? done;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final fill = switch (done) {
      true => c.success,
      false => Colors.transparent,
      null => Colors.transparent,
    };
    final border = done == true ? c.success : c.border;

    return Column(
      children: [
        Container(
          width: ProfileMetrics.activityDot,
          height: ProfileMetrics.activityDot,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: border, width: 1.5)),
          child: done == true ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
        ),
        const SizedBox(height: 6),
        Text(label, style: ProfileTypography.caption(context)),
      ],
    );
  }
}

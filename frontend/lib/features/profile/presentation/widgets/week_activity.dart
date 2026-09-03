import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/profile_repository.dart';
import '../profile_tokens.dart';
import 'profile_card.dart';

List<String> _dayLabels(AppLocalizations l10n) => [
      l10n.weekActivityDayMon,
      l10n.weekActivityDayTue,
      l10n.weekActivityDayWed,
      l10n.weekActivityDayThu,
      l10n.weekActivityDayFri,
      l10n.weekActivityDaySat,
      l10n.weekActivityDaySun,
    ];

/// Mirrors the "Активность за неделю" mock's layout exactly (§ streak mode,
/// 2026-08-29 — real data now, not a placeholder): a 7-dot week row, then
/// the average time/day and a today-vs-yesterday change indicator.
class WeekActivityCard extends StatelessWidget {
  const WeekActivityCard({super.key, required this.activity});

  final WeekActivitySummary activity;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    final avgMinutes = activity.avgSecondsPerDay ~/ 60;
    final percent = activity.percentChangeVsYesterday;
    final dayLabels = _dayLabels(l10n);

    return ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.weekActivityTitle, style: ProfileTypography.sectionTitle(context)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++) _DayDot(label: dayLabels[i], done: activity.days[i].active),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.weekActivityAvgPerDay(avgMinutes), style: ProfileTypography.bigNumber(context)),
              // No badge at all when yesterday had zero time — a percentage
              // change from zero is undefined, not a real number (§6, 2026-08-29).
              if (percent != null)
                Row(
                  children: [
                    Icon(
                      percent >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: percent >= 0 ? c.success : c.danger,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${percent >= 0 ? '+' : ''}$percent%',
                      style: ProfileTypography.body(context).copyWith(color: percent >= 0 ? c.success : c.danger),
                    ),
                  ],
                ),
            ],
          ),
          Text(l10n.weekActivityAverage, style: ProfileTypography.caption(context)),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.label, required this.done});
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final fill = done ? c.success : Colors.transparent;
    final border = done ? c.success : c.danger;

    return Column(
      children: [
        Container(
          width: ProfileMetrics.activityDot,
          height: ProfileMetrics.activityDot,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: border, width: 1.5)),
          child: done ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
        ),
        const SizedBox(height: 6),
        Text(label, style: ProfileTypography.caption(context)),
      ],
    );
  }
}

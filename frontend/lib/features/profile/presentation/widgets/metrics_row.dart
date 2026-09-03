import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../profile_tokens.dart';
import 'profile_card.dart';

/// One compact card, 4 columns in a single row always (not 2x2) — icon,
/// then value, then a short one-line label. FittedBox on both value and
/// label (not maxLines/ellipsis) so a long value like "24ч 30м" shrinks to
/// fit a narrow column instead of wrapping or clipping, down to 360px.
///
/// Shared between the signed-in user's own profile and someone else's
/// public profile (§ subscriptions follow-up, 2026-08-30: "должен увидеть
/// всю статистику как у себя") — the same real numbers, just possibly about
/// a different user id.
class MetricsRow extends StatelessWidget {
  const MetricsRow({
    super.key,
    required this.progressPercent,
    required this.timeSeconds,
    required this.streakDays,
    required this.points,
  });

  final int? progressPercent;

  /// Total time studying the selected language (§ time tracking,
  /// 2026-08-29) — null only while no language is selected/known yet.
  final int? timeSeconds;

  /// Consecutive active calendar days (§ streak mode, 2026-08-29) — global,
  /// not scoped to any one language.
  final int streakDays;

  /// Total points (§ rating system, 2026-08-30) — same number the
  /// leaderboard/rank card use, global across every language.
  final int points;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    final totalMinutes = (timeSeconds ?? 0) ~/ 60;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final items = [
      (emoji: '🔥', icon: null, color: null, value: '$streakDays', label: l10n.metricsStreak),
      (
        emoji: null,
        icon: Icons.trending_up,
        color: c.success,
        value: progressPercent == null ? '—' : '$progressPercent%',
        label: l10n.metricsProgress,
      ),
      (
        emoji: null,
        icon: Icons.schedule,
        color: c.accent,
        value: timeSeconds == null ? '—' : l10n.metricsTimeFormat(hours, minutes),
        label: l10n.metricsTime,
      ),
      (emoji: null, icon: Icons.star, color: c.warning, value: '$points', label: l10n.metricsPoints),
    ];

    return ProfileCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: c.border, indent: 4, endIndent: 4),
              Expanded(
                child: _MetricColumn(
                  emoji: items[i].emoji,
                  icon: items[i].icon,
                  color: items[i].color,
                  value: items[i].value,
                  label: items[i].label,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({this.emoji, this.icon, this.color, required this.value, required this.label});

  final String? emoji;
  final IconData? icon;
  final Color? color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 18)),
        if (icon != null) Icon(icon, size: 18, color: color ?? context.profileColors.accent),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: ProfileTypography.bigNumber(context))),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: ProfileTypography.caption(context))),
      ],
    );
  }
}

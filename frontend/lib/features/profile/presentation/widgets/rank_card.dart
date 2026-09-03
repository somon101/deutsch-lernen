import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../leaderboard/data/leaderboard_repository.dart';
import '../profile_tokens.dart';
import 'profile_card.dart';

/// Real data (§ rating system, 2026-08-30) — global points rank, independent
/// of whichever language is selected for progress/time or shown on
/// Главное. `summary.weeklyChange` is null when there's no meaningful
/// "7 days ago" rank to compare yet, rendered as no badge at all rather
/// than a fabricated number.
class RankCard extends StatelessWidget {
  const RankCard({super.key, required this.summary});

  final MyRankSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    // Rank 1 always reads as "Топ 1%" — the single best position shouldn't
    // show a worse-looking number just because the pool is still small
    // (e.g. 1st of 8 is mathematically the "top 13%", which reads as wrong
    // even though it's technically accurate).
    final topPercent = summary.rank <= 1
        ? 1
        : summary.totalParticipants > 0
            ? (summary.rank / summary.totalParticipants * 100).ceil().clamp(1, 100)
            : 100;
    final change = summary.weeklyChange;

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
              Text(l10n.rankCardTitle, style: ProfileTypography.caption(context)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('#${summary.rank}', maxLines: 1, style: ProfileTypography.bigNumber(context)),
                  ),
                  if (change != null && change != 0) ...[
                    const SizedBox(width: 8),
                    Icon(change > 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: change > 0 ? c.success : c.danger),
                    Text('${change.abs()}', style: ProfileTypography.caption(context).copyWith(color: change > 0 ? c.success : c.danger)),
                  ],
                ],
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
                    _RankFact(value: l10n.rankTop(topPercent), label: l10n.rankGlobal, alignEnd: false),
                    _RankFact(value: l10n.rankOutOf(summary.totalParticipants), label: l10n.rankAmongAllStudents, alignEnd: true),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              _RankFact(value: 'Топ $topPercent%', label: 'Глобально', alignEnd: true),
              const SizedBox(width: 20),
              _RankFact(value: 'из ${summary.totalParticipants}', label: 'Среди всех студентов', alignEnd: true),
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

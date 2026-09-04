import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/leaderboard_entry.dart';

/// Motivational banner computed entirely client-side from the already-
/// fetched leaderboard list (§ leaderboard redesign, 2026-09-04) — no
/// separate request. Renders nothing if the signed-in user isn't among
/// [entries] at all (can't compute "how far to the next place" without
/// knowing who that is), matching spec exactly.
class RankGoalBanner extends StatelessWidget {
  const RankGoalBanner({super.key, required this.entries, required this.myUserId});

  final List<LeaderboardEntry> entries;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    LeaderboardEntry? findByUserId(String id) {
      for (final e in entries) {
        if (e.userId == id) return e;
      }
      return null;
    }

    final me = findByUserId(myUserId);
    if (me == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final isTop = me.rank == 1;

    LeaderboardEntry? above;
    if (!isTop) {
      for (final e in entries) {
        if (e.rank == me.rank - 1) {
          above = e;
          break;
        }
      }
    }
    // Also hide if rank 1 wasn't found above for a non-top user (a gap in
    // the fetched page) — nothing sensible to show without a real target.
    if (!isTop && above == null) return const SizedBox.shrink();

    final progress = isTop ? null : (above!.points == 0 ? 0.0 : (me.points / above.points).clamp(0.0, 1.0));

    final onGradient = scheme.onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: onGradient.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
            alignment: Alignment.center,
            child: const Text('🎯', style: TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTop ? l10n.leaderboardGoalTop : l10n.leaderboardGoalToPlace(above!.rank, above.points - me.points),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: onGradient),
                ),
                if (!isTop) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.leaderboardGoalBeatName(above!.displayName),
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: onGradient.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: onGradient.withValues(alpha: 0.24),
                      valueColor: AlwaysStoppedAnimation(onGradient),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

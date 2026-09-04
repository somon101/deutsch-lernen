import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_identity.dart';
import '../../models/leaderboard_entry.dart';
import 'leaderboard_number_format.dart';
import 'rank_delta_chip.dart';

/// One row for rank 4 and below (§ leaderboard redesign, 2026-09-04) — the
/// signed-in user's own entry never reaches this widget (filtered out by
/// the screen, shown by MyRankBar instead), so there's no `isMe` styling
/// branch here at all, unlike the old _LeaderboardRow it replaces.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.entry, required this.onTap});

  final LeaderboardEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final numberFormat = NumberFormat.decimalPattern(numberFormatLocale(context));
    final hasPhoto = entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: avatarColorFor(entry.userId, scheme),
                  // Plain NetworkImage, not cached — many different users'
                  // avatars shown together, same reasoning as the row this
                  // replaces (caching is reserved for the signed-in user's
                  // own single avatar elsewhere in the app).
                  backgroundImage: hasPhoto ? NetworkImage(entry.avatarUrl!) : null,
                  child: hasPhoto ? null : Text(entry.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      Text('@${entry.username}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RankDeltaChip(delta: entry.delta),
                    if (entry.delta != null) const SizedBox(height: 2),
                    Text(
                      numberFormat.format(entry.points),
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.primary, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

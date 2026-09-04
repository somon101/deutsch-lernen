import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_identity.dart';
import '../../models/leaderboard_entry.dart';
import 'leaderboard_number_format.dart';

/// One podium column (§ leaderboard redesign, 2026-09-04) — avatar with a
/// medal-colored ring, a place badge cut into the bottom of the ring, an
/// optional crown for 1st, name, and points. `rank` is always 1, 2, or 3.
class PodiumPlace extends StatelessWidget {
  const PodiumPlace({super.key, required this.entry, required this.rank, required this.onTap});

  final LeaderboardEntry entry;
  final int rank;
  final VoidCallback onTap;

  double get _avatarDiameter => rank == 1 ? 92 : 66;
  double get _ringWidth => rank == 1 ? 3 : 2.5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final medal = switch (rank) {
      1 => c.gold,
      2 => c.silver,
      _ => c.bronze,
    };
    final numberFormat = NumberFormat.decimalPattern(numberFormatLocale(context));
    final diameter = _avatarDiameter;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: diameter + 16,
              height: diameter + 16 + 14, // + room for the badge cut into the bottom
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  if (rank == 1)
                    const Positioned(top: 0, child: Text('👑', style: TextStyle(fontSize: 24))),
                  Positioned(
                    top: rank == 1 ? 26 : 8,
                    child: Container(
                      width: diameter + _ringWidth * 2 + 6,
                      height: diameter + _ringWidth * 2 + 6,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: medal, width: _ringWidth)),
                      alignment: Alignment.center,
                      child: _Avatar(entry: entry, diameter: diameter, scheme: scheme),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    child: Container(
                      width: rank == 1 ? 30 : 26,
                      height: rank == 1 ? 30 : 26,
                      decoration: BoxDecoration(color: medal, shape: BoxShape.circle, border: Border.all(color: scheme.surface, width: 3)),
                      alignment: Alignment.center,
                      child: Text('$rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: rank == 1 ? 15 : 13)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: rank == 1 ? 120 : 104,
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: rank == 1 ? 15 : 13.5, fontWeight: FontWeight.w700, color: scheme.onSurface),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              numberFormat.format(entry.points),
              style: TextStyle(
                fontSize: rank == 1 ? 14 : 12.5,
                fontWeight: FontWeight.w700,
                color: rank == 1 ? scheme.primary : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, required this.diameter, required this.scheme});
  final LeaderboardEntry entry;
  final double diameter;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty;
    return CircleAvatar(
      radius: diameter / 2,
      backgroundColor: avatarColorFor(entry.userId, scheme),
      backgroundImage: hasPhoto ? NetworkImage(entry.avatarUrl!) : null,
      child: hasPhoto
          ? null
          : Text(entry.initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: diameter * 0.32)),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Small up/down/flat position-change chip (§ leaderboard redesign,
/// 2026-09-04). `null` renders nothing — see LeaderboardEntry.delta's
/// docstring for why every row's delta is null today (no backend field
/// yet); this widget is ready the moment that field exists.
class RankDeltaChip extends StatelessWidget {
  const RankDeltaChip({super.key, required this.delta});

  final int? delta;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final up = d > 0;
    final flat = d == 0;
    final color = flat ? scheme.onSurfaceVariant : (up ? c.success : c.danger);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!flat) Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 14, color: color),
          Text(
            flat ? '—' : '${d.abs()}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

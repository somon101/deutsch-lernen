import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../models/leaderboard_entry.dart';

const _periods = LeaderboardPeriod.values;

String _label(AppLocalizations l10n, LeaderboardPeriod p) => switch (p) {
      LeaderboardPeriod.day => l10n.leaderboardPeriodDay,
      LeaderboardPeriod.week => l10n.leaderboardPeriodWeek,
      LeaderboardPeriod.month => l10n.leaderboardPeriodMonth,
      LeaderboardPeriod.allTime => l10n.leaderboardPeriodAllTime,
    };

/// Day/Week/Month/All-time tabs (§ leaderboard redesign, 2026-09-04) — the
/// active pill moves via AnimatedAlign (a real position transition, not a
/// recolor swap), matching the approved mockup's `.seg-pill` behavior.
class PeriodSegmented extends StatelessWidget {
  const PeriodSegmented({super.key, required this.value, required this.onChanged});

  final LeaderboardPeriod value;
  final ValueChanged<LeaderboardPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final index = _periods.indexOf(value);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = (constraints.maxWidth - 8) / _periods.length;
              return AnimatedAlign(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-1 + (index * 2 / (_periods.length - 1)), 0),
                child: Container(
                  width: cellWidth,
                  height: 34,
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
          Row(
            children: [
              for (final p in _periods)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        _label(l10n, p),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: p == value ? scheme.onPrimary : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

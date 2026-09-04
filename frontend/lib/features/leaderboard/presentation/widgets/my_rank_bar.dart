import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/auth/user.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/leaderboard_entry.dart';
import 'leaderboard_number_format.dart';

/// The signed-in user's own always-visible row, pinned above the shell's
/// bottom nav (§ leaderboard redesign, 2026-09-04) — reads the real,
/// already-existing myRankProvider (MyRankSummary), independent of whether
/// `me` even appears in the fetched top-N `entries` list.
class MyRankBar extends StatelessWidget {
  const MyRankBar({super.key, required this.summary, required this.me, required this.onTap});

  final MyRankSummary summary;
  final AppUser me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = context.colors;
    final onGradient = scheme.onPrimary;
    final numberFormat = NumberFormat.decimalPattern(numberFormatLocale(context));
    final hasPhoto = me.avatarUrl != null && me.avatarUrl!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: Alignment.centerLeft, end: Alignment.centerRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.34), blurRadius: 18, offset: const Offset(0, -2))],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '${summary.rank}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: onGradient.withValues(alpha: 0.72), fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              const SizedBox(width: 11),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: onGradient.withValues(alpha: 0.55), width: 2)),
                alignment: Alignment.center,
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: onGradient.withValues(alpha: 0.2),
                  backgroundImage: hasPhoto ? NetworkImage(me.avatarUrl!) : null,
                  child: hasPhoto ? null : Text(me.firstName.isNotEmpty ? me.firstName[0].toUpperCase() : '', style: TextStyle(color: onGradient, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${me.firstName} ${me.lastName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: onGradient)),
                    Text(l10n.leaderboardThisIsYou, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: onGradient.withValues(alpha: 0.7))),
                  ],
                ),
              ),
              Text(
                numberFormat.format(summary.points),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: onGradient, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

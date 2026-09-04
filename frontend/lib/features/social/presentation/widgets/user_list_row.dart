import 'package:flutter/material.dart';

import '../../../../core/utils/avatar_identity.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../data/social_repository.dart';

/// One row in any list of other users — search results, followers,
/// following, mutual (§ subscriptions follow-up, 2026-08-31). Extracted
/// from the leaderboard's search-result row so every such list looks and
/// behaves identically instead of drifting apart.
class UserListRow extends StatelessWidget {
  const UserListRow({super.key, required this.user, required this.onTap});
  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final initials = ((user.firstName.isNotEmpty ? user.firstName[0] : '') + (user.lastName.isNotEmpty ? user.lastName[0] : '')).toUpperCase();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius), border: Border.all(color: c.border)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              // Same deterministic per-identity color as the leaderboard's
              // podium/rows (§ leaderboard redesign, 2026-09-04) — a given
              // person now looks the same here and there, instead of every
              // initials-only avatar sharing one flat theme color.
              backgroundColor: avatarColorFor(user.id, Theme.of(context).colorScheme),
              // Plain NetworkImage, not cached — same reasoning as every
              // other-users list in the app (leaderboard rows): caching is
              // reserved for the signed-in user's own single avatar.
              backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                  ? Text(initials, style: ProfileTypography.caption(context).copyWith(fontWeight: FontWeight.w700))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${user.firstName} ${user.lastName}', style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
                  Text('@${user.username}', style: ProfileTypography.caption(context)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

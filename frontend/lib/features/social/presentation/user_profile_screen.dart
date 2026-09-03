import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/back_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/data/profile_gamification_repository.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../../profile/presentation/widgets/level_card.dart';
import '../../profile/presentation/widgets/metrics_row.dart';
import '../../profile/presentation/widgets/rank_card.dart';
import '../../profile/presentation/widgets/stat_row.dart';
import '../../profile/presentation/widgets/week_activity.dart';
import '../data/social_repository.dart';

/// Another user's public profile (§ subscriptions, 2026-08-30; extended §
/// subscriptions follow-up, 2026-08-30 to show the same stats a user sees
/// about themselves) — reached by tapping someone in the Рейтинг list, a
/// search result (`context.go(...)`, replaces the stack), OR now a
/// followers/following/mutual list (`context.push(...)`, § subscriptions
/// follow-up, 2026-08-31 — a real page stays underneath). Identity + follow
/// counts + the subscribe action, the real Серия/Прогресс/Время/Очки row,
/// rank card and weekly activity, plus the same "Ваш уровень" card the
/// owner's own profile shows (that card is still backed by the one shared
/// mock value everywhere it appears, not real per-user data yet — but the
/// owner's own profile shows it too, so leaving it out here would just be
/// an inconsistency, not more honest).
///
/// The back arrow has to handle both reach paths: pop back to the real page
/// when there is one, or fall back to Рейтинг (matching [BackGuard]'s own
/// fallback) when reached via `go()` and there's nothing to pop.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final profile = ref.watch(userProfileProvider(userId));

    // canPop is true when this screen was pushed on top of something real
    // (§ subscriptions follow-up, 2026-08-31 — reached from a followers/
    // following/mutual list, itself pushed) — the visible back arrow must
    // pop back there, not always jump to Рейтинг the way the original
    // go()-only leaderboard tap-through needed.
    final canPop = Navigator.of(context).canPop();
    final l10n = AppLocalizations.of(context);

    return BackGuard(
      fallbackPath: '/leaderboard',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(l10n.socialProfileTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: canPop ? () => context.pop() : () => context.go('/leaderboard'),
          ),
        ),
        body: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(child: Text(l10n.socialProfileLoadError(err), style: ProfileTypography.body(context))),
          data: (p) {
            final avatarUrl = ref.read(apiClientProvider).assetUrl(p.avatarUrl);
            final initials = ((p.firstName.isNotEmpty ? p.firstName[0] : '') + (p.lastName.isNotEmpty ? p.lastName[0] : '')).toUpperCase();
            final overview = ref.watch(profileGamificationProvider);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: c.accentSoft,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty ? Text(initials, style: ProfileTypography.sectionTitle(context)) : null,
                  ),
                  const SizedBox(height: 12),
                  Text('${p.firstName} ${p.lastName}', style: ProfileTypography.sectionTitle(context)),
                  Text('@${p.username}', style: ProfileTypography.caption(context)),
                  const SizedBox(height: 20),
                  StatRow(items: [
                    StatRowItem(value: '${p.followersCount}', label: l10n.socialFollowers, onTap: () => context.push('/users/${p.id}/followers')),
                    StatRowItem(value: '${p.mutualCount}', label: l10n.socialMutual, onTap: () => context.push('/users/${p.id}/mutual')),
                    StatRowItem(value: '${p.followingCount}', label: l10n.socialFollowing, onTap: () => context.push('/users/${p.id}/following')),
                  ]),
                  const SizedBox(height: 20),
                  if (!p.isSelf) ...[
                    _FollowButton(userId: p.id, isFollowing: p.isFollowing),
                    const SizedBox(height: 20),
                  ],
                  ref.watch(userStatsProvider(p.id)).when(
                        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                        error: (err, st) => Text(l10n.socialStatsLoadError(err), style: ProfileTypography.body(context)),
                        data: (s) => Column(
                          children: [
                            MetricsRow(
                              progressPercent: s.overallProgressPercent,
                              timeSeconds: s.totalTimeSeconds,
                              streakDays: s.streakDays,
                              points: s.rank.points,
                            ),
                            const SizedBox(height: 16),
                            RankCard(summary: s.rank),
                            const SizedBox(height: 16),
                            WeekActivityCard(activity: s.weekActivity),
                            const SizedBox(height: 16),
                            LevelCard(level: overview.level),
                          ],
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.userId, required this.isFollowing});
  final String userId;
  final bool isFollowing;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _busy = false;
  bool? _optimistic;

  bool get _following => _optimistic ?? widget.isFollowing;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final wasFollowing = _following;
    try {
      final repo = ref.read(socialRepositoryProvider);
      final updated = wasFollowing ? await repo.unfollowUser(widget.userId) : await repo.followUser(widget.userId);
      ref.invalidate(userProfileProvider(widget.userId));
      ref.invalidate(followListProvider((FollowListKind.followers, widget.userId)));
      ref.invalidate(followListProvider((FollowListKind.mutual, widget.userId)));
      // My own counts changed too — not just the target's — since this
      // screen can now be reached via a pushed route stacked on top of my
      // own ProfileScreen (Подписки/Подписчики/Взаимные → a list → someone's
      // profile), which stays mounted and watching its own provider the
      // whole time, unlike the old go()-only navigation this screen used to
      // be reached through exclusively.
      final myId = ref.read(authProvider).value?.id;
      if (myId != null) {
        ref.invalidate(userProfileProvider(myId));
        ref.invalidate(followListProvider((FollowListKind.following, myId)));
        ref.invalidate(followListProvider((FollowListKind.mutual, myId)));
      }
      if (mounted) setState(() => _optimistic = updated.isFollowing);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        final message = wasFollowing ? l10n.socialUnfollowError(e) : l10n.socialFollowError(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final following = _following;
    return SizedBox(
      width: double.infinity,
      child: following
          ? OutlinedButton(
              onPressed: _busy ? null : _toggle,
              child: Text(_busy ? l10n.socialUnfollowing : l10n.socialUnfollow),
            )
          : FilledButton(
              onPressed: _busy ? null : _toggle,
              child: Text(_busy ? l10n.socialFollowingInProgress : l10n.socialFollow),
            ),
    );
  }
}

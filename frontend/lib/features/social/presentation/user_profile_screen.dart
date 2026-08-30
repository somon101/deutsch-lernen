import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/widgets/back_guard.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../../profile/presentation/widgets/stat_row.dart';
import '../data/social_repository.dart';

/// Another user's public profile (§ subscriptions, 2026-08-30) — reached by
/// tapping someone in the Рейтинг list or a search result. Deliberately
/// minimal: identity + follow counts + the subscribe action, not the full
/// own-profile screen's learning stats (progress/time/streak/rank), which
/// stay private to the account they belong to.
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final profile = ref.watch(userProfileProvider(userId));

    return BackGuard(
      fallbackPath: '/leaderboard',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: const Text('Профиль')),
        body: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(child: Text('Не удалось загрузить профиль: $err', style: ProfileTypography.body(context))),
          data: (p) {
            final avatarUrl = ref.read(apiClientProvider).assetUrl(p.avatarUrl);
            final initials = ((p.firstName.isNotEmpty ? p.firstName[0] : '') + (p.lastName.isNotEmpty ? p.lastName[0] : '')).toUpperCase();
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
                    StatRowItem(value: '${p.followersCount}', label: 'Подписчики'),
                    StatRowItem(value: '${p.mutualCount}', label: 'Взаимные'),
                    StatRowItem(value: '${p.followingCount}', label: 'Подписки'),
                  ]),
                  const SizedBox(height: 24),
                  if (!p.isSelf) _FollowButton(userId: p.id, isFollowing: p.isFollowing),
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

  Future<void> _follow() async {
    if (_following) return; // already following — idempotent server-side too, but no need to re-send
    setState(() => _busy = true);
    try {
      final updated = await ref.read(socialRepositoryProvider).followUser(widget.userId);
      ref.invalidate(userProfileProvider(widget.userId));
      if (mounted) setState(() => _optimistic = updated.isFollowing);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось подписаться: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _following || _busy ? null : _follow,
        child: Text(_busy ? 'Подписываемся…' : (_following ? 'Подписан' : 'Подписаться')),
      ),
    );
  }
}

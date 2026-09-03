import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../data/social_repository.dart';
import 'widgets/user_list_row.dart';

/// The full list behind a profile's Подписки/Подписчики/Взаимные number (§
/// subscriptions follow-up, 2026-08-31). Reached with `context.push(...)`
/// from ProfileScreen/UserProfileScreen (both already on the Navigator
/// stack), so — unlike screens reached with `context.go(...)` elsewhere in
/// the app — Flutter's own automatic AppBar back arrow already has
/// something to pop; no BackGuard/manual leading button needed, just the
/// existing push-based navigation already used for `/profile/qr`.
class FollowListScreen extends ConsumerWidget {
  const FollowListScreen({super.key, required this.userId, required this.kind});

  final String userId;
  final FollowListKind kind;

  String _title(AppLocalizations l10n) => switch (kind) {
        FollowListKind.followers => l10n.socialFollowers,
        FollowListKind.following => l10n.socialFollowing,
        FollowListKind.mutual => l10n.socialMutual,
      };

  void _openProfile(BuildContext context, WidgetRef ref, String tappedId) {
    final me = ref.read(authProvider).value;
    if (me != null && me.id == tappedId) {
      // Deliberately no navigation here (project owner's explicit call,
      // 2026-08-31) — just tell the user this row is them, same list stays
      // open. The Рейтинг tab's own self-tap (context.go('/profile')) is a
      // separate code path and is intentionally left untouched.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).socialThisIsYourProfile)));
    } else {
      context.push('/users/$tappedId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    final list = ref.watch(followListProvider((kind, userId)));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(_title(l10n))),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text(l10n.socialListLoadError(err), style: ProfileTypography.body(context))),
        data: (users) {
          if (users.isEmpty) {
            return Center(child: Text(l10n.socialListEmpty, style: ProfileTypography.body(context)));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(followListProvider((kind, userId))),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: users.length,
              itemBuilder: (context, i) {
                final u = users[i];
                return UserListRow(key: ValueKey(u.id), user: u, onTap: () => _openProfile(context, ref, u.id));
              },
            ),
          );
        },
      ),
    );
  }
}

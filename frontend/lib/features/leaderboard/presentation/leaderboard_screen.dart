import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/back_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../../social/data/social_repository.dart';
import '../../social/presentation/widgets/user_list_row.dart';
import '../data/leaderboard_repository.dart';

/// The global points leaderboard (§ rating system, 2026-08-30) — every
/// user's own language choice never affects this: it's always total points
/// across everything they've studied. Also hosts the user search (§
/// subscriptions, 2026-08-30) — a separate, independent feature that just
/// happens to live on the same screen, per the request.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openProfile(String userId) {
    final me = ref.read(authProvider).value;
    if (me != null && me.id == userId) {
      context.go('/profile');
    } else {
      context.go('/users/$userId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    final leaderboard = ref.watch(leaderboardProvider);
    final me = ref.watch(authProvider).value;

    return BackGuard(
      fallbackPath: '/',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: Text(l10n.leaderboardTitle)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.leaderboardSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: c.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: _query.trim().length >= 2
                  ? _SearchResults(query: _query.trim(), onTap: _openProfile)
                  : leaderboard.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, st) => Center(child: Text(l10n.leaderboardLoadError(err), style: ProfileTypography.body(context))),
                      data: (board) {
                        if (board.entries.isEmpty) {
                          return Center(child: Text(l10n.leaderboardEmpty, style: ProfileTypography.body(context)));
                        }
                        return RefreshIndicator(
                          onRefresh: () async => ref.invalidate(leaderboardProvider),
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomBarClearance(context)),
                            itemCount: board.entries.length,
                            itemBuilder: (context, i) {
                              final entry = board.entries[i];
                              // A stable per-user key (not just position) —
                              // without it Flutter can reuse a row's Element
                              // across refreshes when the list is rebuilt.
                              return _LeaderboardRow(
                                key: ValueKey(entry.userId),
                                entry: entry,
                                isMe: entry.userId == me?.id,
                                onTap: () => _openProfile(entry.userId),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.onTap});
  final String query;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final results = ref.watch(_searchResultsProvider(query));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, st) => Center(child: Text(l10n.leaderboardSearchError(err), style: ProfileTypography.body(context))),
      data: (users) {
        if (users.isEmpty) {
          return Center(child: Text(l10n.leaderboardUserNotFound, style: ProfileTypography.body(context)));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: users.length,
          itemBuilder: (context, i) {
            final u = users[i];
            return UserListRow(key: ValueKey(u.id), user: u, onTap: () => onTap(u.id));
          },
        );
      },
    );
  }
}

final _searchResultsProvider = FutureProvider.autoDispose.family<List<UserProfile>, String>((ref, query) {
  return ref.watch(socialRepositoryProvider).searchUsers(query);
});

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({super.key, required this.entry, required this.isMe, required this.onTap});
  final LeaderboardEntry entry;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final initials = ((entry.firstName.isNotEmpty ? entry.firstName[0] : '') + (entry.lastName.isNotEmpty ? entry.lastName[0] : '')).toUpperCase();
    final medalColor = switch (entry.rank) {
      1 => const Color(0xFFFFD700),
      2 => const Color(0xFFC0C0C0),
      3 => const Color(0xFFCD7F32),
      _ => null,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? c.accentSoft : c.card,
          borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
          border: isMe ? Border.all(color: c.accent, width: 1.5) : Border.all(color: c.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${entry.rank}',
                textAlign: TextAlign.center,
                style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w700, color: medalColor ?? c.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 18,
              backgroundColor: c.accentSoft,
              // Plain NetworkImage on purpose here, not CachedNetworkImage —
              // offline caching was only ever asked for the signed-in user's
              // own avatar (shown alone, never in a list); showing many
              // different users' avatars together is exactly the case where
              // that package's web image-identity handling proved unreliable
              // (avatars visibly swapping between rows after leaving and
              // returning to this screen).
              backgroundImage: entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty ? NetworkImage(entry.avatarUrl!) : null,
              child: entry.avatarUrl == null || entry.avatarUrl!.isEmpty
                  ? Text(initials, style: ProfileTypography.caption(context).copyWith(fontWeight: FontWeight.w700))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.firstName} ${entry.lastName}', style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
                  Text('@${entry.username}', style: ProfileTypography.caption(context)),
                ],
              ),
            ),
            Text('${entry.points}', style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w700, color: c.accent)),
          ],
        ),
      ),
    );
  }
}

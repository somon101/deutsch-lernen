import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/back_guard.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../data/leaderboard_repository.dart';

/// The global points leaderboard (§ rating system, 2026-08-30) — every
/// user's own language choice never affects this: it's always total points
/// across everything they've studied.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final leaderboard = ref.watch(leaderboardProvider);
    final me = ref.watch(authProvider).value;

    return BackGuard(
      fallbackPath: '/',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: const Text('Рейтинг')),
        body: leaderboard.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(child: Text('Не удалось загрузить рейтинг: $err', style: ProfileTypography.body(context))),
          data: (board) {
            if (board.entries.isEmpty) {
              return Center(child: Text('Пока нет участников рейтинга', style: ProfileTypography.body(context)));
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(leaderboardProvider),
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarClearance(context)),
                itemCount: board.entries.length,
                itemBuilder: (context, i) {
                  final entry = board.entries[i];
                  // A stable per-user key (not just position) — without it
                  // Flutter can reuse a row's Element/image state across
                  // refreshes when the list is rebuilt, which visibly swaps
                  // avatars between users while a new image is still
                  // loading.
                  return _LeaderboardRow(key: ValueKey(entry.userId), entry: entry, isMe: entry.userId == me?.id);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({super.key, required this.entry, required this.isMe});
  final LeaderboardEntry entry;
  final bool isMe;

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

    return Container(
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
            backgroundImage: entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty ? CachedNetworkImageProvider(entry.avatarUrl!) : null,
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
    );
  }
}

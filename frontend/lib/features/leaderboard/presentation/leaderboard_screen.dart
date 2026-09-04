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
import 'widgets/leaderboard_row.dart';
import 'widgets/leaderboard_skeleton.dart';
import 'widgets/my_rank_bar.dart';
import 'widgets/period_segmented.dart';
import 'widgets/podium.dart';
import 'widgets/rank_goal_banner.dart';

const _maxContentWidth = 480.0;

/// The global points leaderboard (§ rating system, 2026-08-30; redesigned
/// §2026-09-04 into period tabs + podium + goal banner + ranked list + a
/// sticky own-rank bar). Also hosts the user search (§ subscriptions,
/// 2026-08-30) — a separate, independent feature that just happens to live
/// on the same screen, now reached via an AppBar icon instead of a
/// permanently-visible field.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _searchExpanded = false;

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

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  void _showInfoSheet() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.leaderboardInfoTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 8),
              // TODO(product): confirm this wording stays accurate if the
              // scoring formula ever changes — it currently mirrors
              // LeaderboardEntry's own doc comment (10/question, 50/lesson).
              Text(l10n.leaderboardInfoBody, style: Theme.of(sheetContext).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final leaderboard = ref.watch(leaderboardProvider);
    final me = ref.watch(authProvider).value;
    final period = ref.watch(leaderboardPeriodProvider);

    return BackGuard(
      fallbackPath: '/',
      child: Scaffold(
        appBar: AppBar(
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchExpanded
                ? TextField(
                    key: const ValueKey('search-field'),
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(hintText: l10n.leaderboardSearchHint, border: InputBorder.none),
                    style: TextStyle(color: scheme.onSurface),
                    onChanged: (v) => setState(() => _query = v),
                  )
                : Text(l10n.leaderboardTitle, key: const ValueKey('title')),
          ),
          actions: [
            IconButton(
              tooltip: l10n.leaderboardSearchTooltip,
              icon: Icon(_searchExpanded ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
            ),
            if (!_searchExpanded)
              IconButton(tooltip: l10n.leaderboardInfoTooltip, icon: const Icon(Icons.info_outline), onPressed: _showInfoSheet),
          ],
        ),
        // A real Column, not a Stack+Positioned overlay (§ sticky-bar fix,
        // 2026-09-04 verification finding) — matches the approved mockup's
        // OWN structure exactly (`.scroll{flex:1}` + `.myshell{flex:0 0
        // auto}`, two flex siblings, `.myshell` never floats over
        // `.scroll`): MyRankBar is a real sibling below Expanded(list), so
        // it shrinks the list's actual viewport instead of floating on top
        // of it. A Positioned overlay could never fully avoid intruding on
        // whatever row scrolls into its fixed screen band — that's true of
        // any such overlay in any UI framework, not fixable while staying
        // an overlay, so this restructures around it instead of padding
        // around the symptom.
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: _query.trim().length >= 2
                      ? _SearchResults(query: _query.trim(), onTap: _openProfile)
                      : leaderboard.when(
                          loading: () => const LeaderboardSkeleton(),
                          error: (err, st) => _ErrorView(message: l10n.leaderboardLoadError(err), onRetry: () => ref.invalidate(leaderboardProvider)),
                          data: (board) {
                            if (board.entries.isEmpty) {
                              return Center(child: Text(l10n.leaderboardEmpty, style: Theme.of(context).textTheme.bodyMedium));
                            }
                            final rest = board.entries.where((e) => e.userId != me?.id).where((e) => e.rank > 3).toList();
                            return RefreshIndicator(
                              onRefresh: () async => ref.invalidate(leaderboardProvider),
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                children: [
                                  PeriodSegmented(value: period, onChanged: (p) => ref.read(leaderboardPeriodProvider.notifier).state = p),
                                  const SizedBox(height: 20),
                                  LeaderboardPodium(entries: board.entries.where((e) => e.rank <= 3).toList(), onTapEntry: (e) => _openProfile(e.userId)),
                                  const SizedBox(height: 20),
                                  if (me != null) ...[
                                    RankGoalBanner(entries: board.entries, myUserId: me.id),
                                    const SizedBox(height: 20),
                                  ],
                                  if (rest.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Row(
                                        children: [
                                          SizedBox(width: 26, child: Text(l10n.leaderboardColumnRank, style: _headerStyle(scheme))),
                                          const SizedBox(width: 11 + 40 + 11),
                                          Expanded(child: Text(l10n.leaderboardColumnStudent, style: _headerStyle(scheme))),
                                          Text(l10n.leaderboardColumnPoints, style: _headerStyle(scheme)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    for (final entry in rest) LeaderboardRow(key: ValueKey(entry.userId), entry: entry, onTap: () => _openProfile(entry.userId)),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            if (me != null)
              Container(
                padding: EdgeInsets.fromLTRB(12, 8, 12, bottomBarClearance(context) + 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Theme.of(context).scaffoldBackgroundColor, Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0)],
                    stops: const [0.55, 1.0],
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxContentWidth - 24),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final myRank = ref.watch(myRankProvider);
                        return myRank.when(
                          data: (summary) => MyRankBar(summary: summary, me: me, onTap: () => context.go('/profile')),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

TextStyle _headerStyle(ColorScheme scheme) => TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant);

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(l10n.leaderboardRetry)),
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

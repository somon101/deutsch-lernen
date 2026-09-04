import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/leaderboard_entry.dart';

export '../models/leaderboard_entry.dart';

class LeaderboardRepository {
  LeaderboardRepository(this._api);

  final ApiClient _api;

  Future<Leaderboard> fetchLeaderboard({LeaderboardPeriod period = LeaderboardPeriod.allTime}) async {
    final res = await _api.get('/api/leaderboard', query: {'period': period.name});
    return Leaderboard(
      entries: (res['entries'] as List<dynamic>).map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>)).toList(),
      total: res['total'] as int,
    );
  }

  Future<MyRankSummary> fetchMyRank({LeaderboardPeriod period = LeaderboardPeriod.allTime}) async {
    final res = await _api.get('/api/me/rank', query: {'period': period.name});
    return MyRankSummary.fromJson(res);
  }
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) => LeaderboardRepository(ref.watch(apiClientProvider)));

/// Which period the leaderboard tabs are currently set to — a plain local
/// selection, not fetched from anywhere (§ leaderboard redesign,
/// 2026-09-04). Resets on cold start, same convention as
/// home_screen.dart's homeLanguageIdProvider.
final leaderboardPeriodProvider = StateProvider.autoDispose<LeaderboardPeriod>((ref) => LeaderboardPeriod.allTime);

final leaderboardProvider = FutureProvider.autoDispose<Leaderboard>((ref) {
  final period = ref.watch(leaderboardPeriodProvider);
  return ref.watch(leaderboardRepositoryProvider).fetchLeaderboard(period: period);
});

/// Keyed by period (§ leaderboard periods, 2026-09-04) so the leaderboard
/// screen's sticky own-rank bar can track whichever tab is selected there,
/// while profile_screen.dart's rank card keeps requesting `allTime`
/// explicitly and so stays on the global standing it has always shown,
/// independent of whatever tab was last picked on the leaderboard screen.
final myRankProvider = FutureProvider.autoDispose.family<MyRankSummary, LeaderboardPeriod>((ref, period) {
  return ref.watch(leaderboardRepositoryProvider).fetchMyRank(period: period);
});

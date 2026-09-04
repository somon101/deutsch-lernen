import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/leaderboard_entry.dart';

export '../models/leaderboard_entry.dart';

class LeaderboardRepository {
  LeaderboardRepository(this._api);

  final ApiClient _api;

  Future<Leaderboard> fetchLeaderboard({LeaderboardPeriod period = LeaderboardPeriod.allTime}) async {
    // TODO(backend): `period` isn't sent yet — see LeaderboardPeriod's
    // docstring. Once GET /api/leaderboard accepts one, add
    // `query: {'period': period.name}` here.
    final res = await _api.get('/api/leaderboard');
    return Leaderboard(
      entries: (res['entries'] as List<dynamic>).map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>)).toList(),
      total: res['total'] as int,
    );
  }

  Future<MyRankSummary> fetchMyRank() async {
    final res = await _api.get('/api/me/rank');
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

final myRankProvider = FutureProvider.autoDispose<MyRankSummary>((ref) {
  return ref.watch(leaderboardRepositoryProvider).fetchMyRank();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// One row on the global leaderboard (§ rating system, 2026-08-30) — 10
/// points per distinct correctly-answered question + 50 per completed
/// lesson, summed across every language the user studies.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.avatarUrl,
    required this.points,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        userId: json['userId'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        points: json['points'] as int,
        rank: json['rank'] as int,
      );

  final String userId;
  final String firstName;
  final String lastName;
  final String username;
  final String? avatarUrl;
  final int points;
  final int rank;
}

class Leaderboard {
  const Leaderboard({required this.entries, required this.total});
  final List<LeaderboardEntry> entries;
  final int total;
}

/// The signed-in user's own standing (§ rating system, 2026-08-30) — global,
/// independent of whichever language is selected for progress/time or shown
/// on Главное. `weeklyChange` is null when there's no meaningful "7 days
/// ago" rank to compare against yet (e.g. a brand-new participant), not a
/// fabricated zero.
class MyRankSummary {
  const MyRankSummary({required this.rank, required this.totalParticipants, required this.points, required this.weeklyChange});

  factory MyRankSummary.fromJson(Map<String, dynamic> json) => MyRankSummary(
        rank: json['rank'] as int,
        totalParticipants: json['totalParticipants'] as int,
        points: json['points'] as int,
        weeklyChange: json['weeklyChange'] as int?,
      );

  final int rank;
  final int totalParticipants;
  final int points;
  final int? weeklyChange;
}

class LeaderboardRepository {
  LeaderboardRepository(this._api);

  final ApiClient _api;

  Future<Leaderboard> fetchLeaderboard() async {
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

final leaderboardProvider = FutureProvider.autoDispose<Leaderboard>((ref) {
  return ref.watch(leaderboardRepositoryProvider).fetchLeaderboard();
});

final myRankProvider = FutureProvider.autoDispose<MyRankSummary>((ref) {
  return ref.watch(leaderboardRepositoryProvider).fetchMyRank();
});

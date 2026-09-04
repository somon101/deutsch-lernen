/// Which window of activity the leaderboard is ranked over (§ leaderboard
/// redesign, 2026-09-04). TODO(backend): GET /api/leaderboard has no period
/// parameter yet — every value here currently produces the identical
/// all-time ranking; services/leaderboard.py's own docstring already
/// anticipates this ("`as_of` already makes 'rank as of a point in time'
/// reusable for a real period filter later"), it just isn't wired up. Once
/// it is, LeaderboardRepository.fetchLeaderboard is the only place that
/// needs to actually send it.
enum LeaderboardPeriod { day, week, month, allTime }

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
    this.delta,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        userId: json['userId'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        points: json['points'] as int,
        rank: json['rank'] as int,
        // TODO(backend): position-change-vs-previous-period isn't in the
        // API response at all yet — this key is never present, so `delta`
        // is always null until a real field (e.g. `rankDelta`) is added.
        delta: json['rankDelta'] as int?,
      );

  final String userId;
  final String firstName;
  final String lastName;
  final String username;
  final String? avatarUrl;
  final int points;
  final int rank;
  final int? delta;

  String get displayName => '$firstName $lastName';

  String get initials => ((firstName.isNotEmpty ? firstName[0] : '') + (lastName.isNotEmpty ? lastName[0] : '')).toUpperCase();
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

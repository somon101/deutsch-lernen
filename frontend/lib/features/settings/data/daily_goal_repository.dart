import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// The daily study goal, as the server sees it (§ daily goal, 2026-09-03).
///
/// Separate from SettingsPrefs on purpose: everything in that class is still
/// device-local SharedPreferences, and this one setting is not. It follows
/// the account, so it survives a reinstall and is the same on every device —
/// which is also why the reward can only ever be paid once per day.
class DailyGoalStatus {
  const DailyGoalStatus({
    required this.goalMinutes,
    required this.goalSeconds,
    required this.secondsToday,
    required this.progressSeconds,
    required this.completed,
    required this.pointsAwarded,
    required this.pointsAwardedNow,
  });

  final int goalMinutes;
  final int goalSeconds;

  /// The real total for today, uncapped — can exceed [goalSeconds].
  final int secondsToday;

  /// The same figure capped at the goal, so a bar never overfills.
  final int progressSeconds;

  final bool completed;

  /// Points this day's completed goal is worth (0 until it completes).
  final int pointsAwarded;

  /// Non-zero only on the single response that actually paid the reward —
  /// the one moment a "goal reached" message may be shown.
  final int pointsAwardedNow;

  double get ratio => goalSeconds == 0 ? 0 : (progressSeconds / goalSeconds).clamp(0.0, 1.0);
  int get minutesToday => secondsToday ~/ 60;

  static const fallback = DailyGoalStatus(
    goalMinutes: 10,
    goalSeconds: 600,
    secondsToday: 0,
    progressSeconds: 0,
    completed: false,
    pointsAwarded: 0,
    pointsAwardedNow: 0,
  );

  factory DailyGoalStatus.fromJson(Map<String, dynamic> json) => DailyGoalStatus(
        goalMinutes: (json['goalMinutes'] as num?)?.toInt() ?? fallback.goalMinutes,
        goalSeconds: (json['goalSeconds'] as num?)?.toInt() ?? fallback.goalSeconds,
        secondsToday: (json['secondsToday'] as num?)?.toInt() ?? 0,
        progressSeconds: (json['progressSeconds'] as num?)?.toInt() ?? 0,
        completed: json['completed'] as bool? ?? false,
        pointsAwarded: (json['pointsAwarded'] as num?)?.toInt() ?? 0,
        pointsAwardedNow: (json['pointsAwardedNow'] as num?)?.toInt() ?? 0,
      );
}

/// The five goals the learner may pick, and what completing each is worth.
///
/// The points are shown, never applied: the server decides what a completed
/// goal pays, and this list only labels the choice. Kept in the same order
/// the picker shows them.
const dailyGoalOptions = <int>[3, 5, 10, 15, 20];
const dailyGoalPoints = <int, int>{3: 5, 5: 10, 10: 20, 15: 30, 20: 50};

class DailyGoalRepository {
  DailyGoalRepository(this._api);

  final ApiClient _api;

  Future<DailyGoalStatus> fetch() async {
    return DailyGoalStatus.fromJson(await _api.get('/api/me/daily-goal'));
  }

  /// Returns the status the server computed AFTER the change — lowering the
  /// goal below what today already covers completes it immediately, and the
  /// response is where that shows up.
  Future<DailyGoalStatus> setGoal(int minutes) async {
    return DailyGoalStatus.fromJson(await _api.put('/api/me/daily-goal', body: {'dailyGoalMinutes': minutes}));
  }
}

final dailyGoalRepositoryProvider = Provider((ref) => DailyGoalRepository(ref.watch(apiClientProvider)));

/// autoDispose on purpose: today's progress changes while the learner
/// studies, so a value cached for the life of the app would show a stale
/// figure the moment they came back from a lesson. Dropping it when nothing
/// is watching means the next screen to ask gets a fresh answer.
final dailyGoalProvider =
    FutureProvider.autoDispose<DailyGoalStatus>((ref) => ref.watch(dailyGoalRepositoryProvider).fetch());

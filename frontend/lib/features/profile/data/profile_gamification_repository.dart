import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MOCK DATA LAYER.
///
/// None of this is backed by the API — there is no social graph, streak
/// tracking, XP/level system, achievements, ranking, or per-day activity
/// log in the backend today. profile_screen.dart previously deliberately
/// left all of this out during the React->Flutter migration for exactly
/// that reason (see its old docstring). It's reintroduced here, isolated
/// to this one file, because the new profile design calls for it visually
/// — but every value below is static placeholder data. Swap this repository
/// for one backed by real endpoints once they exist; nothing outside this
/// file should need to change.
class SocialStats {
  const SocialStats({required this.followers, required this.mutual, required this.following});
  final int followers;
  final int mutual;
  final int following;
}

enum AchievementState { earned, inProgress, locked }

class Achievement {
  const Achievement({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String icon; // Material icon name resolved by the widget.
  final String title;
  final String subtitle;
  final AchievementState state;
}

class LevelProgress {
  const LevelProgress({required this.code, required this.name, required this.percent, required this.hint, required this.score});
  final String code;
  final String name;
  final int percent;
  final String hint;

  /// Average lesson score at this level — the "Уровень (B1)" metric tile.
  final double score;
}

class RankInfo {
  const RankInfo({required this.place, required this.topPercent, required this.periodLabel, required this.totalStudents});
  final int place;
  final int topPercent;
  final String periodLabel;
  final int totalStudents;
}

class WeeklyActivity {
  const WeeklyActivity({required this.days, required this.avgHoursPerDay, required this.trendPercent});

  /// Monday..Sunday. `true` = active that day, `false` = missed, `null` =
  /// no data yet (today/future).
  final List<bool?> days;
  final double avgHoursPerDay;
  final int trendPercent;
}

class ProfileGamificationOverview {
  const ProfileGamificationOverview({
    required this.bio,
    required this.social,
    required this.streakDays,
    required this.studyMinutes,
    required this.level,
    required this.achievements,
    required this.rank,
    required this.weeklyActivity,
  });

  final String bio;
  final SocialStats social;
  final int streakDays;
  final int studyMinutes;
  final LevelProgress level;
  final List<Achievement> achievements;
  final RankInfo rank;
  final WeeklyActivity weeklyActivity;
}

class ProfileGamificationRepository {
  const ProfileGamificationRepository();

  ProfileGamificationOverview fetchOverview() => const ProfileGamificationOverview(
        bio: 'Изучаю язык с целью свободного общения и путешествий ✈️',
        social: SocialStats(followers: 128, mutual: 42, following: 67),
        streakDays: 17,
        studyMinutes: 24 * 60 + 30,
        level: LevelProgress(code: 'B1', name: 'Intermediate', percent: 78, hint: 'Вы близки к следующему уровню!', score: 4.2),
        achievements: [
          Achievement(icon: 'mic', title: 'Первый урок', subtitle: 'Пройден', state: AchievementState.earned),
          Achievement(icon: 'week', title: 'Неделя 7 дней', subtitle: 'Пройден', state: AchievementState.earned),
          Achievement(icon: 'target', title: 'Цель 10 уроков', subtitle: '7/10', state: AchievementState.inProgress),
          Achievement(icon: 'trophy', title: 'Активный ученик', subtitle: '10 уроков', state: AchievementState.earned),
          Achievement(icon: 'lock', title: 'Мастер слов', subtitle: 'Заблокировано', state: AchievementState.locked),
        ],
        rank: RankInfo(place: 48, topPercent: 12, periodLabel: 'По неделе', totalStudents: 8452),
        weeklyActivity: WeeklyActivity(
          days: [true, true, true, true, true, true, null],
          avgHoursPerDay: 4.2,
          trendPercent: 12,
        ),
      );
}

final profileGamificationProvider = Provider<ProfileGamificationOverview>(
  (ref) => const ProfileGamificationRepository().fetchOverview(),
);

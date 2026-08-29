import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';

/// Mirrors ProfilePage.tsx's LessonProgressSummary — the wire shape
/// GET /api/me/progress returns per lesson the learner has attempted.
class LessonProgressSummary {
  const LessonProgressSummary({
    required this.lessonId,
    required this.attempts,
    required this.bestScore,
    required this.lastScore,
    required this.lastAttemptAt,
  });

  factory LessonProgressSummary.fromJson(Map<String, dynamic> json) => LessonProgressSummary(
        lessonId: json['lessonId'] as String,
        attempts: json['attempts'] as int,
        bestScore: json['bestScore'] as int,
        lastScore: json['lastScore'] as int,
        lastAttemptAt: json['lastAttemptAt'] as String,
      );

  final String lessonId;
  final int attempts;
  final int bestScore;
  final int lastScore;
  final String lastAttemptAt;
}

/// A Language the learner can pick in Settings to see its own overall
/// progress — only languages with at least one published course are ever
/// offered (see the backend's `withCourses` filter), since a language with
/// nothing published has no progress to show.
class LanguageOption {
  const LanguageOption({required this.id, required this.name});

  factory LanguageOption.fromJson(Map<String, dynamic> json) =>
      LanguageOption(id: json['id'] as String, name: json['name'] as String);

  final String id;
  final String name;
}

class LegacyLessonSummary {
  const LegacyLessonSummary({required this.lessonId, required this.title, required this.vocabularyCount});

  factory LegacyLessonSummary.fromJson(Map<String, dynamic> json) => LegacyLessonSummary(
        lessonId: json['lessonId'] as String,
        title: json['title'] as String,
        vocabularyCount: json['vocabularyCount'] as int,
      );

  final String lessonId;
  final String title;
  final int vocabularyCount;
}

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<List<LegacyLessonSummary>> fetchLegacyLessons() async {
    final lessons = await fetchLegacyLessonsRaw();
    return lessons.map(LegacyLessonSummary.fromJson).toList();
  }

  /// Raw-JSON variant for the caching layer (see cached_json.dart).
  Future<List<Map<String, dynamic>>> fetchLegacyLessonsRaw() async {
    final res = await _api.get('/api/content');
    return (res['lessons'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<LessonProgressSummary>> fetchProgressSummaries() async {
    final res = await _api.get('/api/me/progress');
    return (res['progress'] as List<dynamic>).map((p) => LessonProgressSummary.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    String? username,
    String? bio,
    DateTime? birthDate,
  }) async {
    final res = await _api.patch('/api/me/', body: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'username': ?username,
      'bio': ?bio,
      if (birthDate != null) 'birthDate': birthDate.toUtc().toIso8601String(),
    });
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<AppUser> uploadAvatar({required List<int> bytes, required String filename}) async {
    final res = await _api.postMultipart('/api/me/avatar', fieldName: 'avatar', bytes: bytes, filename: filename);
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<AppUser> deleteAvatar() async {
    final res = await _api.deleteExpectingBody('/api/me/avatar');
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) {
    return _api.patch('/api/me/password', body: {'currentPassword': currentPassword, 'newPassword': newPassword});
  }

  /// Only languages with a published course under them — matches what a
  /// learner can actually see/answer, so the picker never offers a language
  /// with nothing to show progress for.
  Future<List<LanguageOption>> fetchAvailableLanguages() async {
    final res = await _api.get('/api/languages', query: {'withCourses': true});
    return (res['languages'] as List<dynamic>).map((l) => LanguageOption.fromJson(l as Map<String, dynamic>)).toList();
  }

  Future<AppUser> setSelectedLanguage(String? languageId) async {
    final res = await _api.patch('/api/me/', body: {'selectedLanguageId': languageId});
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  /// Overall progress (§ per-language overall progress, 2026-08-29), scoped
  /// to one language's own courses/levels — independent of every other
  /// language's progress.
  Future<int> fetchOverallProgressPercent(String languageId) async {
    final res = await _api.get('/api/me/progress/overall', query: {'languageId': languageId});
    return (res['progress'] as Map<String, dynamic>)['percent'] as int;
  }

  /// Total time spent (§ time tracking, 2026-08-29), scoped to one
  /// language's own lessons — independent of every other language's time,
  /// same isolation as fetchOverallProgressPercent above.
  Future<int> fetchTotalTimeSeconds(String languageId) async {
    final res = await _api.get('/api/me/time/overall', query: {'languageId': languageId});
    return res['seconds'] as int;
  }

  /// Consecutive calendar days with a qualifying activity (§ streak mode,
  /// 2026-08-29) — deliberately global across every language the learner
  /// studies, not scoped to any one of them.
  Future<int> fetchStreakDays() async {
    final res = await _api.get('/api/me/streak');
    return res['days'] as int;
  }

  Future<WeekActivitySummary> fetchWeekActivity() async {
    final res = await _api.get('/api/me/activity/week');
    return WeekActivitySummary.fromJson(res);
  }
}

/// One calendar day's activity summary (§ streak mode, 2026-08-29).
class DayActivity {
  const DayActivity({required this.date, required this.active, required this.seconds});

  factory DayActivity.fromJson(Map<String, dynamic> json) =>
      DayActivity(date: json['date'] as String, active: json['active'] as bool, seconds: json['seconds'] as int);

  final String date;
  final bool active;
  final int seconds;
}

/// The current Monday-Sunday week's per-day activity plus the average and
/// today-vs-yesterday comparison the "Активность за неделю" card shows (§
/// streak mode, 2026-08-29) — global across every language, same reasoning
/// as fetchStreakDays above.
class WeekActivitySummary {
  const WeekActivitySummary({
    required this.days,
    required this.avgSecondsPerDay,
    required this.todaySeconds,
    required this.yesterdaySeconds,
    required this.percentChangeVsYesterday,
  });

  factory WeekActivitySummary.fromJson(Map<String, dynamic> json) => WeekActivitySummary(
        days: (json['days'] as List<dynamic>).map((d) => DayActivity.fromJson(d as Map<String, dynamic>)).toList(),
        avgSecondsPerDay: json['avgSecondsPerDay'] as int,
        todaySeconds: json['todaySeconds'] as int,
        yesterdaySeconds: json['yesterdaySeconds'] as int,
        // Null when yesterday had no time at all — a percentage change from
        // zero is undefined, not a real number to display.
        percentChangeVsYesterday: json['percentChangeVsYesterday'] as int?,
      );

  final List<DayActivity> days;
  final int avgSecondsPerDay;
  final int todaySeconds;
  final int yesterdaySeconds;
  final int? percentChangeVsYesterday;
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));

/// The learner's available languages plus which one is "in effect" right
/// now: the one they explicitly picked in Settings, or — when there's
/// exactly one language with any published content — that one language,
/// auto-selected (§3: "если есть только [один язык], пользователь видит
/// только [его], и он автоматически выбран"). Null only when nothing is
/// chosen AND there's more than one language to choose from.
class EffectiveLanguage {
  const EffectiveLanguage({required this.languages, required this.selectedId});
  final List<LanguageOption> languages;
  final String? selectedId;
}

/// Every language with a published course — the same list feeds the
/// Settings language picker, the profile-progress language, and (§ Home
/// lesson list, 2026-08-29) the independent "which language's lessons am I
/// browsing" switcher on the Главное screen. One fetch, three unrelated uses.
final availableLanguagesProvider = FutureProvider.autoDispose<List<LanguageOption>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchAvailableLanguages();
});

final effectiveLanguageProvider = FutureProvider.autoDispose<EffectiveLanguage>((ref) async {
  final user = ref.watch(authProvider).value;
  final languages = await ref.watch(availableLanguagesProvider.future);
  final selectedId = user?.selectedLanguageId ?? (languages.length == 1 ? languages.single.id : null);
  return EffectiveLanguage(languages: languages, selectedId: selectedId);
});

/// The single number the profile's "Прогресс" tile shows — null when no
/// language is in effect yet (more than one language exists and the user
/// hasn't picked one), which the UI renders the same way it already does
/// for "no data yet" (a dash, not 0%).
final overallProgressProvider = FutureProvider.autoDispose<int?>((ref) async {
  final effective = await ref.watch(effectiveLanguageProvider.future);
  final languageId = effective.selectedId;
  if (languageId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchOverallProgressPercent(languageId);
});

/// The single number the profile's "Время" tile shows (§ time tracking,
/// 2026-08-29) — same selected-language source as overallProgressProvider,
/// deliberately NOT the Главное screen's own independent language switcher
/// (see homeLanguageIdProvider's doc comment for why those two must never
/// affect each other).
final totalTimeSecondsProvider = FutureProvider.autoDispose<int?>((ref) async {
  final effective = await ref.watch(effectiveLanguageProvider.future);
  final languageId = effective.selectedId;
  if (languageId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchTotalTimeSeconds(languageId);
});

/// The profile's "Серия" tile (§ streak mode, 2026-08-29) — global, so
/// switching the Главное screen's language or the profile's progress
/// language never changes it.
final streakDaysProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(profileRepositoryProvider).fetchStreakDays();
});

/// The "Активность за неделю" card's data (§ streak mode, 2026-08-29).
final weekActivityProvider = FutureProvider.autoDispose<WeekActivitySummary>((ref) {
  return ref.watch(profileRepositoryProvider).fetchWeekActivity();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_store.dart';
import '../../../core/cache/cached_json.dart';
import '../../lesson_runner/data/lesson_repository.dart';
import '../../lesson_runner/domain/progress.dart';
import '../../lesson_runner/domain/stage.dart';
import '../../profile/data/profile_repository.dart';
import '../data/courses_repository.dart';

Map<String, LessonProgress> _progressFromRaw(Map<String, dynamic> raw) {
  final states = (raw['states'] as List<dynamic>).cast<Map<String, dynamic>>();
  return {for (final s in states) s['lessonId'] as String: LessonProgress.fromJson(s)};
}

/// One lesson-grid card, legacy or builder — carries just enough of
/// LessonProgress (via the shared Stage helpers) to render the same
/// progress bar / "Продолжить" vs "Начать урок" vs "✓ Урок завершён" states
/// Home.tsx/CourseLessonsPage.tsx compute from useProgressStore().
class LessonCard {
  const LessonCard({required this.lessonId, required this.title, required this.vocabularyCount, required this.progress});

  final String lessonId;
  final String title;
  final int vocabularyCount;
  final LessonProgress? progress;

  double get ratio => courseProgressRatio(progress?.completedStages);
  bool get completed => progress?.completedStages.contains(Stage.complete) ?? false;
  Stage get targetStage => progress != null ? nextIncompleteStage(progress!.completedStages) : Stage.vocabulary;
}

class CoursesOverviewData {
  const CoursesOverviewData({required this.legacyLessons, required this.builderCourses});
  final List<LessonCard> legacyLessons;
  final List<BuilderCourseSummary> builderCourses;
}

CoursesOverviewData _overviewFromRaw(Map<String, dynamic> raw) {
  final legacyLessons =
      (raw['legacyLessons'] as List<dynamic>).cast<Map<String, dynamic>>().map((l) => LegacyLessonSummary.fromJson(l)).toList();
  final progressByLesson = _progressFromRaw({'states': raw['progressStates']});
  final builderCourses =
      (raw['builderCourses'] as List<dynamic>).cast<Map<String, dynamic>>().map((c) => BuilderCourseSummary.fromJson(c)).toList();

  final legacyCards = [
    for (final l in legacyLessons)
      LessonCard(lessonId: l.lessonId, title: l.title, vocabularyCount: l.vocabularyCount, progress: progressByLesson[l.lessonId]),
  ];
  return CoursesOverviewData(legacyLessons: legacyCards, builderCourses: builderCourses);
}

/// Combines what the old app split across two routes (Home.tsx's legacy
/// lesson grid + CoursesPage.tsx's course hub) into the one screen Flutter's
/// "Курсы" nav card leads to — HomeScreen here is a native app menu, not a
/// lesson grid, so this screen is where that grid actually lives.
///
/// Cached (caching plan, 2026-08-29): the last-known overview shows
/// instantly, then a background check silently swaps in fresh data only if
/// something actually changed — no more full loading screen on every
/// re-open. Progress/answers themselves are never served stale from here;
/// this only defers the DISPLAY, and a background refresh always follows.
final coursesOverviewProvider = StreamProvider.autoDispose<CoursesOverviewData>((ref) async* {
  final profileRepo = ref.watch(profileRepositoryProvider);
  final lessonRepo = ref.watch(lessonRepositoryProvider);
  final coursesRepo = ref.watch(coursesRepositoryProvider);

  await for (final raw in cachedJsonStream(
    key: 'courses_overview',
    fetchFresh: () async => {
      'legacyLessons': await profileRepo.fetchLegacyLessonsRaw(),
      'progressStates': await lessonRepo.fetchAllProgressRaw(),
      'builderCourses': (await coursesRepo.fetchPublishedCoursesRaw())['courses'],
    },
  )) {
    yield _overviewFromRaw(raw);
  }
});

class CourseLessonsData {
  const CourseLessonsData({required this.title, required this.description, required this.lessons});
  final String title;
  final String? description;
  final List<LessonCard> lessons;
}

CourseLessonsData _courseLessonsFromRaw(Map<String, dynamic> courseRaw, Map<String, LessonProgress> progressByLesson) {
  final course = BuilderCourseDetail.fromJson(courseRaw);
  final cards = [
    for (final l in course.lessons)
      LessonCard(lessonId: l.id, title: l.title, vocabularyCount: l.vocabularyCount, progress: progressByLesson[l.id]),
  ];
  return CourseLessonsData(title: course.title, description: course.description, lessons: cards);
}

/// Cached (caching plan, 2026-08-29) like coursesOverviewProvider above, but
/// with the version check Stage 2 adds for single-course fetches: a cheap
/// GET .../version call confirms whether the (potentially large) course
/// payload needs re-downloading at all. Progress is deliberately fetched
/// fresh every time regardless of the course version — it changes far more
/// often than course content and is answer-adjacent data, never served
/// stale-on-purpose the way content is.
final courseLessonsProvider = StreamProvider.autoDispose.family<CourseLessonsData, String>((ref, courseId) async* {
  final coursesRepo = ref.watch(coursesRepositoryProvider);
  final lessonRepo = ref.watch(lessonRepositoryProvider);
  final cacheKey = 'course_$courseId';

  final cached = await CacheStore.instance.read(cacheKey);
  final cachedData = cached?['data'] as Map<String, dynamic>?;
  final cachedVersion = cached?['version'] as String?;

  if (cachedData != null) {
    yield _courseLessonsFromRaw(cachedData, await lessonRepo.fetchAllProgress());
  }

  String? freshVersion;
  try {
    freshVersion = await coursesRepo.fetchCourseVersion(courseId);
  } catch (_) {
    // Couldn't check — fall through and fetch the full course to be safe.
  }
  final versionConfirmedUnchanged = cachedData != null && freshVersion != null && freshVersion == cachedVersion;
  if (versionConfirmedUnchanged) return;

  final freshRaw = await coursesRepo.fetchCourseRaw(courseId);
  await CacheStore.instance.write(cacheKey, {'data': freshRaw, 'version': freshVersion});
  if (cachedData == null || !jsonValuesEqual(freshRaw, cachedData)) {
    yield _courseLessonsFromRaw(freshRaw, await lessonRepo.fetchAllProgress());
  }
});

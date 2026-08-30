import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_json.dart';
import '../../lesson_runner/data/lesson_repository.dart';
import '../../lesson_runner/domain/progress.dart';
import '../../lesson_runner/domain/stage.dart';
import '../../profile/data/profile_repository.dart';
import '../data/courses_repository.dart';

/// One lesson-grid card, legacy or builder — carries just enough of
/// LessonProgress (via the shared Stage helpers) to render the same
/// progress bar / "Продолжить" vs "Начать урок" vs "✓ Урок завершён" states
/// Home.tsx/CourseLessonsPage.tsx compute from useProgressStore().
///
/// `courseId` is null for a legacy (file-based) lesson and the owning
/// Course's id for a builder lesson — the only thing the flat Главное list
/// (§ Home lesson list, 2026-08-29) needs to build the right lesson-runner
/// route on tap, since both kinds are now shown side by side in one list.
class LessonCard {
  const LessonCard({required this.lessonId, required this.title, required this.vocabularyCount, required this.progress, this.courseId});

  final String lessonId;
  final String? courseId;
  final String title;
  final int vocabularyCount;
  final LessonProgress? progress;

  double get ratio => courseProgressRatio(progress?.completedStages);
  bool get completed => progress?.completedStages.contains(Stage.complete) ?? false;
  Stage get targetStage => progress != null ? nextIncompleteStage(progress!.completedStages) : Stage.vocabulary;
}

/// Everything homeLessonsProvider needs about one language's content, minus
/// progress (which is always fetched fresh — see the provider below) —
/// exactly the shape cachedJsonStream stores/diffs.
Map<String, dynamic> _buildHomeContentRaw(List<Map<String, dynamic>> legacy, List<Map<String, dynamic>> courseDetails) =>
    {'legacy': legacy, 'courseDetails': courseDetails};

List<LessonCard> _cardsFromHomeContentRaw(Map<String, dynamic> raw, Map<String, LessonProgress> progressByLesson) {
  final cards = <LessonCard>[];
  for (final l in (raw['legacy'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    cards.add(LessonCard(
      lessonId: l['lessonId'] as String,
      title: l['title'] as String,
      vocabularyCount: l['vocabularyCount'] as int,
      progress: progressByLesson[l['lessonId']],
    ));
  }
  for (final course in (raw['courseDetails'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final courseId = course['id'] as String;
    for (final l in (course['lessons'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      cards.add(LessonCard(
        lessonId: l['id'] as String,
        courseId: courseId,
        title: l['title'] as String,
        vocabularyCount: (l['vocabulary'] as List<dynamic>? ?? const []).length,
        progress: progressByLesson[l['id']],
      ));
    }
  }
  return cards;
}

/// The flat lesson list for one language on the Главное screen — every
/// published course under that language's levels, flattened (levels
/// themselves are deliberately not shown, per the approved Home redesign),
/// plus the legacy file-based lessons when the language is German (see the
/// screen's own doc comment for why: those lessons predate Language/Level
/// and have no Course row to link through).
///
/// Cached (caching plan, 2026-08-29 — extended to Главное): the lesson
/// list itself (titles, word counts, which course) shows instantly from
/// disk and updates silently in the background. Progress is deliberately
/// NOT part of the cached blob — it's re-fetched fresh every time, same
/// "content cached, progress live" rule the old courseLessonsProvider used.
final homeLessonsProvider = StreamProvider.autoDispose.family<List<LessonCard>, ({String id, String name})>((ref, language) async* {
  final coursesRepo = ref.watch(coursesRepositoryProvider);
  final lessonRepo = ref.watch(lessonRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final isGerman = language.name.trim().toLowerCase() == 'немецкий';

  await for (final raw in cachedJsonStream(
    key: 'home_lessons_${language.id}',
    fetchFresh: () async {
      final legacy = isGerman ? await profileRepo.fetchLegacyLessonsRaw() : <Map<String, dynamic>>[];
      final courseIds = ((await coursesRepo.fetchPublishedCoursesRaw(languageId: language.id))['courses'] as List<dynamic>)
          .map((c) => (c as Map<String, dynamic>)['id'] as String);
      final courseDetails = [for (final id in courseIds) await coursesRepo.fetchCourseRaw(id)];
      return _buildHomeContentRaw(legacy, courseDetails);
    },
  )) {
    final progressByLesson = await lessonRepo.fetchAllProgress();
    yield _cardsFromHomeContentRaw(raw, progressByLesson);
  }
});

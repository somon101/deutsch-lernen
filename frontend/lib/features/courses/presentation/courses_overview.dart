import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The flat lesson list for one language on the Главное screen — every
/// published course under that language's levels, flattened (levels
/// themselves are deliberately not shown, per the approved Home redesign),
/// plus the legacy file-based lessons when the language is German (see the
/// screen's own doc comment for why: those lessons predate Language/Level
/// and have no Course row to link through).
///
/// Deliberately a plain (uncached) fetch, unlike courseLessonsProvider used
/// to be — this combines multiple sources at once, and nothing in this task
/// calls for stale-while-revalidate here.
final homeLessonsProvider = FutureProvider.autoDispose.family<List<LessonCard>, ({String id, String name})>((ref, language) async {
  final coursesRepo = ref.watch(coursesRepositoryProvider);
  final lessonRepo = ref.watch(lessonRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);

  final progressByLesson = await lessonRepo.fetchAllProgress();
  final cards = <LessonCard>[];

  if (language.name.trim().toLowerCase() == 'немецкий') {
    final legacy = await profileRepo.fetchLegacyLessons();
    cards.addAll([
      for (final l in legacy)
        LessonCard(lessonId: l.lessonId, title: l.title, vocabularyCount: l.vocabularyCount, progress: progressByLesson[l.lessonId]),
    ]);
  }

  final courses = await coursesRepo.fetchPublishedCourses(languageId: language.id);
  for (final course in courses) {
    final detail = await coursesRepo.fetchCourse(course.id);
    cards.addAll([
      for (final l in detail.lessons)
        LessonCard(lessonId: l.id, courseId: course.id, title: l.title, vocabularyCount: l.vocabularyCount, progress: progressByLesson[l.id]),
    ]);
  }
  return cards;
});

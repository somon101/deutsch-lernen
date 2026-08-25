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

/// Combines what the old app split across two routes (Home.tsx's legacy
/// lesson grid + CoursesPage.tsx's course hub) into the one screen Flutter's
/// "Курсы" nav card leads to — HomeScreen here is a native app menu, not a
/// lesson grid, so this screen is where that grid actually lives.
final coursesOverviewProvider = FutureProvider.autoDispose<CoursesOverviewData>((ref) async {
  final legacyLessons = await ref.watch(profileRepositoryProvider).fetchLegacyLessons();
  final progressByLesson = await ref.watch(lessonRepositoryProvider).fetchAllProgress();
  final builderCourses = await ref.watch(coursesRepositoryProvider).fetchPublishedCourses();

  final legacyCards = [
    for (final l in legacyLessons)
      LessonCard(lessonId: l.lessonId, title: l.title, vocabularyCount: l.vocabularyCount, progress: progressByLesson[l.lessonId]),
  ];

  return CoursesOverviewData(legacyLessons: legacyCards, builderCourses: builderCourses);
});

class CourseLessonsData {
  const CourseLessonsData({required this.title, required this.description, required this.lessons});
  final String title;
  final String? description;
  final List<LessonCard> lessons;
}

final courseLessonsProvider = FutureProvider.autoDispose.family<CourseLessonsData, String>((ref, courseId) async {
  final course = await ref.watch(coursesRepositoryProvider).fetchCourse(courseId);
  final progressByLesson = await ref.watch(lessonRepositoryProvider).fetchAllProgress();

  final cards = [
    for (final l in course.lessons)
      LessonCard(lessonId: l.id, title: l.title, vocabularyCount: l.vocabularyCount, progress: progressByLesson[l.id]),
  ];

  return CourseLessonsData(title: course.title, description: course.description, lessons: cards);
});

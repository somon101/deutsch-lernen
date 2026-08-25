import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../domain/lesson_content.dart';
import '../domain/progress.dart';

/// Fetches lesson content (legacy or builder-course, same resulting shape)
/// and syncs progress — mirrors content/loader.ts + progress/ProgressContext.tsx's
/// combined responsibilities, minus the client-side file parsing (the
/// backend now does that once and serves structured JSON — see the
/// migration plan's Phase 5 notes).
class LessonRepository {
  LessonRepository(this._api);

  final ApiClient _api;

  Future<LessonContentData> fetchLegacyContent(String lessonId) async {
    final res = await _api.get('/api/content/${Uri.encodeComponent(lessonId)}');
    return LessonContentData.fromLegacyJson(lessonId, res['content'] as Map<String, dynamic>);
  }

  /// Builder courses are fetched whole (same endpoint the course-lessons
  /// list screen uses) and the one lesson picked out — mirrors
  /// content/learnerCourses.ts + builderExercises.ts's toLessonContent().
  Future<LessonContentData> fetchBuilderLessonContent(String courseId, String lessonId) async {
    final res = await _api.get('/api/courses/${Uri.encodeComponent(courseId)}');
    final course = res['course'] as Map<String, dynamic>;
    final lessons = (course['lessons'] as List<dynamic>).cast<Map<String, dynamic>>();
    final lesson = lessons.firstWhere((l) => l['id'] == lessonId, orElse: () => throw ApiException(404, 'Урок не найден'));
    return LessonContentData.fromBuilderJson(lesson);
  }

  /// All of the signed-in user's lesson states — mirrors
  /// ProgressContext.tsx's "hydrate the whole store on login" behavior; the
  /// caller picks out the one lesson it needs (or gets nothing back for a
  /// lesson never started, exactly like the React version).
  Future<Map<String, LessonProgress>> fetchAllProgress() async {
    final res = await _api.get('/api/me/lesson-state');
    final states = (res['states'] as List<dynamic>).cast<Map<String, dynamic>>();
    return {for (final s in states) s['lessonId'] as String: LessonProgress.fromJson(s)};
  }

  Future<LessonProgress> saveProgress(LessonProgress progress) async {
    final res = await _api.put('/api/me/lesson-state/${Uri.encodeComponent(progress.lessonId)}', body: progress.toJson());
    return LessonProgress.fromJson(res['state'] as Map<String, dynamic>);
  }

  /// Records one full completed pass (mini-test+practice+review score
  /// triple) — mirrors attemptSync.ts, called only once all three results
  /// exist (see the lesson runner shell's recordQuizResult equivalent).
  Future<void> recordAttempt(
    String lessonId, {
    required int miniTestCorrect,
    required int miniTestTotal,
    required int practiceCorrect,
    required int practiceTotal,
    required int reviewCorrect,
    required int reviewTotal,
  }) async {
    await _api.post(
      '/api/me/progress/${Uri.encodeComponent(lessonId)}/attempts',
      body: {
        'miniTestCorrect': miniTestCorrect,
        'miniTestTotal': miniTestTotal,
        'practiceCorrect': practiceCorrect,
        'practiceTotal': practiceTotal,
        'reviewCorrect': reviewCorrect,
        'reviewTotal': reviewTotal,
      },
    );
  }
}

final lessonRepositoryProvider = Provider<LessonRepository>((ref) => LessonRepository(ref.watch(apiClientProvider)));

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../domain/exercise.dart';
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
    final json = await fetchLegacyContentRaw(lessonId);
    return LessonContentData.fromLegacyJson(lessonId, json);
  }

  /// Builder courses are fetched whole (same endpoint the course-lessons
  /// list screen uses) and the one lesson picked out — mirrors
  /// content/learnerCourses.ts + builderExercises.ts's toLessonContent().
  Future<LessonContentData> fetchBuilderLessonContent(String courseId, String lessonId) async {
    final json = await fetchBuilderLessonContentRaw(courseId, lessonId);
    return LessonContentData.fromBuilderJson(json);
  }

  /// Raw-JSON variants for the caching layer (see cached_json.dart) — same
  /// data as the parsed methods above, just not run through
  /// LessonContentData.fromXJson yet, so the cache can store/compare plain
  /// JSON without the domain model needing a toJson.
  Future<Map<String, dynamic>> fetchLegacyContentRaw(String lessonId) async {
    final res = await _api.get('/api/content/${Uri.encodeComponent(lessonId)}');
    return res['content'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchBuilderLessonContentRaw(String courseId, String lessonId) async {
    final res = await _api.get('/api/courses/${Uri.encodeComponent(courseId)}');
    final course = res['course'] as Map<String, dynamic>;
    final lessons = (course['lessons'] as List<dynamic>).cast<Map<String, dynamic>>();
    return lessons.firstWhere((l) => l['id'] == lessonId, orElse: () => throw ApiException(404, 'Урок не найден'));
  }

  /// All of the signed-in user's lesson states — mirrors
  /// ProgressContext.tsx's "hydrate the whole store on login" behavior; the
  /// caller picks out the one lesson it needs (or gets nothing back for a
  /// lesson never started, exactly like the React version).
  Future<Map<String, LessonProgress>> fetchAllProgress() async {
    final states = await fetchAllProgressRaw();
    return {for (final s in states) s['lessonId'] as String: LessonProgress.fromJson(s)};
  }

  /// Raw-JSON variant for the caching layer — see fetchAllProgress.
  Future<List<Map<String, dynamic>>> fetchAllProgressRaw() async {
    final res = await _api.get('/api/me/lesson-state');
    return (res['states'] as List<dynamic>).cast<Map<String, dynamic>>();
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

  /// Real per-question answer log (content-taxonomy plan, 2026-08-26) —
  /// `questionId` is a loose reference: either a reusable pool Question's id
  /// (material-block checkpoint questions) or a quiz LessonQuestion's id
  /// (minitest/practice/review) — both are accepted server-side. Fire-and
  /// -forget from the caller's point of view: a failure here must never
  /// block the learner's flow, so this can be awaited without surfacing
  /// errors to the UI beyond a caught exception.
  Future<void> submitAnswer(String questionId, bool correct, {String? placementId}) async {
    await _api.post(
      '/api/me/answers',
      body: {'questionId': questionId, 'placementId': ?placementId, 'answerData': {'correct': correct}, 'correct': correct},
    );
  }

  /// Generates one version of an auto_blank phrase slot (§ auto blank,
  /// 2026-08-31) — fresh and random every call, nothing is written to the
  /// database by this (generating a question is not answering it). Null
  /// means the server couldn't safely generate one for this slot right now
  /// (e.g. not enough learned vocabulary yet) — the caller must not show a
  /// broken exercise in that case.
  Future<GeneratedBlankQuestion?> generateBlankQuestion(String questionId, int phraseIndex) async {
    try {
      final res = await _api.get('/api/questions/${Uri.encodeComponent(questionId)}/blank/$phraseIndex');
      return GeneratedBlankQuestion.fromJson(res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// The server re-derives correctness from `generatedQuestionId` itself
  /// (§25) — this never sends a client-computed `correct` boolean, unlike
  /// submitAnswer above. `correctText` only comes back now, post-answer —
  /// the generate response never states which option was correct.
  Future<({bool correct, String correctText})> submitBlankAnswer(
    String questionId, {
    required String generatedQuestionId,
    required String selectedText,
    String? placementId,
  }) async {
    final res = await _api.post(
      '/api/questions/${Uri.encodeComponent(questionId)}/blank/answer',
      body: {'generatedQuestionId': generatedQuestionId, 'selectedText': selectedText, 'placementId': ?placementId},
    );
    return (correct: res['correct'] as bool, correctText: res['correctText'] as String);
  }

  /// Reports one already-capped time delta for one activity type within one
  /// lesson (§ time tracking, 2026-08-29) — fire-and-forget from the
  /// caller's point of view, same contract as submitAnswer above.
  Future<void> submitActivityTime({
    required String? courseId,
    required String lessonId,
    required String activityType,
    required int seconds,
  }) async {
    await _api.post(
      '/api/me/activity-time',
      body: {'courseId': ?courseId, 'lessonId': lessonId, 'activityType': activityType, 'seconds': seconds},
    );
  }

  /// Marks today as a streak day (§ streak mode, 2026-08-29) — idempotent
  /// server-side, so calling this more than once for the same day (e.g.
  /// completing a second lesson) is harmless.
  Future<void> recordDailyActivity(String activityType) async {
    await _api.post('/api/me/activity', body: {'activityType': activityType});
  }
}

final lessonRepositoryProvider = Provider<LessonRepository>((ref) => LessonRepository(ref.watch(apiClientProvider)));

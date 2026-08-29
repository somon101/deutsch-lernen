import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_store.dart';
import '../../../core/cache/cached_json.dart';
import '../../courses/data/courses_repository.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson_content.dart';
import '../domain/progress.dart';
import '../domain/stage.dart';

typedef LessonRunnerKey = ({String? courseId, String lessonId});

class LessonRunnerData {
  const LessonRunnerData({required this.content, required this.progress});
  final LessonContentData content;
  final LessonProgress progress;
}

/// Mirrors ProgressContext.tsx's per-lesson slice: loads content + the
/// user's saved progress once, then every mutation (stage complete, vocab
/// index, quiz result) persists via PUT /api/me/lesson-state/:id and
/// updates local state from the server's own response — same
/// server-authoritative contract as the React version (no localStorage
/// fallback).
class LessonRunnerController extends FamilyAsyncNotifier<LessonRunnerData, LessonRunnerKey> {
  late LessonRunnerKey _key;

  String _cacheKeyFor(LessonRunnerKey key) => key.courseId != null ? 'lesson_content_${key.courseId}_${key.lessonId}' : 'lesson_content_legacy_${key.lessonId}';

  Future<Map<String, dynamic>> _fetchRawContent(LessonRunnerKey key) => key.courseId != null
      ? ref.read(lessonRepositoryProvider).fetchBuilderLessonContentRaw(key.courseId!, key.lessonId)
      : ref.read(lessonRepositoryProvider).fetchLegacyContentRaw(key.lessonId);

  LessonContentData _parseRawContent(LessonRunnerKey key, Map<String, dynamic> raw) =>
      key.courseId != null ? LessonContentData.fromBuilderJson(raw) : LessonContentData.fromLegacyJson(key.lessonId, raw);

  /// A course's cache-busting version (CoursesRepository.fetchCourseVersion)
  /// also covers every lesson inside it — reused here so opening a lesson
  /// skips re-downloading its content when the course hasn't changed.
  /// Legacy lessons have no such endpoint (no owning course), so they fall
  /// back to Stage 1 only: always refetch in the background, diff, and swap
  /// only if different.
  Future<String?> _fetchVersion(LessonRunnerKey key) async {
    if (key.courseId == null) return null;
    try {
      return await ref.read(coursesRepositoryProvider).fetchCourseVersion(key.courseId!);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LessonRunnerData> build(LessonRunnerKey key) async {
    _key = key;
    final repo = ref.read(lessonRepositoryProvider);
    final cacheKey = _cacheKeyFor(key);
    final cached = await CacheStore.instance.read(cacheKey);
    final cachedRaw = cached?['data'] as Map<String, dynamic>?;

    if (cachedRaw != null) {
      // Instant path: show what's on disk right away, and kick a
      // background check that silently swaps `state` in later only if the
      // server's version actually differs — never awaited here, so build()
      // returns immediately with the cached content.
      final content = _parseRawContent(key, cachedRaw);
      final allProgress = await repo.fetchAllProgress();
      final progress = allProgress[key.lessonId] ?? LessonProgress.empty(key.lessonId);
      unawaited(_refreshContentInBackground(key, cacheKey, cachedRaw, cached?['version'] as String?));
      return LessonRunnerData(content: content, progress: progress);
    }

    // Nothing cached yet — first-ever open of this lesson still has to wait
    // for the network, exactly like before this caching layer existed.
    final rawContent = await _fetchRawContent(key);
    final version = await _fetchVersion(key);
    await CacheStore.instance.write(cacheKey, {'data': rawContent, 'version': version});
    final content = _parseRawContent(key, rawContent);
    final allProgress = await repo.fetchAllProgress();
    final progress = allProgress[key.lessonId] ?? LessonProgress.empty(key.lessonId);
    return LessonRunnerData(content: content, progress: progress);
  }

  Future<void> _refreshContentInBackground(LessonRunnerKey key, String cacheKey, Map<String, dynamic> cachedRaw, String? cachedVersion) async {
    try {
      final freshVersion = await _fetchVersion(key);
      if (freshVersion != null && freshVersion == cachedVersion) return; // confirmed unchanged

      final freshRaw = await _fetchRawContent(key);
      await CacheStore.instance.write(cacheKey, {'data': freshRaw, 'version': freshVersion});
      if (jsonValuesEqual(freshRaw, cachedRaw)) return;

      final current = state.value;
      if (current == null) return; // notifier was disposed/reset meanwhile
      state = AsyncData(LessonRunnerData(content: _parseRawContent(key, freshRaw), progress: current.progress));
    } catch (_) {
      // A failed background refresh keeps showing the cached content —
      // never surfaces as an error once something is already on screen.
    }
  }

  Future<void> _persist(LessonProgress updated) async {
    final current = state.value;
    if (current == null) return;
    final saved = await ref.read(lessonRepositoryProvider).saveProgress(updated);
    state = AsyncData(LessonRunnerData(content: current.content, progress: saved));
  }

  Future<void> markStageComplete(Stage stage) async {
    final current = state.value;
    if (current == null) return;
    if (current.progress.completedStages.contains(stage)) return;
    await _persist(current.progress.copyWith(completedStages: {...current.progress.completedStages, stage}));
  }

  Future<void> setVocabIndex(int index) async {
    final current = state.value;
    if (current == null) return;
    await _persist(current.progress.copyWith(vocabIndex: index));
  }

  /// Mirrors recordQuizResult in ProgressContext.tsx: saves the one stage
  /// result, and — only once all three exist — also logs a full attempt
  /// (see attemptSync.ts) for the profile's progress-history and the
  /// "best/last score" summary.
  Future<void> recordQuizResult(Stage stage, QuizResult result) async {
    final current = state.value;
    if (current == null) return;

    LessonProgress updated;
    switch (stage) {
      case Stage.minitest:
        updated = current.progress.copyWith(miniTestResult: result);
      case Stage.practice:
        updated = current.progress.copyWith(practiceResult: result);
      case Stage.review:
        updated = current.progress.copyWith(reviewResult: result);
      default:
        return;
    }

    await _persist(updated);

    if (stage == Stage.review) {
      final p = state.value?.progress;
      if (p?.miniTestResult != null && p?.practiceResult != null && p?.reviewResult != null) {
        await ref.read(lessonRepositoryProvider).recordAttempt(
              current.content.lessonId,
              miniTestCorrect: p!.miniTestResult!.correct,
              miniTestTotal: p.miniTestResult!.total,
              practiceCorrect: p.practiceResult!.correct,
              practiceTotal: p.practiceResult!.total,
              reviewCorrect: p.reviewResult!.correct,
              reviewTotal: p.reviewResult!.total,
            );
      }
    }
  }

  Future<void> completeLesson() async {
    final current = state.value;
    if (current == null) return;
    if (current.progress.completedStages.contains(Stage.complete)) return;
    await _persist(
      current.progress.copyWith(
        completedStages: {...current.progress.completedStages, Stage.complete},
        completedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    // A full completion — not just opening the lesson — is what counts as a
    // streak day (§ streak mode, 2026-08-29). Best-effort: a failed report
    // must never surface as an error on the lesson's results screen.
    try {
      await ref.read(lessonRepositoryProvider).recordDailyActivity('lesson_completed');
    } catch (_) {}
  }

  /// Reports one already-capped time delta for one activity type (§ time
  /// tracking, 2026-08-29) — best-effort, same "must never interrupt the
  /// lesson" contract as submitAnswer's own caller has.
  Future<void> recordActivityTime(String activityType, int seconds) async {
    if (seconds <= 0) return;
    try {
      await ref.read(lessonRepositoryProvider).submitActivityTime(
            courseId: _key.courseId,
            lessonId: _key.lessonId,
            activityType: activityType,
            seconds: seconds,
          );
    } catch (_) {
      // Losing one time report is harmless — the total just undercounts
      // slightly, same tolerance the rest of this file already has.
    }
  }

  /// Full reset for "Пройти ещё раз" — clears every stage back to
  /// not-started (fresh `startedAt`, no quiz results), so the learner walks
  /// through the whole lesson again from vocabulary. Old AnswerLog rows are
  /// untouched (attemptNumber keeps counting up), only THIS lesson's
  /// stage-completion state is reset.
  Future<void> restartLesson() async {
    final current = state.value;
    if (current == null) return;
    await _persist(LessonProgress.empty(current.content.lessonId));
  }
}

final lessonRunnerControllerProvider =
    AsyncNotifierProviderFamily<LessonRunnerController, LessonRunnerData, LessonRunnerKey>(LessonRunnerController.new);

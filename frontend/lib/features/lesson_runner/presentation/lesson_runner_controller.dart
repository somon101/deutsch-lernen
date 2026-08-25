import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  Future<LessonRunnerData> build(LessonRunnerKey key) async {
    final repo = ref.read(lessonRepositoryProvider);
    final content = key.courseId != null
        ? await repo.fetchBuilderLessonContent(key.courseId!, key.lessonId)
        : await repo.fetchLegacyContent(key.lessonId);
    final allProgress = await repo.fetchAllProgress();
    final progress = allProgress[key.lessonId] ?? LessonProgress.empty(key.lessonId);
    return LessonRunnerData(content: content, progress: progress);
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
  }
}

final lessonRunnerControllerProvider =
    AsyncNotifierProviderFamily<LessonRunnerController, LessonRunnerData, LessonRunnerKey>(LessonRunnerController.new);

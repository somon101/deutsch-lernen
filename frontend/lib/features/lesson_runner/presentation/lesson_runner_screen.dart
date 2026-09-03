import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/back_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/stage.dart';
import 'graph_lesson_runner_screen.dart';
import 'lesson_runner_controller.dart';
import 'stages/audio_stage.dart';
import 'stages/complete_stage.dart';
import 'stages/exercise_stage.dart';
import 'stages/material_stage.dart';
import 'stages/video_stage.dart';
import 'stages/vocabulary_stage.dart';

/// Entry point every lesson route builds (§ lesson graph, 2026-09-03) —
/// loads the lesson's content once and dispatches on `content.graph`: a
/// converted lesson goes to [GraphLessonRunnerScreen], everything else (the
/// overwhelming majority today) goes to the exact same [LessonRunnerScreen]
/// as before, byte-for-byte unchanged. `stage` is either one of the 8 fixed
/// stage names (legacy) or a LessonNode id (graph) — each screen validates
/// it against its own model and redirects if it's neither.
class LessonRunnerEntryScreen extends ConsumerWidget {
  const LessonRunnerEntryScreen({super.key, required this.lessonId, required this.stage, this.courseId});

  final String lessonId;
  final String stage;
  final String? courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (courseId: courseId, lessonId: lessonId);
    final async = ref.watch(lessonRunnerControllerProvider(key));
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, st) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).lessonTitle)),
        body: Center(child: Text(AppLocalizations.of(context).lessonLoadError(err))),
      ),
      data: (data) => data.content.graph != null
          ? GraphLessonRunnerScreen(courseId: courseId, lessonId: lessonId, nodeId: stage)
          : LessonRunnerScreen(courseId: courseId, lessonId: lessonId, stage: stage),
    );
  }
}

/// Mirrors LessonPage.tsx/BuilderLessonPage.tsx: validates the :stage URL
/// param, redirects to the correct incomplete stage if it's invalid or
/// locked, and renders the matching stage widget inside a shared shell
/// (top progress rail + stage content). Reached only for a lesson still on
/// the old fixed chain — see [LessonRunnerEntryScreen].
class LessonRunnerScreen extends ConsumerWidget {
  const LessonRunnerScreen({super.key, required this.lessonId, required this.stage, this.courseId});

  final String lessonId;
  final String stage;
  final String? courseId;

  String _basePath() => courseId != null ? '/courses/$courseId/lesson/$lessonId' : '/lesson/$lessonId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (courseId: courseId, lessonId: lessonId);
    final async = ref.watch(lessonRunnerControllerProvider(key));

    return BackGuard(
      fallbackPath: '/',
      child: async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, st) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).lessonTitle)),
        body: Center(child: Text(AppLocalizations.of(context).lessonLoadError(err))),
      ),
      data: (data) {
        final requestedStage = stageFromId(stage);
        final completed = data.progress.completedStages;

        // Invalid stage id, or the requested stage isn't unlocked yet —
        // bounce to the correct one, same as the React version.
        if (requestedStage == null || !isStageUnlocked(completed, requestedStage)) {
          final target = nextIncompleteStage(completed);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('${_basePath()}/${target.name}');
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(data.content.title),
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.go('/')),
          ),
          body: Column(
            children: [
              _StageRail(currentStage: requestedStage, completed: completed),
              const Divider(height: 1),
              Expanded(child: _StageBody(courseId: courseId, lessonId: lessonId, stage: requestedStage)),
            ],
          ),
        );
      },
      ),
    );
  }
}

class _StageRail extends StatelessWidget {
  const _StageRail({required this.currentStage, required this.completed});

  final Stage currentStage;
  final Set<Stage> completed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final s in stageOrder)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Chip(
                avatar: Icon(
                  completed.contains(s)
                      ? Icons.check_circle
                      : s == currentStage
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  size: 18,
                  color: completed.contains(s) ? Colors.green : null,
                ),
                label: Text(stageLabel(s, l10n)),
                backgroundColor: s == currentStage ? Theme.of(context).colorScheme.primaryContainer : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _StageBody extends ConsumerWidget {
  const _StageBody({required this.courseId, required this.lessonId, required this.stage});

  final String? courseId;
  final String lessonId;
  final Stage stage;

  void _advance(BuildContext context) {
    final next = stageOrder[stageOrder.indexOf(stage) + 1];
    final base = courseId != null ? '/courses/$courseId/lesson/$lessonId' : '/lesson/$lessonId';
    context.go('$base/${next.name}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (courseId: courseId, lessonId: lessonId);
    final controller = ref.read(lessonRunnerControllerProvider(key).notifier);

    Future<void> completeAndAdvance() async {
      await controller.markStageComplete(stage);
      if (context.mounted) _advance(context);
    }

    switch (stage) {
      case Stage.vocabulary:
        return VocabularyStage(runnerKey: key, onComplete: completeAndAdvance);
      case Stage.material:
        return MaterialStage(runnerKey: key, onComplete: completeAndAdvance);
      case Stage.video:
        return VideoStage(runnerKey: key, onComplete: completeAndAdvance);
      case Stage.audio:
        return AudioStage(runnerKey: key, onComplete: completeAndAdvance);
      case Stage.minitest:
      case Stage.practice:
      case Stage.review:
        // The key is load-bearing, not decoration (§ review stage reused
        // practice's state, 2026-09-02). All three of these stages are the
        // same widget type behind the same route, `/lesson/:lessonId/:stage`,
        // and go_router builds a page key from the route PATTERN rather than
        // the filled-in location — so practice and review produced identical
        // page keys, Flutter matched the Elements, and the State object (with
        // its `late final` exercise list and its `_finished` flag) survived
        // the move. Review then opened already-finished, showing practice's
        // questions, and recorded practice's score as its own. Keying by
        // stage forces a fresh State per stage.
        final exercises = ref.read(lessonRunnerControllerProvider(key)).value!.content.exercisesFor(stage.name);
        return ExerciseStage(
          key: ValueKey(stage),
          runnerKey: key,
          exercises: exercises,
          activityType: stage.name,
          onResult: (result) => controller.recordQuizResult(stage, result),
          onComplete: completeAndAdvance,
        );
      case Stage.complete:
        return CompleteStage(runnerKey: key);
    }
  }
}

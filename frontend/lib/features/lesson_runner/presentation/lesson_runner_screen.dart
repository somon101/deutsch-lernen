import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/stage.dart';
import 'lesson_runner_controller.dart';
import 'stages/audio_stage.dart';
import 'stages/complete_stage.dart';
import 'stages/exercise_stage.dart';
import 'stages/material_stage.dart';
import 'stages/video_stage.dart';
import 'stages/vocabulary_stage.dart';

/// Mirrors LessonPage.tsx/BuilderLessonPage.tsx: validates the :stage URL
/// param, redirects to the correct incomplete stage if it's invalid or
/// locked, and renders the matching stage widget inside a shared shell
/// (top progress rail + stage content).
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

    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, st) => Scaffold(
        appBar: AppBar(title: const Text('Урок')),
        body: Center(child: Text('Не удалось загрузить урок: $err')),
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
    );
  }
}

class _StageRail extends StatelessWidget {
  const _StageRail({required this.currentStage, required this.completed});

  final Stage currentStage;
  final Set<Stage> completed;

  @override
  Widget build(BuildContext context) {
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
                label: Text(stageLabels[s]!),
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
        return ExerciseStage(runnerKey: key, stage: stage, onComplete: completeAndAdvance);
      case Stage.complete:
        return CompleteStage(runnerKey: key);
    }
  }
}

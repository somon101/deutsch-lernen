import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/sound_effects.dart';
import '../../../core/widgets/back_guard.dart';
import '../data/lesson_repository.dart';
import '../domain/exercise.dart';
import '../domain/lesson_content.dart';
import '../domain/lesson_graph.dart';
import 'lesson_runner_controller.dart';
import 'stages/audio_stage.dart';
import 'stages/exercise_stage.dart';
import 'stages/material_stage.dart';
import 'stages/video_stage.dart';
import 'stages/vocabulary_stage.dart';

const _kComplete = 'complete';

const Map<String, String> _typeLabels = {
  'vocabulary': 'Слова',
  'material': 'Материал',
  'video': 'Видео',
  'audio': 'Аудио',
  'minitest': 'Мини-тест',
  'practice': 'Практика',
  'review': 'Закрепление',
};

/// Student runner for a converted lesson (§ lesson graph, 2026-09-03) —
/// executes the graph the teacher built instead of a fixed chain: the URL's
/// `nodeId` segment is validated against the flattened route (a topological
/// sort of the lesson's real nodes/edges, see flattenGraph) exactly the way
/// LessonRunnerScreen validates its `:stage` segment against the fixed
/// Stage enum, redirecting to the correct incomplete node otherwise. A node
/// type the lesson simply has none of never appears in the flattened list
/// at all — there is no empty placeholder to skip, unlike the old chain's
/// "Видео не найдено" screen for a lesson with no video.
class GraphLessonRunnerScreen extends ConsumerWidget {
  const GraphLessonRunnerScreen({super.key, required this.lessonId, required this.nodeId, this.courseId});

  final String lessonId;
  final String nodeId;
  final String? courseId;

  String _basePath() => courseId != null ? '/courses/$courseId/lesson/$lessonId' : '/lesson/$lessonId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (courseId: courseId, lessonId: lessonId);
    final async = ref.watch(graphLessonRunnerControllerProvider(key));

    return BackGuard(
      fallbackPath: '/',
      child: async.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (err, st) => Scaffold(
          appBar: AppBar(title: const Text('Урок')),
          body: Center(child: Text('Не удалось загрузить урок: $err')),
        ),
        data: (data) {
          final flat = flattenGraph(data.content.graph!);
          final completed = data.progress.completedNodeIds;
          final everyNodeDone = flat.isNotEmpty && flat.every((n) => completed.contains(n.id));

          if (nodeId == _kComplete) {
            if (!everyNodeDone) {
              final target = nextIncompleteNode(flat, completed);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted && target != null) context.go('${_basePath()}/${target.id}');
              });
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return _GraphCompleteScreen(runnerKey: key, flat: flat);
          }

          final requestedNode = flat.cast<GraphNode?>().firstWhere((n) => n!.id == nodeId, orElse: () => null);
          if (requestedNode == null || !isNodeUnlocked(flat, completed, requestedNode.id)) {
            final target = everyNodeDone ? null : nextIncompleteNode(flat, completed);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              context.go(target != null ? '${_basePath()}/${target.id}' : '${_basePath()}/$_kComplete');
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
                _GraphRail(flat: flat, current: requestedNode, completed: completed),
                const Divider(height: 1),
                Expanded(
                  child: _GraphNodeBody(
                    key: ValueKey(requestedNode.id),
                    runnerKey: key,
                    content: data.content,
                    node: requestedNode,
                    flat: flat,
                    basePath: _basePath(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GraphRail extends StatelessWidget {
  const _GraphRail({required this.flat, required this.current, required this.completed});
  final List<GraphNode> flat;
  final GraphNode current;
  final Set<String> completed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final n in flat)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Chip(
                avatar: Icon(
                  completed.contains(n.id)
                      ? Icons.check_circle
                      : n.id == current.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                  size: 18,
                  color: completed.contains(n.id) ? Colors.green : null,
                ),
                label: Text(n.title),
                backgroundColor: n.id == current.id ? Theme.of(context).colorScheme.primaryContainer : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _GraphNodeBody extends ConsumerWidget {
  const _GraphNodeBody({super.key, required this.runnerKey, required this.content, required this.node, required this.flat, required this.basePath});

  final LessonRunnerKey runnerKey;
  final LessonContentData content;
  final GraphNode node;
  final List<GraphNode> flat;
  final String basePath;

  GraphNode? get _next {
    final idx = flat.indexWhere((n) => n.id == node.id);
    return idx >= 0 && idx + 1 < flat.length ? flat[idx + 1] : null;
  }

  void _goNext(BuildContext context) {
    final next = _next;
    context.go(next != null ? '$basePath/${next.id}' : '$basePath/$_kComplete');
  }

  Future<void> _completeAndAdvance(BuildContext context, WidgetRef ref) async {
    await ref.read(graphLessonRunnerControllerProvider(runnerKey).notifier).markNodeComplete(node.id);
    if (context.mounted) _goNext(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onComplete() => _completeAndAdvance(context, ref);

    switch (node.type) {
      case 'vocabulary':
        final progress = ref.watch(graphLessonRunnerControllerProvider(runnerKey)).value!.progress;
        return VocabularyStage(
          runnerKey: runnerKey,
          onComplete: onComplete,
          initialIndexOverride: progress.vocabIndex,
          onIndexChanged: (i) => ref.read(graphLessonRunnerControllerProvider(runnerKey).notifier).setVocabIndex(i),
        );
      case 'video':
        return VideoStage(
          runnerKey: runnerKey,
          onComplete: onComplete,
          graphNodeMediaUrl: true,
          mediaUrlOverride: node.mediaUrl,
          nextLabel: _nextLabel(),
        );
      case 'audio':
        return AudioStage(
          runnerKey: runnerKey,
          onComplete: onComplete,
          graphNodeMediaUrl: true,
          mediaUrlOverride: node.mediaUrl,
          nextLabel: _nextLabel(),
        );
      case 'material':
        return FutureBuilder<List<MaterialBlock>>(
          future: ref.read(lessonRepositoryProvider).fetchMaterialBlocksForNode(node.refId!),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            return MaterialStage(runnerKey: runnerKey, onComplete: onComplete, materialOverride: snapshot.data, nextLabel: _nextLabel());
          },
        );
      case 'minitest':
      case 'practice':
      case 'review':
        final exercises = exercisesForBlock(content.blocks, node.refId ?? '');
        return ExerciseStage(
          runnerKey: runnerKey,
          exercises: exercises,
          activityType: node.type,
          onResult: (result) => ref.read(graphLessonRunnerControllerProvider(runnerKey).notifier).recordNodeQuizResult(node.id, result),
          onComplete: onComplete,
        );
      default:
        return Center(child: Text('Неизвестный тип блока: ${node.type}'));
    }
  }

  String? _nextLabel() {
    final next = _next;
    return next == null ? 'Завершить урок' : 'Далее: ${next.title} →';
  }
}

/// Results screen for a graph lesson (§ lesson graph, 2026-09-03) — mirrors
/// CompleteStage's substance (vocab-learned count, per-type score rings,
/// marks the lesson complete exactly once, "Пройти ещё раз") but sums each
/// minitest/practice/review NODE's own result by type first, since a graph
/// lesson can have several nodes of the same type where the legacy screen
/// only ever had exactly one of each.
class _GraphCompleteScreen extends ConsumerStatefulWidget {
  const _GraphCompleteScreen({required this.runnerKey, required this.flat});
  final LessonRunnerKey runnerKey;
  final List<GraphNode> flat;

  @override
  ConsumerState<_GraphCompleteScreen> createState() => _GraphCompleteScreenState();
}

class _GraphCompleteScreenState extends ConsumerState<_GraphCompleteScreen> {
  bool _sideEffectsRan = false;
  bool _restarting = false;

  void _runSideEffectsOnce(bool alreadyComplete) {
    if (_sideEffectsRan) return;
    _sideEffectsRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!alreadyComplete) {
        ref.read(graphLessonRunnerControllerProvider(widget.runnerKey).notifier).completeGraphLesson(widget.flat);
      }
      ref.read(soundEffectsProvider).playComplete();
    });
  }

  Future<void> _restart() async {
    setState(() => _restarting = true);
    await ref.read(graphLessonRunnerControllerProvider(widget.runnerKey).notifier).restartLesson();
    if (!mounted) return;
    final key = widget.runnerKey;
    final base = key.courseId != null ? '/courses/${key.courseId}/lesson/${key.lessonId}' : '/lesson/${key.lessonId}';
    context.go('$base/start');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(graphLessonRunnerControllerProvider(widget.runnerKey)).value!;
    _runSideEffectsOnce(data.progress.completedAt != null);

    final byType = <String, ({int correct, int total})>{};
    for (final node in widget.flat) {
      if (node.type != 'minitest' && node.type != 'practice' && node.type != 'review') continue;
      final r = data.progress.nodeResults[node.id];
      if (r == null) continue;
      final prev = byType[node.type] ?? (correct: 0, total: 0);
      byType[node.type] = (correct: prev.correct + r.correct, total: prev.total + r.total);
    }

    return Scaffold(
      appBar: AppBar(title: Text(data.content.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events, size: 56, color: Colors.amber.shade600),
            const SizedBox(height: 12),
            Text('Отличная работа!', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Вы прошли урок «${data.content.title}». Вот ваши результаты:',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _StatCard(label: 'слов изучено', value: '${data.content.vocabulary.length}'),
                for (final entry in byType.entries)
                  _StatCard(
                    label: _typeLabels[entry.key] ?? entry.key,
                    value: entry.value.total > 0 ? '${((entry.value.correct / entry.value.total) * 100).round()}%' : '—',
                  ),
              ],
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(onPressed: () => context.go('/'), child: const Text('На главную')),
                FilledButton(
                  onPressed: _restarting ? null : _restart,
                  child: Text(_restarting ? 'Начинаем…' : 'Пройти ещё раз'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

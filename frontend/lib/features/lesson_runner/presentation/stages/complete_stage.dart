import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/sound_effects.dart';
import '../../domain/progress.dart';
import '../../domain/stage.dart';
import '../lesson_runner_controller.dart';

int? _pct(QuizResult? result) => result != null && result.total > 0 ? ((result.correct / result.total) * 100).round() : null;

/// Mirrors CompleteStage.tsx's substance (vocab-learned count + mini-test/
/// practice/review percentages, marks the lesson complete exactly once,
/// plays a completion chime) but is a native results screen rather than a
/// literal port of the web version's hand-drawn SVG confetti ribbons — per
/// the migration plan's instruction to natively adapt, not transliterate,
/// the web UI.
class CompleteStage extends ConsumerStatefulWidget {
  const CompleteStage({super.key, required this.runnerKey});

  final LessonRunnerKey runnerKey;

  @override
  ConsumerState<CompleteStage> createState() => _CompleteStageState();
}

class _CompleteStageState extends ConsumerState<CompleteStage> {
  bool _sideEffectsRan = false;
  bool _restarting = false;

  void _runSideEffectsOnce(bool alreadyComplete) {
    if (_sideEffectsRan) return;
    _sideEffectsRan = true;
    if (!alreadyComplete) {
      ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier).completeLesson();
    }
    ref.read(soundEffectsProvider).playComplete();
  }

  Future<void> _restart() async {
    setState(() => _restarting = true);
    await ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier).restartLesson();
    if (!mounted) return;
    final key = widget.runnerKey;
    final base = key.courseId != null ? '/courses/${key.courseId}/lesson/${key.lessonId}' : '/lesson/${key.lessonId}';
    context.go('$base/vocabulary');
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(lessonRunnerControllerProvider(widget.runnerKey)).value!;
    _runSideEffectsOnce(data.progress.completedStages.contains(Stage.complete));

    final stats = [
      (label: 'мини-тест', value: _pct(data.progress.miniTestResult), color: Colors.green),
      (label: 'практика', value: _pct(data.progress.practiceResult), color: Theme.of(context).colorScheme.primary),
      (label: 'закрепление', value: _pct(data.progress.reviewResult), color: Theme.of(context).colorScheme.primary),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events, size: 56, color: Colors.amber.shade600),
          const SizedBox(height: 12),
          Text('Отличная работа!', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Вы прошли все этапы урока «${data.content.title}». Вот ваши результаты:',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _VocabCountCard(count: data.content.vocabulary.length),
              for (final s in stats) _RingStat(label: s.label, value: s.value, color: s.color),
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
    );
  }
}

class _VocabCountCard extends StatelessWidget {
  const _VocabCountCard({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: count),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text('$value', style: Theme.of(context).textTheme.headlineMedium),
          ),
          const SizedBox(height: 4),
          const Text('слов изучено', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _RingStat extends StatelessWidget {
  const _RingStat({required this.label, required this.value, required this.color});

  final String label;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value ?? 0) / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 6,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  CircularProgressIndicator(value: t, strokeWidth: 6, color: color),
                  Text(value == null ? '—' : '${(t * 100).round()}%'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

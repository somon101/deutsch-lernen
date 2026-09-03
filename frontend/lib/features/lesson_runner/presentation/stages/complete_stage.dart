import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/sound_effects.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/progress.dart';
import '../../domain/stage.dart';
import '../lesson_runner_controller.dart';

/// Null only when the stage was never attempted at all (no QuizResult
/// exists yet) — a real result with zero questions (an empty block) is
/// genuine 0% progress, not "no data" (§ zero-progress display fix,
/// 2026-08-29: a ring/percentage must show "0%", never a blank/dash, when
/// there's nothing to show but the value really is zero).
int? _pct(QuizResult? result) => result == null ? null : (result.total > 0 ? ((result.correct / result.total) * 100).round() : 0);

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

  /// Marking the lesson complete writes to a provider, and playing the chime
  /// touches another — both are side effects, and both used to run straight
  /// out of `build()`. That only stayed upright because of the run-once flag;
  /// mutating a provider while the tree is building is the standard way to
  /// earn "Tried to modify a provider while the widget tree was building".
  /// Deferring to after the frame keeps the same "exactly once" behaviour
  /// without doing the work at a moment when it isn't allowed
  /// (§ side effects out of build, 2026-09-02).
  void _runSideEffectsOnce(bool alreadyComplete) {
    if (_sideEffectsRan) return;
    _sideEffectsRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!alreadyComplete) {
        ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier).completeLesson();
      }
      ref.read(soundEffectsProvider).playComplete();
    });
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
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(lessonRunnerControllerProvider(widget.runnerKey)).value!;
    _runSideEffectsOnce(data.progress.completedStages.contains(Stage.complete));

    final stats = [
      (label: l10n.lessonCompleteMinitestLabel, value: _pct(data.progress.miniTestResult), color: Colors.green),
      (label: l10n.lessonCompletePracticeLabel, value: _pct(data.progress.practiceResult), color: Theme.of(context).colorScheme.primary),
      (label: l10n.lessonCompleteReviewLabel, value: _pct(data.progress.reviewResult), color: Theme.of(context).colorScheme.primary),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events, size: 56, color: Colors.amber.shade600),
          const SizedBox(height: 12),
          Text(l10n.lessonCompleteTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            l10n.lessonCompleteSubtitleLinear(data.content.title),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _VocabCountCard(count: data.content.vocabulary.length, l10n: l10n),
              for (final s in stats) _RingStat(label: s.label, value: s.value, color: s.color),
            ],
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: () => context.go('/'), child: Text(l10n.forbiddenGoHome)),
              FilledButton(
                onPressed: _restarting ? null : _restart,
                child: Text(_restarting ? l10n.lessonCompleteRestarting : l10n.lessonCompleteRestart),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VocabCountCard extends StatelessWidget {
  const _VocabCountCard({required this.count, required this.l10n});
  final int count;
  final AppLocalizations l10n;

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
          Text(l10n.lessonCompleteWordsLearned, textAlign: TextAlign.center),
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

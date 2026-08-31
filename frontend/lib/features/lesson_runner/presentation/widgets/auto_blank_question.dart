import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lesson_repository.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

/// Renders one generated "missing word" slot (§ auto blank, 2026-08-31).
/// [prefetched] is the stage's own buffered Future for this slot, if it
/// already started one ahead of time (ExerciseStage's §11 prefetch buffer)
/// — when absent (e.g. the inline material-reading checkpoint use in
/// material_stage.dart, which has no notion of "upcoming slots" to prefetch)
/// this widget generates on its own, once, in initState. Grading is
/// server-side (§25): this widget never decides `correct` locally, it just
/// reports whatever the server said via [onAnswered].
class AutoBlankQuestionView extends ConsumerStatefulWidget {
  const AutoBlankQuestionView({
    super.key,
    required this.exercise,
    this.prefetched,
    required this.onAnswered,
    this.onSkip,
  });

  final AutoBlankSlot exercise;
  final Future<GeneratedBlankQuestion?>? prefetched;
  final ValueChanged<bool> onAnswered;

  /// Called instead of [onAnswered] when the server couldn't safely
  /// generate this slot at all (§5/§9) — e.g. advances a quiz stage
  /// without recording a right/wrong result, since nothing was actually
  /// shown. Null (the inline-in-material-reading case, which has no
  /// "advance to the next slot" concept) just shows the message with no
  /// button.
  final VoidCallback? onSkip;

  @override
  ConsumerState<AutoBlankQuestionView> createState() => _AutoBlankQuestionViewState();
}

class _AutoBlankQuestionViewState extends ConsumerState<AutoBlankQuestionView> {
  late final Future<GeneratedBlankQuestion?> _generation =
      widget.prefetched ?? ref.read(lessonRepositoryProvider).generateBlankQuestion(widget.exercise.questionId, widget.exercise.phraseIndex);
  String? _selected;
  String? _correctText;
  bool _busy = false;
  String? _error;

  Future<void> _select(GeneratedBlankQuestion q, String optionText) async {
    if (_selected != null || _busy) return;
    setState(() {
      _selected = optionText;
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(lessonRepositoryProvider).submitBlankAnswer(
            widget.exercise.questionId,
            generatedQuestionId: q.generatedQuestionId,
            selectedText: optionText,
            placementId: widget.exercise.placementId,
          );
      if (!mounted) return;
      setState(() {
        _correctText = result.correctText;
        _busy = false;
      });
      widget.onAnswered(result.correct);
    } catch (e) {
      if (!mounted) return;
      // Let them retry — a network hiccup shouldn't strand the learner on
      // a half-answered question with no way forward.
      setState(() {
        _selected = null;
        _busy = false;
        _error = 'Не удалось отправить ответ. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GeneratedBlankQuestion?>(
      future: _generation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final question = snapshot.data;
        if (question == null) {
          final onSkip = widget.onSkip;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(onSkip != null ? 'Не удалось подготовить это упражнение — переходим дальше.' : 'Не удалось подготовить это упражнение.'),
                if (onSkip != null) ...[
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: onSkip, child: const Text('Продолжить')),
                ],
              ],
            ),
          );
        }

        final selected = _selected;
        final correctText = _correctText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(question.promptWithBlank, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            for (final option in question.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OptionButton(
                  label: option.text,
                  state: selected == null
                      ? OptionState.neutral
                      : correctText != null && option.text == correctText
                          ? OptionState.correct
                          : option.text == selected
                              ? OptionState.incorrect
                              : OptionState.neutral,
                  onTap: selected == null && !_busy ? () => _select(question, option.text) : null,
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (correctText != null) ...[
              const SizedBox(height: 8),
              FeedbackBanner(
                correct: selected == correctText,
                text: selected == correctText ? 'Верно!' : 'Неверно. Правильный ответ: «$correctText».',
              ),
            ],
          ],
        );
      },
    );
  }
}

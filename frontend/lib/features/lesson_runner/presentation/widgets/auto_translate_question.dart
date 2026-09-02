import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lesson_repository.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

/// Renders one generated "translate the word" slot (§ auto translate,
/// 2026-09-02). Mirrors AutoBlankQuestionView: [prefetched] is the stage's
/// buffered Future for this slot when it started one ahead of time, grading
/// happens server-side (this widget never decides `correct` itself), and a
/// slot the server couldn't fill — the source pool is smaller than the
/// teacher asked for — is skipped rather than shown broken.
class AutoTranslateQuestionView extends ConsumerStatefulWidget {
  const AutoTranslateQuestionView({
    super.key,
    required this.exercise,
    this.prefetched,
    required this.onAnswered,
    this.onSkip,
  });

  final AutoTranslateSlot exercise;
  final Future<GeneratedTranslateQuestion?>? prefetched;
  final ValueChanged<bool> onAnswered;

  /// Called instead of [onAnswered] when this slot couldn't be generated,
  /// so the stage advances without recording a right/wrong result for a
  /// question the learner was never actually shown.
  final VoidCallback? onSkip;

  @override
  ConsumerState<AutoTranslateQuestionView> createState() => _AutoTranslateQuestionViewState();
}

class _AutoTranslateQuestionViewState extends ConsumerState<AutoTranslateQuestionView> {
  late final Future<GeneratedTranslateQuestion?> _generation =
      widget.prefetched ?? ref.read(lessonRepositoryProvider).generateTranslateQuestion(widget.exercise.questionId, widget.exercise.slotIndex);
  String? _selected;
  String? _correctText;
  bool _busy = false;
  String? _error;

  Future<void> _select(GeneratedTranslateQuestion q, String optionText) async {
    if (_selected != null || _busy) return;
    setState(() {
      _selected = optionText;
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(lessonRepositoryProvider).submitTranslateAnswer(
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
      // Let them retry rather than stranding them on a half-answered
      // question with no way forward.
      setState(() {
        _selected = null;
        _busy = false;
        _error = 'Не удалось отправить ответ. Попробуйте ещё раз.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GeneratedTranslateQuestion?>(
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
            Text(question.prompt, style: Theme.of(context).textTheme.titleMedium),
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

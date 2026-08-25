import 'package:flutter/material.dart';

import '../../../../core/utils/seeded_random.dart';
import '../../grading/cloze_grader.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

/// Mirrors ClozeView.tsx.
class ClozeQuestionView extends StatefulWidget {
  const ClozeQuestionView({super.key, required this.exercise, required this.onAnswered});

  final ClozeExercise exercise;
  final ValueChanged<bool> onAnswered;

  @override
  State<ClozeQuestionView> createState() => _ClozeQuestionViewState();
}

class _ClozeQuestionViewState extends State<ClozeQuestionView> {
  late final List<String> _options = shuffleRandom(widget.exercise.options);
  String? _selected;

  void _select(String option) {
    if (_selected != null) return;
    setState(() => _selected = option);
    widget.onAnswered(gradeCloze(option, widget.exercise.answer));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final correct = selected != null && gradeCloze(selected, widget.exercise.answer);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Перевод: «${widget.exercise.translation}»', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface),
            children: [
              TextSpan(text: '${widget.exercise.before} '),
              TextSpan(
                text: selected ?? '…',
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
              TextSpan(text: ' ${widget.exercise.after}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final option in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OptionButton(
              label: option,
              state: selected == null
                  ? OptionState.neutral
                  : gradeCloze(option, widget.exercise.answer)
                      ? OptionState.correct
                      : option == selected
                          ? OptionState.incorrect
                          : OptionState.neutral,
              onTap: selected == null ? () => _select(option) : null,
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          FeedbackBanner(
            correct: correct,
            text: correct ? 'Верно!' : 'Неверно. Правильное слово: «${widget.exercise.answer}».',
          ),
        ],
      ],
    );
  }
}

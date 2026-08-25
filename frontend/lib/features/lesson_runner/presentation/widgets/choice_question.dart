import 'package:flutter/material.dart';

import '../../../../core/utils/seeded_random.dart';
import '../../grading/choice_grader.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

/// Mirrors ChoiceView.tsx.
class ChoiceQuestionView extends StatefulWidget {
  const ChoiceQuestionView({super.key, required this.exercise, required this.onAnswered});

  final ChoiceQuestion exercise;
  final ValueChanged<bool> onAnswered;

  @override
  State<ChoiceQuestionView> createState() => _ChoiceQuestionViewState();
}

class _ChoiceQuestionViewState extends State<ChoiceQuestionView> {
  late final List<String> _options = shuffleRandom(widget.exercise.options);
  String? _selected;

  void _select(String option) {
    if (_selected != null) return;
    setState(() => _selected = option);
    widget.onAnswered(gradeChoice(option, widget.exercise.correctAnswer));
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final correct = selected != null && gradeChoice(selected, widget.exercise.correctAnswer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.exercise.prompt, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        for (final option in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OptionButton(
              label: option,
              state: selected == null
                  ? OptionState.neutral
                  : gradeChoice(option, widget.exercise.correctAnswer)
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
            text: correct ? 'Верно!' : 'Неверно. Правильный ответ: «${widget.exercise.correctAnswer}».',
          ),
        ],
      ],
    );
  }
}

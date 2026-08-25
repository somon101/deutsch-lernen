import 'package:flutter/material.dart';

import '../../grading/truefalse_grader.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

/// Mirrors TrueFalseView.tsx.
class TrueFalseQuestionView extends StatefulWidget {
  const TrueFalseQuestionView({super.key, required this.exercise, required this.onAnswered});

  final TrueFalseQuestion exercise;
  final ValueChanged<bool> onAnswered;

  @override
  State<TrueFalseQuestionView> createState() => _TrueFalseQuestionViewState();
}

class _TrueFalseQuestionViewState extends State<TrueFalseQuestionView> {
  bool? _answer;

  void _select(bool value) {
    if (_answer != null) return;
    setState(() => _answer = value);
    widget.onAnswered(gradeTrueFalse(value, widget.exercise.correct));
  }

  OptionState _stateFor(bool value) {
    if (_answer == null) return OptionState.neutral;
    if (value == widget.exercise.correct) return OptionState.correct;
    if (value == _answer) return OptionState.incorrect;
    return OptionState.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.exercise.statement, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OptionButton(label: 'Верно', state: _stateFor(true), onTap: answer == null ? () => _select(true) : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OptionButton(label: 'Неверно', state: _stateFor(false), onTap: answer == null ? () => _select(false) : null),
            ),
          ],
        ),
        if (answer != null) ...[
          const SizedBox(height: 12),
          FeedbackBanner(
            correct: answer == widget.exercise.correct,
            text: '${answer == widget.exercise.correct ? "Верно! " : "Неверно. "}${widget.exercise.explanation}',
          ),
        ],
      ],
    );
  }
}

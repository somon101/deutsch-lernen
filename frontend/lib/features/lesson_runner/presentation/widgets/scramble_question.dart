import 'package:flutter/material.dart';

import '../../grading/scramble_grader.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

class _Token {
  const _Token(this.key, this.word);
  final String key;
  final String word;
}

/// Mirrors ScrambleView.tsx: exercise.tokens already arrives pre-shuffled
/// (see domain/exercise.dart's toExercise) — this widget only manages
/// which tokens have been placed into the answer row.
class ScrambleQuestionView extends StatefulWidget {
  const ScrambleQuestionView({super.key, required this.exercise, required this.onAnswered});

  final ScrambleExercise exercise;
  final ValueChanged<bool> onAnswered;

  @override
  State<ScrambleQuestionView> createState() => _ScrambleQuestionViewState();
}

class _ScrambleQuestionViewState extends State<ScrambleQuestionView> {
  late List<_Token> _bank = [for (var i = 0; i < widget.exercise.tokens.length; i++) _Token('$i-${widget.exercise.tokens[i]}', widget.exercise.tokens[i])];
  final List<_Token> _placed = [];
  bool _checked = false;
  bool _correct = false;

  void _place(_Token token) {
    if (_checked) return;
    setState(() {
      _bank = _bank.where((t) => t.key != token.key).toList();
      _placed.add(token);
    });
  }

  void _unplace(_Token token) {
    if (_checked) return;
    setState(() {
      _placed.removeWhere((t) => t.key == token.key);
      _bank = [..._bank, token];
    });
  }

  /// Two ways to be ready, because "every piece used" isn't always the same
  /// as "the phrase is complete":
  ///
  /// - every piece placed — the usual case, and the only one that works when
  ///   a piece holds several words ("every day" as one draggable chunk), for
  ///   which there are fewer pieces than the answer has words;
  /// - as many pieces placed as the answer has words — what makes an
  ///   exercise with distractor words solvable at all. Requiring every piece
  ///   there would force the learner to place the distractors too, and the
  ///   grader compares the placed pieces against the phrase, so such an
  ///   exercise could never be answered correctly.
  ///
  /// When there are no distractors and no multi-word chunks the two counts
  /// are equal, so this changes nothing for the exercises that already work.
  bool get _canCheck =>
      _placed.length == widget.exercise.tokens.length || _placed.length == widget.exercise.answer.length;

  void _check() {
    final correct = gradeScramble(_placed.map((t) => t.word).toList(), widget.exercise.answer);
    setState(() {
      _checked = true;
      _correct = correct;
    });
    widget.onAnswered(correct);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Соберите фразу по переводу: «${widget.exercise.translation}»', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _placed)
                _TokenChip(label: t.word, placed: true, onTap: _checked ? null : () => _unplace(t)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in _bank) _TokenChip(label: t.word, placed: false, onTap: _checked ? null : () => _place(t)),
          ],
        ),
        const SizedBox(height: 16),
        if (!_checked)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _canCheck ? _check : null,
              child: const Text('Проверить'),
            ),
          ),
        if (_checked) ...[
          const SizedBox(height: 4),
          FeedbackBanner(
            correct: _correct,
            text: _correct ? 'Верно!' : 'Неверно. Правильно: «${widget.exercise.answer.join(" ")}».',
          ),
        ],
      ],
    );
  }
}

class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.label, required this.placed, required this.onTap});

  final String label;
  final bool placed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: placed ? scheme.primaryContainer : null,
    );
  }
}

import 'package:flutter/material.dart';

enum OptionState { neutral, correct, incorrect, selected }

/// Shared quiz-option button used by choice/cloze/truefalse: neutral until
/// answered, then highlights the correct option green and (if different)
/// the learner's wrong pick red — mirrors the .quiz-option/.correct/
/// .incorrect classes shared across ChoiceView/ClozeView/TrueFalseView.tsx.
class OptionButton extends StatelessWidget {
  const OptionButton({super.key, required this.label, required this.state, this.onTap});

  final String label;
  final OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color? background;
    Color? border;
    switch (state) {
      case OptionState.correct:
        background = Colors.green.withValues(alpha: 0.15);
        border = Colors.green;
      case OptionState.incorrect:
        background = scheme.errorContainer;
        border = scheme.error;
      case OptionState.selected:
        background = scheme.primaryContainer;
        border = scheme.primary;
      case OptionState.neutral:
        background = null;
        border = scheme.outlineVariant;
    }

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        side: BorderSide(color: border, width: state == OptionState.neutral ? 1 : 2),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        alignment: Alignment.centerLeft,
      ),
      child: Text(label),
    );
  }
}

class FeedbackBanner extends StatelessWidget {
  const FeedbackBanner({super.key, required this.correct, required this.text});

  final bool correct;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: correct ? Colors.green.withValues(alpha: 0.12) : scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(color: correct ? Colors.green.shade800 : scheme.onErrorContainer, fontWeight: FontWeight.w600),
      ),
    );
  }
}

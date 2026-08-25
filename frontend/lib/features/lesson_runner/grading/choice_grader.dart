import '../../../core/utils/text_utils.dart';

/// Mirrors ChoiceView.tsx: correctness by value (via normalizeAnswer), not
/// by option position — option order is shuffled per render, so position
/// was never meaningful.
bool gradeChoice(String selected, String correctAnswer) => answersMatch(selected, correctAnswer);

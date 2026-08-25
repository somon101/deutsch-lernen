import '../../../core/utils/text_utils.dart';

/// Mirrors ClozeView.tsx: the picked word-bank option is compared against
/// the blank's answer via normalizeAnswer, same as choice.
bool gradeCloze(String selectedOption, String answer) => answersMatch(selectedOption, answer);

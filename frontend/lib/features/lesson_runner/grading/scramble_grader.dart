import '../../../core/utils/text_utils.dart';

/// Mirrors ScrambleView.tsx: the learner's placed token order is joined
/// with spaces and compared against the joined answer order via
/// normalizeAnswer — so punctuation/case on individual tokens can't cause
/// a false negative, but token ORDER still matters (this is not a set
/// comparison).
bool gradeScramble(List<String> placed, List<String> answer) => answersMatch(placed.join(' '), answer.join(' '));

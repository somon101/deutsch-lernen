import '../domain/exercise.dart';

/// Mirrors MatchView.tsx's grading rule exactly — the one genuinely
/// stateful grader of the 5, since "correct" depends on the whole session,
/// not a single answer: tap one item from each column; a correct pair
/// locks in, a wrong pair counts against the final verdict (a brief
/// "wrong" flash in the UI, but the mismatch itself is what's tracked
/// here). The exercise as a whole only grades as correct once every pair
/// is matched AND zero wrong attempts were made anywhere in the session —
/// eventually getting everything right after some wrong guesses still
/// grades as incorrect. This is the one rule easy to accidentally drop
/// with a naive "are all pairs matched?" reimplementation, so it has its
/// own explicit test (see match_grader_test.dart).
class MatchGrader {
  MatchGrader(this.pairs);

  final List<MatchPair> pairs;
  final Set<String> _matchedPairIds = {};
  int wrongAttempts = 0;

  bool get isComplete => _matchedPairIds.length == pairs.length;

  /// Only meaningful once [isComplete] is true — matches the UI's own
  /// contract (the exercise reports a result once, at completion).
  bool get isCorrect => wrongAttempts == 0;

  bool isPairMatched(String pairId) => _matchedPairIds.contains(pairId);

  /// One attempt: the learner picked a left-column item belonging to
  /// [leftPairId] and a right-column item belonging to [rightPairId]. Pair
  /// ids come from MatchPair.id — the UI never lets the same pair be
  /// attempted twice once matched.
  bool attempt({required String leftPairId, required String rightPairId}) {
    if (leftPairId == rightPairId) {
      _matchedPairIds.add(leftPairId);
      return true;
    }
    wrongAttempts += 1;
    return false;
  }
}

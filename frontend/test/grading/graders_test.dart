import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/features/lesson_runner/domain/exercise.dart';
import 'package:deutsch_lernen/features/lesson_runner/grading/choice_grader.dart';
import 'package:deutsch_lernen/features/lesson_runner/grading/cloze_grader.dart';
import 'package:deutsch_lernen/features/lesson_runner/grading/match_grader.dart';
import 'package:deutsch_lernen/features/lesson_runner/grading/scramble_grader.dart';
import 'package:deutsch_lernen/features/lesson_runner/grading/truefalse_grader.dart';

void main() {
  group('gradeChoice', () {
    test('matches by normalized value, not exact string', () {
      expect(gradeChoice('Hallo', 'hallo!'), isTrue);
      expect(gradeChoice('Tschüss', 'Hallo'), isFalse);
    });
  });

  group('gradeTrueFalse', () {
    test('matches the stored boolean exactly', () {
      expect(gradeTrueFalse(true, true), isTrue);
      expect(gradeTrueFalse(false, true), isFalse);
      expect(gradeTrueFalse(false, false), isTrue);
    });
  });

  group('gradeCloze', () {
    test('matches the blank answer by normalized value', () {
      expect(gradeCloze('Katze', 'katze!'), isTrue);
      expect(gradeCloze('Hund', 'Katze'), isFalse);
    });
  });

  group('gradeScramble', () {
    test('correct only when token order matches', () {
      expect(gradeScramble(['Ich', 'heiße', 'Anna'], ['Ich', 'heiße', 'Anna']), isTrue);
      expect(gradeScramble(['heiße', 'Ich', 'Anna'], ['Ich', 'heiße', 'Anna']), isFalse);
    });

    test('tolerant of punctuation/case on individual tokens', () {
      expect(gradeScramble(['ich', 'HEISSE!'], ['Ich', 'heisse']), isTrue);
    });
  });

  group('MatchGrader — the zero-wrong-attempts rule', () {
    List<MatchPair> pairs() => const [
          MatchPair(id: 'p-0', left: 'Katze', right: 'кошка'),
          MatchPair(id: 'p-1', left: 'Hund', right: 'собака'),
          MatchPair(id: 'p-2', left: 'Maus', right: 'мышь'),
        ];

    test('all-correct-first-try grades correct', () {
      final grader = MatchGrader(pairs());
      expect(grader.attempt(leftPairId: 'p-0', rightPairId: 'p-0'), isTrue);
      expect(grader.attempt(leftPairId: 'p-1', rightPairId: 'p-1'), isTrue);
      expect(grader.attempt(leftPairId: 'p-2', rightPairId: 'p-2'), isTrue);

      expect(grader.isComplete, isTrue);
      expect(grader.isCorrect, isTrue);
      expect(grader.wrongAttempts, 0);
    });

    test('CRITICAL: eventually matching everything after a wrong guess still grades incorrect', () {
      final grader = MatchGrader(pairs());
      expect(grader.attempt(leftPairId: 'p-0', rightPairId: 'p-0'), isTrue);
      // One wrong guess along the way...
      expect(grader.attempt(leftPairId: 'p-1', rightPairId: 'p-2'), isFalse);
      // ...corrected afterward. Every pair still ends up matched.
      expect(grader.attempt(leftPairId: 'p-1', rightPairId: 'p-1'), isTrue);
      expect(grader.attempt(leftPairId: 'p-2', rightPairId: 'p-2'), isTrue);

      expect(grader.isComplete, isTrue, reason: 'every pair was eventually matched');
      expect(grader.isCorrect, isFalse, reason: 'one wrong attempt happened along the way — the exercise must NOT grade as correct');
      expect(grader.wrongAttempts, 1);
    });

    test('multiple wrong attempts are all counted, not just the first', () {
      final grader = MatchGrader(pairs());
      grader.attempt(leftPairId: 'p-0', rightPairId: 'p-1');
      grader.attempt(leftPairId: 'p-0', rightPairId: 'p-2');
      grader.attempt(leftPairId: 'p-0', rightPairId: 'p-0');
      grader.attempt(leftPairId: 'p-1', rightPairId: 'p-1');
      grader.attempt(leftPairId: 'p-2', rightPairId: 'p-2');

      expect(grader.wrongAttempts, 2);
      expect(grader.isComplete, isTrue);
      expect(grader.isCorrect, isFalse);
    });

    test('isPairMatched reflects locked-in pairs only', () {
      final grader = MatchGrader(pairs());
      expect(grader.isPairMatched('p-0'), isFalse);
      grader.attempt(leftPairId: 'p-0', rightPairId: 'p-0');
      expect(grader.isPairMatched('p-0'), isTrue);
      expect(grader.isPairMatched('p-1'), isFalse);
    });
  });
}

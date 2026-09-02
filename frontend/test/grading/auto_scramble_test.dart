import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/features/lesson_runner/domain/exercise.dart';
import 'package:deutsch_lernen/features/lesson_runner/grading/scramble_grader.dart';

/// Covers the auto "Собери фразу" mode (§ auto scramble, 2026-09-02): the
/// server sends only the phrase, the pieces are derived from it, and the
/// order is reshuffled on every pass so a repeat attempt can't be solved
/// from memory.
QuestionDto scrambleDto({required String phrase, List<String> options = const [], String translation = 'перевод'}) =>
    QuestionDto(kind: 'scramble', prompt: translation, id: 'q1', options: options, correctAnswer: phrase);

ScrambleExercise build(QuestionDto dto) => toExercise(dto, dto.id!) as ScrambleExercise;

void main() {
  group('auto mode — pieces derived from the phrase', () {
    test('an exercise with no stored options still gets its pieces', () {
      final ex = build(scrambleDto(phrase: 'Ich bin müde.'));
      expect(ex.tokens, hasLength(3));
      expect(ex.tokens.toSet(), {'Ich', 'bin', 'müde.'});
      expect(ex.answer, ['Ich', 'bin', 'müde.']);
    });

    test('assembling the pieces in the answer order grades as correct', () {
      final ex = build(scrambleDto(phrase: 'Ich bin müde.'));
      expect(gradeScramble(ex.answer, ex.answer), isTrue);
    });

    test('a wrong order grades as wrong', () {
      final ex = build(scrambleDto(phrase: 'Ich bin müde.'));
      expect(gradeScramble(['müde.', 'Ich', 'bin'], ex.answer), isFalse);
    });

    test('punctuation on a token never causes a false negative', () {
      final ex = build(scrambleDto(phrase: 'Er sagt: "Ja".'));
      expect(gradeScramble(ex.answer, ex.answer), isTrue);
      // Same words, punctuation stripped by the shared normalizer.
      expect(gradeScramble(['Er', 'sagt', 'Ja'], ex.answer), isTrue);
    });
  });

  group('repeated words', () {
    test('every occurrence survives as its own piece', () {
      final ex = build(scrambleDto(phrase: 'ich und ich'));
      expect(ex.tokens, hasLength(3));
      expect(ex.tokens.where((t) => t == 'ich'), hasLength(2));
      expect(gradeScramble(ex.answer, ex.answer), isTrue);
    });

    test('a phrase made only of one repeated word still grades', () {
      final ex = build(scrambleDto(phrase: 'ja ja ja'));
      expect(ex.tokens, hasLength(3));
      expect(gradeScramble(['ja', 'ja', 'ja'], ex.answer), isTrue);
    });
  });

  group('edge-case phrases', () {
    test('a single-word phrase produces exactly one piece', () {
      final ex = build(scrambleDto(phrase: 'Hallo!'));
      expect(ex.tokens, ['Hallo!']);
      expect(gradeScramble(['Hallo!'], ex.answer), isTrue);
    });

    test('runs of whitespace never produce empty pieces', () {
      final ex = build(scrambleDto(phrase: 'Ich   bin \t da'));
      expect(ex.tokens, hasLength(3));
      expect(ex.tokens.any((t) => t.trim().isEmpty), isFalse);
    });

    test('a long phrase keeps every piece', () {
      const phrase = 'Wie geht es dir heute mein lieber Freund aus Berlin';
      final ex = build(scrambleDto(phrase: phrase));
      expect(ex.tokens, hasLength(10));
      expect(gradeScramble(ex.answer, ex.answer), isTrue);
    });
  });

  group('order is regenerated, never memorizable', () {
    test('repeated passes over the same phrase do not all share one order', () {
      const phrase = 'eins zwei drei vier fünf sechs sieben acht neun zehn';
      final orders = {for (var i = 0; i < 40; i++) build(scrambleDto(phrase: phrase)).tokens.join('|')};
      // With 10! possible orders, 40 passes landing on a single order would
      // mean the shuffle isn't running at all.
      expect(orders.length, greaterThan(1));
    });

    test('every pass still contains exactly the phrase, whatever the order', () {
      const phrase = 'eins zwei drei vier fünf';
      for (var i = 0; i < 25; i++) {
        final ex = build(scrambleDto(phrase: phrase));
        expect((ex.tokens.toList()..sort()), (ex.answer.toList()..sort()));
        expect(gradeScramble(ex.answer, ex.answer), isTrue);
      }
    });
  });

  group('hand-built exercises keep working', () {
    test('stored options (with extra distractors) are used as-is', () {
      final ex = build(scrambleDto(phrase: 'Ich bin müde.', options: ['Ich', 'bin', 'müde.', 'Hund', 'Katze']));
      expect(ex.tokens, hasLength(5));
      expect(ex.tokens.toSet(), {'Ich', 'bin', 'müde.', 'Hund', 'Katze'});
      // The answer is still only the phrase — the distractors are extra.
      expect(ex.answer, ['Ich', 'bin', 'müde.']);
    });

    test('a hand-built exercise is also reshuffled each pass', () {
      const options = ['eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs'];
      final orders = {for (var i = 0; i < 40; i++) build(scrambleDto(phrase: 'eins zwei drei', options: options)).tokens.join('|')};
      expect(orders.length, greaterThan(1));
    });
  });

  group('exercises stay independent of each other', () {
    test('two different phrases never borrow each other\'s pieces', () {
      final a = build(scrambleDto(phrase: 'Ich bin müde.'));
      final b = build(scrambleDto(phrase: 'Wir gehen nach Hause'));
      expect(a.tokens.toSet().intersection(b.tokens.toSet()), isEmpty);
      expect(gradeScramble(a.answer, a.answer), isTrue);
      expect(gradeScramble(b.answer, b.answer), isTrue);
      expect(gradeScramble(a.answer, b.answer), isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/features/lesson_runner/domain/exercise.dart';
import 'package:deutsch_lernen/features/lesson_runner/presentation/widgets/scramble_question.dart';

/// Covers when "Проверить" may be pressed. The three shapes below are the
/// ones that actually exist in the content: pieces equal to the phrase's
/// words, a piece holding several words, and a phrase padded with distractor
/// words the learner is meant to leave alone.
ScrambleExercise ex({required List<String> tokens, required String phrase}) => ScrambleExercise(
      id: 'q',
      translation: 'перевод',
      tokens: tokens,
      answer: phrase.split(' ').where((w) => w.isNotEmpty).toList(),
    );

Future<void> pump(WidgetTester tester, ScrambleExercise e, {void Function(bool)? onAnswered}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ScrambleQuestionView(exercise: e, onAnswered: onAnswered ?? (_) {})),
  ));
}

bool checkEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Проверить')).onPressed != null;

Future<void> place(WidgetTester tester, String word) async {
  await tester.tap(find.widgetWithText(ActionChip, word).first);
  await tester.pump();
}

void main() {
  group('ordinary exercise — pieces are exactly the phrase words', () {
    testWidgets('stays disabled until the phrase is complete, then enables', (tester) async {
      final e = ex(tokens: ['bin', 'Ich', 'müde.'], phrase: 'Ich bin müde.');
      await pump(tester, e);
      expect(checkEnabled(tester), isFalse);
      await place(tester, 'Ich');
      expect(checkEnabled(tester), isFalse);
      await place(tester, 'bin');
      expect(checkEnabled(tester), isFalse);
      await place(tester, 'müde.');
      expect(checkEnabled(tester), isTrue);
    });

    testWidgets('a correct assembly is graded correct', (tester) async {
      bool? result;
      final e = ex(tokens: ['bin', 'Ich', 'müde.'], phrase: 'Ich bin müde.');
      await pump(tester, e, onAnswered: (r) => result = r);
      for (final w in ['Ich', 'bin', 'müde.']) {
        await place(tester, w);
      }
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(result, isTrue);
    });
  });

  group('multi-word chunk — fewer pieces than the phrase has words', () {
    testWidgets('enables once every piece is placed, not at the word count', (tester) async {
      // Exactly the shape found in the content: 3 pieces, 4 words.
      final e = ex(tokens: ['every morning', 'he', 'works'], phrase: 'He works every morning.');
      await pump(tester, e);
      await place(tester, 'he');
      await place(tester, 'works');
      expect(checkEnabled(tester), isFalse, reason: 'still one piece short');
      await place(tester, 'every morning');
      expect(checkEnabled(tester), isTrue);
    });

    testWidgets('assembling it in order is graded correct', (tester) async {
      bool? result;
      final e = ex(tokens: ['every morning', 'he', 'works'], phrase: 'He works every morning.');
      await pump(tester, e, onAnswered: (r) => result = r);
      for (final w in ['he', 'works', 'every morning']) {
        await place(tester, w);
      }
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(result, isTrue);
    });
  });

  group('distractor words — more pieces than the phrase has words', () {
    testWidgets('the phrase can be submitted with the distractors left alone', (tester) async {
      bool? result;
      final e = ex(tokens: ['Ich', 'bin', 'müde.', 'Hund', 'Katze'], phrase: 'Ich bin müde.');
      await pump(tester, e, onAnswered: (r) => result = r);
      await place(tester, 'Ich');
      await place(tester, 'bin');
      expect(checkEnabled(tester), isFalse);
      await place(tester, 'müde.');
      expect(checkEnabled(tester), isTrue, reason: 'phrase complete — distractors stay in the bank');
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(result, isTrue);
    });

    testWidgets('using a distractor instead of a real word is graded wrong', (tester) async {
      bool? result;
      final e = ex(tokens: ['Ich', 'bin', 'müde.', 'Hund', 'Katze'], phrase: 'Ich bin müde.');
      await pump(tester, e, onAnswered: (r) => result = r);
      for (final w in ['Ich', 'bin', 'Hund']) {
        await place(tester, w);
      }
      expect(checkEnabled(tester), isTrue);
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(result, isFalse);
    });

    testWidgets('placing every piece, distractors included, is still gradeable and wrong', (tester) async {
      bool? result;
      final e = ex(tokens: ['Ich', 'bin', 'müde.', 'Hund', 'Katze'], phrase: 'Ich bin müde.');
      await pump(tester, e, onAnswered: (r) => result = r);
      for (final w in ['Ich', 'bin', 'müde.', 'Hund', 'Katze']) {
        await place(tester, w);
      }
      expect(checkEnabled(tester), isTrue, reason: 'the old all-pieces rule still applies');
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(result, isFalse);
    });
  });
}

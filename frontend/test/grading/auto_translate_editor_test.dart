import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/features/admin/course_builder/domain/block_question.dart';
import 'package:deutsch_lernen/features/admin/course_builder/presentation/widgets/question_kind_editors.dart';

/// Test 11's UI half: the "Количество вопросов" field must hold whole
/// numbers only. The server validates it too — this checks the input itself
/// can't even produce anything else.
void main() {
  late QuestionDraft? saved;

  Future<void> pump(WidgetTester tester, {AutoTranslateDraft? initial, int? poolSize}) async {
    saved = null;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AutoTranslateEditor(
          draft: initial ?? AutoTranslateDraft.blank(),
          poolSize: poolSize,
          onChanged: (d) => saved = d,
        ),
      ),
    ));
  }

  Finder countField() => find.byType(TextField);

  group('количество вопросов — только целое число', () {
    testWidgets('целое число принимается', (tester) async {
      await pump(tester);
      await tester.enterText(countField(), '7');
      await tester.pump();
      expect((saved as AutoTranslateDraft).count, 7);
    });

    testWidgets('буквы не попадают в поле', (tester) async {
      await pump(tester);
      await tester.enterText(countField(), 'abc');
      await tester.pump();
      expect(tester.widget<TextField>(countField()).controller?.text ?? '', isEmpty);
    });

    testWidgets('дробное значение теряет разделитель, остаются цифры', (tester) async {
      await pump(tester);
      await tester.enterText(countField(), '2.5');
      await tester.pump();
      final text = tester.widget<TextField>(countField()).controller?.text ?? '';
      expect(text.contains('.'), isFalse, reason: 'разделитель не должен приниматься');
      expect((saved as AutoTranslateDraft).count, isA<int>());
    });

    testWidgets('произвольный текст не принимается', (tester) async {
      await pump(tester);
      await tester.enterText(countField(), 'пять вопросов');
      await tester.pump();
      expect(tester.widget<TextField>(countField()).controller?.text ?? '', isEmpty);
    });

    testWidgets('минус не принимается — отрицательное число ввести нельзя', (tester) async {
      await pump(tester);
      await tester.enterText(countField(), '-3');
      await tester.pump();
      final text = tester.widget<TextField>(countField()).controller?.text ?? '';
      expect(text.contains('-'), isFalse);
    });
  });

  group('источник', () {
    testWidgets('оба источника предлагаются', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<WordPoolSource>));
      await tester.pumpAndSettle();
      expect(find.text('Из этого урока').hitTestable(), findsWidgets);
      expect(find.text('Из изученных слов пользователя').hitTestable(), findsWidgets);
    });

    testWidgets('выбранный источник попадает в черновик', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<WordPoolSource>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Из изученных слов пользователя').last);
      await tester.pumpAndSettle();
      expect((saved as AutoTranslateDraft).source, WordPoolSource.learned);
    });
  });

  group('подсказка про размер пула', () {
    testWidgets('показывает доступное количество слов', (tester) async {
      await pump(tester, poolSize: 10);
      expect(find.textContaining('Доступно слов в источнике: 10'), findsOneWidget);
    });

    testWidgets('предупреждает, когда запрошено больше, чем есть', (tester) async {
      await pump(tester, initial: const AutoTranslateDraft(source: WordPoolSource.lesson, count: 15), poolSize: 10);
      expect(find.textContaining('будет показано не более 10'), findsOneWidget);
    });

    testWidgets('не предупреждает, когда запрошено в пределах пула', (tester) async {
      await pump(tester, initial: const AutoTranslateDraft(source: WordPoolSource.lesson, count: 5), poolSize: 10);
      expect(find.textContaining('будет показано не более'), findsNothing);
    });
  });

  group('wire-формат', () {
    test('черновик сохраняется только как источник + количество', () {
      final wire = const AutoTranslateDraft(source: WordPoolSource.learned, count: 4).toWire();
      expect(wire, {'kind': 'auto_translate', 'source': 'learned', 'count': 4});
      // Никаких слов, правильных ответов или вариантов — они решаются на
      // сервере для каждого прохождения.
      expect(wire.containsKey('options'), isFalse);
      expect(wire.containsKey('correctAnswer'), isFalse);
    });

    test('черновик восстанавливается из сохранённого вида', () {
      final d = questionDraftFromWire({'kind': 'auto_translate', 'source': 'learned', 'count': 6}) as AutoTranslateDraft;
      expect(d.source, WordPoolSource.learned);
      expect(d.count, 6);
    });

    test('неизвестный источник откатывается к безопасному значению', () {
      final d = questionDraftFromWire({'kind': 'auto_translate', 'source': 'nonsense', 'count': 2}) as AutoTranslateDraft;
      expect(d.source, WordPoolSource.lesson);
    });
  });
}

// The read-only rail view for a graph-converted lesson must actually be
// read-only — not just visually dimmed (§ graph/rail toggle, 2026-09-03).
//
// _LessonContentView (builder_lesson_edit_screen.dart) is private, so this
// isolates the one property that matters for data safety: wrapping content
// in IgnorePointer genuinely blocks every tap from reaching it. That
// guarantee is why the rail can safely reuse LessonEditorPanel unmodified
// instead of threading a read-only flag through every child editor
// (VocabularyEditor/MaterialBlockEditor/MediaEditor/BlockEditor) — a single
// missed flag there would let an edit through and silently widen the
// video/audio/material fork this feature exists to prevent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('IgnorePointer действительно блокирует нажатие', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IgnorePointer(
          child: ElevatedButton(onPressed: () => taps++, child: const Text('Добавить блок')),
        ),
      ),
    ));

    await tester.tap(find.text('Добавить блок'));
    await tester.pump();

    expect(taps, 0, reason: 'просмотровый режим не должен пропускать нажатия к кнопкам редактирования');
  });

  testWidgets('без IgnorePointer то же нажатие проходит (контрольная проверка)', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ElevatedButton(onPressed: () => taps++, child: const Text('Добавить блок')),
      ),
    ));

    await tester.tap(find.text('Добавить блок'));
    await tester.pump();

    expect(taps, 1, reason: 'контроль: без обёртки то же нажатие должно срабатывать');
  });

  testWidgets('переключение между двумя видами меняет только активный, данные обоих сохраняются', (tester) async {
    var edits = 0;
    var graphTaps = 0;

    Widget harness(bool showLinear) => MaterialApp(
          home: Scaffold(
            body: showLinear
                ? IgnorePointer(child: ElevatedButton(onPressed: () => edits++, child: const Text('Изменить (линейный)')))
                : ElevatedButton(onPressed: () => graphTaps++, child: const Text('Изменить (граф)')),
          ),
        );

    await tester.pumpWidget(harness(false));
    await tester.tap(find.text('Изменить (граф)'));
    await tester.pump();
    expect(graphTaps, 1);

    await tester.pumpWidget(harness(true));
    expect(find.text('Изменить (граф)'), findsNothing);
    await tester.tap(find.text('Изменить (линейный)'));
    await tester.pump();
    expect(edits, 0, reason: 'после переключения в просмотр редактирование не проходит');
  });
}

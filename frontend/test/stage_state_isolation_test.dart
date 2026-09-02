// Each quiz stage must get its own State (§ review stage reused practice's
// state, 2026-09-02).
//
// minitest, practice and review are all ExerciseStage behind one route,
// `/lesson/:lessonId/:stage`. go_router keys a page by the route PATTERN,
// not by the filled-in location, so without an explicit key Flutter matched
// the Elements across a stage change and kept the old State — its `late
// final` exercise list and its `_finished` flag included. Review then opened
// already-finished on practice's questions and saved practice's score as its
// own. These tests pin down both halves: the failure mode, and the fix.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

int statesCreated = 0;

class _Stage extends StatefulWidget {
  const _Stage({super.key, required this.stage});

  final String stage;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  // Stands in for ExerciseStage's `late final _exercises`: resolved once,
  // from whichever stage this State was born for.
  late final String capturedAtInit = widget.stage;

  @override
  void initState() {
    super.initState();
    statesCreated += 1;
  }

  @override
  Widget build(BuildContext context) =>
      Text('${widget.stage}|$capturedAtInit', textDirection: TextDirection.ltr);
}

GoRouter _router({required bool keyed}) => GoRouter(
      initialLocation: '/lesson/L1/practice',
      routes: [
        GoRoute(
          path: '/lesson/:lessonId/:stage',
          builder: (context, state) {
            final stage = state.pathParameters['stage']!;
            return _Stage(key: keyed ? ValueKey(stage) : null, stage: stage);
          },
        ),
      ],
    );

void main() {
  testWidgets('без ключа состояние переиспользуется — этап приносит чужие данные', (tester) async {
    statesCreated = 0;
    final router = _router(keyed: false);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('/lesson/L1/review');
    await tester.pumpAndSettle();

    // The widget says "review" while the data inside is still practice's —
    // exactly the bug, kept here so a regression is visible rather than
    // silent.
    expect(find.text('review|practice'), findsOneWidget);
    expect(statesCreated, 1);
  });

  testWidgets('с ключом по этапу каждый этап получает своё состояние', (tester) async {
    statesCreated = 0;
    final router = _router(keyed: true);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('practice|practice'), findsOneWidget);

    router.go('/lesson/L1/review');
    await tester.pumpAndSettle();
    expect(find.text('review|review'), findsOneWidget);
    expect(statesCreated, 2);
  });

  testWidgets('с ключом переход мини-тест -> практика -> закрепление даёт три состояния', (tester) async {
    statesCreated = 0;
    final router = GoRouter(
      initialLocation: '/lesson/L1/minitest',
      routes: [
        GoRoute(
          path: '/lesson/:lessonId/:stage',
          builder: (context, state) {
            final stage = state.pathParameters['stage']!;
            return _Stage(key: ValueKey(stage), stage: stage);
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    for (final stage in ['practice', 'review']) {
      router.go('/lesson/L1/$stage');
      await tester.pumpAndSettle();
      expect(find.text('$stage|$stage'), findsOneWidget);
    }
    expect(statesCreated, 3);
  });
}

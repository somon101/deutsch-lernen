// "Выйти из графа" must behave like the screen's own back button
// (§ graph exit navigation, 2026-09-03).
//
// LessonGraphEditor is a widget swapped in by `lesson.graph != null`, not a
// pushed route — so its old `onExit: () => Navigator.of(context).maybePop()`
// had nothing reliable of its own to pop. Inside this app's ShellRoute that
// either did nothing or left the admin on a screen they didn't ask for,
// instead of returning to the regular course editor. The fix mirrors
// BuilderLessonEditScreen's own AppBar back button exactly: pop if there is
// something to pop, else `context.go` to the course editor explicitly.
//
// Building the real LessonGraphEditor here would mean standing up its
// BuilderRepository/AdminLesson/canvas dependencies just to exercise one
// navigation decision — so this isolates that decision in a minimal harness
// with the identical shape, the same approach already used for the
// same-class bug in stage_state_isolation_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void _exit(BuildContext context, String courseId) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
  } else {
    context.go('/admin/builder/$courseId');
  }
}

class _GraphScreen extends StatelessWidget {
  const _GraphScreen({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(onPressed: () => _exit(context, courseId), child: const Text('Выйти из графа')),
      ),
    );
  }
}

void main() {
  testWidgets('без стека навигации — явный переход на редактор курса', (tester) async {
    final router = GoRouter(
      initialLocation: '/admin/builder/c1/lesson/l1',
      routes: [
        GoRoute(path: '/admin/builder/:courseId', builder: (context, state) => const Scaffold(body: Text('Редактор курса'))),
        GoRoute(
          path: '/admin/builder/:courseId/lesson/:lessonId',
          builder: (context, state) => _GraphScreen(courseId: state.pathParameters['courseId']!),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выйти из графа'));
    await tester.pumpAndSettle();

    expect(find.text('Редактор курса'), findsOneWidget);
  });

  testWidgets('со стеком навигации — обычный pop, без лишнего перехода', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Scaffold(body: Text('Список уроков')),
    ));
    await tester.pumpAndSettle();

    navKey.currentState!.push(MaterialPageRoute(builder: (context) => _GraphScreen(courseId: 'c1')));
    await tester.pumpAndSettle();
    expect(find.text('Выйти из графа'), findsOneWidget);

    await tester.tap(find.text('Выйти из графа'));
    await tester.pumpAndSettle();

    expect(find.text('Список уроков'), findsOneWidget);
    expect(find.text('Выйти из графа'), findsNothing);
  });
}

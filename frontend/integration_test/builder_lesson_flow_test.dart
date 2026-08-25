// Phase 7 gap-check: a published builder-course lesson had never been taken
// end-to-end as a learner (Phase 5's lesson_flow_test only ever exercised
// the legacy course). Drives: admin creates+publishes a bare course+lesson
// -> as a learner, opens it via /courses -> walks all 8 stages through
// their "nothing here yet, skip" paths (no material/video/audio/questions
// were authored) -> reaches the completion screen -> cleans up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:deutsch_lernen/app.dart';
import 'package:deutsch_lernen/core/auth/secure_storage.dart';
import 'package:deutsch_lernen/core/auth/user.dart';

class _InMemorySecureStorage implements SecureStorage {
  String? token;
  AppUser? user;
  String? theme;

  @override
  Future<String?> readToken() async => token;
  @override
  Future<AppUser?> readUser() async => user;
  @override
  Future<void> saveAuth(String newToken, AppUser newUser) async {
    token = newToken;
    user = newUser;
  }

  @override
  Future<void> clearAuth() async {
    token = null;
    user = null;
  }

  @override
  Future<String?> readTheme() async => theme;
  @override
  Future<void> saveTheme(String value) async => theme = value;
}

Future<void> _scrollToVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final list = find.byType(ListView).first;
    for (var i = 0; i < 25; i++) {
      await tester.drag(list, const Offset(0, -260));
      await tester.pumpAndSettle();
      if (finder.evaluate().isNotEmpty) break;
    }
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await _scrollToVisible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Every stage's "there's nothing authored here" screen uses one of these
/// two labels (see vocabulary/material/video/audio/exercise stage widgets)
/// — taps whichever is currently on screen.
Future<void> _tapContinue(WidgetTester tester) async {
  const candidates = ['Далее', 'Пропустить и продолжить'];
  for (final label in candidates) {
    final finder = find.text(label);
    if (finder.evaluate().isNotEmpty) {
      await _tapAndSettle(tester, finder);
      return;
    }
  }
  // Not yet built (below the fold) — scroll and retry each candidate once.
  for (final label in candidates) {
    final finder = find.text(label);
    await _scrollToVisible(tester, finder);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      return;
    }
  }
  fail('No continue/skip button found on the current stage');
}

const _courseTitle = 'QA Builder Lesson IT01';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a published builder-course lesson can be taken start to finish as a learner', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_InMemorySecureStorage())],
        child: const DeutschLernenApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'ChangeMe123!');
    await _tapAndSettle(tester, find.text('Войти'));

    // --- Admin: create course, add lesson, publish -------------------------
    await _tapAndSettle(tester, find.text('Конструктор курсов'));
    await tester.enterText(find.widgetWithText(TextField, 'Название'), _courseTitle);
    await _tapAndSettle(tester, find.text('Создать курс'));
    await _scrollToVisible(tester, find.text('Открыть'));
    await _tapAndSettle(tester, find.text('Открыть'));

    await tester.enterText(find.widgetWithText(TextField, 'Название нового урока'), 'QA Lesson');
    await _tapAndSettle(tester, find.text('+ Добавить урок'));
    await _expectFound(tester, find.textContaining('QA Lesson'));

    await _tapAndSettle(tester, find.text('Опубликовать курс'));
    await _expectFound(tester, find.text('Вернуть в черновики'));

    // --- Learner: open the course from the courses hub ---------------------
    await _tapAndSettle(tester, find.byIcon(Icons.arrow_back).first); // -> hub
    await _tapAndSettle(tester, find.byIcon(Icons.arrow_back).first); // -> Home
    await _tapAndSettle(tester, find.text('Курсы'));
    await _tapAndSettle(tester, find.textContaining(_courseTitle));

    await _tapAndSettle(tester, find.textContaining('QA Lesson'));

    // Walk all 8 stages — nothing was authored, so every stage should
    // offer an immediate skip/continue path straight through to the end.
    for (var i = 0; i < 7; i++) {
      await _tapContinue(tester);
    }
    await _expectFound(tester, find.text('Отличная работа!'));

    // --- Cleanup: delete the QA course --------------------------------
    await _tapAndSettle(tester, find.text('На главную'));
    await _tapAndSettle(tester, find.text('Конструктор курсов'));
    final deleteButton = find.ancestor(of: find.byIcon(Icons.delete_outline), matching: find.byType(IconButton));
    await _tapAndSettle(tester, deleteButton.first);
    await _tapAndSettle(tester, find.text('Удалить').last);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text(_courseTitle), findsNothing);
  });
}

Future<void> _expectFound(WidgetTester tester, Finder finder) async {
  await _scrollToVisible(tester, finder);
  expect(finder, findsOneWidget);
}

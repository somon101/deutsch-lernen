// Drives the new Phase 6 admin panel against the live FastAPI backend:
// user list -> user detail, and the course builder's core create/edit/
// delete loop (course -> lesson -> vocabulary word -> block+question ->
// save), with cleanup at the end so the dev DB ends the run exactly as it
// started (matches the Phase 3 checkpoint's own "0 courses on both
// backends" discipline).
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

// These admin screens are long ListViews once a lesson/block is expanded —
// Flutter only mounts elements near the current viewport (even for a plain
// ListView(children: ...), not just .builder ones), so a target further
// down the page doesn't exist in the widget tree at all until scrolled
// into range. Neither tap() nor expect() scroll on their own, so every
// interaction with content that might be off-screen goes through one of
// these two helpers instead of a bare find.

Future<void> _scrollToVisible(WidgetTester tester, Finder finder) async {
  // Drags the page's own ListView directly rather than using
  // scrollUntilVisible's `scrollable:` finder, which — on a screen with
  // several TextFields above the target — was ambiguous enough to pick an
  // unrelated internal Scrollable and never find anything real.
  if (finder.evaluate().isEmpty) {
    final list = find.byType(ListView).first;
    for (var i = 0; i < 25; i++) {
      await tester.drag(list, const Offset(0, -260));
      await tester.pumpAndSettle();
      if (finder.evaluate().isNotEmpty) break;
    }
  }
  // Being present in the element tree isn't the same as being painted
  // inside the viewport — ListView keeps a cache extent of built-but-
  // offscreen children, which fails a real tap/hit-test. ensureVisible
  // nudges the scroll offset so an already-built element is actually shown.
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await _scrollToVisible(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

Future<void> _expectVisible(WidgetTester tester, Finder finder) async {
  await _scrollToVisible(tester, finder);
  expect(finder, findsOneWidget);
}

const _courseTitle = 'QA Course IT01';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin: users list -> user detail -> back', (tester) async {
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
    expect(find.text('Курсы'), findsOneWidget);

    await _tapAndSettle(tester, find.text('Пользователи'));
    expect(find.textContaining('Все пользователи ('), findsOneWidget);
    expect(find.textContaining('@admin'), findsOneWidget);

    final adminTile = find.ancestor(of: find.textContaining('@admin'), matching: find.byType(ListTile));
    await _tapAndSettle(tester, adminTile);

    expect(find.text('Пользователь'), findsOneWidget); // AppBar title on the detail screen
    // Checked in on-page top-to-bottom order — the note sits right under
    // the online/last-login block, above the edit form and reset-password
    // card, so this scrolls monotonically down instead of ever needing to
    // backtrack up.
    await _expectVisible(tester, find.textContaining('снять с себя роль администратора'));
    await _expectVisible(tester, find.text('Сброс пароля'));

    await _tapAndSettle(tester, find.byIcon(Icons.arrow_back).first);
    expect(find.textContaining('Все пользователи ('), findsOneWidget);
    await _tapAndSettle(tester, find.byIcon(Icons.arrow_back).first);
    expect(find.text('Курсы'), findsOneWidget);
  });

  testWidgets('admin: course builder create -> lesson -> word -> block+question -> delete', (tester) async {
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

    await _tapAndSettle(tester, find.text('Конструктор курсов'));
    expect(find.text('Новый курс'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Название'), _courseTitle);
    await tester.enterText(find.widgetWithText(TextField, 'Описание (необязательно)'), 'Created by integration_test');
    await _tapAndSettle(tester, find.text('Создать курс'));
    await _expectVisible(tester, find.text(_courseTitle));

    await _tapAndSettle(tester, find.text('Открыть'));
    expect(find.text('Название'), findsOneWidget); // course settings card

    // Add a lesson.
    await tester.enterText(find.widgetWithText(TextField, 'Название нового урока'), 'QA Lesson');
    await _tapAndSettle(tester, find.text('+ Добавить урок'));
    await _expectVisible(tester, find.textContaining('QA Lesson'));

    // Expand the lesson — its "Слова" (vocabulary) section is open by
    // default, per LessonEditorPanel's initial _open state.
    await _tapAndSettle(tester, find.textContaining('QA Lesson'));
    await _expectVisible(tester, find.text('Слова'));

    await _scrollToVisible(tester, find.widgetWithText(TextField, 'Немецкий').first);
    await tester.enterText(find.widgetWithText(TextField, 'Немецкий').first, 'Testwort');
    await tester.enterText(find.widgetWithText(TextField, 'Перевод').first, 'тестовое слово');
    await tester.enterText(find.widgetWithText(TextField, 'Транскрипция').first, 'тестворт');
    await tester.pumpAndSettle();
    await _tapAndSettle(tester, find.text('+ Добавить'));
    await _expectVisible(tester, find.text('Testwort'));

    // Minitest: add a block, add a choice question, save.
    await _tapAndSettle(tester, find.text('Мини-тест'));
    await _tapAndSettle(tester, find.text('+ Добавить мини-тест'));
    await _expectVisible(tester, find.textContaining('Мини-тест 1'));

    await _tapAndSettle(tester, find.textContaining('Мини-тест 1 ('));
    await _tapAndSettle(tester, find.text('Вопрос с вариантами'));

    final promptField = find.widgetWithText(TextField, 'Вопрос');
    await _scrollToVisible(tester, promptField);
    expect(promptField, findsOneWidget);
    await tester.enterText(promptField, 'Wie geht es?');
    await tester.pumpAndSettle();

    // The blank ChoiceDraft starts with two empty options — the backend
    // correctly rejects empty option text, so both need real values before
    // "Сохранить вопросы" can actually persist anything.
    final option1 = find.widgetWithText(TextField, 'Вариант 1');
    await _scrollToVisible(tester, option1);
    await tester.enterText(option1, 'Gut, danke.');
    await tester.pumpAndSettle();
    final option2 = find.widgetWithText(TextField, 'Вариант 2');
    await _scrollToVisible(tester, option2);
    await tester.enterText(option2, 'Schlecht.');
    await tester.pumpAndSettle();

    await _tapAndSettle(tester, find.text('Сохранить вопросы'));
    // BlockEditor reloads the whole course after a successful save — the
    // block header's question count should now read "(1 вопросов)".
    await _expectVisible(tester, find.textContaining('Мини-тест 1 (1'));

    // --- Cleanup: delete the QA course --------------------------------
    await _tapAndSettle(tester, find.byIcon(Icons.arrow_back).first);
    await _expectVisible(tester, find.text(_courseTitle));

    final deleteButton = find.ancestor(
      of: find.byIcon(Icons.delete_outline),
      matching: find.byType(IconButton),
    );
    await _tapAndSettle(tester, deleteButton.first);
    await _tapAndSettle(tester, find.text('Удалить').last);
    // The dialog closes as soon as it pops, but deleteCourse()'s request
    // and the subsequent list refetch still need to land — an extra settle
    // pass avoids asserting absence against a frame from mid-refetch.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text(_courseTitle), findsNothing);
  });
}

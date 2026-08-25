// Drives the real app end-to-end against the live FastAPI backend
// (localhost:8000, same instance the migration's Phase 1-3 checkpoints
// used) — verifies the login screen -> Home navigation actually works,
// without any OS-level input (Flutter's WidgetTester synthesizes events at
// the engine level, so this never touches real window focus/keyboard,
// unlike SendKeys-style automation).
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login with real admin credentials navigates to Home', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_InMemorySecureStorage())],
        child: const DeutschLernenApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Войти'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'ChangeMe123!');
    await tester.tap(find.text('Войти'));

    // Network round trip to the real backend.
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Курсы'), findsOneWidget);
    expect(find.text('Выйти'), findsOneWidget);

    // Log back out — should bounce to the login screen, not stay on Home.
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(find.text('Войти'), findsOneWidget);
  });

  testWidgets('no session redirects straight to login, even mid-app', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_InMemorySecureStorage())],
        child: const DeutschLernenApp(),
      ),
    );
    await tester.pumpAndSettle();

    // initialLocation is "/" (Home) but with no session the redirect
    // callback should have bounced to /login before Home ever painted.
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Курсы'), findsNothing);
  });
}

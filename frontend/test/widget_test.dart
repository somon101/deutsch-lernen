import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:payroha/app.dart';
import 'package:payroha/core/auth/secure_storage.dart';
import 'package:payroha/core/auth/user.dart';

/// In-memory stand-in for SecureStorage — flutter_secure_storage needs a
/// real platform channel, which isn't available under flutter_test.
class _FakeSecureStorage implements SecureStorage {
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
  testWidgets('shows the login screen when no session is stored', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_FakeSecureStorage())],
        child: const PayrohaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payroha'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
  });
}

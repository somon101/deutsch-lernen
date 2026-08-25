import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/core/auth/auth_state.dart';
import 'package:deutsch_lernen/core/auth/secure_storage.dart';
import 'package:deutsch_lernen/core/auth/user.dart';
import 'package:deutsch_lernen/features/profile/presentation/profile_qr_screen.dart';
import 'package:deutsch_lernen/l10n/app_localizations.dart';

class _FakeSecureStorage implements SecureStorage {
  _FakeSecureStorage(this.user);
  AppUser? user;
  String? token = 'fake-token';
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

final _testUser = AppUser(
  id: 'uuid-should-never-render',
  publicId: '004213087',
  firstName: 'Иван',
  lastName: 'Иванов',
  email: 'a@b.com',
  phone: null,
  username: 'ivan',
  role: UserRole.user,
  status: UserStatus.active,
  avatarUrl: null,
  bio: null,
  birthDate: null,
  canEditProfile: true,
  lastLoginAt: null,
  lastActiveAt: null,
);

void main() {
  testWidgets('Copy ID button copies the 9-digit publicId, not the UUID', (tester) async {
    // flutter_test's default binding mocks Clipboard.setData but not
    // Clipboard.getData (it just hangs with no handler registered) —
    // fake both ends of the platform channel so the roundtrip actually
    // completes in the test environment.
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': clipboardText};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.binding.setSurfaceSize(const Size(400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_FakeSecureStorage(_testUser))],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileQrScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pumpAndSettle();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, '004213087');
    expect(clipboard?.text, isNot(contains('uuid-should-never-render')));
  });
}

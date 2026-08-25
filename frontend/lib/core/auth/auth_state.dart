import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'secure_storage.dart';
import 'user.dart';

/// Mirrors src/auth/AuthContext.tsx: user state restored from storage on
/// startup (no login flash on relaunch), login()/logout(), and a way to
/// patch the cached user after a profile edit without a full refetch (see
/// updateLocalUser in the React version).
class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final storage = ref.read(secureStorageProvider);
    final token = await storage.readToken();
    if (token == null) return null;
    return storage.readUser();
  }

  Future<void> login(String login, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/api/auth/login', body: {'login': login, 'password': password});
      final token = res['token'] as String;
      final user = AppUser.fromJson(res['user'] as Map<String, dynamic>);
      await ref.read(secureStorageProvider).saveAuth(token, user);
      return user;
    });
    if (state.hasError) {
      // Re-throw so the login screen's try/catch can show the message —
      // AsyncValue.guard already captured it into state for other watchers.
      throw state.error!;
    }
  }

  Future<void> logout() async {
    await ref.read(secureStorageProvider).clearAuth();
    state = const AsyncData(null);
  }

  /// Mirrors updateLocalUser() — patches the cached user (e.g. after a
  /// profile/avatar edit) without a round trip through login().
  Future<void> updateLocalUser(AppUser user) async {
    final token = await ref.read(secureStorageProvider).readToken();
    if (token == null) return;
    await ref.read(secureStorageProvider).saveAuth(token, user);
    state = AsyncData(user);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);

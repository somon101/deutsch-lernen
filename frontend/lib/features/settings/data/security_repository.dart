import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LinkedProvider { google, apple }

/// Self-service password/email change and account deletion have no backend
/// endpoints today — only POST /api/auth/login and the admin-only
/// reset-password route exist (see backend/app/routers/auth.py,
/// backend/app/routers/admin.py). Every method here is a working-looking
/// stub over local state, matched in shape to what a real implementation
/// would need, so the screen doesn't have to change when the endpoints
/// exist. Phone is the one exception — User.phone is already a real,
/// backend-backed field, so SecurityPrivacyScreen calls
/// ProfileRepository.updateProfile for that one instead of anything here.
class SecurityRepository {
  const SecurityRepository();

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // TODO: подключить API — POST /api/me/password не существует.
  }

  Future<void> requestEmailChange(String newEmail) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // TODO: подключить API — отправка кода подтверждения на бэкенде не реализована.
  }

  Future<void> confirmEmailChange(String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // TODO: подключить API — подтверждение кода на бэкенде не реализовано.
  }

  Future<void> deleteAccount() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // TODO: подключить API — самостоятельное удаление аккаунта не реализовано.
  }
}

final securityRepositoryProvider = Provider<SecurityRepository>((ref) => const SecurityRepository());

/// TODO: подключить API — OAuth (Google/Apple) не реализован в бэкенде
/// вообще, ни модели, ни роутов. Локальное состояние только для того,
/// чтобы экран выглядел рабочим.
class LinkedAccountsNotifier extends Notifier<Set<LinkedProvider>> {
  @override
  Set<LinkedProvider> build() => const {};

  void toggle(LinkedProvider provider) {
    state = state.contains(provider) ? ({...state}..remove(provider)) : ({...state}..add(provider));
  }
}

final linkedAccountsProvider = NotifierProvider<LinkedAccountsNotifier, Set<LinkedProvider>>(LinkedAccountsNotifier.new);

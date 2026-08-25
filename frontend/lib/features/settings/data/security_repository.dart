import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LinkedProvider { google, apple }

/// Self-service account deletion has no backend endpoint today (see
/// backend/app/routers/auth.py, backend/app/routers/admin.py). Password
/// change (PATCH /api/me/password) and email change (PATCH /api/me/ via
/// ProfileRepository.updateProfile) are real now — SecurityPrivacyScreen
/// calls ProfileRepository directly for those, not this class.
class SecurityRepository {
  const SecurityRepository();

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

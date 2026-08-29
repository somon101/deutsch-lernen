import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// The admin-facing on/off switch for automatic push sending — one boolean
/// per event type (only "on new lesson" exists today; a future event adds
/// a field here, not a new repository).
class NotificationSettingsRepository {
  NotificationSettingsRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/admin/notification-settings';

  Future<bool> getAutoSendOnNewLesson() async {
    final res = await _api.get(_base);
    return (res['settings'] as Map<String, dynamic>)['autoSendOnNewLesson'] as bool;
  }

  Future<bool> setAutoSendOnNewLesson(bool value) async {
    final res = await _api.patch(_base, body: {'autoSendOnNewLesson': value});
    return (res['settings'] as Map<String, dynamic>)['autoSendOnNewLesson'] as bool;
  }
}

final notificationSettingsRepositoryProvider = Provider<NotificationSettingsRepository>(
  (ref) => NotificationSettingsRepository(ref.watch(apiClientProvider)),
);

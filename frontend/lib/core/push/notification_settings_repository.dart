import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// The admin-facing on/off switches for automatic push sending — one
/// boolean per mechanism. `autoSendOnNewLesson` gates the "new lesson"
/// broadcast; `streakReminderEnabled` (§ streak reminder, 2026-09-15)
/// gates the streak-at-risk push chain — the only control for that
/// mechanism anywhere, since no per-user setting for it exists at all.
class NotificationSettingsRepository {
  NotificationSettingsRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/admin/notification-settings';

  Future<AdminNotificationSettings> getSettings() async {
    final res = await _api.get(_base);
    return AdminNotificationSettings.fromJson(res['settings'] as Map<String, dynamic>);
  }

  Future<bool> getAutoSendOnNewLesson() async => (await getSettings()).autoSendOnNewLesson;

  Future<bool> setAutoSendOnNewLesson(bool value) async {
    final res = await _api.patch(_base, body: {'autoSendOnNewLesson': value});
    return AdminNotificationSettings.fromJson(res['settings'] as Map<String, dynamic>).autoSendOnNewLesson;
  }

  Future<bool> setStreakReminderEnabled(bool value) async {
    final res = await _api.patch(_base, body: {'streakReminderEnabled': value});
    return AdminNotificationSettings.fromJson(res['settings'] as Map<String, dynamic>).streakReminderEnabled;
  }
}

class AdminNotificationSettings {
  const AdminNotificationSettings({required this.autoSendOnNewLesson, required this.streakReminderEnabled});
  factory AdminNotificationSettings.fromJson(Map<String, dynamic> json) => AdminNotificationSettings(
        autoSendOnNewLesson: json['autoSendOnNewLesson'] as bool,
        streakReminderEnabled: json['streakReminderEnabled'] as bool,
      );
  final bool autoSendOnNewLesson;
  final bool streakReminderEnabled;
}

final notificationSettingsRepositoryProvider = Provider<NotificationSettingsRepository>(
  (ref) => NotificationSettingsRepository(ref.watch(apiClientProvider)),
);

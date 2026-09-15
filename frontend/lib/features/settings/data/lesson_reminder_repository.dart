import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/api/api_client.dart';

/// Server-backed "Push-уведомления" + "Напоминание о занятии" settings (§
/// lesson reminder fix, 2026-09-07).
///
/// Previously local-only SharedPreferences state in settings_repository.dart
/// (that file's own header still said "TODO: подключить API") — which is
/// exactly why the reminder never actually fired: nothing the user set ever
/// reached the server, so nothing server-side could ever check it. Mirrors
/// core/settings/sound_preferences.dart's load-then-patch pattern, the
/// established way this app moves a device-local setting onto the account.
///
/// Delivery briefly moved to a local on-device notification (§ study
/// reminder local delivery, 2026-09-15) and moved back to push the same day:
/// a real Xiaomi/MIUI device test found the local alarm fires but MIUI's own
/// autostart restriction can block the app from completing the notification
/// afterwards, with no in-app way to detect or fix that — see
/// backend/app/services/reminders.py's header for the full story. Push rides
/// Google Play Services' already-whitelisted process, so it isn't affected
/// by that same restriction. This file is back to being pure settings I/O:
/// the actual send now happens server-side (services/reminders.py's
/// run_reminder_tick), which is why `_syncTimezone` below still matters —
/// it's the one signal that server-side tick needs and has no other way to
/// learn.
///
/// `dailyGoalMinutes`/`languageLevel` stay exactly where they were, in
/// settingsProvider — untouched, out of scope for this fix. The unrelated,
/// admin-only streak-at-risk push reminder has no per-user setting at all
/// (see AdminNotificationSettings) — nothing here gates or affects it, by
/// design.
class LessonReminderPreferences {
  const LessonReminderPreferences({
    required this.pushEnabled,
    required this.lessonReminderEnabled,
    required this.lessonReminderHour,
    required this.lessonReminderMinute,
  });

  final bool pushEnabled;
  final bool lessonReminderEnabled;
  final int lessonReminderHour;
  final int lessonReminderMinute;

  /// What a user who has never opened Settings gets — identical to
  /// SettingsPrefs.defaults' own pushNotifications/lessonReminder/
  /// lessonReminderHour/lessonReminderMinute, so migrating this off the
  /// device doesn't change anyone's actual behavior before they touch these
  /// switches again.
  static const defaults = LessonReminderPreferences(
    pushEnabled: true,
    lessonReminderEnabled: false,
    lessonReminderHour: 19,
    lessonReminderMinute: 0,
  );

  LessonReminderPreferences copyWith({bool? pushEnabled, bool? lessonReminderEnabled, int? lessonReminderHour, int? lessonReminderMinute}) =>
      LessonReminderPreferences(
        pushEnabled: pushEnabled ?? this.pushEnabled,
        lessonReminderEnabled: lessonReminderEnabled ?? this.lessonReminderEnabled,
        lessonReminderHour: lessonReminderHour ?? this.lessonReminderHour,
        lessonReminderMinute: lessonReminderMinute ?? this.lessonReminderMinute,
      );

  factory LessonReminderPreferences.fromJson(Map<String, dynamic> json) => LessonReminderPreferences(
        pushEnabled: json['pushEnabled'] as bool? ?? true,
        lessonReminderEnabled: json['lessonReminderEnabled'] as bool? ?? false,
        lessonReminderHour: json['lessonReminderHour'] as int? ?? 19,
        lessonReminderMinute: json['lessonReminderMinute'] as int? ?? 0,
      );
}

class LessonReminderPreferencesNotifier extends Notifier<LessonReminderPreferences> {
  @override
  LessonReminderPreferences build() {
    // Fired and not awaited on purpose, same reasoning as
    // SoundPreferencesNotifier.build(): the defaults are safe to show until
    // the real values arrive.
    Future.microtask(load);
    return LessonReminderPreferences.defaults;
  }

  Future<void> load() async {
    try {
      final json = await ref.read(apiClientProvider).get('/api/me/preferences');
      state = LessonReminderPreferences.fromJson(json);
    } catch (_) {
      // Not signed in yet, or offline — keep whatever is in state.
      return;
    }
    await _syncTimezone();
  }

  /// Applies the change locally first so the switch responds at once, then
  /// asks the server. A rejected save is rolled back rather than left
  /// showing a state that was never stored.
  Future<void> _patch(LessonReminderPreferences next, Map<String, dynamic> body) async {
    final previous = state;
    state = next;
    try {
      final json = await ref.read(apiClientProvider).patch('/api/me/preferences', body: body);
      state = LessonReminderPreferences.fromJson(json);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  Future<void> setPushEnabled(bool value) => _patch(state.copyWith(pushEnabled: value), {'pushEnabled': value});

  Future<void> setLessonReminderEnabled(bool value) =>
      _patch(state.copyWith(lessonReminderEnabled: value), {'lessonReminderEnabled': value});

  Future<void> setLessonReminderTime(int hour, int minute) => _patch(
        state.copyWith(lessonReminderHour: hour, lessonReminderMinute: minute),
        {'lessonReminderHour': hour, 'lessonReminderMinute': minute},
      );

  /// Sends the device's current IANA timezone whenever Settings loads (§
  /// lesson reminder fix, 2026-09-07) — the one signal the backend's
  /// reminder tick needs to compute "is it 08:00 for this user yet" (and
  /// correctly through a DST transition) and has no other way to learn.
  /// Refreshed on every load rather than set once, so a traveling user's
  /// zone stays correct without any manual step. Best-effort: a detection
  /// failure on an unsupported platform must not block the rest of the
  /// settings screen, so it's swallowed same as everything else here.
  Future<void> _syncTimezone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (info.identifier.isEmpty) return;
      await ref.read(apiClientProvider).patch('/api/me/preferences', body: {'timezone': info.identifier});
    } catch (_) {}
  }
}

final lessonReminderPreferencesProvider =
    NotifierProvider<LessonReminderPreferencesNotifier, LessonReminderPreferences>(LessonReminderPreferencesNotifier.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../../core/api/api_client.dart';
import '../../../core/notifications/local_reminder_service.dart';

/// Server-backed "Push-уведомления" + "Напоминание о занятии" settings (§
/// lesson reminder fix, 2026-09-07; delivery moved to a LOCAL device
/// notification §2026-09-15 — see local_reminder_service.dart's own header
/// for why).
///
/// Previously local-only SharedPreferences state in settings_repository.dart
/// (that file's own header still says "TODO: подключить API") — which is
/// exactly why the reminder never actually fired: nothing the user set ever
/// reached the server, so nothing server-side could ever check it. Mirrors
/// core/settings/sound_preferences.dart's load-then-patch pattern, the
/// established way this app moves a device-local setting onto the account.
///
/// The setting itself still lives on the server (so it survives a
/// reinstall/new device), but what actually fires the reminder at the
/// chosen time is now a locally-scheduled OS notification, reconciled
/// against this state after every load/patch — see `_syncLocalSchedule`.
///
/// `dailyGoalMinutes`/`languageLevel`/`streakReminder` stay exactly where
/// they were, in settingsProvider — untouched, out of scope for this fix.
/// The unrelated, admin-only streak-at-risk push reminder has no per-user
/// setting at all (see AdminNotificationSettings) — nothing here gates or
/// affects it, by design.
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
      // Not signed in yet, or offline — keep whatever is in state, and
      // don't touch the local schedule: on a genuine offline app start
      // the last OS-level schedule (from the previous successful load) is
      // exactly what should keep firing, not something this failed
      // request should cancel or guess about.
      return;
    }
    await _syncTimezone();
    await _syncLocalSchedule();
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
    await _syncLocalSchedule();
  }

  /// Reconciles the OS-level local notification against the current state
  /// (§ study reminder local delivery, 2026-09-15) — the actual mechanism
  /// behind "изменение времени должно сразу перепланировать локальное
  /// уведомление" / "выключение должно отменять локальное уведомление".
  /// Called after every successful load/patch, so the schedule can never
  /// drift from what Settings currently shows: on by itself is not enough,
  /// the master "Push-уведомления" switch has to be on too, matching how
  /// that switch already reads to the user as "notifications, in general".
  Future<void> _syncLocalSchedule() async {
    final s = state;
    if (s.pushEnabled && s.lessonReminderEnabled) {
      await LocalReminderService.scheduleStudyReminder(hour: s.lessonReminderHour, minute: s.lessonReminderMinute);
    } else {
      await LocalReminderService.cancelStudyReminder();
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

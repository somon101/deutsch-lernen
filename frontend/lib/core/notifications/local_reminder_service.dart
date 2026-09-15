import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local, on-device delivery for the "Напоминание об учёбе" (study
/// reminder) — §2 of the two-reminder split, 2026-09-15.
///
/// This is deliberately the ONLY delivery path for that reminder: it used
/// to be a server push (services/reminders.py's run_reminder_tick, now
/// retired — see that file's own updated header), which meant it could
/// never fire without connectivity and a live cron tick. A local
/// notification is scheduled directly with the OS (AlarmManager on
/// Android), so it fires exactly on time whether or not the app, the
/// server, or the network are reachable at that moment — matching "не
/// должно зависеть от доступности сервера или интернета" precisely.
///
/// Fixed notification id (`_studyReminderId`) is what makes rescheduling
/// idempotent: scheduling again with the same id replaces the previous
/// schedule instead of stacking a second one, so a settings change is
/// always "the one active schedule," never an accumulation.
///
/// Platform reality, stated plainly rather than assumed:
///  - Android: full daily-repeat support via `matchDateTimeComponents:
///    DateTimeComponents.time`, and — with the boot-receiver declared in
///    AndroidManifest.xml — survives a real device reboot, not just an
///    app restart.
///  - Windows: the underlying plugin does NOT support automatic daily
///    repeat on this platform (its own doc comment on zonedSchedule says
///    so explicitly) — this schedules the next single occurrence, and
///    _syncFromServer's re-schedule-on-every-load (see
///    lesson_reminder_repository.dart) re-arms the next one each time the
///    app is opened. So on Windows this only stays reliable if the app is
///    opened at least once between firings — a real, disclosed limitation,
///    not a silent gap.
///  - Web: no true background scheduling exists in a browser without a
///    service worker + Push API (a fundamentally different, server-driven
///    mechanism) — initialization here is a safe no-op so nothing crashes,
///    but a closed browser tab will never show this notification.
class LocalReminderService {
  LocalReminderService._();

  static const _studyReminderId = 9001;
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get _supportsRealScheduling =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.windows);

  /// Must run once at app startup, before any schedule/cancel call — mirrors
  /// push_service.dart's own initializePushIfSupported shape. Safe to call
  /// on every platform; a failure here (e.g. no notification channel
  /// support on this exact device/build) is swallowed, matching this
  /// codebase's "a notification feature failing must never stop the app
  /// from starting" convention.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(settings: initSettings);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _initialized = true;
    } catch (e) {
      developer.log('LocalReminderService.initialize failed: $e', name: 'LocalReminderService');
    }
  }

  static Future<tz.Location> _deviceLocation() async {
    final name = await FlutterTimezone.getLocalTimezone();
    return tz.getLocation(name.identifier);
  }

  /// (Re)schedules the daily study reminder at the given local time,
  /// replacing whatever was scheduled before under the same id. Called
  /// whenever the setting is turned on or its time changes, and once at
  /// app startup to reconcile against whatever the server last reported
  /// (§ "после перезапуска приложения расписание не должно теряться" —
  /// this reconciliation, not OS persistence alone, is what actually
  /// guarantees that: even if the OS-level alarm somehow didn't survive,
  /// the next app open re-arms it from the same server-synced setting).
  static Future<void> scheduleStudyReminder({required int hour, required int minute}) async {
    if (!_supportsRealScheduling) return;
    try {
      await initialize();
      final location = await _deviceLocation();
      tz.setLocalLocation(location);
      final now = tz.TZDateTime.now(location);
      var scheduled = tz.TZDateTime(location, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

      await _plugin.zonedSchedule(
        id: _studyReminderId,
        title: 'Пора заниматься!',
        body: 'Ты ещё не заходил в уроки сегодня. Не дай своему прогрессу остановиться.',
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'study_reminder',
            'Напоминание об учёбе',
            channelDescription: 'Ежедневное напоминание в выбранное вами время',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      developer.log('scheduleStudyReminder failed: $e', name: 'LocalReminderService');
    }
  }

  /// Cancels the study reminder — called when the toggle is turned off (or
  /// the global "Push-уведомления" master switch is), leaving no dangling
  /// alarm behind.
  static Future<void> cancelStudyReminder() async {
    if (!_supportsRealScheduling) return;
    try {
      await initialize();
      await _plugin.cancel(id: _studyReminderId);
    } catch (e) {
      developer.log('cancelStudyReminder failed: $e', name: 'LocalReminderService');
    }
  }
}

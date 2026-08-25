import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TODO: подключить API — none of this has a backend endpoint yet (no
/// user-preferences table/route exists). Persisted locally in
/// SharedPreferences purely so choices survive an app restart; every
/// setter here is a placeholder for what will eventually be a PATCH to a
/// real preferences endpoint.
enum LanguageLevel { a1, a2, b1, b2, c1, c2 }

extension LanguageLevelLabel on LanguageLevel {
  String get label => switch (this) {
        LanguageLevel.a1 => 'A1',
        LanguageLevel.a2 => 'A2',
        LanguageLevel.b1 => 'B1',
        LanguageLevel.b2 => 'B2',
        LanguageLevel.c1 => 'C1',
        LanguageLevel.c2 => 'C2',
      };
}

class SettingsPrefs {
  const SettingsPrefs({
    required this.dailyGoalMinutes,
    required this.languageLevel,
    required this.lessonSounds,
    required this.wordPronunciation,
    required this.pushNotifications,
    required this.lessonReminder,
    required this.lessonReminderHour,
    required this.lessonReminderMinute,
    required this.streakReminder,
    required this.courseLanguage,
  });

  final int dailyGoalMinutes;
  final LanguageLevel languageLevel;
  final bool lessonSounds;
  final bool wordPronunciation;
  final bool pushNotifications;
  final bool lessonReminder;
  final int lessonReminderHour;
  final int lessonReminderMinute;
  final bool streakReminder;
  final String courseLanguage;

  static const defaults = SettingsPrefs(
    dailyGoalMinutes: 20,
    languageLevel: LanguageLevel.a1,
    lessonSounds: true,
    wordPronunciation: true,
    pushNotifications: true,
    lessonReminder: false,
    lessonReminderHour: 19,
    lessonReminderMinute: 0,
    streakReminder: true,
    courseLanguage: 'Русский',
  );

  SettingsPrefs copyWith({
    int? dailyGoalMinutes,
    LanguageLevel? languageLevel,
    bool? lessonSounds,
    bool? wordPronunciation,
    bool? pushNotifications,
    bool? lessonReminder,
    int? lessonReminderHour,
    int? lessonReminderMinute,
    bool? streakReminder,
    String? courseLanguage,
  }) =>
      SettingsPrefs(
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        languageLevel: languageLevel ?? this.languageLevel,
        lessonSounds: lessonSounds ?? this.lessonSounds,
        wordPronunciation: wordPronunciation ?? this.wordPronunciation,
        pushNotifications: pushNotifications ?? this.pushNotifications,
        lessonReminder: lessonReminder ?? this.lessonReminder,
        lessonReminderHour: lessonReminderHour ?? this.lessonReminderHour,
        lessonReminderMinute: lessonReminderMinute ?? this.lessonReminderMinute,
        streakReminder: streakReminder ?? this.streakReminder,
        courseLanguage: courseLanguage ?? this.courseLanguage,
      );
}

const _kDailyGoal = 'settings_daily_goal';
const _kLevel = 'settings_level';
const _kLessonSounds = 'settings_lesson_sounds';
const _kWordPronunciation = 'settings_word_pronunciation';
const _kPush = 'settings_push';
const _kLessonReminder = 'settings_lesson_reminder';
const _kReminderHour = 'settings_reminder_hour';
const _kReminderMinute = 'settings_reminder_minute';
const _kStreakReminder = 'settings_streak_reminder';
const _kCourseLanguage = 'settings_course_language';

class SettingsNotifier extends Notifier<SettingsPrefs> {
  @override
  SettingsPrefs build() {
    _restore();
    return SettingsPrefs.defaults;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final d = SettingsPrefs.defaults;
    state = SettingsPrefs(
      dailyGoalMinutes: prefs.getInt(_kDailyGoal) ?? d.dailyGoalMinutes,
      languageLevel: LanguageLevel.values.byName(prefs.getString(_kLevel) ?? d.languageLevel.name),
      lessonSounds: prefs.getBool(_kLessonSounds) ?? d.lessonSounds,
      wordPronunciation: prefs.getBool(_kWordPronunciation) ?? d.wordPronunciation,
      pushNotifications: prefs.getBool(_kPush) ?? d.pushNotifications,
      lessonReminder: prefs.getBool(_kLessonReminder) ?? d.lessonReminder,
      lessonReminderHour: prefs.getInt(_kReminderHour) ?? d.lessonReminderHour,
      lessonReminderMinute: prefs.getInt(_kReminderMinute) ?? d.lessonReminderMinute,
      streakReminder: prefs.getBool(_kStreakReminder) ?? d.streakReminder,
      courseLanguage: prefs.getString(_kCourseLanguage) ?? d.courseLanguage,
    );
  }

  Future<void> _apply(SettingsPrefs next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyGoal, next.dailyGoalMinutes);
    await prefs.setString(_kLevel, next.languageLevel.name);
    await prefs.setBool(_kLessonSounds, next.lessonSounds);
    await prefs.setBool(_kWordPronunciation, next.wordPronunciation);
    await prefs.setBool(_kPush, next.pushNotifications);
    await prefs.setBool(_kLessonReminder, next.lessonReminder);
    await prefs.setInt(_kReminderHour, next.lessonReminderHour);
    await prefs.setInt(_kReminderMinute, next.lessonReminderMinute);
    await prefs.setBool(_kStreakReminder, next.streakReminder);
    await prefs.setString(_kCourseLanguage, next.courseLanguage);
  }

  Future<void> setDailyGoal(int minutes) => _apply(state.copyWith(dailyGoalMinutes: minutes));
  Future<void> setLanguageLevel(LanguageLevel level) => _apply(state.copyWith(languageLevel: level));
  Future<void> setLessonSounds(bool value) => _apply(state.copyWith(lessonSounds: value));
  Future<void> setWordPronunciation(bool value) => _apply(state.copyWith(wordPronunciation: value));
  Future<void> setPushNotifications(bool value) => _apply(state.copyWith(pushNotifications: value));
  Future<void> setLessonReminder(bool value) => _apply(state.copyWith(lessonReminder: value));
  Future<void> setLessonReminderTime(int hour, int minute) =>
      _apply(state.copyWith(lessonReminderHour: hour, lessonReminderMinute: minute));
  Future<void> setStreakReminder(bool value) => _apply(state.copyWith(streakReminder: value));
  Future<void> setCourseLanguage(String value) => _apply(state.copyWith(courseLanguage: value));
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsPrefs>(SettingsNotifier.new);

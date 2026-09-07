import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TODO: подключить API — dailyGoalMinutes/languageLevel/streakReminder have
/// no backend endpoint yet. Persisted locally in SharedPreferences purely so
/// choices survive an app restart; every setter here is a placeholder for
/// what will eventually be a PATCH to a real preferences endpoint.
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

// Lesson-sound/word-pronunciation toggles live in
// core/settings/sound_preferences.dart (soundPreferencesProvider), and
// push/lesson-reminder settings live in
// features/settings/data/lesson_reminder_repository.dart
// (lessonReminderPreferencesProvider, § lesson reminder fix, 2026-09-07) —
// both server-backed, unlike everything still in this file.
class SettingsPrefs {
  const SettingsPrefs({
    required this.dailyGoalMinutes,
    required this.languageLevel,
    required this.streakReminder,
  });

  final int dailyGoalMinutes;
  final LanguageLevel languageLevel;
  final bool streakReminder;

  static const defaults = SettingsPrefs(
    dailyGoalMinutes: 20,
    languageLevel: LanguageLevel.a1,
    streakReminder: true,
  );

  SettingsPrefs copyWith({
    int? dailyGoalMinutes,
    LanguageLevel? languageLevel,
    bool? streakReminder,
  }) =>
      SettingsPrefs(
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        languageLevel: languageLevel ?? this.languageLevel,
        streakReminder: streakReminder ?? this.streakReminder,
      );
}

const _kDailyGoal = 'settings_daily_goal';
const _kLevel = 'settings_level';
const _kStreakReminder = 'settings_streak_reminder';

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
      streakReminder: prefs.getBool(_kStreakReminder) ?? d.streakReminder,
    );
  }

  Future<void> _apply(SettingsPrefs next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyGoal, next.dailyGoalMinutes);
    await prefs.setString(_kLevel, next.languageLevel.name);
    await prefs.setBool(_kStreakReminder, next.streakReminder);
  }

  Future<void> setDailyGoal(int minutes) => _apply(state.copyWith(dailyGoalMinutes: minutes));
  Future<void> setLanguageLevel(LanguageLevel level) => _apply(state.copyWith(languageLevel: level));
  Future<void> setStreakReminder(bool value) => _apply(state.copyWith(streakReminder: value));
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsPrefs>(SettingsNotifier.new);

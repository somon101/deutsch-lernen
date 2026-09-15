import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TODO: подключить API — dailyGoalMinutes/languageLevel have no backend
/// endpoint yet. Persisted locally in SharedPreferences purely so choices
/// survive an app restart; every setter here is a placeholder for what will
/// eventually be a PATCH to a real preferences endpoint.
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
//
// A `streakReminder` field used to live here: a local-only placeholder
// switch with no backend behind it. It was removed (§ streak reminder,
// 2026-09-15) because the streak-at-risk push reminder is a server+push
// mechanism gated by a single global admin switch and must never be exposed
// as a per-user setting — this dead toggle looked like one and confused
// users into thinking they controlled it.
class SettingsPrefs {
  const SettingsPrefs({
    required this.dailyGoalMinutes,
    required this.languageLevel,
  });

  final int dailyGoalMinutes;
  final LanguageLevel languageLevel;

  static const defaults = SettingsPrefs(
    dailyGoalMinutes: 20,
    languageLevel: LanguageLevel.a1,
  );

  SettingsPrefs copyWith({
    int? dailyGoalMinutes,
    LanguageLevel? languageLevel,
  }) =>
      SettingsPrefs(
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        languageLevel: languageLevel ?? this.languageLevel,
      );
}

const _kDailyGoal = 'settings_daily_goal';
const _kLevel = 'settings_level';

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
    );
  }

  Future<void> _apply(SettingsPrefs next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDailyGoal, next.dailyGoalMinutes);
    await prefs.setString(_kLevel, next.languageLevel.name);
  }

  Future<void> setDailyGoal(int minutes) => _apply(state.copyWith(dailyGoalMinutes: minutes));
  Future<void> setLanguageLevel(LanguageLevel level) => _apply(state.copyWith(languageLevel: level));
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsPrefs>(SettingsNotifier.new);

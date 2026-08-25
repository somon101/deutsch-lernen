import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'deutsch_lernen_theme_mode';

String _toPrefsValue(ThemeMode mode) => switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

ThemeMode? _fromPrefsValue(String? value) => switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };

/// Light / dark / system, persisted in SharedPreferences. Defaults to
/// following the OS — unlike the old two-state toggle (see git history),
/// this no longer hardcodes light as the app's own opinion, since the
/// settings screen now offers all three as an explicit user choice.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _fromPrefsValue(prefs.getString(_prefsKey));
    if (mode != null) state = mode;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _toPrefsValue(mode));
  }

  /// Quick light<->dark switch (the theme icon in the profile header) —
  /// leaves system alone by treating "not dark" as light.
  Future<void> toggle() => setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

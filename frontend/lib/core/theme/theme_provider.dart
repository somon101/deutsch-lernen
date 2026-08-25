import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/secure_storage.dart';

/// Mirrors src/theme/ThemeContext.tsx: explicit light/dark toggle,
/// persisted, defaulting to light regardless of the OS preference (same
/// documented reasoning as the web version — the site's default look is
/// light, so this never silently switches to dark on its own).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.light;
  }

  Future<void> _restore() async {
    final stored = await ref.read(secureStorageProvider).readTheme();
    if (stored == 'dark') state = ThemeMode.dark;
  }

  Future<void> toggle() async {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await ref.read(secureStorageProvider).saveTheme(state == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

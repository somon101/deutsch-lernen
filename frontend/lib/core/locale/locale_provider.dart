import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

const _prefsKey = 'deutsch_lernen_locale';

/// Null state means "follow the device locale" — MaterialApp.router falls
/// back to it automatically when `locale` is null. The picker's option list
/// comes from `AppLocalizations.supportedLocales` (generated from the ARB
/// files under lib/l10n/) rather than a second hardcoded list, so a new
/// locale only needs an ARB file to show up here too.
class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code == null) return;
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode == code) {
        state = locale;
        return;
      }
    }
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, locale.languageCode);
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

/// Display names for the language picker — a small flag plus the language's
/// own native name (§ interface localization, 2026-09-03: shown in every UI
/// language, not just Russian, since a learner switching TO Tajik must still
/// recognize the Tajik option by name). Falls back to the bare language code
/// for any locale added without an entry here.
String localeDisplayName(Locale locale) => switch (locale.languageCode) {
      'ru' => '🇷🇺 Русский',
      'tg' => '🇹🇯 Тоҷикӣ',
      _ => locale.languageCode,
    };

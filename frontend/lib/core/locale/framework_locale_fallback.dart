import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter's own bundled Material/Widgets/Cupertino localizations (the
/// `flutter_localizations` package) have ZERO built-in data for Tajik ("tg")
/// — confirmed by grepping the SDK's generated_material_localizations.dart
/// and generated_widgets_localizations.dart, both zero matches. Passing
/// `locale: Locale('tg')` straight into MaterialApp without this wrapper
/// makes every one of those three delegates report "not supported" for it,
/// which makes `MaterialLocalizations.of(context)` (required internally by
/// TextField/EditableText, among others) throw — the framework's own
/// ErrorWidget then renders in that widget's place, which in a release web
/// build shows as a blank/grey box rather than the debug red screen. It
/// also explains why the language picker itself became unusable once "tg"
/// was selected: the picker's own sheet/dialog widgets hit the same crash.
///
/// The fix (a standard, documented pattern for shipping a language Flutter
/// itself doesn't localize): wrap each of the three delegates so they claim
/// to support every locale THIS APP supports, and silently load the nearest
/// locale Flutter's framework actually has data for when the requested one
/// isn't one of them. This only affects framework-internal strings/behavior
/// (cut/copy/paste menu labels, date-picker chrome, right-to-left handling,
/// etc.) — every user-visible string in this app's OWN UI still comes from
/// AppLocalizations (app_tg.arb), fully in Tajik, untouched by this.
class FrameworkLocaleFallback {
  const FrameworkLocaleFallback._();

  /// Locale used for framework-internal chrome when the app's locale has no
  /// native Flutter framework data — Russian, the other locale this app
  /// actually supports, rather than Flutter's own default (English), so the
  /// framework-provided bits stay closer to what a Tajik-speaking user
  /// already reads elsewhere in the region.
  static const _frameworkFallback = Locale('ru');

  static const List<LocalizationsDelegate<dynamic>> delegates = [
    _FallbackDelegate<MaterialLocalizations>(GlobalMaterialLocalizations.delegate),
    _FallbackDelegate<WidgetsLocalizations>(GlobalWidgetsLocalizations.delegate),
    _FallbackDelegate<CupertinoLocalizations>(GlobalCupertinoLocalizations.delegate),
  ];
}

class _FallbackDelegate<T> extends LocalizationsDelegate<T> {
  const _FallbackDelegate(this._inner);
  final LocalizationsDelegate<T> _inner;

  // Claims every locale AppLocalizations.supportedLocales lists, even ones
  // `_inner` has no real data for — load() below is what actually covers
  // the gap, this just stops Localizations from excluding this delegate
  // entirely for an unsupported locale.
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) {
    final effective = _inner.isSupported(locale) ? locale : FrameworkLocaleFallback._frameworkFallback;
    return _inner.load(effective);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<T> old) => false;
}

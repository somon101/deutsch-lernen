import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Falls back to "ru" when the app's locale has no `intl` decimal-pattern
/// data of its own — the exact same gap already hit and fixed for
/// DateFormat (see personal_details_screen.dart's `_dateFormatLocale`) and
/// for Flutter's own framework localizations (core/locale/
/// framework_locale_fallback.dart): `intl` has zero data for "tg" either.
/// Shared by every leaderboard widget that formats a points count.
String numberFormatLocale(BuildContext context) {
  final locale = Localizations.localeOf(context).toString();
  return NumberFormat.localeExists(locale) ? locale : 'ru';
}

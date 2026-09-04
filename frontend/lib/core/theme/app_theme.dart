import 'package:flutter/material.dart';

import '../../features/profile/presentation/profile_tokens.dart';

/// Ports the CSS custom-property palette from src/styles/global.css
/// (both the light :root values and the :root[data-theme="dark"] override
/// block) into Flutter ColorSchemes — same colors, same two themes, so the
/// app looks like a native continuation of the web/Capacitor version
/// rather than a fresh redesign.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
    required this.gold,
    required this.silver,
    required this.bronze,
  });

  final Color bg;
  final Color surface;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;
  // Podium/rank medal colors (§ leaderboard redesign, 2026-09-04) — not
  // part of the original CSS port above, added for the podium's gold/
  // silver/bronze rings; same literal hex values in both themes (a medal is
  // a medal regardless of light/dark), matching the approved mockup.
  final Color gold;
  final Color silver;
  final Color bronze;

  static const light = AppColors(
    bg: Color(0xFFF5F6FB),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE6E8F2),
    text: Color(0xFF1C1F33),
    textMuted: Color(0xFF676C85),
    textFaint: Color(0xFF9297AB),
    primary: Color(0xFF4A5CF0),
    primaryDark: Color(0xFF3745C2),
    primarySoft: Color(0xFFECEEFF),
    success: Color(0xFF1FA974),
    successSoft: Color(0xFFE4F7EF),
    danger: Color(0xFFE5484D),
    dangerSoft: Color(0xFFFDEAEA),
    warning: Color(0xFFB8860B),
    warningSoft: Color(0xFFFFF6E0),
    gold: Color(0xFFE8A33D),
    silver: Color(0xFFA8AEC2),
    bronze: Color(0xFFC97B45),
  );

  static const dark = AppColors(
    bg: Color(0xFF0F1117),
    surface: Color(0xFF191B25),
    border: Color(0xFF2B2E3D),
    text: Color(0xFFF2F3F9),
    textMuted: Color(0xFF9A9DB3),
    textFaint: Color(0xFF6C6F85),
    primary: Color(0xFF8B7CF6),
    primaryDark: Color(0xFFA596FF),
    primarySoft: Color(0xFF262A44),
    success: Color(0xFF35D399),
    successSoft: Color(0xFF113228),
    danger: Color(0xFFF2696D),
    dangerSoft: Color(0xFF3A1E22),
    warning: Color(0xFFE0B03D),
    warningSoft: Color(0xFF3A2F14),
    gold: Color(0xFFF0B24A),
    silver: Color(0xFF8E96AD),
    bronze: Color(0xFFC97B45),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      border: mix(border, other.border),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      primary: mix(primary, other.primary),
      primaryDark: mix(primaryDark, other.primaryDark),
      primarySoft: mix(primarySoft, other.primarySoft),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      warning: mix(warning, other.warning),
      warningSoft: mix(warningSoft, other.warningSoft),
      gold: mix(gold, other.gold),
      silver: mix(silver, other.silver),
      bronze: mix(bronze, other.bronze),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData _buildTheme(AppColors c, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: Colors.white,
    secondary: c.primarySoft,
    onSecondary: c.primaryDark,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    appBarTheme: AppBarTheme(backgroundColor: c.surface, foregroundColor: c.text, elevation: 0),
    // global.css's card recipe (.profile-card/.lesson-card/.auth-card/...) is
    // background + border-radius + box-shadow — no visible border. Material's
    // Card doesn't support CSS's two-layer soft shadow directly, so this is
    // an elevation-based approximation rather than a literal port.
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 3,
      shadowColor: brightness == Brightness.dark ? Colors.black : const Color(0xFF1C1F33),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 4,
        shadowColor: c.primary,
      ),
    ),
    // Mirrors .auth-field input: surface bg (not page bg), 1.5px border,
    // radius-sm (10px), 11px/14px padding, primary border on focus.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      isDense: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary, width: 1.5)),
    ),
    extensions: [c, brightness == Brightness.dark ? ProfileColors.dark : ProfileColors.light],
  );
}

final lightTheme = _buildTheme(AppColors.light, Brightness.light);
final darkTheme = _buildTheme(AppColors.dark, Brightness.dark);

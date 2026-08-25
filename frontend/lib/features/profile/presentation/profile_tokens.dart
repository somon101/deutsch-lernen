import 'package:flutter/material.dart';

/// Design tokens for the profile/gamification screen family — a distinct,
/// dark-first palette from the rest of the app (core/theme/app_theme.dart's
/// AppColors), matching the profile mockup exactly rather than the general
/// UI palette. Kept as its own ThemeExtension so nothing here leaks hex
/// values into widgets: read via `context.profileColors`.
class ProfileColors extends ThemeExtension<ProfileColors> {
  const ProfileColors({
    required this.bg,
    required this.card,
    required this.cardHover,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.streak,
  });

  final Color bg;
  final Color card;
  final Color cardHover;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color streak;

  // Exact values from the design handoff.
  static const dark = ProfileColors(
    bg: Color(0xFF0B0E14),
    card: Color(0xFF151A24),
    cardHover: Color(0xFF1B2130),
    border: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF8B93A7),
    accent: Color(0xFF7C5CFF),
    accentSoft: Color(0x267C5CFF), // rgba(124,92,255,0.15)
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    streak: Color(0xFFFF6B35),
  );

  // No light spec was given — derived from the same hues, lifted to the
  // light surface/contrast levels the rest of the app's light theme uses
  // (core/theme/app_theme.dart's AppColors.light).
  static const light = ProfileColors(
    bg: Color(0xFFF5F6FB),
    card: Color(0xFFFFFFFF),
    cardHover: Color(0xFFF0F1FA),
    border: Color(0xFFE6E8F2),
    text: Color(0xFF1C1F33),
    textMuted: Color(0xFF676C85),
    accent: Color(0xFF7C5CFF),
    accentSoft: Color(0x1F7C5CFF),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    streak: Color(0xFFE8590C),
  );

  @override
  ProfileColors copyWith() => this;

  @override
  ProfileColors lerp(ThemeExtension<ProfileColors>? other, double t) {
    if (other is! ProfileColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ProfileColors(
      bg: mix(bg, other.bg),
      card: mix(card, other.card),
      cardHover: mix(cardHover, other.cardHover),
      border: mix(border, other.border),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      streak: mix(streak, other.streak),
    );
  }
}

extension ProfileColorsContext on BuildContext {
  ProfileColors get profileColors => Theme.of(this).extension<ProfileColors>() ?? ProfileColors.dark;
}

/// Spacing/radius/size scale (4px grid) and typography for the profile
/// screen family. Plain const values rather than a ThemeExtension since
/// none of it is color-mode-dependent.
class ProfileMetrics {
  ProfileMetrics._();

  static const cardRadius = 20.0;
  static const smallRadius = 12.0;
  static const cardPadding = 20.0;
  static const cardGap = 12.0;
  static const pageMarginMobile = 16.0;
  static const pageMarginDesktop = 24.0;
  static const avatarMobile = 104.0;
  static const avatarDesktop = 120.0;
  static const badgeSize = 64.0;
  static const badgeStroke = 2.0;
  static const activityDot = 28.0;
  static const menuRowHeight = 52.0;
  static const progressBarHeight = 8.0;
  static const progressBarRadius = 4.0;
  static const transition = Duration(milliseconds: 150);
  static const transitionCurve = Curves.easeInOut;

  /// Desktop content is centered with this max width; the mobile/desktop
  /// split itself matches AppShell's own rail breakpoint.
  static const desktopContentMaxWidth = 700.0;
  static const wideBreakpoint = 768.0;

  /// Height of AppShell's mobile bottom tab bar (_BottomBar), not counting
  /// the safe-area inset it adds on top via its own SafeArea. Shared here
  /// so screens hosted inside the shell can size their own scroll padding
  /// to it — see [bottomBarClearance].
  static const bottomBarHeight = 60.0;
}

/// Extra bottom padding a shell-hosted scrollable screen needs so its last
/// item isn't hidden behind AppShell's mobile bottom tab bar. Each routed
/// screen builds its own nested Scaffold inside AppShell's `child`, and a
/// nested Scaffold has no way to know about an ancestor Scaffold's
/// `bottomNavigationBar` height — so this has to be added explicitly to
/// each screen's own scroll padding, rather than relying on Flutter to
/// account for it automatically. Just the bar's own height — the system
/// gesture-bar/home-indicator inset underneath it is a separate concern
/// each screen's own SafeArea already handles. Zero on wide layouts, where
/// the bottom bar doesn't exist (AppShell shows the side rail instead).
double bottomBarClearance(BuildContext context) {
  final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;
  return isWide ? 0 : ProfileMetrics.bottomBarHeight;
}

/// Font is Inter per the design spec, with a system-ui fallback for when
/// it isn't bundled — no font asset is in pubspec.yaml today, so this
/// always resolves to the fallback (Flutter's platform default, which is
/// the system-ui equivalent) until an Inter asset/package is added.
class ProfileTypography {
  ProfileTypography._();

  static const _fontFamilyFallback = <String>['Inter'];

  static TextStyle username(BuildContext context) => TextStyle(
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: context.profileColors.text,
        height: 1.2,
      );

  static TextStyle bigNumber(BuildContext context) => TextStyle(
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: context.profileColors.text,
      );

  static TextStyle sectionTitle(BuildContext context) => TextStyle(
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: context.profileColors.text,
      );

  static TextStyle body(BuildContext context) => TextStyle(
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: context.profileColors.text,
      );

  static TextStyle caption(BuildContext context) => TextStyle(
        fontFamilyFallback: _fontFamilyFallback,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: context.profileColors.textMuted,
      );
}

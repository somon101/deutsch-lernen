import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the admin course-builder/lesson-editor screen family —
/// a dense, compact "working tool" look, deliberately distinct from both the
/// general app theme (core/theme/app_theme.dart's AppColors) and the profile
/// feature's own tokens (profile_tokens.dart's ProfileColors). Fixed light
/// palette only — the reference design has no dark variant, so (like
/// ProfileQrCard) this doesn't follow the app's light/dark toggle.
///
/// § course-builder redesign, 2026-09-01, phase 1 (tokens only — every
/// screen still uses the exact same widget structure as before, just with
/// these updated values, per the redesign's own "step 1: tokens into their
/// own file, migrate existing screens onto them, no markup changes yet").
/// One deliberate resolution of an inconsistency in that spec: §2 says the
/// one accent color means only "this connects to that" and buttons stay
/// neutral, while §10's button recipe says the primary button is filled
/// with the accent — confirmed with the user, §2 wins: `accent` is
/// reserved for connectivity indicators (the future "verifies block Б2"
/// chip) only. Buttons render with neutral ink/paper, never the accent.
class AdminColors {
  AdminColors._();

  static const bg = Color(0xFFF6F7F4);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE0E3DD);
  /// Border of an expanded/active card, 1.5px — distinct from the resting
  /// [border] without reaching for the accent (§2: accent means "connects
  /// to", not "focused/expanded").
  static const borderStrong = Color(0xFFC7CCC4);
  static const text = Color(0xFF15181A);
  static const textSecondary = Color(0xFF5C6560);
  static const textMuted = Color(0xFF939B96);
  /// The one accent in the whole admin family — reserved for connectivity
  /// indicators only (see class doc). Never a button fill.
  static const accent = Color(0xFF0E7C86);
  static const accentHover = Color(0xFF0B6068);
  static const accentSoft = Color(0xFFE4F1F2);
  static const danger = Color(0xFFB42318);
  /// Warnings that aren't errors — e.g. "a block has no checks yet" — soft
  /// amber, never the accent and never [danger].
  static const warn = Color(0xFF9A6B1E);
  static const warnSoft = Color(0xFFFBF3E4);
  static const blockBg = Color(0xFFFAFBF9);
}

class AdminMetrics {
  AdminMetrics._();

  static const cardRadius = 10.0;
  static const inputRadius = 10.0;
  static const buttonRadius = 999.0;
  static const blockRadius = 10.0;
  static const inputHeight = 38.0;
  static const buttonHeight = 36.0;
  static const buttonHPad = 18.0;
  static const cardPadding = 16.0;
  static const cardGap = 8.0;
  static const sectionGap = 24.0;
  static const fieldGap = 12.0;
  static const maxContentWidth = 760.0;
  /// The step rail's fixed width (§4 of the redesign) — defined now so it's
  /// ready when the rail itself is built later; unused until then.
  static const railWidth = 220.0;
  static const transition = Duration(milliseconds: 150);
}

class AdminTypography {
  AdminTypography._();

  static TextStyle get pageTitle => GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: AdminColors.text);
  static TextStyle get cardTitle => GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AdminColors.text);
  static TextStyle get stageTitle => GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminColors.text);
  static TextStyle get body => GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: AdminColors.text);
  static TextStyle get fieldLabel => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AdminColors.textSecondary);
  static TextStyle get caption => GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: AdminColors.textMuted);
  /// Block tokens (`Б1`, `Б2`) and JSON-shaped fields.
  static TextStyle get mono => GoogleFonts.ibmPlexMono(fontSize: 12, color: AdminColors.text, height: 1.5);
  /// German lesson content shown in admin previews (phrases, words, answer
  /// options) — deliberately a different face from the UI chrome above, so
  /// in a long list of questions the eye instantly separates content from
  /// interface. Not yet applied anywhere (that's a later redesign phase);
  /// defined here so it's ready.
  static TextStyle get germanContent => GoogleFonts.ibmPlexSerif(fontSize: 14, fontWeight: FontWeight.w400, color: AdminColors.text);
}

/// Compact pill buttons sized to their text (Principle 2) — never
/// full-width except the deliberate list "+ add" exception, which callers
/// wrap in their own SizedBox(width: double.infinity) rather than this
/// style baking that in.
class AdminButtonStyles {
  AdminButtonStyles._();

  /// Filled pill in neutral ink — never the accent (§2: accent means
  /// "connects to", reserved for the verifies-block chip; a save/create
  /// button isn't a connectivity indicator).
  static ButtonStyle primary() => FilledButton.styleFrom(
    backgroundColor: AdminColors.text,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AdminColors.text.withValues(alpha: 0.4),
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: AdminMetrics.buttonHPad),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AdminMetrics.buttonRadius),
    ),
    textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
    elevation: 0,
  );

  static ButtonStyle secondary() => OutlinedButton.styleFrom(
    foregroundColor: AdminColors.text,
    side: const BorderSide(color: AdminColors.border),
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: AdminMetrics.buttonHPad),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AdminMetrics.buttonRadius),
    ),
    textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
  );

  /// Danger actions are a plain text link, never a filled button
  /// (Principle 3 — red fill is never used).
  static ButtonStyle dangerText() => TextButton.styleFrom(
    foregroundColor: AdminColors.danger,
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
  );

  /// Plain text button — neutral ink-secondary, not the accent (§2).
  static ButtonStyle text() => TextButton.styleFrom(
    foregroundColor: AdminColors.textSecondary,
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
  );
}

InputDecoration adminInputDecoration({String? label, String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: AdminTypography.fieldLabel,
      isDense: true,
      filled: true,
      fillColor: AdminColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminMetrics.inputRadius),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminMetrics.inputRadius),
        borderSide: const BorderSide(color: AdminColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminMetrics.inputRadius),
        // Neutral, not the accent (§2) — a focus ring isn't a connectivity
        // indicator, so it stays in the ink/paper vocabulary, just heavier.
        borderSide: const BorderSide(color: AdminColors.text, width: 1.5),
      ),
    );

/// Deliberately not Material's `Card` (which inherits the app-wide
/// CardTheme's elevation/shadow from app_theme.dart) — flat color+border
/// only (Principle: cards separate from the page by color/border, no
/// shadows). Built on `Material` rather than a plain `Container` so any
/// `ListTile`/`InkWell` nested inside still has a proper ink-painting
/// ancestor — a bare `DecoratedBox`/`Container` background hides their
/// splashes and Flutter asserts about it at runtime.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AdminMetrics.cardPadding),
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// The "raised, strong-bordered" treatment for an expanded accordion item
  /// (Screenshot 1's "visual anchor" requirement).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AdminMetrics.cardRadius);
    return Material(
      color: AdminColors.card,
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: highlighted ? AdminColors.borderStrong : AdminColors.border,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Centers content at a 760px reading-width max (Principle 4), full width
/// below that.
class AdminMaxWidth extends StatelessWidget {
  const AdminMaxWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AdminMetrics.maxContentWidth,
        ),
        child: child,
      ),
    );
  }
}

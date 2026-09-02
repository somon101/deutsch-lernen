import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the admin course-builder/lesson-editor screen family —
/// a dense, compact "working tool" look. Fixed light palette only: the
/// reference design has no dark variant, so (like ProfileQrCard) this
/// doesn't follow the app's light/dark toggle.
///
/// § builder palette unification, 2026-09-02: these values used to be a
/// deliberately separate warm-paper + teal family, kept distinct from the
/// app theme on purpose. That stopped working once the builder screens
/// moved inside the app's own shell chrome — a warm beige card with teal
/// accents sitting inside a cool indigo frame reads as two different
/// products bolted together. Every value below is now taken from
/// core/theme/app_theme.dart's AppColors.light, so the builder is the same
/// product as the rest of the app; what stays its own is the *structure*
/// (denser metrics, its own typography, fixed light), not the hues.
///
/// Roles are still separated the way the redesign spec asked, just inside
/// one hue family now: [accent] marks connectivity ("this checks that") as
/// a soft tinted chip, while a primary button is the same accent as a solid
/// fill. Shape and weight carry the difference, exactly as they already do
/// on the student-facing screens.
class AdminColors {
  AdminColors._();

  static const bg = Color(0xFFF5F6FB);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6E8F2);
  /// Border of an expanded/active card, 1.5px — a heavier neutral rather
  /// than the accent, so "focused/expanded" never reads as "connected to".
  static const borderStrong = Color(0xFFC9CEE3);
  static const text = Color(0xFF1C1F33);
  static const textSecondary = Color(0xFF676C85);
  static const textMuted = Color(0xFF9297AB);
  /// The one accent in the admin family: connectivity chips use [accentSoft]
  /// behind [accentHover] text, primary buttons use it as a solid fill.
  static const accent = Color(0xFF4A5CF0);
  static const accentHover = Color(0xFF3745C2);
  static const accentSoft = Color(0xFFECEEFF);
  static const danger = Color(0xFFE5484D);
  static const dangerSoft = Color(0xFFFDEAEA);
  /// "Published", "answer is correct" — the status green. Previously each
  /// call site hardcoded its own #16A34A/#DC2626 pair, which drifted from
  /// the app's greens; both now come from here (§ builder palette
  /// unification, 2026-09-02).
  static const success = Color(0xFF1FA974);
  static const successSoft = Color(0xFFE4F7EF);
  /// Warnings that aren't errors — e.g. "a block has no checks yet" — soft
  /// amber, never the accent and never [danger].
  static const warn = Color(0xFFB8860B);
  static const warnSoft = Color(0xFFFFF6E0);
  static const blockBg = Color(0xFFFAFBFF);
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
  /// Reading-width cap for the list-shaped admin screens (courses hub, course
  /// structure) — wide enough to use a real monitor, still short enough that a
  /// course description doesn't run edge to edge (§ builder full-width layout,
  /// 2026-09-02). The lesson editor deliberately has no cap at all: its rail +
  /// working-area split genuinely uses every pixel.
  static const maxListWidth = 1400.0;
  /// The step rail's fixed width (§4 of the redesign) — defined now so it's
  /// ready when the rail itself is built later; unused until then.
  static const railWidth = 220.0;
  /// Course-card cover thumbnail on the hub list (§9 of the redesign,
  /// 2026-09-01: "Обложка 64×48 слева").
  static const courseCoverWidth = 64.0;
  static const courseCoverHeight = 48.0;
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

  /// Filled pill in the accent, matching the app's own primary button
  /// (§ builder palette unification, 2026-09-02 — it used to be neutral ink
  /// so the accent could mean "connects to" exclusively; now that both live
  /// in one hue family, a solid fill vs a soft tinted chip carries that
  /// difference instead).
  static ButtonStyle primary() => FilledButton.styleFrom(
    backgroundColor: AdminColors.accent,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AdminColors.accent.withValues(alpha: 0.4),
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
        // Accent focus ring, same as the app's own inputs (§ builder palette
        // unification, 2026-09-02).
        borderSide: const BorderSide(color: AdminColors.accent, width: 1.5),
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

/// Centers content at a reading-width max (Principle 4), full width below
/// that. [maxWidth] overrides the default 760px cap — the list-shaped admin
/// screens pass [AdminMetrics.maxListWidth] so they actually use a wide
/// monitor (§ builder full-width layout, 2026-09-02).
class AdminMaxWidth extends StatelessWidget {
  const AdminMaxWidth({super.key, required this.child, this.maxWidth = AdminMetrics.maxContentWidth});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

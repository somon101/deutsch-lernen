import 'package:flutter/material.dart';

/// Design tokens for the admin course-builder/lesson-editor screen family —
/// a dense, compact "working tool" look, deliberately distinct from both the
/// general app theme (core/theme/app_theme.dart's AppColors) and the profile
/// feature's own tokens (profile_tokens.dart's ProfileColors). Fixed light
/// palette only — the reference design has no dark variant, so (like
/// ProfileQrCard) this doesn't follow the app's light/dark toggle.
class AdminColors {
  AdminColors._();

  static const bg = Color(0xFFF4F6FB);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6EAF2);
  static const text = Color(0xFF1A1D26);
  static const textSecondary = Color(0xFF6B7280);
  static const textMuted = Color(0xFF9CA3AF);
  static const accent = Color(0xFF3B5BFE);
  static const accentHover = Color(0xFF2E49D6);
  static const accentSoft = Color(0xFFEEF1FE);
  static const danger = Color(0xFFDC2626);
  static const blockBg = Color(0xFFFAFBFD);
}

class AdminMetrics {
  AdminMetrics._();

  static const cardRadius = 14.0;
  static const inputRadius = 8.0;
  static const buttonRadius = 999.0;
  static const blockRadius = 10.0;
  static const inputHeight = 38.0;
  static const buttonHeight = 36.0;
  static const buttonHPad = 18.0;
  static const cardPadding = 20.0;
  static const cardGap = 16.0;
  static const fieldGap = 12.0;
  static const maxContentWidth = 880.0;
  static const transition = Duration(milliseconds: 150);
}

class AdminTypography {
  AdminTypography._();

  static const pageTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AdminColors.text,
  );
  static const cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AdminColors.text,
  );
  static const stageTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AdminColors.text,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AdminColors.text,
  );
  static const fieldLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AdminColors.textSecondary,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AdminColors.textMuted,
  );
  static const mono = TextStyle(
    fontSize: 13,
    fontFamily: 'monospace',
    color: AdminColors.text,
    height: 1.5,
  );
}

/// Compact pill buttons sized to their text (Principle 2) — never
/// full-width except the deliberate list "+ add" exception, which callers
/// wrap in their own SizedBox(width: double.infinity) rather than this
/// style baking that in.
class AdminButtonStyles {
  AdminButtonStyles._();

  static ButtonStyle primary() => FilledButton.styleFrom(
    backgroundColor: AdminColors.accent,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AdminColors.accent.withValues(alpha: 0.5),
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: AdminMetrics.buttonHPad),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AdminMetrics.buttonRadius),
    ),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );

  /// Danger actions are a plain text link, never a filled button
  /// (Principle 3 — red fill is never used).
  static ButtonStyle dangerText() => TextButton.styleFrom(
    foregroundColor: AdminColors.danger,
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  );

  static ButtonStyle text() => TextButton.styleFrom(
    foregroundColor: AdminColors.accent,
    minimumSize: const Size(0, AdminMetrics.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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

  /// The "raised, dark-bordered" treatment for an expanded accordion item
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
            color: highlighted ? AdminColors.text : AdminColors.border,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}

/// Centers content at a 880px reading-width max (Principle 4), full width
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

import 'package:flutter/material.dart';

import '../profile_tokens.dart';
import 'profile_card.dart';

/// One cell of the 4-across metric row (streak / progress / study time /
/// level). `emoji` mirrors the mockup's emoji glyphs; pass `icon` instead
/// for metrics that should use a Material icon (tinted with `accentColor`)
/// rather than an emoji.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    this.emoji,
    this.icon,
    this.accentColor,
    required this.value,
    required this.label,
  }) : assert(emoji != null || icon != null, 'MetricCard needs either an emoji or an icon');

  final String? emoji;
  final IconData? icon;
  final Color? accentColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ProfileCard(
      // Tighter than ProfileCard's 20px default — four of these need to fit
      // across a 360px phone with room for two lines of label underneath.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 20)),
          if (icon != null) Icon(icon, size: 20, color: accentColor ?? context.profileColors.accent),
          const SizedBox(height: 6),
          // FittedBox rather than a fixed font size: shrinks "24ч 30м"-style
          // values that would otherwise wrap or clip in a narrow column,
          // instead of losing characters.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, maxLines: 1, style: ProfileTypography.bigNumber(context)),
          ),
          const SizedBox(height: 2),
          Text(label, style: ProfileTypography.caption(context), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

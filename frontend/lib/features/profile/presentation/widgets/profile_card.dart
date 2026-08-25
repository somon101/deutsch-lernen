import 'package:flutter/material.dart';

import '../profile_tokens.dart';

/// Shared card shell for the profile screen family: card-color fill + a
/// hairline border, no shadow (per the design spec — cards are separated
/// by fill/border, not elevation).
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return Container(
      padding: padding ?? const EdgeInsets.all(ProfileMetrics.cardPadding),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
        border: Border.all(color: c.border, width: 1),
      ),
      child: child,
    );
  }
}

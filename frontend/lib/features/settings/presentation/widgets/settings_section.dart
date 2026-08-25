import 'package:flutter/material.dart';

import '../../../profile/presentation/profile_tokens.dart';

/// A caps-label section title over a card grouping its rows, with hairline
/// dividers between them — reused by SettingsScreen for every section
/// ("АККАУНТ", "ОБУЧЕНИЕ", ...).
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: ProfileTypography.caption(context).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.6),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.border, indent: 16, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

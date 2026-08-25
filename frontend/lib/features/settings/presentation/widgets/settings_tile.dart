import 'package:flutter/material.dart';

import '../../../profile/presentation/profile_tokens.dart';

/// Base row shared by every settings list item: icon on the left, label
/// (+optional subtitle), free-form trailing slot on the right. 56px tall,
/// no shadow — rows are separated by the section card's background/border,
/// per the design spec.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final labelColor = danger ? c.danger : c.text;
    final iconColor = danger ? c.danger : c.textMuted;

    return InkWell(
      onTap: onTap,
      hoverColor: c.cardHover,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ProfileMetrics.menuRowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: ProfileTypography.body(context).copyWith(color: labelColor)),
                    if (subtitle != null) Text(subtitle!, style: ProfileTypography.caption(context)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

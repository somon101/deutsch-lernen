import 'package:flutter/material.dart';

import '../../../profile/presentation/profile_tokens.dart';
import 'settings_tile.dart';

/// SettingsTile with a trailing chevron (and optional current-value label)
/// — every "goes somewhere / opens a picker" row.
class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.danger = false,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return SettingsTile(
      icon: icon,
      label: label,
      danger: danger,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(value!, style: ProfileTypography.caption(context)),
            ),
          Icon(Icons.chevron_right, size: 20, color: c.textMuted),
        ],
      ),
    );
  }
}

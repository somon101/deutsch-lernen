import 'package:flutter/material.dart';

import '../../../profile/presentation/profile_tokens.dart';
import 'settings_tile.dart';

/// SettingsTile with a trailing Switch — every boolean toggle row.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return SettingsTile(
      icon: icon,
      label: label,
      subtitle: subtitle,
      trailing: Switch(value: value, activeThumbColor: c.accent, onChanged: onChanged),
    );
  }
}

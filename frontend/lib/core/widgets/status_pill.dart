import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Mirrors global.css's `.admin-status` / `.admin-status--active` /
/// `.admin-status--blocked` — the small rounded status pill used for account
/// status and online status in the admin user list/detail screens.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = active ? c.successSoft : c.dangerSoft;
    final fg = active ? c.success : c.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

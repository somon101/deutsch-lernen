import 'package:flutter/material.dart';

import '../profile_tokens.dart';
import 'profile_card.dart';

class MenuListItem {
  const MenuListItem({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Settings-style list of rows (icon, label, chevron), 52px each, sharing
/// one card shell with hairline dividers between rows.
class MenuList extends StatelessWidget {
  const MenuList({super.key, required this.items});

  final List<MenuListItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return ProfileCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.border, indent: 20, endIndent: 20),
            _MenuRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});
  final MenuListItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return InkWell(
      onTap: item.onTap,
      hoverColor: c.cardHover,
      child: SizedBox(
        height: ProfileMetrics.menuRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: c.textMuted),
              const SizedBox(width: 14),
              Expanded(child: Text(item.label, style: ProfileTypography.body(context))),
              Icon(Icons.chevron_right, size: 20, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../profile_tokens.dart';

class StatRowItem {
  const StatRowItem({required this.value, required this.label, this.onTap});
  final String value;
  final String label;

  /// When set (§ subscriptions follow-up, 2026-08-31), tapping this stat
  /// opens its full list (followers/following/mutual) — null keeps a plain,
  /// non-interactive stat exactly as before.
  final VoidCallback? onTap;
}

/// Followers / mutual / following row — three stats separated by hairline
/// vertical dividers, no card background of its own (sits directly under
/// the avatar header, matching the mockup).
class StatRow extends StatelessWidget {
  const StatRow({super.key, required this.items});

  final List<StatRowItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 32, color: c.border),
          _Stat(item: items[i]),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.item});
  final StatRowItem item;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.value, style: ProfileTypography.bigNumber(context)),
        const SizedBox(height: 2),
        Text(item.label, style: ProfileTypography.caption(context)),
      ],
    );
    if (item.onTap == null) return column;
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: column),
    );
  }
}

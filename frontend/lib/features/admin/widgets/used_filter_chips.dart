import 'package:flutter/material.dart';

/// «Все / Используются / Не используются» chips for a base list (words,
/// phrases): `value` null = all, true = used in lessons, false = not used.
class UsedFilterChips extends StatelessWidget {
  const UsedFilterChips({super.key, required this.value, required this.usedCount, required this.unusedCount, required this.onChanged});

  final bool? value;
  final int usedCount;
  final int unusedCount;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final (v, label) in [
            (null, 'Все · ${usedCount + unusedCount}'),
            (true, 'Используются · $usedCount'),
            (false, 'Не используются · $unusedCount'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: value == v,
              onSelected: (_) {
                if (value != v) onChanged(v);
              },
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'admin_tokens.dart';

/// Compact ↑/↓ reorder buttons — used identically for courses, lessons,
/// blocks and questions (previously copy-pasted per-screen).
class AdminReorderArrows extends StatelessWidget {
  const AdminReorderArrows({
    super.key,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMove,
    this.size = 18,
  });

  final bool canMoveUp;
  final bool canMoveDown;
  final void Function(int delta) onMove;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.arrow_upward, size: size),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: size + 14,
            height: size + 14,
          ),
          color: canMoveUp
              ? AdminColors.textSecondary
              : AdminColors.textMuted.withValues(alpha: 0.4),
          onPressed: canMoveUp ? () => onMove(-1) : null,
        ),
        IconButton(
          icon: Icon(Icons.arrow_downward, size: size),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: size + 14,
            height: size + 14,
          ),
          color: canMoveDown
              ? AdminColors.textSecondary
              : AdminColors.textMuted.withValues(alpha: 0.4),
          onPressed: canMoveDown ? () => onMove(1) : null,
        ),
      ],
    );
  }
}

/// A plain-text "Удалить" danger link (Principle 3 — never a filled red
/// button).
class AdminDeleteLink extends StatelessWidget {
  const AdminDeleteLink({
    super.key,
    required this.onPressed,
    this.label = 'Удалить',
  });
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: AdminButtonStyles.dangerText(),
      child: Text(label),
    );
  }
}

/// One row of the "Черновик"/"Опубликован" status badge — text-only chip,
/// no red fill anywhere per the design spec.
class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({super.key, required this.published});
  final bool published;

  @override
  Widget build(BuildContext context) {
    final color = published ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final bg = published ? const Color(0xFFE7F7EE) : const Color(0xFFFDEAEA);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AdminMetrics.buttonRadius),
      ),
      child: Text(
        published ? 'Опубликован' : 'Черновик',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// A collapsed-by-default reference/help box ("▸ Формат материала") —
/// useful to a newcomer, out of the way for everyone else.
class AdminCollapsibleHelp extends StatefulWidget {
  const AdminCollapsibleHelp({
    super.key,
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;

  @override
  State<AdminCollapsibleHelp> createState() => _AdminCollapsibleHelpState();
}

class _AdminCollapsibleHelpState extends State<AdminCollapsibleHelp> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 18,
                    color: AdminColors.textSecondary,
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AdminTypography.fieldLabel.copyWith(
                        color: AdminColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// One row of the "ЧТО НУЖНО / КАК НАПИСАТЬ" material-format reference
/// table (Screenshot 4).
class AdminHelpTableRow extends StatelessWidget {
  const AdminHelpTableRow({
    super.key,
    required this.label,
    required this.example,
  });
  final String label;
  final String example;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: AdminTypography.body)),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AdminColors.blockBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(example, style: AdminTypography.mono),
            ),
          ),
        ],
      ),
    );
  }
}

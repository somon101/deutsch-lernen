import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../models/lesson_node_data.dart';

enum LabelSide { left, right }

/// Plain text next to a node — no card/container, per spec ("никаких
/// карточек-контейнеров вокруг текста"). Always sits on the side OPPOSITE
/// the node's own horizontal offset, so it reads away from the curve
/// instead of overlapping it.
class LessonNodeLabel extends StatelessWidget {
  const LessonNodeLabel({super.key, required this.data, required this.side});

  final LessonNodeData data;
  final LabelSide side;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final column = Column(
      crossAxisAlignment: side == LabelSide.right ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: side == LabelSide.right ? TextAlign.left : TextAlign.right,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.homeMapWordCount(data.wordCount),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        if (data.state == LessonNodeState.current) ...[
          const SizedBox(height: 2),
          Text(
            '${(data.progress * 100).round()}%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary),
          ),
        ],
      ],
    );

    return Align(alignment: side == LabelSide.right ? Alignment.centerLeft : Alignment.centerRight, child: column);
  }
}

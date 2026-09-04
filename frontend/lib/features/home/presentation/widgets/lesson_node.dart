import 'package:flutter/material.dart';

import '../models/lesson_node_data.dart';

/// One node bubble on the lesson map (§ lesson map, 2026-09-04). Only the
/// `current` node carries an AnimationController (a looping pulse ring) —
/// completed/locked nodes are plain StatelessWidget-shaped, so a 50+ lesson
/// map never has more than one live animation ticking at a time.
class LessonNodeWidget extends StatelessWidget {
  const LessonNodeWidget({super.key, required this.data, required this.onTap});

  final LessonNodeData data;
  final VoidCallback onTap;

  static const completedDiameter = 68.0;
  static const currentDiameter = 84.0;
  static const lockedDiameter = 68.0;

  double get _diameter => switch (data.state) {
        LessonNodeState.completed => completedDiameter,
        LessonNodeState.current => currentDiameter,
        LessonNodeState.locked => lockedDiameter,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diameter = _diameter;

    final Color fill;
    final Widget icon;
    final List<BoxShadow> shadows;
    switch (data.state) {
      case LessonNodeState.completed:
        fill = scheme.primary;
        icon = Icon(Icons.check, color: scheme.onPrimary, size: diameter * 0.42);
        shadows = [BoxShadow(color: scheme.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))];
      case LessonNodeState.current:
        fill = scheme.primary;
        icon = Icon(Icons.play_arrow_rounded, color: scheme.onPrimary, size: diameter * 0.42);
        shadows = [BoxShadow(color: scheme.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))];
      case LessonNodeState.locked:
        fill = scheme.surfaceContainerHighest;
        icon = Icon(Icons.lock_outline, color: scheme.onSurfaceVariant.withValues(alpha: 0.6), size: diameter * 0.36);
        shadows = const [];
    }

    final bubble = Semantics(
      button: true,
      label: data.title,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle, boxShadow: shadows),
          alignment: Alignment.center,
          child: icon,
        ),
      ),
    );

    return SizedBox(
      width: currentDiameter + 24, // stable hit-testing footprint regardless of state, avoids layout jump
      height: currentDiameter + 24,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (data.state == LessonNodeState.current) _PulseRing(diameter: diameter, color: scheme.primary),
          bubble,
          Positioned(
            top: (currentDiameter + 24 - diameter) / 2 - 4,
            right: (currentDiameter + 24 - diameter) / 2 - 4,
            child: _IndexBadge(index: data.index, scheme: scheme, muted: data.state == LessonNodeState.locked),
          ),
        ],
      ),
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index, required this.scheme, required this.muted});
  final int index;
  final ColorScheme scheme;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: muted ? scheme.surface : scheme.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '${index + 1}',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: muted ? scheme.onSurfaceVariant : scheme.onSecondary),
      ),
    );
  }
}

class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.diameter, required this.color});
  final double diameter;
  final Color color;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final scale = 1.0 + 0.18 * t;
        final opacity = 0.35 * (1 - t);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.diameter,
            height: widget.diameter,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color.withValues(alpha: opacity), width: 6)),
          ),
        );
      },
    );
  }
}

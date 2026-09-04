import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../courses/presentation/courses_overview.dart';
import '../models/lesson_node_data.dart';
import 'lesson_node.dart';
import 'lesson_node_label.dart';
import 'lesson_path_painter.dart';

const _maxContentWidth = 480.0;
const _verticalStep = 160.0;
const _topPadding = 60.0;
const _bottomPadding = 120.0;
const _staggerPerNode = Duration(milliseconds: 60);
const _staggerDuration = Duration(milliseconds: 300);
const _labelGap = 8.0;
const _labelMargin = 16.0;

/// The winding lesson path (§ lesson map, 2026-09-04) — replaces the old
/// flat ListView of LessonGridCards in home_screen.dart. Reads the exact
/// same `List<LessonCard>` the old list did and calls the exact same
/// `onOpenLesson` navigation the caller already had; this widget only
/// changes how that list is laid out and how a locked lesson is handled
/// (there was no such state before — see LessonNodeData's docstring).
class LessonMap extends StatefulWidget {
  const LessonMap({super.key, required this.lessons, required this.onOpenLesson});

  final List<LessonCard> lessons;
  final ValueChanged<LessonCard> onOpenLesson;

  @override
  State<LessonMap> createState() => _LessonMapState();
}

class _LessonMapState extends State<LessonMap> with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  late final AnimationController _entrance;

  Duration _entranceDuration(int count) => _staggerDuration + _staggerPerNode * (count == 0 ? 0 : count - 1);

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: _entranceDuration(widget.lessons.length))..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(covariant LessonMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different lesson set (language switched, list refreshed) replays
    // the entrance instead of leaving stale progress on it.
    if (oldWidget.lessons.length != widget.lessons.length) {
      _entrance.duration = _entranceDuration(widget.lessons.length);
      _entrance.forward(from: 0);
    }
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final nodes = buildLessonNodes(widget.lessons);
    final currentIndex = nodes.indexWhere((n) => n.state == LessonNodeState.current);
    if (currentIndex == -1) return;
    final targetY = _topPadding + currentIndex * _verticalStep;
    final viewport = _scrollController.position.viewportDimension;
    final target = (targetY - viewport * 0.4).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _entrance.dispose();
    super.dispose();
  }

  void _handleTap(LessonCard lesson, LessonNodeData node) {
    if (node.state == LessonNodeState.locked) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).homeMapLockedSnack)));
      return;
    }
    widget.onOpenLesson(lesson);
  }

  // Interval for node `index`'s own entrance, expressed as a fraction of
  // the whole controller's duration — every node reuses the SAME
  // AnimationController (cheap even at 50+ lessons), just staggered via
  // Interval instead of one controller each.
  Interval _staggerInterval(int index, int totalMs) {
    final startMs = _staggerPerNode.inMilliseconds * index;
    final start = (startMs / totalMs).clamp(0.0, 1.0);
    final end = ((startMs + _staggerDuration.inMilliseconds) / totalMs).clamp(0.0, 1.0);
    return Interval(start, end, curve: Curves.easeOutBack);
  }

  @override
  Widget build(BuildContext context) {
    final nodes = buildLessonNodes(widget.lessons);
    if (nodes.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = nodes.indexWhere((n) => n.state == LessonNodeState.current);
    final currentProgress = currentIndex == -1 ? 0.0 : nodes[currentIndex].progress;
    final totalMs = _entrance.duration!.inMilliseconds;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > _maxContentWidth ? _maxContentWidth : constraints.maxWidth;
        final positions = calculateNodePositions(count: nodes.length, width: width, verticalStep: _verticalStep, topPadding: _topPadding);
        final height = totalMapHeight(nodes.length, verticalStep: _verticalStep, topPadding: _topPadding, bottomPadding: _bottomPadding);
        const nodeRadius = LessonNodeWidget.currentDiameter / 2;

        return Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Fades in alongside the very first node (§ line
                    // appearing before any node existed yet, 2026-09-04
                    // browser-verification finding) instead of snapping to
                    // full opacity the instant lesson data arrives, before
                    // the staggered nodes have drawn anything at all. Only
                    // opacity, never scale — the line's own geometry is
                    // already anchored to the real node positions, so
                    // scaling it (like _Stagger does for a node bubble)
                    // would pull its endpoints away from them mid-animation.
                    _FadeIn(
                      animation: _entrance,
                      interval: _staggerInterval(0, totalMs),
                      child: CustomPaint(
                        size: Size(width, height),
                        painter: LessonPathPainter(
                          positions: positions,
                          currentIndex: currentIndex,
                          currentProgress: currentProgress,
                          trackColor: scheme.outlineVariant,
                          progressColor: scheme.primary,
                        ),
                      ),
                    ),
                    for (var i = 0; i < nodes.length; i++) ...[
                      Positioned(
                        left: positions[i].dx - nodeRadius - 12,
                        top: positions[i].dy - nodeRadius - 12,
                        child: _Stagger(
                          animation: _entrance,
                          interval: _staggerInterval(i, totalMs),
                          child: LessonNodeWidget(data: nodes[i], onTap: () => _handleTap(widget.lessons[i], nodes[i])),
                        ),
                      ),
                      _positionedLabel(
                        node: nodes[i],
                        position: positions[i],
                        width: width,
                        nodeRadius: nodeRadius,
                        stagger: _Stagger(animation: _entrance, interval: _staggerInterval(i, totalMs), child: LessonNodeLabel(data: nodes[i], side: positions[i].dx <= width / 2 ? LabelSide.right : LabelSide.left)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _positionedLabel({required LessonNodeData node, required Offset position, required double width, required double nodeRadius, required Widget stagger}) {
    final onRight = position.dx <= width / 2;
    return Positioned(
      top: position.dy - 20,
      left: onRight ? position.dx + nodeRadius + _labelGap : _labelMargin,
      right: onRight ? _labelMargin : width - (position.dx - nodeRadius - _labelGap),
      child: stagger,
    );
  }
}

/// Opacity-only counterpart of [_Stagger], for the path line (see its call
/// site's comment for why it can't share [_Stagger]'s scale transform).
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.animation, required this.interval, required this.child});
  final Animation<double> animation;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Opacity(opacity: interval.transform(animation.value).clamp(0.0, 1.0), child: child),
    );
  }
}

/// Shared fade+scale entrance (§ staggered node appearance, 2026-09-04) —
/// one AnimationController for the whole map, this just reads its own
/// [Interval] slice of it. Used for both a node bubble and its label so the
/// two always animate in together.
class _Stagger extends StatelessWidget {
  const _Stagger({required this.animation, required this.interval, required this.child});
  final Animation<double> animation;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = interval.transform(animation.value).clamp(0.0, 1.0);
        return Opacity(opacity: t, child: Transform.scale(scale: 0.7 + 0.3 * t, child: child));
      },
    );
  }
}

import 'package:flutter/material.dart';

/// Draws the winding path connecting lesson nodes (§ lesson map,
/// 2026-09-04) — one continuous cubic-Bezier path, control points placed
/// directly above/below each anchor point (same X, midpoint Y) so the curve
/// enters and leaves every node moving straight up/down, never at an angle.
/// Two layers: the full path in a muted track color, then only the
/// "walked" portion redrawn in the accent color on top — the walked length
/// stops exactly [currentProgress] of the way into the segment leading to
/// the current node (PathMetric.extractPath), so the line's tip visually
/// matches how far into that lesson the learner actually is.
class LessonPathPainter extends CustomPainter {
  const LessonPathPainter({
    required this.positions,
    required this.currentIndex,
    required this.currentProgress,
    required this.trackColor,
    required this.progressColor,
    this.strokeWidth = 6,
  });

  final List<Offset> positions;
  // Index of the `current`-state node, or -1 when every lesson is
  // completed (the whole path is then drawn as walked).
  final int currentIndex;
  final double currentProgress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  static ({Offset c1, Offset c2}) _controlPoints(Offset start, Offset end) {
    final midY = (start.dy + end.dy) / 2;
    return (c1: Offset(start.dx, midY), c2: Offset(end.dx, midY));
  }

  Path _fullPath() {
    final path = Path()..moveTo(positions.first.dx, positions.first.dy);
    for (var i = 0; i < positions.length - 1; i++) {
      final start = positions[i];
      final end = positions[i + 1];
      final c = _controlPoints(start, end);
      path.cubicTo(c.c1.dx, c.c1.dy, c.c2.dx, c.c2.dy, end.dx, end.dy);
    }
    return path;
  }

  double _segmentLength(Offset start, Offset end) {
    final c = _controlPoints(start, end);
    final segment = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c.c1.dx, c.c1.dy, c.c2.dx, c.c2.dy, end.dx, end.dy);
    var length = 0.0;
    for (final metric in segment.computeMetrics()) {
      length += metric.length;
    }
    return length;
  }

  double _walkedLength() {
    if (currentIndex == -1) return double.infinity; // everything completed — draw it all
    double walked = 0;
    for (var i = 0; i < positions.length - 1; i++) {
      if (i < currentIndex - 1) {
        walked += _segmentLength(positions[i], positions[i + 1]);
      } else if (i == currentIndex - 1) {
        walked += _segmentLength(positions[i], positions[i + 1]) * currentProgress.clamp(0.0, 1.0);
        break;
      } else {
        break;
      }
    }
    return walked;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;
    final path = _fullPath();

    canvas.drawPath(
      path,
      Paint()
        ..color = trackColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    var remaining = _walkedLength();
    if (remaining <= 0) return;

    final progressPaint = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      if (remaining <= 0) break;
      canvas.drawPath(metric.extractPath(0, remaining.clamp(0, metric.length)), progressPaint);
      remaining -= metric.length;
    }
  }

  @override
  bool shouldRepaint(covariant LessonPathPainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.currentIndex != currentIndex ||
      oldDelegate.currentProgress != currentProgress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

import 'dart:ui';

import '../../../courses/presentation/courses_overview.dart';

/// A lesson's place on the Главное-screen path (§ lesson map, 2026-09-04) —
/// `locked`/`current` don't exist on LessonCard itself (only stage-level
/// locking does, inside one lesson); this enum and [buildLessonNodes] are
/// where that lesson-level state gets derived, purely from list order: the
/// first not-yet-completed lesson is `current`, everything after it is
/// `locked`, everything before (and it, once done) is `completed`. This
/// mirrors the flat list exactly as shown today — a lesson from a different
/// course later in the same language's list is still "next", by design (the
/// approved rule for this feature; the list has no per-course grouping to
/// begin with).
enum LessonNodeState { completed, current, locked }

class LessonNodeData {
  const LessonNodeData({
    required this.lessonId,
    required this.index,
    required this.title,
    required this.wordCount,
    required this.progress,
    required this.state,
  });

  final String lessonId;
  final int index;
  final String title;
  final int wordCount;
  // 0..1 — LessonCard.ratio, meaningful only for `current` (a completed
  // lesson is visually full regardless, a locked one is never shown).
  final double progress;
  final LessonNodeState state;
}

List<LessonNodeData> buildLessonNodes(List<LessonCard> lessons) {
  final firstIncomplete = lessons.indexWhere((l) => !l.completed);
  return [
    for (var i = 0; i < lessons.length; i++)
      LessonNodeData(
        lessonId: lessons[i].lessonId,
        index: i,
        title: lessons[i].title,
        wordCount: lessons[i].vocabularyCount,
        progress: lessons[i].ratio,
        state: firstIncomplete == -1 || i < firstIncomplete
            ? LessonNodeState.completed
            : (i == firstIncomplete ? LessonNodeState.current : LessonNodeState.locked),
      ),
  ];
}

/// Single source of truth for node coordinates (§ lesson map, 2026-09-04) —
/// both LessonPathPainter and the Positioned node widgets read from this
/// same list, so the line and the bubbles can never drift apart. Horizontal
/// offset cycles through the exact 4 fractions of half-width the design
/// calls for (not a continuous sine — a hand-tuned repeating pattern), Y
/// just steps down by [verticalStep] per node.
const _xFractionCycle = [-0.55, 0.0, 0.55, 0.0];

List<Offset> calculateNodePositions({
  required int count,
  required double width,
  double verticalStep = 160,
  double topPadding = 60,
}) {
  final centerX = width / 2;
  return [
    for (var i = 0; i < count; i++) Offset(centerX + _xFractionCycle[i % _xFractionCycle.length] * centerX, topPadding + i * verticalStep),
  ];
}

double totalMapHeight(int count, {double verticalStep = 160, double topPadding = 60, double bottomPadding = 120}) =>
    count == 0 ? 0 : topPadding + (count - 1) * verticalStep + bottomPadding;

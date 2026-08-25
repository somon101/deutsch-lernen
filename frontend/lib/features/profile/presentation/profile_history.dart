import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';

class LessonHistoryRow {
  const LessonHistoryRow({required this.lessonId, required this.title, this.summary});
  final String lessonId;
  final String title;
  final LessonProgressSummary? summary;
}

class ProfileHistoryData {
  const ProfileHistoryData({required this.rows, required this.overallProgressPercent});
  final List<LessonHistoryRow> rows;

  /// The one real, already-computable number in the old React stats grid:
  /// how far the learner has gotten across every legacy lesson, weighted by
  /// best score — an unattempted lesson counts as 0%, not excluded from the
  /// average. Mirrors ProfilePage.tsx's overallProgressPercent exactly.
  /// Null only when there are no legacy lessons at all.
  final int? overallProgressPercent;
}

/// Mirrors ProfilePage.tsx's history-loading effect: every legacy lesson
/// joined with the learner's own progress summary (null when never
/// attempted). Builder-course lessons are deliberately out of scope here —
/// the original page never included them either (see loader.ts's
/// listLessonIds, which only ever discovered the file-based legacy course).
final profileHistoryProvider = FutureProvider.autoDispose<ProfileHistoryData>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  final lessons = await repo.fetchLegacyLessons();
  final summaries = await repo.fetchProgressSummaries();

  final rows = <LessonHistoryRow>[];
  for (final lesson in lessons) {
    LessonProgressSummary? match;
    for (final s in summaries) {
      if (s.lessonId == lesson.lessonId) {
        match = s;
        break;
      }
    }
    rows.add(LessonHistoryRow(lessonId: lesson.lessonId, title: lesson.title, summary: match));
  }

  if (rows.isEmpty) return const ProfileHistoryData(rows: [], overallProgressPercent: null);
  final earned = rows.fold<int>(0, (sum, r) => sum + (r.summary?.bestScore ?? 0));
  return ProfileHistoryData(rows: rows, overallProgressPercent: (earned / rows.length).round());
});

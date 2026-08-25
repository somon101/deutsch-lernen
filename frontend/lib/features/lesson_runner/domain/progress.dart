import 'stage.dart';

/// Mirrors src/progress/types.ts's QuizResult/LessonProgress — the wire
/// shape PUT /api/me/lesson-state/:id sends/receives.
class QuizResult {
  const QuizResult({required this.total, required this.correct, required this.completedAt});

  final int total;
  final int correct;
  final String completedAt;

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
        total: json['total'] as int,
        correct: json['correct'] as int,
        completedAt: json['completedAt'] as String,
      );

  Map<String, dynamic> toJson() => {'total': total, 'correct': correct, 'completedAt': completedAt};
}

class LessonProgress {
  const LessonProgress({
    required this.lessonId,
    required this.completedStages,
    required this.vocabIndex,
    this.miniTestResult,
    this.practiceResult,
    this.reviewResult,
    required this.startedAt,
    this.completedAt,
  });

  factory LessonProgress.empty(String lessonId) => LessonProgress(
        lessonId: lessonId,
        completedStages: const {},
        vocabIndex: 0,
        startedAt: DateTime.now().toUtc().toIso8601String(),
      );

  factory LessonProgress.fromJson(Map<String, dynamic> json) => LessonProgress(
        lessonId: json['lessonId'] as String,
        completedStages: (json['completedStages'] as List<dynamic>).map((s) => stageFromId(s as String)).whereType<Stage>().toSet(),
        vocabIndex: json['vocabIndex'] as int? ?? 0,
        miniTestResult: json['miniTestResult'] != null ? QuizResult.fromJson(json['miniTestResult'] as Map<String, dynamic>) : null,
        practiceResult: json['practiceResult'] != null ? QuizResult.fromJson(json['practiceResult'] as Map<String, dynamic>) : null,
        reviewResult: json['reviewResult'] != null ? QuizResult.fromJson(json['reviewResult'] as Map<String, dynamic>) : null,
        startedAt: json['startedAt'] as String,
        completedAt: json['completedAt'] as String?,
      );

  final String lessonId;
  final Set<Stage> completedStages;
  final int vocabIndex;
  final QuizResult? miniTestResult;
  final QuizResult? practiceResult;
  final QuizResult? reviewResult;
  final String startedAt;
  final String? completedAt;

  LessonProgress copyWith({
    Set<Stage>? completedStages,
    int? vocabIndex,
    QuizResult? miniTestResult,
    QuizResult? practiceResult,
    QuizResult? reviewResult,
    String? completedAt,
  }) =>
      LessonProgress(
        lessonId: lessonId,
        completedStages: completedStages ?? this.completedStages,
        vocabIndex: vocabIndex ?? this.vocabIndex,
        miniTestResult: miniTestResult ?? this.miniTestResult,
        practiceResult: practiceResult ?? this.practiceResult,
        reviewResult: reviewResult ?? this.reviewResult,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => {
        'completedStages': completedStages.map((s) => s.name).toList(),
        'vocabIndex': vocabIndex,
        if (miniTestResult != null) 'miniTestResult': miniTestResult!.toJson(),
        if (practiceResult != null) 'practiceResult': practiceResult!.toJson(),
        if (reviewResult != null) 'reviewResult': reviewResult!.toJson(),
        'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
      };
}

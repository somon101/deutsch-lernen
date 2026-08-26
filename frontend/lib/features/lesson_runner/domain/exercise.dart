import 'dart:math';

/// Exact port of src/content/exercises.ts's Exercise union, plus
/// questionMapping.ts's toExercise()/exercisesForStage() — the one place
/// that converts a stored question (any of the 5 kinds, from any course)
/// into the shape the runner renders and grades. Every course (legacy or
/// builder) is now 100% DB-resident with real blocks (see the migration
/// plan §3's Решение 2), so this Dart port never needs a procedural
/// generator — it only ever maps already-authored/frozen questions.
sealed class Exercise {
  const Exercise(this.id);
  final String id;
}

class ChoiceQuestion extends Exercise {
  const ChoiceQuestion({required String id, required this.prompt, required this.options, required this.correctAnswer}) : super(id);
  final String prompt;
  final List<String> options;
  final String correctAnswer;
}

class TrueFalseQuestion extends Exercise {
  const TrueFalseQuestion({required String id, required this.statement, required this.correct, required this.explanation}) : super(id);
  final String statement;
  final bool correct;
  final String explanation;
}

class ClozeExercise extends Exercise {
  const ClozeExercise({
    required String id,
    required this.translation,
    required this.before,
    required this.after,
    required this.options,
    required this.answer,
  }) : super(id);
  final String translation;
  final String before;
  final String after;
  final List<String> options;
  final String answer;
}

class ScrambleExercise extends Exercise {
  const ScrambleExercise({required String id, required this.translation, required this.tokens, required this.answer}) : super(id);
  final String translation;
  final List<String> tokens;
  final List<String> answer;
}

class MatchPair {
  const MatchPair({required this.id, required this.left, required this.right});
  final String id;
  final String left;
  final String right;
}

class MatchExercise extends Exercise {
  const MatchExercise({required String id, required this.pairs}) : super(id);
  final List<MatchPair> pairs;
}

/// Raw shape a LessonQuestion row round-trips as (server's to_question_dto)
/// — the input to toExercise(), one level below the final Exercise shape.
class QuestionDto {
  const QuestionDto({
    required this.kind,
    required this.prompt,
    this.id,
    this.options = const [],
    this.correctAnswer = '',
    this.correct = false,
    this.pairs = const [],
  });

  factory QuestionDto.fromJson(Map<String, dynamic> json) => QuestionDto(
        kind: json['kind'] as String,
        id: json['id'] as String?,
        prompt: json['prompt'] as String? ?? '',
        options: (json['options'] as List<dynamic>?)?.cast<String>() ?? const [],
        correctAnswer: json['correctAnswer'] as String? ?? '',
        correct: json['correct'] as bool? ?? false,
        pairs: (json['pairs'] as List<dynamic>?)
                ?.map((p) => (left: (p as Map<String, dynamic>)['left'] as String, right: p['right'] as String))
                .toList() ??
            const [],
      );

  // Real, stable Question/LessonQuestion id — null only for shapes that
  // never carried one before this field existed (e.g. the legacy flat
  // "questions" list in ContentPayload, unrelated to the graded exercises).
  final String? id;
  final String kind;
  final String prompt;
  final List<String> options;
  final String correctAnswer;
  final bool correct;
  final List<({String left, String right})> pairs;
}

String _explanationFor(String prompt, bool correct) =>
    correct ? 'Утверждение верно: «$prompt»' : 'Утверждение неверно: «$prompt»';

({String before, String after}) _splitBlank(String prompt) {
  final parts = prompt.split('___');
  final before = parts.isNotEmpty ? parts[0].trim() : '';
  final after = parts.length > 1 ? parts[1].trim() : '';
  return (before: before, after: after);
}

final _random = Random();

List<T> _shuffle<T>(List<T> items) {
  final copy = List<T>.from(items);
  for (var i = copy.length - 1; i > 0; i--) {
    final j = _random.nextInt(i + 1);
    final tmp = copy[i];
    copy[i] = copy[j];
    copy[j] = tmp;
  }
  return copy;
}

/// Mirrors toExercise() exactly, including scramble's genuinely-random
/// (non-seeded) reshuffle on every call — matches Math.random() in the
/// original, not the deterministic generator (which no longer exists in
/// this stack — see the module doc comment above).
Exercise toExercise(QuestionDto q, String id) {
  switch (q.kind) {
    case 'truefalse':
      return TrueFalseQuestion(id: id, statement: q.prompt, correct: q.correct, explanation: _explanationFor(q.prompt, q.correct));
    case 'cloze':
      final split = _splitBlank(q.prompt);
      return ClozeExercise(id: id, translation: '', before: split.before, after: split.after, options: q.options, answer: q.correctAnswer);
    case 'scramble':
      final answer = q.correctAnswer.split(' ').where((w) => w.isNotEmpty).toList();
      return ScrambleExercise(id: id, translation: q.prompt, tokens: _shuffle(q.options), answer: answer);
    case 'match':
      return MatchExercise(
        id: id,
        pairs: [for (var i = 0; i < q.pairs.length; i++) MatchPair(id: '$id-$i', left: q.pairs[i].left, right: q.pairs[i].right)],
      );
    case 'choice':
    default:
      return ChoiceQuestion(id: id, prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer);
  }
}

class QuestionBlock {
  const QuestionBlock({required this.id, required this.stage, required this.position, required this.questions});

  factory QuestionBlock.fromJson(Map<String, dynamic> json) => QuestionBlock(
        id: json['id'] as String,
        stage: json['stage'] as String,
        position: json['position'] as int,
        questions: (json['questions'] as List<dynamic>).map((q) => QuestionDto.fromJson(q as Map<String, dynamic>)).toList(),
      );

  final String id;
  final String stage;
  final int position;
  final List<QuestionDto> questions;
}

/// Flattens a stage's named blocks (ordered by block position, then
/// question position) into the flat exercise list the runner expects —
/// mirrors exercisesForStage() exactly.
List<Exercise> exercisesForStage(List<QuestionBlock> blocks, String stage) {
  final stageBlocks = blocks.where((b) => b.stage == stage).toList()..sort((a, b) => a.position.compareTo(b.position));
  return [
    for (final block in stageBlocks)
      for (var i = 0; i < block.questions.length; i++)
        toExercise(block.questions[i], block.questions[i].id ?? '${block.id}-$i'),
  ];
}

import 'dart:math';

/// Exact port of src/content/exercises.ts's Exercise union, plus
/// questionMapping.ts's toExercise()/exercisesForStage() — the one place
/// that converts a stored question (any of the 5 kinds, from any course)
/// into the shape the runner renders and grades. Every course (legacy or
/// builder) is now 100% DB-resident with real blocks (see the migration
/// plan §3's Решение 2), so this Dart port never needs a procedural
/// generator — it only ever maps already-authored/frozen questions.
sealed class Exercise {
  const Exercise(this.id, this.placementId);
  final String id;
  // Which specific use of this question this is (§ approved architecture,
  // 2026-08-27) — null for the old, non-reusable LessonQuestion path, where
  // the question itself is already 1:1 with one lesson. Sent back with the
  // answer so the server can scope progress to the lesson this placement
  // belongs to, instead of crediting every lesson that happens to reuse the
  // same underlying question.
  final String? placementId;
}

class ChoiceQuestion extends Exercise {
  const ChoiceQuestion({required String id, String? placementId, required this.prompt, required this.options, required this.correctAnswer})
      : super(id, placementId);
  final String prompt;
  final List<String> options;
  final String correctAnswer;
}

class TrueFalseQuestion extends Exercise {
  const TrueFalseQuestion({required String id, String? placementId, required this.statement, required this.correct, required this.explanation})
      : super(id, placementId);
  final String statement;
  final bool correct;
  final String explanation;
}

class ClozeExercise extends Exercise {
  const ClozeExercise({
    required String id,
    String? placementId,
    required this.translation,
    required this.before,
    required this.after,
    required this.options,
    required this.answer,
  }) : super(id, placementId);
  final String translation;
  final String before;
  final String after;
  final List<String> options;
  final String answer;
}

class ScrambleExercise extends Exercise {
  const ScrambleExercise({required String id, String? placementId, required this.translation, required this.tokens, required this.answer})
      : super(id, placementId);
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
  const MatchExercise({required String id, String? placementId, required this.pairs}) : super(id, placementId);
  final List<MatchPair> pairs;
}

/// One phrase slot of an auto-generated "missing word" exercise (§ auto
/// blank, 2026-08-31) — deliberately carries NO prompt/options of its own.
/// Unlike every other Exercise subclass, this one's actual question (which
/// word got blanked, what the options are) isn't known yet at content-fetch
/// time — it's resolved per-learner via a separate call
/// (AutoBlankRepository.generate), ideally already sitting in the runner's
/// prefetch buffer by the time this slot is reached.
class AutoBlankSlot extends Exercise {
  const AutoBlankSlot({required String id, String? placementId, required this.questionId, required this.phraseIndex}) : super(id, placementId);
  // The stable Question.id (the teacher's authored exercise) - NOT the same
  // as this slot's own `id` (which is "questionId::phraseIndex", unique per
  // slot) - the generate/answer endpoints need this real id.
  final String questionId;
  final int phraseIndex;
}

/// One "translate the word" slot (§ auto translate, 2026-09-02). Carries no
/// content for the same reason AutoBlankSlot doesn't: the word, its options
/// and the correct answer are resolved per learner and per session when the
/// slot is actually reached.
class AutoTranslateSlot extends Exercise {
  const AutoTranslateSlot({required String id, String? placementId, required this.questionId, required this.slotIndex}) : super(id, placementId);
  final String questionId;
  final int slotIndex;
}

/// One option shown for a generated auto_blank question — `wordId` is set
/// for a wrong option (a real learned-word card) and null for the correct
/// one (just the text actually removed from the phrase — clarified in
/// conversation: the blanked word doesn't need a matching word card).
class BlankOption {
  const BlankOption({required this.text, this.wordId});

  factory BlankOption.fromJson(Map<String, dynamic> json) => BlankOption(text: json['text'] as String, wordId: json['wordId'] as String?);

  final String text;
  final String? wordId;
}

/// The result of GET /api/questions/{id}/blank/{phraseIndex} (§ auto blank,
/// 2026-08-31) — `generatedQuestionId` is an opaque, server-signed token;
/// it must be echoed back unmodified when answering (LessonRepository.
/// submitBlankAnswer), since the server re-derives correctness from it
/// rather than trusting anything the client claims.
class GeneratedBlankQuestion {
  const GeneratedBlankQuestion({required this.generatedQuestionId, required this.promptWithBlank, required this.options});

  factory GeneratedBlankQuestion.fromJson(Map<String, dynamic> json) => GeneratedBlankQuestion(
        generatedQuestionId: json['generatedQuestionId'] as String,
        promptWithBlank: json['promptWithBlank'] as String,
        options: (json['options'] as List<dynamic>).map((o) => BlankOption.fromJson(o as Map<String, dynamic>)).toList(),
      );

  final String generatedQuestionId;
  final String promptWithBlank;
  final List<BlankOption> options;
}

/// The result of GET /api/questions/{id}/translate/{slotIndex} (§ auto
/// translate, 2026-09-02). Same signed-token contract as the blank version:
/// `generatedQuestionId` goes back unmodified when answering, and the
/// response never says which option is correct.
class GeneratedTranslateQuestion {
  const GeneratedTranslateQuestion({required this.generatedQuestionId, required this.prompt, required this.word, required this.options});

  factory GeneratedTranslateQuestion.fromJson(Map<String, dynamic> json) => GeneratedTranslateQuestion(
        generatedQuestionId: json['generatedQuestionId'] as String,
        prompt: json['prompt'] as String,
        word: json['word'] as String,
        options: (json['options'] as List<dynamic>).map((o) => BlankOption.fromJson(o as Map<String, dynamic>)).toList(),
      );

  final String generatedQuestionId;
  final String prompt;
  final String word;
  final List<BlankOption> options;
}

/// Raw shape a LessonQuestion row round-trips as (server's to_question_dto)
/// — the input to toExercise(), one level below the final Exercise shape.
class QuestionDto {
  const QuestionDto({
    required this.kind,
    required this.prompt,
    this.id,
    this.placementId,
    this.options = const [],
    this.correctAnswer = '',
    this.correct = false,
    this.pairs = const [],
    this.questionId,
    this.phraseIndex,
    this.slotIndex,
  });

  factory QuestionDto.fromJson(Map<String, dynamic> json) => QuestionDto(
        kind: json['kind'] as String,
        id: json['id'] as String?,
        placementId: json['placementId'] as String?,
        prompt: json['prompt'] as String? ?? '',
        options: (json['options'] as List<dynamic>?)?.cast<String>() ?? const [],
        correctAnswer: json['correctAnswer'] as String? ?? '',
        correct: json['correct'] as bool? ?? false,
        pairs: (json['pairs'] as List<dynamic>?)
                ?.map((p) => (left: (p as Map<String, dynamic>)['left'] as String, right: p['right'] as String))
                .toList() ??
            const [],
        questionId: json['questionId'] as String?,
        phraseIndex: json['phraseIndex'] as int?,
        slotIndex: json['slotIndex'] as int?,
      );

  // Real, stable Question/LessonQuestion id — null only for shapes that
  // never carried one before this field existed (e.g. the legacy flat
  // "questions" list in ContentPayload, unrelated to the graded exercises).
  final String? id;
  // Which QuestionPlacement this specific appearance came from — null for
  // the old LessonQuestion path (never reusable, so no placement concept).
  final String? placementId;
  final String kind;
  final String prompt;
  final List<String> options;
  final String correctAnswer;
  final bool correct;
  final List<({String left, String right})> pairs;
  // auto_blank only (§ auto blank, 2026-08-31) — the real Question.id this
  // slot's generation/answer calls target, and which phrase (in the
  // teacher's own order) this slot is.
  final String? questionId;
  final int? phraseIndex;
  // auto_translate only — which of the question's requested slots this is.
  final int? slotIndex;
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
      return TrueFalseQuestion(
        id: id,
        placementId: q.placementId,
        statement: q.prompt,
        correct: q.correct,
        explanation: _explanationFor(q.prompt, q.correct),
      );
    case 'cloze':
      final split = _splitBlank(q.prompt);
      return ClozeExercise(
        id: id,
        placementId: q.placementId,
        translation: '',
        before: split.before,
        after: split.after,
        options: q.options,
        answer: q.correctAnswer,
      );
    case 'scramble':
      final answer = q.correctAnswer.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      // The server already derives the pieces from the phrase when a
      // question is in auto mode (§ auto scramble, 2026-09-02); deriving
      // them again here keeps a payload that predates that — a cached
      // lesson on disk, say — from rendering an exercise with no tokens at
      // all. The shuffle itself stays here, unseeded and recomputed every
      // time this runs, so each pass through the stage gets a fresh order.
      final pieces = q.options.isNotEmpty ? q.options : answer;
      return ScrambleExercise(id: id, placementId: q.placementId, translation: q.prompt, tokens: _shuffle(pieces), answer: answer);
    case 'match':
      return MatchExercise(
        id: id,
        placementId: q.placementId,
        pairs: [for (var i = 0; i < q.pairs.length; i++) MatchPair(id: '$id-$i', left: q.pairs[i].left, right: q.pairs[i].right)],
      );
    case 'auto_blank':
      return AutoBlankSlot(id: id, placementId: q.placementId, questionId: q.questionId!, phraseIndex: q.phraseIndex!);
    case 'auto_translate':
      return AutoTranslateSlot(id: id, placementId: q.placementId, questionId: q.questionId!, slotIndex: q.slotIndex!);
    case 'choice':
    default:
      return ChoiceQuestion(id: id, placementId: q.placementId, prompt: q.prompt, options: q.options, correctAnswer: q.correctAnswer);
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

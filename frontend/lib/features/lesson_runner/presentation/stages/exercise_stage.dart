import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/sound_effects.dart';
import '../../data/lesson_repository.dart';
import '../../domain/exercise.dart';
import '../../domain/progress.dart';
import '../../domain/stage.dart';
import '../lesson_runner_controller.dart';
import '../widgets/auto_blank_question.dart';
import '../widgets/auto_match_question.dart';
import '../widgets/auto_translate_question.dart';
import '../widgets/choice_question.dart';
import '../widgets/cloze_question.dart';
import '../widgets/match_question.dart';
import '../widgets/scramble_question.dart';
import '../widgets/truefalse_question.dart';

/// How many upcoming auto_blank slots to keep generated ahead of the
/// learner (§11, "буфер = 3-5 следующих вопросов") — small enough that
/// opening a lesson never fires a burst of requests, big enough that
/// normal forward progress essentially never waits on a live generation.
const _blankBufferSize = 3;

/// Per-exercise time caps (§ time tracking, 2026-08-29) — an exercise left
/// open longer than this contributes at most this many seconds. Matching
/// gets more time since it's inherently a multi-step task (several pairs),
/// unlike every other kind here which is answered in one action.
int _exerciseCapSeconds(Exercise e) => (e is MatchExercise || e is AutoMatchSlot) ? 90 : 60;

String _kindLabel(Exercise e) => switch (e) {
      ChoiceQuestion() => 'Выбор ответа',
      TrueFalseQuestion() => 'Верно или неверно',
      MatchExercise() => 'Сопоставление',
      ScrambleExercise() => 'Собери фразу',
      ClozeExercise() => 'Заполни пропуск',
      AutoBlankSlot() => 'Пропущенное слово',
      AutoTranslateSlot() => 'Переведи слово',
      AutoMatchSlot() => 'Сопоставление',
    };

String _prompt(Exercise e) => switch (e) {
      ChoiceQuestion() => e.prompt,
      TrueFalseQuestion() => e.statement,
      MatchExercise() => 'Сопоставление слов и переводов',
      ScrambleExercise() => 'Фраза по переводу «${e.translation}»',
      ClozeExercise() => 'Пропуск во фразе «${e.translation}»',
      // The actual phrase only exists inside the generated version, held
      // by the widget itself (§ auto blank, 2026-08-31) — not on the
      // static Exercise the results screen re-reads after the fact.
      AutoBlankSlot() => 'Пропущенное слово',
      // Same as the blank slots: the word this slot resolved to lives in
      // the generated version the widget held, not on the static Exercise
      // the results screen re-reads afterwards.
      AutoTranslateSlot() => 'Переведи слово',
      AutoMatchSlot() => 'Сопоставление слов и переводов',
    };

String _correctAnswerLabel(Exercise e) => switch (e) {
      ChoiceQuestion() => 'Правильный ответ: «${e.correctAnswer}»',
      TrueFalseQuestion() => e.explanation,
      MatchExercise() => 'Не все пары были сопоставлены с первой попытки',
      ScrambleExercise() => 'Правильно: «${e.answer.join(" ")}»',
      ClozeExercise() => 'Правильное слово: «${e.answer}»',
      AutoBlankSlot() => 'Подробности — в истории ответов',
      AutoTranslateSlot() => 'Подробности — в истории ответов',
      AutoMatchSlot() => 'Подробности — в истории ответов',
    };

/// Mirrors ExerciseRunner.tsx: runs one stage's flat exercise list
/// (minitest/practice/review, per exercisesForStage), tracks score, plays a
/// correct/incorrect chime per question, shows a final results screen with
/// missed questions, then reports the score up through
/// LessonRunnerController.recordQuizResult before advancing.
class ExerciseStage extends ConsumerStatefulWidget {
  const ExerciseStage({super.key, required this.runnerKey, required this.stage, required this.onComplete});

  final LessonRunnerKey runnerKey;
  final Stage stage;
  final VoidCallback onComplete;

  @override
  ConsumerState<ExerciseStage> createState() => _ExerciseStageState();
}

class _ExerciseStageState extends ConsumerState<ExerciseStage> {
  late final List<Exercise> _exercises =
      ref.read(lessonRunnerControllerProvider(widget.runnerKey)).value!.content.exercisesFor(widget.stage.name);
  final List<bool> _results = [];
  int _index = 0;
  bool _answered = false;
  bool _finished = false;
  final _focusNode = FocusNode();
  DateTime _exerciseShownAt = DateTime.now();

  /// Held as a field so `dispose()` can still report the time for a stage
  /// the learner walked out of half-way. Reading `ref` during dispose is not
  /// merely discouraged — flutter_riverpod throws a StateError ("Using
  /// "ref" when a widget is about to or has been unmounted is unsafe"), and
  /// because that throw happened before `super.dispose()`, the FocusNode
  /// leaked and the time was lost anyway (§ dispose-time flush, 2026-09-02).
  LessonRunnerController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier);
  }

  // Prefetch buffer for auto_blank slots (§11, "буфер = 3-5 следующих
  // вопросов") — keyed by exercise index so re-visiting an index (there is
  // none in this linear runner, but it's a cheap safety) never re-fires a
  // request; a cached null means generation genuinely failed for that slot,
  // not "not tried yet".
  final Map<int, Future<GeneratedBlankQuestion?>> _blankBuffer = {};
  // Same prefetch buffer, for "translate the word" slots.
  final Map<int, Future<GeneratedTranslateQuestion?>> _translateBuffer = {};
  final Map<int, Future<GeneratedMatchQuestion?>> _matchBuffer = {};

  @override
  void initState() {
    super.initState();
    _prefetchBlanksAhead();
  }

  void _prefetchBlanksAhead() {
    final end = (_index + _blankBufferSize).clamp(0, _exercises.length);
    for (var i = _index; i < end; i++) {
      final ex = _exercises[i];
      if (ex is AutoBlankSlot) {
        _blankBuffer.putIfAbsent(i, () => ref.read(lessonRepositoryProvider).generateBlankQuestion(ex.questionId, ex.phraseIndex));
      }
      if (ex is AutoTranslateSlot) {
        _translateBuffer.putIfAbsent(i, () => ref.read(lessonRepositoryProvider).generateTranslateQuestion(ex.questionId, ex.slotIndex));
      }
      if (ex is AutoMatchSlot) {
        _matchBuffer.putIfAbsent(i, () => ref.read(lessonRepositoryProvider).generateMatchQuestion(ex.questionId));
      }
    }
  }

  int get _correct => _results.where((r) => r).length;

  /// Flushes the exercise being LEFT (still `_exercises[_index]` at call
  /// time) before advancing to the next one or leaving the stage —
  /// minitest/practice/review each keep their own time bucket via
  /// `widget.stage.name`, per exercise, capped per §5 of the time spec.
  void _flushExercise() {
    if (_index >= _exercises.length) return;
    final cap = _exerciseCapSeconds(_exercises[_index]);
    final elapsed = DateTime.now().difference(_exerciseShownAt).inSeconds.clamp(0, cap);
    _exerciseShownAt = DateTime.now();
    if (elapsed > 0) {
      _controller?.recordActivityTime(widget.stage.name, elapsed);
    }
  }

  Future<void> _handleAnswered(bool correct) async {
    if (_results.length > _index) {
      _results[_index] = correct;
    } else {
      _results.add(correct);
    }
    setState(() => _answered = true);
    final sounds = ref.read(soundEffectsProvider);
    if (correct) {
      await sounds.playCorrect();
    } else {
      await sounds.playIncorrect();
    }
    // auto_blank already wrote its own AnswerLog row server-side (with the
    // richer generated-question snapshot) inside AutoBlankQuestionView's
    // own submitBlankAnswer call — calling the generic submitAnswer here
    // too would either double-write history or (since this slot's `id` is
    // a synthetic "questionId::phraseIndex" string, not a real Question/
    // LessonQuestion row) just 404 harmlessly. Either way, skip it.
    final current = _exercises[_index];
    if (current is! AutoBlankSlot && current is! AutoTranslateSlot && current is! AutoMatchSlot) {
      try {
        await ref
            .read(lessonRepositoryProvider)
            .submitAnswer(_exercises[_index].id, correct, placementId: _exercises[_index].placementId);
      } catch (_) {
        // Best-effort — a logging failure must never block the quiz flow.
      }
    }
  }

  void _next() {
    _flushExercise();
    if (_index + 1 < _exercises.length) {
      setState(() {
        _index += 1;
        _answered = false;
      });
      _prefetchBlanksAhead();
    } else {
      setState(() => _finished = true);
    }
  }

  Future<void> _finish() async {
    final controller = ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier);
    await controller.recordQuizResult(
      widget.stage,
      QuizResult(total: _exercises.length, correct: _correct, completedAt: DateTime.now().toUtc().toIso8601String()),
    );
    widget.onComplete();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.enter) return KeyEventResult.ignored;
    if (_finished) {
      _finish();
      return KeyEventResult.handled;
    }
    if (_answered) {
      _next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (!_finished) _flushExercise();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_exercises.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Недостаточно материала для этого блока — переходим дальше.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _finish, child: const Text('Далее')),
          ],
        ),
      );
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _finished ? _ResultsView(exercises: _exercises, results: _results, correct: _correct, onContinue: _finish) : _buildQuestion(context),
      ),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final current = _exercises[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Задание ${_index + 1} из ${_exercises.length}'),
            Text('$_correct правильно'),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _index / _exercises.length, minHeight: 6),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_kindLabel(current), style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 12),
                    _questionWidget(current),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_answered) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _next,
              child: Text(_index + 1 < _exercises.length ? 'Следующее (Enter)' : 'Завершить (Enter)'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _questionWidget(Exercise exercise) {
    return switch (exercise) {
      ChoiceQuestion() => ChoiceQuestionView(key: ValueKey(exercise.id), exercise: exercise, onAnswered: _handleAnswered),
      TrueFalseQuestion() => TrueFalseQuestionView(key: ValueKey(exercise.id), exercise: exercise, onAnswered: _handleAnswered),
      ClozeExercise() => ClozeQuestionView(key: ValueKey(exercise.id), exercise: exercise, onAnswered: _handleAnswered),
      ScrambleExercise() => ScrambleQuestionView(key: ValueKey(exercise.id), exercise: exercise, onAnswered: _handleAnswered),
      MatchExercise() => MatchQuestionView(key: ValueKey(exercise.id), exercise: exercise, onAnswered: _handleAnswered),
      AutoBlankSlot() => AutoBlankQuestionView(
          key: ValueKey(exercise.id),
          exercise: exercise,
          prefetched: _blankBuffer.putIfAbsent(
            _index,
            () => ref.read(lessonRepositoryProvider).generateBlankQuestion(exercise.questionId, exercise.phraseIndex),
          ),
          onAnswered: _handleAnswered,
          onSkip: _next,
        ),
      AutoMatchSlot() => AutoMatchQuestionView(
          key: ValueKey(exercise.id),
          exercise: exercise,
          prefetched: _matchBuffer.putIfAbsent(
            _index,
            () => ref.read(lessonRepositoryProvider).generateMatchQuestion(exercise.questionId),
          ),
          onAnswered: _handleAnswered,
          onSkip: _next,
        ),
      AutoTranslateSlot() => AutoTranslateQuestionView(
          key: ValueKey(exercise.id),
          exercise: exercise,
          prefetched: _translateBuffer.putIfAbsent(
            _index,
            () => ref.read(lessonRepositoryProvider).generateTranslateQuestion(exercise.questionId, exercise.slotIndex),
          ),
          onAnswered: _handleAnswered,
          onSkip: _next,
        ),
    };
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.exercises, required this.results, required this.correct, required this.onContinue});

  final List<Exercise> exercises;
  final List<bool> results;
  final int correct;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final mistakes = [
      for (var i = 0; i < exercises.length; i++)
        if (i >= results.length || !results[i]) exercises[i],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('Результат', style: Theme.of(context).textTheme.labelLarge),
        Text('$correct / ${exercises.length}', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 4),
        Text(correct == exercises.length ? 'Отлично, всё верно!' : 'Хороший результат. Разберём ошибки ниже.'),
        const SizedBox(height: 16),
        if (mistakes.isNotEmpty)
          Expanded(
            child: ListView.separated(
              itemCount: mistakes.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final m = mistakes[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${_prompt(m)} — ${_correctAnswerLabel(m)}'),
                );
              },
            ),
          )
        else
          const Spacer(),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onContinue, child: const Text('Продолжить (Enter)')),
      ],
    );
  }
}

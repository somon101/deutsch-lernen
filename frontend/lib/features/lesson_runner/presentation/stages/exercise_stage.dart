import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/sound_effects.dart';
import '../../data/lesson_repository.dart';
import '../../domain/exercise.dart';
import '../../domain/progress.dart';
import '../../domain/stage.dart';
import '../lesson_runner_controller.dart';
import '../widgets/choice_question.dart';
import '../widgets/cloze_question.dart';
import '../widgets/match_question.dart';
import '../widgets/scramble_question.dart';
import '../widgets/truefalse_question.dart';

String _kindLabel(Exercise e) => switch (e) {
      ChoiceQuestion() => 'Выбор ответа',
      TrueFalseQuestion() => 'Верно или неверно',
      MatchExercise() => 'Сопоставление',
      ScrambleExercise() => 'Собери фразу',
      ClozeExercise() => 'Заполни пропуск',
    };

String _prompt(Exercise e) => switch (e) {
      ChoiceQuestion() => e.prompt,
      TrueFalseQuestion() => e.statement,
      MatchExercise() => 'Сопоставление слов и переводов',
      ScrambleExercise() => 'Фраза по переводу «${e.translation}»',
      ClozeExercise() => 'Пропуск во фразе «${e.translation}»',
    };

String _correctAnswerLabel(Exercise e) => switch (e) {
      ChoiceQuestion() => 'Правильный ответ: «${e.correctAnswer}»',
      TrueFalseQuestion() => e.explanation,
      MatchExercise() => 'Не все пары были сопоставлены с первой попытки',
      ScrambleExercise() => 'Правильно: «${e.answer.join(" ")}»',
      ClozeExercise() => 'Правильное слово: «${e.answer}»',
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

  int get _correct => _results.where((r) => r).length;

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
    try {
      await ref.read(lessonRepositoryProvider).submitAnswer(_exercises[_index].id, correct);
    } catch (_) {
      // Best-effort — a logging failure must never block the quiz flow.
    }
  }

  void _next() {
    if (_index + 1 < _exercises.length) {
      setState(() {
        _index += 1;
        _answered = false;
      });
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

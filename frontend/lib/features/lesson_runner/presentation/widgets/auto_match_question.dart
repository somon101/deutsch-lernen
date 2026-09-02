import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lesson_repository.dart';
import '../../domain/exercise.dart';
import 'exercise_common.dart';

/// Renders one generated matching exercise (§ auto match, 2026-09-02).
///
/// Deliberately the same interaction as the hand-built "Сопоставление":
/// tap a word, then tap its translation. What differs is only where the
/// pairs come from — they are generated per learner and per session, and
/// graded server-side from a signed payload rather than locally.
class AutoMatchQuestionView extends ConsumerStatefulWidget {
  const AutoMatchQuestionView({
    super.key,
    required this.exercise,
    this.prefetched,
    required this.onAnswered,
    this.onSkip,
  });

  final AutoMatchSlot exercise;
  final Future<GeneratedMatchQuestion?>? prefetched;
  final ValueChanged<bool> onAnswered;

  /// Called instead of [onAnswered] when the learner doesn't have enough
  /// words yet for the configured number of pairs, so the stage advances
  /// without recording a result for something never shown.
  final VoidCallback? onSkip;

  @override
  ConsumerState<AutoMatchQuestionView> createState() => _AutoMatchQuestionViewState();
}

class _AutoMatchQuestionViewState extends ConsumerState<AutoMatchQuestionView> {
  late final Future<GeneratedMatchQuestion?> _generation =
      widget.prefetched ?? ref.read(lessonRepositoryProvider).generateMatchQuestion(widget.exercise.questionId);

  String? _selectedLeft;
  // wordId -> the translation text the learner attached to it.
  final Map<String, String> _matched = {};
  bool _busy = false;
  bool? _result;
  String? _error;

  Future<void> _submit(GeneratedMatchQuestion q) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final correct = await ref.read(lessonRepositoryProvider).submitMatchAnswer(
            widget.exercise.questionId,
            generatedQuestionId: q.generatedQuestionId,
            pairs: [for (final e in _matched.entries) (wordId: e.key, right: e.value)],
            placementId: widget.exercise.placementId,
          );
      if (!mounted) return;
      setState(() {
        _result = correct;
        _busy = false;
      });
      widget.onAnswered(correct);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось отправить ответ. Попробуйте ещё раз.';
      });
    }
  }

  void _tapRight(GeneratedMatchQuestion q, MatchOption right) {
    final left = _selectedLeft;
    if (left == null || _result != null) return;
    setState(() {
      _matched[left] = right.text;
      _selectedLeft = null;
    });
    if (_matched.length == q.left.length) _submit(q);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GeneratedMatchQuestion?>(
      future: _generation,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final q = snapshot.data;
        if (q == null) {
          final onSkip = widget.onSkip;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(onSkip != null
                    ? 'Пока не хватает изученных слов для этого упражнения — переходим дальше.'
                    : 'Пока не хватает изученных слов для этого упражнения.'),
                if (onSkip != null) ...[
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: onSkip, child: const Text('Продолжить')),
                ],
              ],
            ),
          );
        }

        final usedRights = _matched.values.toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Соедините слова с переводами', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      for (final l in q.left)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OptionButton(
                            label: _matched.containsKey(l.wordId) ? '${l.text} → ${_matched[l.wordId]}' : l.text,
                            state: _matched.containsKey(l.wordId)
                                ? OptionState.correct
                                : _selectedLeft == l.wordId
                                    ? OptionState.incorrect
                                    : OptionState.neutral,
                            onTap: _result != null || _matched.containsKey(l.wordId)
                                ? null
                                : () => setState(() => _selectedLeft = l.wordId),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (final r in q.right)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OptionButton(
                            label: r.text,
                            state: usedRights.contains(r.text) ? OptionState.correct : OptionState.neutral,
                            onTap: _result != null || _selectedLeft == null || usedRights.contains(r.text)
                                ? null
                                : () => _tapRight(q, r),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 8),
              FeedbackBanner(
                correct: _result!,
                text: _result! ? 'Верно!' : 'Неверно. Не все пары совпали.',
              ),
            ],
          ],
        );
      },
    );
  }
}

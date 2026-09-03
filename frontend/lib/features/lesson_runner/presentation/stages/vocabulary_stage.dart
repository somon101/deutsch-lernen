import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lesson_runner_controller.dart';
import '../widgets/word_card_deck.dart';

/// Per-word time cap (§ time tracking, 2026-08-29) — a word left open longer
/// than this contributes at most this many seconds.
const _wordCapSeconds = 10;

/// Swipeable word-card deck (§ word card deck, 2026-08-31) — flips through
/// content.newVocabulary, persisting vocabIndex as the learner moves
/// through them; skips gracefully if the list is empty (nothing new to
/// learn in this lesson). The actual card rendering/gestures live in the
/// reusable WordCardDeck widget; this stage only wires it to this lesson's
/// data and progress persistence.
class VocabularyStage extends ConsumerStatefulWidget {
  const VocabularyStage({super.key, required this.runnerKey, required this.onComplete, this.initialIndexOverride, this.onIndexChanged});

  final LessonRunnerKey runnerKey;
  final VoidCallback onComplete;
  // A graph lesson (§ lesson graph, 2026-09-03) persists vocabIndex through
  // its own controller instead of the legacy one below — writing through
  // the legacy controller would blindly overwrite the graph's own
  // completedStages (node ids) back to empty on every save, since
  // LessonRunnerController's LessonProgress never learns about them (see
  // GraphLessonProgress's docstring). Both null keep the original,
  // single-shared-vocabulary-list behavior unchanged.
  final int? initialIndexOverride;
  final ValueChanged<int>? onIndexChanged;

  @override
  ConsumerState<VocabularyStage> createState() => _VocabularyStageState();
}

class _VocabularyStageState extends ConsumerState<VocabularyStage> {
  DateTime _wordShownAt = DateTime.now();

  /// Held as a field so `dispose()` can still report the time for a stage
  /// the learner walked out of. Reading `ref` during dispose is not merely
  /// discouraged — flutter_riverpod throws, and because the throw landed
  /// before `super.dispose()`, the time was lost AND the dispose contract
  /// was broken (§ daily goal, 2026-09-03; same fix already applied to
  /// exercise_stage).
  LessonRunnerController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier);
  }

  /// Flushes the word being LEFT before moving to another word or leaving
  /// the stage entirely.
  void _flushWord() {
    final elapsed = DateTime.now().difference(_wordShownAt).inSeconds.clamp(0, _wordCapSeconds);
    _wordShownAt = DateTime.now();
    if (elapsed > 0) {
      _controller?.recordActivityTime('vocabulary', elapsed);
    }
  }

  void _onCardChanged(int index) {
    _flushWord();
    final onIndexChanged = widget.onIndexChanged;
    if (onIndexChanged != null) {
      onIndexChanged(index);
    } else {
      ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier).setVocabIndex(index);
    }
  }

  @override
  void dispose() {
    _flushWord();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(lessonRunnerControllerProvider(widget.runnerKey)).value!;
    final words = data.content.newVocabulary;

    if (words.isEmpty) {
      return _EmptyStage(
        message: 'В этом уроке нет новых слов — все они уже встречались раньше.',
        onContinue: widget.onComplete,
      );
    }

    final initialIndex = (widget.initialIndexOverride ?? data.progress.vocabIndex).clamp(0, words.length - 1);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: WordCardDeck(
          courseId: widget.runnerKey.courseId ?? 'legacy',
          initialIndex: initialIndex,
          onCardChanged: _onCardChanged,
          onComplete: widget.onComplete,
          words: [
            for (final w in words)
              WordDeckCard(id: w.id, word: w.german, translation: w.translation, ipa: w.pronunciation, imageUrl: w.imageUrl, audioUrl: w.audioUrl),
          ],
        ),
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.message, required this.onContinue});
  final String message;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onContinue, child: const Text('Далее')),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/word_audio_button.dart';
import '../lesson_runner_controller.dart';

/// Mirrors VocabularyStage.tsx: flips through content.newVocabulary word
/// cards, persisting vocabIndex as the learner moves through them; skips
/// gracefully if the list is empty (nothing new to learn in this lesson).
class VocabularyStage extends ConsumerWidget {
  const VocabularyStage({super.key, required this.runnerKey, required this.onComplete});

  final LessonRunnerKey runnerKey;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(lessonRunnerControllerProvider(runnerKey)).value!;
    final words = data.content.newVocabulary;

    if (words.isEmpty) {
      return _EmptyStage(
        message: 'В этом уроке нет новых слов — все они уже встречались раньше.',
        onContinue: onComplete,
      );
    }

    final index = data.progress.vocabIndex.clamp(0, words.length - 1);
    final word = words[index];
    final controller = ref.read(lessonRunnerControllerProvider(runnerKey).notifier);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Слово ${index + 1} из ${words.length}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(word.german, style: Theme.of(context).textTheme.headlineMedium),
                      WordAudioButton(word: word.german, audioUrl: word.audioUrl),
                    ],
                  ),
                  if (word.pronunciation != null) ...[
                    const SizedBox(height: 4),
                    Text('[${word.pronunciation}]', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 16),
                  Text(word.translation, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: index > 0 ? () => controller.setVocabIndex(index - 1) : null,
                child: const Text('← Назад'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (index < words.length - 1) {
                    controller.setVocabIndex(index + 1);
                  } else {
                    onComplete();
                  }
                },
                child: Text(index < words.length - 1 ? 'Далее' : 'Перейти к материалу'),
              ),
            ],
          ),
        ],
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

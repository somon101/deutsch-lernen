import 'package:flutter/material.dart';

import '../../domain/lesson_graph.dart';

/// The «Фразы» step of a graph lesson (§ course modules, 2026-10-05):
/// the phrases the teacher picked from the phrase base, each with its
/// translation in the learner's content language, then "next".
class PhrasesStage extends StatelessWidget {
  const PhrasesStage({super.key, required this.phrases, required this.onComplete, required this.nextLabel});

  final List<GraphPhrase> phrases;
  final VoidCallback onComplete;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: phrases.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = phrases[i];
                return Card(
                  elevation: 0,
                  color: scheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(p.text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                        if (p.translation.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(p.translation, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(width: double.infinity, child: FilledButton(onPressed: onComplete, child: Text(nextLabel))),
          ),
        ],
      ),
    );
  }
}

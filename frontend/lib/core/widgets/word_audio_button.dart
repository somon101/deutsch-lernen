import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/sound_preferences.dart';
import '../utils/word_audio.dart';

/// Mirrors WordAudioButton.tsx — a speaker control next to a German word.
/// Deliberately not used inside exercises: hearing the word there would
/// turn a question into a hint.
class WordAudioButton extends ConsumerStatefulWidget {
  const WordAudioButton({super.key, required this.word, this.audioUrl, this.size = 20});

  final String word;
  final String? audioUrl;
  final double size;

  @override
  ConsumerState<WordAudioButton> createState() => _WordAudioButtonState();
}

class _WordAudioButtonState extends ConsumerState<WordAudioButton> {
  bool _playing = false;

  Future<void> _handleTap() async {
    setState(() => _playing = true);
    try {
      await ref.read(wordAudioServiceProvider).play(widget.word, audioUrl: widget.audioUrl);
    } finally {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _playing = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The single place every current AND future word-audio button hides
    // itself (§ sound settings, 2026-09-03) — the request's own §9: the
    // check belongs in the shared component, not copied into each screen
    // that uses it. `.select` so this widget rebuilds only on the one flag
    // it cares about.
    final enabled = ref.watch(soundPreferencesProvider.select((s) => s.wordAudioEnabled));
    if (!enabled) return const SizedBox.shrink();
    return IconButton(
      icon: Icon(
        Icons.volume_up,
        size: widget.size,
        color: _playing ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: 'Прослушать произношение',
      onPressed: _handleTap,
    );
  }
}

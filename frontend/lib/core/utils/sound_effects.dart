import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mirrors src/lib/sound.ts's playSound: short, cached one-shot UI sound
/// effects for correct/incorrect answers and the lesson-complete chime.
/// Never throws — a sound that fails to play (missing audio device, etc.)
/// simply stays silent, same as the browser version's swallowed rejection.
class SoundEffects {
  final _correct = AudioPlayer();
  final _incorrect = AudioPlayer();
  final _complete = AudioPlayer();

  Future<void> playCorrect() => _play(_correct, 'sounds/correct-answer.mp3');
  Future<void> playIncorrect() => _play(_incorrect, 'sounds/incorrect-answer.mp3');
  Future<void> playComplete() => _play(_complete, 'sounds/progress-complete.mp3');

  Future<void> _play(AudioPlayer player, String asset) async {
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // No audio output available — stay silent.
    }
  }

  void dispose() {
    _correct.dispose();
    _incorrect.dispose();
    _complete.dispose();
  }
}

final soundEffectsProvider = Provider<SoundEffects>((ref) {
  final effects = SoundEffects();
  ref.onDispose(effects.dispose);
  return effects;
});

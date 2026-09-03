import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/sound_preferences.dart';

/// Mirrors src/lib/sound.ts's playSound: short, cached one-shot UI sound
/// effects for correct/incorrect answers and the lesson-complete chime.
/// Never throws — a sound that fails to play (missing audio device, etc.)
/// simply stays silent, same as the browser version's swallowed rejection.
class SoundEffects {
  SoundEffects(this._lessonSoundEnabled);

  /// Asked at the moment of playing, not captured once: the learner can
  /// flip the switch mid-lesson and the next sound must already obey it.
  final bool Function() _lessonSoundEnabled;

  final _correct = AudioPlayer();
  final _incorrect = AudioPlayer();
  final _complete = AudioPlayer();

  Future<void> playCorrect() => _play(_correct, 'sounds/correct-answer.mp3');
  Future<void> playIncorrect() => _play(_incorrect, 'sounds/incorrect-answer.mp3');
  Future<void> playComplete() => _play(_complete, 'sounds/progress-complete.mp3');

  /// The single gate for the "Звук в уроках" setting (§ sound settings,
  /// 2026-09-03). Placed here rather than at each call site so a lesson
  /// sound added later is covered without anyone remembering to add a check
  /// — and so the setting can never be half-applied. Word pronunciation does
  /// NOT pass through here; it is a separate mechanism with its own switch.
  Future<void> _play(AudioPlayer player, String asset) async {
    if (!_lessonSoundEnabled()) return;
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
  // `read` inside the callback, not `watch` at build time: watching would
  // rebuild the whole player set on every toggle, cutting off a sound that
  // was already playing.
  final effects = SoundEffects(() => ref.read(soundPreferencesProvider).lessonSoundEnabled);
  ref.onDispose(effects.dispose);
  return effects;
});

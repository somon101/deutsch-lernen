import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:media_kit/media_kit.dart';

import '../api/api_client.dart';
import '../settings/sound_preferences.dart';

/// Mirrors src/lib/speech.ts's playWord: plays an admin-uploaded recording
/// when there is one, otherwise falls back to on-device TTS. A recording
/// always wins over the synthesised voice; a word that cannot be voiced
/// simply stays silent (never throws to the caller).
class WordAudioService {
  WordAudioService(this._api, this._wordAudioEnabled);

  final ApiClient _api;

  /// Asked at the moment of playing, so flipping the switch takes effect on
  /// the very next tap.
  final bool Function() _wordAudioEnabled;
  final Player _player = Player();
  final FlutterTts _tts = FlutterTts();
  bool _ttsConfigured = false;

  Future<void> _configureTts() async {
    if (_ttsConfigured) return;
    await _tts.setLanguage('de-DE');
    await _tts.setSpeechRate(0.45);
    _ttsConfigured = true;
  }

  Future<void> play(String word, {String? audioUrl}) async {
    // The single gate for the "Озвучка слов" setting (§ sound settings,
    // 2026-09-03). Placed before the recording/TTS split on purpose: the
    // setting is about whether the learner may hear the word at all, not
    // about which mechanism would have said it. Hiding the buttons is the
    // visible half of the feature; this is the half that holds even if some
    // future screen forgets to hide its own control.
    if (!_wordAudioEnabled()) return;
    final src = _api.assetUrl(audioUrl);
    if (src.isNotEmpty) {
      try {
        await _player.open(Media(src));
        return;
      } catch (_) {
        // Recording missing or blocked — fall through to synthesis.
      }
    }
    try {
      await _configureTts();
      await _tts.speak(word);
    } catch (_) {
      // No TTS voice available on this platform — stay silent.
    }
  }

  void dispose() {
    _player.dispose();
    _tts.stop();
  }
}

final wordAudioServiceProvider = Provider<WordAudioService>((ref) {
  // `read` inside the callback rather than `watch` at build time: watching
  // would rebuild the player and the TTS engine on every toggle.
  final service = WordAudioService(
    ref.watch(apiClientProvider),
    () => ref.read(soundPreferencesProvider).wordAudioEnabled,
  );
  ref.onDispose(service.dispose);
  return service;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:media_kit/media_kit.dart';

import '../api/api_client.dart';

/// Mirrors src/lib/speech.ts's playWord: plays an admin-uploaded recording
/// when there is one, otherwise falls back to on-device TTS. A recording
/// always wins over the synthesised voice; a word that cannot be voiced
/// simply stays silent (never throws to the caller).
class WordAudioService {
  WordAudioService(this._api);

  final ApiClient _api;
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
  final service = WordAudioService(ref.watch(apiClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// The two global sound settings (§ sound settings, 2026-09-03).
///
/// Deliberately in `core/`, not under the settings feature: the lesson
/// runner, the word deck, the vocabulary screens and the admin builder all
/// need to consult these, and none of them should have to reach into another
/// feature's folder to do it.
///
/// They are two independent flags, never one "sound on/off". Wanting silence
/// during exercises while still being able to hear how a word is pronounced
/// is an ordinary wish, and a single flag could not express it.
class SoundPreferences {
  const SoundPreferences({required this.lessonSoundEnabled, required this.wordAudioEnabled});

  /// Gates the sounds that belong to working through a lesson: right answer,
  /// wrong answer, the finishing chime — and anything of that kind added
  /// later, since the check lives in the one place that plays them.
  final bool lessonSoundEnabled;

  /// Gates the learner's ability to hear a word said aloud: whether the
  /// speaker control is offered at all, and whether playback starts. Covers
  /// a recorded file and the TTS fallback alike — it is about the act of
  /// listening, not about which mechanism does the speaking.
  final bool wordAudioEnabled;

  /// What the app does before the server has answered, and if it never
  /// answers: both on. That is exactly how the app behaved before these
  /// switches existed, so a slow or failed request can never leave a learner
  /// with a silence they did not ask for.
  static const defaults = SoundPreferences(lessonSoundEnabled: true, wordAudioEnabled: true);

  SoundPreferences copyWith({bool? lessonSoundEnabled, bool? wordAudioEnabled}) => SoundPreferences(
        lessonSoundEnabled: lessonSoundEnabled ?? this.lessonSoundEnabled,
        wordAudioEnabled: wordAudioEnabled ?? this.wordAudioEnabled,
      );

  factory SoundPreferences.fromJson(Map<String, dynamic> json) => SoundPreferences(
        lessonSoundEnabled: json['lessonSoundEnabled'] as bool? ?? true,
        wordAudioEnabled: json['wordAudioEnabled'] as bool? ?? true,
      );
}

/// The current settings, readable synchronously from anywhere.
///
/// A plain [Notifier] rather than a FutureProvider because the callers are
/// places like "should this sound play right now" and "should this button
/// exist" — neither can wait on a future or handle a loading state. It holds
/// the permissive default until [SoundPreferencesNotifier.load] replaces it
/// with the server's answer.
class SoundPreferencesNotifier extends Notifier<SoundPreferences> {
  @override
  SoundPreferences build() {
    // Fired and not awaited on purpose: `build` must return a usable value
    // immediately, and the defaults are safe to act on until the real ones
    // arrive.
    Future.microtask(load);
    return SoundPreferences.defaults;
  }

  Future<void> load() async {
    try {
      final json = await ref.read(apiClientProvider).get('/api/me/preferences');
      state = SoundPreferences.fromJson(json);
    } catch (_) {
      // Not signed in yet, or offline. Keep whatever is in state — the
      // defaults on a first run, or the last known values afterwards.
    }
  }

  /// Applies the change locally first so the switch responds at once, then
  /// asks the server. A rejected save is rolled back rather than left
  /// showing a state that was never stored.
  Future<void> _patch(SoundPreferences next, Map<String, dynamic> body) async {
    final previous = state;
    state = next;
    try {
      final json = await ref.read(apiClientProvider).patch('/api/me/preferences', body: body);
      state = SoundPreferences.fromJson(json);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }

  Future<void> setLessonSound(bool value) =>
      _patch(state.copyWith(lessonSoundEnabled: value), {'lessonSoundEnabled': value});

  Future<void> setWordAudio(bool value) => _patch(state.copyWith(wordAudioEnabled: value), {'wordAudioEnabled': value});
}

final soundPreferencesProvider =
    NotifierProvider<SoundPreferencesNotifier, SoundPreferences>(SoundPreferencesNotifier.new);

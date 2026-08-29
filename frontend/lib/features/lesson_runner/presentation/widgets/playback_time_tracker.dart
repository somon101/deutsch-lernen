import 'dart:async';

/// Tracks real wall-clock time while a media player is actually playing (§
/// time tracking, 2026-08-29 — "если файл воспроизводится, время
/// считается; если пауза — не считается"). No artificial delay/cooldown
/// rules: a play->pause segment is flushed exactly as long as it lasted, and
/// rewinding to re-watch/re-listen to the same part simply starts a new
/// segment that counts again, since this never looks at playback position —
/// only at whether the player is currently playing.
///
/// A periodic safety flush while still playing keeps a long, uninterrupted
/// session from being lost if the app closes mid-play; it doesn't change
/// how much time is ultimately counted, only how often it's reported.
class PlaybackTimeTracker {
  PlaybackTimeTracker({required this.onFlush, this.periodicFlushInterval = const Duration(seconds: 20)});

  final void Function(int seconds) onFlush;
  final Duration periodicFlushInterval;

  DateTime? _segmentStartedAt;
  Timer? _periodicTimer;

  void setPlaying(bool playing) {
    if (playing) {
      _segmentStartedAt ??= DateTime.now();
      _periodicTimer ??= Timer.periodic(periodicFlushInterval, (_) => _flush());
    } else {
      _flush();
      _periodicTimer?.cancel();
      _periodicTimer = null;
    }
  }

  void _flush() {
    final startedAt = _segmentStartedAt;
    if (startedAt == null) return;
    final now = DateTime.now();
    _segmentStartedAt = now;
    final elapsed = now.difference(startedAt).inSeconds;
    if (elapsed > 0) onFlush(elapsed);
  }

  void dispose() {
    _flush();
    _periodicTimer?.cancel();
  }
}

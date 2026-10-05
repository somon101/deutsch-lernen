import 'dart:math' as math;

/// Speech timeline built by the server (backend services/speech_timeline.py):
/// per-frame loudness inside speech, 0 everywhere else, plus the speech
/// segments themselves. `visemes` is reserved for phoneme lip-sync later.
class SpeechTimeline {
  const SpeechTimeline({required this.frameMs, required this.durationMs, required this.envelope, required this.segments, this.words = const []});

  factory SpeechTimeline.fromJson(Map<String, dynamic> json) => SpeechTimeline(
        frameMs: (json['frameMs'] as num?)?.toInt() ?? 20,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        envelope: [for (final v in (json['envelope'] as List<dynamic>? ?? const [])) (v as num).toDouble() / 100.0],
        segments: [
          for (final s in (json['segments'] as List<dynamic>? ?? const []))
            SpeechSegment((s['start'] as num).toInt(), (s['end'] as num).toInt()),
        ],
        words: [
          for (final w in (json['words'] as List<dynamic>? ?? const []))
            SpokenWord(w['text'] as String? ?? '', (w['start'] as num).toInt(), (w['end'] as num).toInt()),
        ],
      );

  final int frameMs;
  final int durationMs;
  final List<double> envelope;
  final List<SpeechSegment> segments;
  final List<SpokenWord> words;

  bool get hasSpeech => segments.isNotEmpty;

  bool isSpeakingAt(int ms) {
    for (final s in segments) {
      if (ms >= s.start && ms < s.end) return true;
      if (s.start > ms) break;
    }
    return false;
  }

  /// How open the mouth should be at [ms]: 0 (closed) whenever there is no
  /// speech, otherwise the smoothed loudness with a small floor so a
  /// speaking mouth never looks frozen. Pure — the same input always gives
  /// the same output, so the preview and a future export agree.
  double mouthOpenAt(int ms) {
    if (!isSpeakingAt(ms) || envelope.isEmpty) return 0;
    final pos = ms / frameMs;
    final i = pos.floor().clamp(0, envelope.length - 1);
    final j = math.min(i + 1, envelope.length - 1);
    final t = pos - pos.floor();
    final level = envelope[i] * (1 - t) + envelope[j] * t;
    return (0.12 + 0.88 * level).clamp(0.0, 1.0);
  }

  SpokenWord? wordAt(int ms) {
    for (final w in words) {
      if (ms >= w.start && ms < w.end) return w;
    }
    return null;
  }
}

class SpeechSegment {
  const SpeechSegment(this.start, this.end);
  final int start;
  final int end;
}

class SpokenWord {
  const SpokenWord(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

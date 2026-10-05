import 'package:flutter_test/flutter_test.dart';
import 'package:payroha/features/video_lessons/domain/speech_timeline.dart';

void main() {
  // 0..2000 ms, 20 ms frames: speech 500-1000 and 1500-1800, loud in the middle.
  final envelope = List<int>.generate(100, (i) {
    final ms = i * 20;
    if (ms >= 500 && ms < 1000) return 80;
    if (ms >= 1500 && ms < 1800) return 40;
    return 0;
  });
  final t = SpeechTimeline.fromJson({
    'frameMs': 20,
    'durationMs': 2000,
    'envelope': envelope,
    'segments': [
      {'start': 500, 'end': 1000},
      {'start': 1500, 'end': 1800},
    ],
    'words': [
      {'text': 'Hallo', 'start': 520, 'end': 980},
    ],
  });

  test('рот закрыт в тишине до, между и после речи', () {
    for (final ms in [0, 250, 499, 1000, 1200, 1499, 1800, 1999, 5000]) {
      expect(t.mouthOpenAt(ms), 0, reason: 'ms=$ms');
    }
  });

  test('рот открыт во время речи и громче там, где громче', () {
    expect(t.mouthOpenAt(700), greaterThan(0.5));
    expect(t.mouthOpenAt(1600), greaterThan(0));
    expect(t.mouthOpenAt(700), greaterThan(t.mouthOpenAt(1600)));
  });

  test('без сегментов речи рот никогда не двигается', () {
    final silent = SpeechTimeline.fromJson({'frameMs': 20, 'durationMs': 1000, 'envelope': List.filled(50, 0), 'segments': []});
    expect(silent.hasSpeech, isFalse);
    for (var ms = 0; ms < 1000; ms += 10) {
      expect(silent.mouthOpenAt(ms), 0);
    }
  });

  test('слово под текущей позицией', () {
    expect(t.wordAt(600)?.text, 'Hallo');
    expect(t.wordAt(1200), isNull);
  });
}

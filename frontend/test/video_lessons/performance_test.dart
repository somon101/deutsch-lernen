import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:payroha/features/video_lessons/domain/performance.dart';
import 'package:payroha/features/video_lessons/domain/speech_timeline.dart';

// Fixtures are real server output: edge-tts German speech -> ffmpeg ->
// speech analysis + Rhubarb phoneme mouth shapes.
SpeechTimeline _load(String name) =>
    SpeechTimeline.fromJson(jsonDecode(File('test/video_lessons/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>);

bool _armAtRest(ArmPose a, ArmPose rest) => (a.upper - rest.upper).abs() < 0.06 && (a.fore - rest.fore).abs() < 0.08;

void main() {
  final long = _load('long');
  final short = _load('short');
  final fast = _load('fast');
  final slow = _load('slow');

  test('lip-sync: во время речи рот принимает разные формы, в паузах закрыт', () {
    final perf = Performance(long, const AnimationSettings(), seed: 1);
    final opens = <double>{};
    var closedInSilence = 0, silenceSamples = 0;
    for (var ms = 0; ms < long.durationMs; ms += 20) {
      final m = perf.poseAt(ms).mouth;
      if (long.isSpeakingAt(ms)) {
        opens.add((m.open * 10).roundToDouble());
      } else if (long.segments.any((s) => ms > s.end + 80) || ms < long.segments.first.start) {
        // Silence (allowing the last viseme a moment to close).
        silenceSamples++;
        if (m.open < 0.05 || long.visemes[long.visemeIndexAt(ms).clamp(0, long.visemes.length - 1)].shape == 'X') closedInSilence++;
      }
    }
    expect(long.visemeSource, 'rhubarb');
    expect(opens.length, greaterThanOrEqualTo(5), reason: 'рот должен менять степень раскрытия, а не просто открыт/закрыт');
    expect(closedInSilence / silenceSamples, greaterThan(0.95));
  });

  test('lip-sync: используются формы разных звуков (visemes)', () {
    final shapes = long.visemes.map((v) => v.shape).toSet();
    expect(shapes.length, greaterThanOrEqualTo(7), reason: 'shapes=$shapes');
    final perf = Performance(long, const AnimationSettings(), seed: 1);
    var rounded = false, teeth = false, pressed = false;
    for (var ms = 0; ms < long.durationMs; ms += 10) {
      final m = perf.poseAt(ms).mouth;
      rounded |= m.round > 0.6;
      teeth |= m.teeth > 0.6;
      pressed |= m.press > 0.6;
    }
    expect(rounded && teeth && pressed, isTrue, reason: 'rounded=$rounded teeth=$teeth pressed=$pressed');
  });

  test('после фразы рот возвращается в покой', () {
    final perf = Performance(short, const AnimationSettings(), seed: 2);
    final end = short.segments.last.end;
    expect(perf.poseAt(end + 150).mouth.open, lessThan(0.05));
    expect(perf.poseAt(end + 600).mouth.open, 0);
  });

  test('быстрая речь меняет формы рта чаще, чем медленная', () {
    double changesPerSecond(SpeechTimeline t) => t.visemes.length / (t.durationMs / 1000);
    expect(changesPerSecond(fast), greaterThan(changesPerSecond(slow)));
  });

  test('моргание: регулярно, но с разными интервалами', () {
    final perf = Performance(long, const AnimationSettings(), seed: 3);
    final starts = <int>[];
    var wasClosed = false;
    for (var ms = 0; ms < long.durationMs; ms += 10) {
      final closed = perf.poseAt(ms).blink > 0.9;
      if (closed && !wasClosed) starts.add(ms);
      wasClosed = closed;
    }
    final perMinute = starts.length / (long.durationMs / 60000);
    expect(perMinute, inInclusiveRange(8, 35), reason: 'blinks=$starts');
    final gaps = [for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1]];
    expect(gaps.toSet().length, greaterThan(gaps.length ~/ 2), reason: 'интервалы не должны повторяться: $gaps');
  });

  test('взгляд и голова двигаются, но не по одному циклу', () {
    final perf = Performance(long, const AnimationSettings(), seed: 4);
    final gaze = <String>{};
    final heads = <double>[];
    for (var ms = 0; ms < long.durationMs; ms += 250) {
      final p = perf.poseAt(ms);
      gaze.add('${(p.gazeX * 10).round()},${(p.gazeY * 10).round()}');
      heads.add(p.headRot);
    }
    expect(gaze.length, greaterThan(3));
    final range = heads.reduce(math.max) - heads.reduce(math.min);
    expect(range, greaterThan(0.02));
  });

  test('мимика: улыбка меняется в зависимости от речи', () {
    final perf = Performance(long, const AnimationSettings(), seed: 5);
    final seg = long.segments.first;
    final speakingSmile = perf.poseAt(seg.start + (seg.end - seg.start) ~/ 2).smile;
    final afterSmile = perf.poseAt(seg.end + 500).smile;
    expect(afterSmile, greaterThan(speakingSmile));
  });

  test('руки: жесты во время длинных фраз и возврат в покой', () {
    final perf = Performance(long, const AnimationSettings(), seed: 6);
    var gestured = 0;
    for (final s in long.segments.where((s) => s.end - s.start >= 1400)) {
      final mid = s.start + (s.end - s.start) ~/ 2;
      final p = perf.poseAt(mid);
      if (!_armAtRest(p.leftArm, Performance.restLeft) || !_armAtRest(p.rightArm, Performance.restRight)) gestured++;
    }
    expect(gestured, greaterThan(0));
    final after = perf.poseAt(long.segments.last.end + 1500);
    expect(_armAtRest(after.leftArm, Performance.restLeft) && _armAtRest(after.rightArm, Performance.restRight), isTrue);
  });

  test('без речи: рот закрыт, руки в покое, но персонаж живой (моргает, дышит)', () {
    final silent = SpeechTimeline.fromJson({'frameMs': 20, 'durationMs': 6000, 'envelope': List.filled(300, 0), 'segments': [], 'visemes': []});
    final perf = Performance(silent, const AnimationSettings(), seed: 7);
    var blinked = false;
    final body = <double>{};
    for (var ms = 0; ms < 6000; ms += 20) {
      final p = perf.poseAt(ms);
      expect(p.mouth.open, 0);
      expect(_armAtRest(p.leftArm, Performance.restLeft), isTrue);
      blinked |= p.blink > 0.9;
      body.add((p.bodyDy * 10).roundToDouble());
    }
    expect(blinked, isTrue);
    expect(body.length, greaterThan(3));
  });

  test('повтор и пауза: одна и та же позиция даёт одну и ту же позу', () {
    final a = Performance(long, const AnimationSettings(), seed: 9);
    final b = Performance(long, const AnimationSettings(), seed: 9);
    for (final ms in [0, 1234, 5000, 12345, 20000]) {
      final pa = a.poseAt(ms), pb = b.poseAt(ms);
      expect(pa.mouth.open, pb.mouth.open);
      expect(pa.headRot, pb.headRot);
      expect(pa.rightArm.fore, pb.rightArm.fore);
      expect(pa.blink, pb.blink);
    }
  });

  test('настройки: жесты выключены и голова неподвижна', () {
    final perf = Performance(long, const AnimationSettings(gestures: false, headMotion: 0), seed: 1);
    for (var ms = 0; ms < long.durationMs; ms += 100) {
      final p = perf.poseAt(ms);
      expect(_armAtRest(p.rightArm, Performance.restRight), isTrue);
      expect(p.headRot, 0);
      expect(p.headDx, 0);
    }
  });

  test('настройки сохраняются и читаются обратно', () {
    const s = AnimationSettings(gestures: false, gestureIntensity: 1.4, headMotion: 0.5, expressiveness: 1.7, blinkRate: 0.8);
    final back = AnimationSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.toJson(), s.toJson());
  });
}

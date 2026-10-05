import 'dart:math' as math;

import 'speech_timeline.dart';

/// Teacher-adjustable performance knobs (stored on the video lesson).
class AnimationSettings {
  const AnimationSettings({this.gestures = true, this.gestureIntensity = 1, this.headMotion = 1, this.expressiveness = 1, this.blinkRate = 1});

  factory AnimationSettings.fromJson(Map<String, dynamic>? j) => j == null
      ? const AnimationSettings()
      : AnimationSettings(
          gestures: j['gestures'] as bool? ?? true,
          gestureIntensity: (j['gestureIntensity'] as num?)?.toDouble() ?? 1,
          headMotion: (j['headMotion'] as num?)?.toDouble() ?? 1,
          expressiveness: (j['expressiveness'] as num?)?.toDouble() ?? 1,
          blinkRate: (j['blinkRate'] as num?)?.toDouble() ?? 1,
        );

  final bool gestures;
  final double gestureIntensity;
  final double headMotion;
  final double expressiveness;
  final double blinkRate;

  Map<String, dynamic> toJson() => {
        'gestures': gestures,
        'gestureIntensity': gestureIntensity,
        'headMotion': headMotion,
        'expressiveness': expressiveness,
        'blinkRate': blinkRate,
      };

  AnimationSettings copyWith({bool? gestures, double? gestureIntensity, double? headMotion, double? expressiveness, double? blinkRate}) => AnimationSettings(
        gestures: gestures ?? this.gestures,
        gestureIntensity: gestureIntensity ?? this.gestureIntensity,
        headMotion: headMotion ?? this.headMotion,
        expressiveness: expressiveness ?? this.expressiveness,
        blinkRate: blinkRate ?? this.blinkRate,
      );
}

/// Mouth shape parameters, blended between visemes.
class MouthShape {
  const MouthShape({this.open = 0, this.width = 1, this.round = 0, this.teeth = 0, this.tongueUp = 0, this.press = 0});
  final double open; // 0 closed .. 1 wide open
  final double width; // relative to rest width
  final double round; // 0 flat .. 1 pursed "oo"
  final double teeth; // visible upper teeth
  final double tongueUp; // tongue behind teeth ("L")
  final double press; // lips pressed (M, B, P)

  static MouthShape lerp(MouthShape a, MouthShape b, double t) => MouthShape(
        open: a.open + (b.open - a.open) * t,
        width: a.width + (b.width - a.width) * t,
        round: a.round + (b.round - a.round) * t,
        teeth: a.teeth + (b.teeth - a.teeth) * t,
        tongueUp: a.tongueUp + (b.tongueUp - a.tongueUp) * t,
        press: a.press + (b.press - a.press) * t,
      );

  MouthShape scaleOpen(double k) => MouthShape(open: open * k, width: width, round: round, teeth: teeth, tongueUp: tongueUp, press: press);
}

/// Rhubarb / Preston Blair shapes.
const visemeShapes = <String, MouthShape>{
  'X': MouthShape(),
  'A': MouthShape(open: 0, width: 0.92, press: 1),
  'B': MouthShape(open: 0.24, width: 1.08, teeth: 0.9),
  'C': MouthShape(open: 0.5, width: 1.02, teeth: 0.5),
  'D': MouthShape(open: 0.92, width: 0.96, teeth: 0.35),
  'E': MouthShape(open: 0.55, width: 0.78, round: 0.45),
  'F': MouthShape(open: 0.32, width: 0.52, round: 1),
  'G': MouthShape(open: 0.18, width: 0.98, teeth: 1),
  'H': MouthShape(open: 0.55, width: 0.86, tongueUp: 1, teeth: 0.4),
};

/// One arm: angles from straight down, positive = away from the body.
class ArmPose {
  const ArmPose({required this.upper, required this.fore, this.handOpen = 0.3, this.point = 0});
  final double upper; // radians
  final double fore; // radians (absolute)
  final double handOpen; // 0 relaxed .. 1 spread
  final double point; // 0 open hand .. 1 index finger pointing

  static ArmPose lerp(ArmPose a, ArmPose b, double t) => ArmPose(
        upper: a.upper + (b.upper - a.upper) * t,
        fore: a.fore + (b.fore - a.fore) * t,
        handOpen: a.handOpen + (b.handOpen - a.handOpen) * t,
        point: a.point + (b.point - a.point) * t,
      );
}

/// Full pose of the character at one instant.
class CharacterPose {
  const CharacterPose({
    required this.mouth,
    required this.smile,
    required this.blink,
    required this.gazeX,
    required this.gazeY,
    required this.eyeOpen,
    required this.headRot,
    required this.headDx,
    required this.headDy,
    required this.bodyDy,
    required this.bodyRot,
    required this.leftArm,
    required this.rightArm,
    required this.blush,
  });

  final MouthShape mouth;
  final double smile; // 0..1
  final double blink; // 0 open .. 1 closed
  final double gazeX, gazeY; // -1..1
  final double eyeOpen; // ~0.85 squint .. 1.12 wide
  final double headRot, headDx, headDy;
  final double bodyDy, bodyRot;
  final ArmPose leftArm; // screen-left
  final ArmPose rightArm; // screen-right
  final double blush;

  static const rest = CharacterPose(
    mouth: MouthShape(),
    smile: 0.7,
    blink: 0,
    gazeX: 0,
    gazeY: 0,
    eyeOpen: 1,
    headRot: 0,
    headDx: 0,
    headDy: 0,
    bodyDy: 0,
    bodyRot: 0,
    leftArm: Performance.restLeft,
    rightArm: Performance.restRight,
    blush: 0.6,
  );
}

double _rad(double deg) => deg * math.pi / 180;
double _smooth(double x) => x <= 0 ? 0 : x >= 1 ? 1 : x * x * (3 - 2 * x);

class _Gesture {
  _Gesture(this.kind, this.start, this.end);
  final String kind; // wave | explain | openBoth | point | beats
  final int start, end;
}

class _Event {
  _Event(this.at, this.x, this.y);
  final int at;
  final double x, y;
}

/// Turns a speech timeline into a performance: everything is a pure
/// function of the audio position, so Play/Pause/Replay (and a future
/// export) always show exactly the same thing at the same moment. Random
/// choices come from a seeded generator, so blinks, glances and gestures
/// are irregular — not a repeating loop — yet stable between runs.
class Performance {
  Performance(this.timeline, this.settings, {int seed = 1}) {
    final rng = math.Random(seed);
    _phases = List.generate(6, (_) => rng.nextDouble() * math.pi * 2);
    _planBlinks(rng);
    _planGaze(rng);
    _planNods();
    _planTilts(rng);
    _planGestures(rng);
  }

  final SpeechTimeline? timeline;
  final AnimationSettings settings;

  static const restLeft = ArmPose(upper: 0.16, fore: 0.10, handOpen: 0.25);
  static const restRight = ArmPose(upper: 0.16, fore: 0.10, handOpen: 0.25);

  late final List<double> _phases;
  final _blinks = <int>[];
  final _gaze = <_Event>[];
  final _nods = <int>[];
  final _tilts = <_Event>[]; // x = tilt target at segment start
  final _gestures = <_Gesture>[];

  List<SpeechSegment> get _segments => timeline?.segments ?? const [];
  int get _duration => math.max(timeline?.durationMs ?? 0, 4000);

  void _planBlinks(math.Random rng) {
    final rate = settings.blinkRate.clamp(0.2, 2.0);
    var t = 700 + rng.nextInt(900);
    while (t < _duration + 8000) {
      _blinks.add(t);
      t += ((2200 + rng.nextInt(3600)) / rate).round();
    }
    // People often blink right after finishing a phrase.
    for (final s in _segments) {
      if (rng.nextDouble() < 0.6) {
        final at = s.end + 120 + rng.nextInt(160);
        if (_blinks.every((b) => (b - at).abs() > 600)) _blinks.add(at);
      }
    }
    _blinks.sort();
  }

  void _planGaze(math.Random rng) {
    var t = 0;
    while (t < _duration + 8000) {
      final speaking = timeline?.isSpeakingAt(t) ?? false;
      final away = rng.nextDouble() < (speaking ? 0.25 : 0.5);
      _gaze.add(_Event(t, away ? (rng.nextDouble() * 2 - 1) * 0.7 : (rng.nextDouble() - 0.5) * 0.15, away ? (rng.nextDouble() * 2 - 1) * 0.35 - 0.05 : 0));
      t += 900 + rng.nextInt(2300);
    }
    // Look at the viewer when a phrase starts.
    for (final s in _segments) {
      _gaze.add(_Event(s.start - 80, 0, 0));
    }
    _gaze.sort((a, b) => a.at.compareTo(b.at));
  }

  void _planNods() {
    final tl = timeline;
    if (tl == null || tl.envelope.isEmpty) return;
    final frame = tl.frameMs;
    final env = tl.envelope;
    const half = 4; // ~80 ms on each side
    var last = -100000;
    for (var i = half; i < env.length - half; i++) {
      final v = env[i];
      if (v < 0.62) continue;
      var peak = true;
      for (var k = -half; k <= half; k++) {
        if (env[i + k] > v) {
          peak = false;
          break;
        }
      }
      final at = i * frame;
      if (peak && at - last > 420) {
        _nods.add(at);
        last = at;
      }
    }
  }

  void _planTilts(math.Random rng) {
    for (final s in _segments) {
      _tilts.add(_Event(s.start, (rng.nextDouble() * 2 - 1), rng.nextDouble()));
    }
  }

  void _planGestures(math.Random rng) {
    if (!settings.gestures) return;
    const library = ['explain', 'openBoth', 'beats', 'point', 'explain', 'beats'];
    var next = rng.nextInt(library.length);
    for (var i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      final length = s.end - s.start;
      if (i == 0 && s.start < 1500 && length >= 900) {
        _gestures.add(_Gesture('wave', s.start, s.start + math.min(length, 1700)));
        continue;
      }
      if (length >= 1400) {
        _gestures.add(_Gesture(library[next % library.length], s.start, s.end));
        next += 1 + rng.nextInt(2);
      } else {
        _gestures.add(_Gesture('beats', s.start, s.end));
      }
    }
  }

  // ------------------------------------------------------------ evaluation

  MouthShape _mouthAt(int ms, double smile) {
    final tl = timeline;
    if (tl == null || tl.visemes.isEmpty) return const MouthShape();
    final i = tl.visemeIndexAt(ms);
    if (i < 0) return const MouthShape();
    final cue = tl.visemes[i];
    final target = visemeShapes[cue.shape] ?? const MouthShape();
    // Coarticulation: ease in from the previous shape over the first 70 ms.
    const blend = 70;
    var shape = target;
    if (i > 0 && ms - cue.start < blend) {
      final prev = visemeShapes[tl.visemes[i - 1].shape] ?? const MouthShape();
      shape = MouthShape.lerp(prev, target, _smooth((ms - cue.start) / blend));
    }
    // Louder syllables open a little more; never move without speech.
    final level = tl.levelAt(ms);
    return shape.scaleOpen(0.82 + 0.3 * level);
  }

  double _blinkAt(int ms) {
    const close = 70, hold = 40, open = 90;
    for (final b in _blinks) {
      if (b > ms) break;
      final d = ms - b;
      if (d < close) return d / close;
      if (d < close + hold) return 1;
      if (d < close + hold + open) return 1 - (d - close - hold) / open;
    }
    return 0;
  }

  (double, double) _gazeAt(int ms) {
    _Event? prev;
    for (final e in _gaze) {
      if (e.at > ms) break;
      prev = e;
    }
    if (prev == null) return (0, 0);
    final idx = _gaze.indexOf(prev);
    final before = idx > 0 ? _gaze[idx - 1] : _Event(0, 0, 0);
    final k = _smooth((ms - prev.at) / 90); // quick saccade
    return (before.x + (prev.x - before.x) * k, before.y + (prev.y - before.y) * k);
  }

  double _nodAt(int ms) {
    var v = 0.0;
    for (final n in _nods) {
      final d = (ms - n) / 160;
      if (d < -3) break;
      if (d.abs() < 3) v += math.exp(-d * d);
    }
    return v.clamp(0.0, 1.2);
  }

  double _tiltAt(int ms) {
    var tilt = 0.0;
    for (var i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      final target = _tilts[i].x;
      final inW = _smooth((ms - s.start) / 350);
      final outW = 1 - _smooth((ms - s.end) / 600);
      tilt += target * math.min(inW, outW);
    }
    return tilt;
  }

  double _phraseEnd(int ms) {
    // Rises after a phrase ends (a small satisfied smile), then fades.
    var v = 0.0;
    for (final s in _segments) {
      final d = ms - s.end;
      if (d >= 0 && d < 2200) v = math.max(v, _smooth(d / 350) * (1 - _smooth((d - 900) / 1300)));
    }
    return v;
  }

  double _phraseStart(int ms) {
    var v = 0.0;
    for (final s in _segments) {
      final d = ms - s.start;
      if (d >= -150 && d < 900) v = math.max(v, 1 - _smooth(d.abs() / 700));
    }
    return v;
  }

  ArmPose _gesturePose(String kind, int ms, _Gesture g, {required bool left}) {
    final t = (ms - g.start) / 1000.0;
    final beat = _nodAt(ms);
    switch (kind) {
      case 'wave':
        if (!left) return restRight;
        return ArmPose(upper: _rad(105), fore: _rad(160 + 14 * math.sin(t * 2 * math.pi * 2.2)), handOpen: 1);
      case 'explain':
        if (left) return restLeft;
        return ArmPose(upper: _rad(30 + 4 * math.sin(t * 1.7)), fore: _rad(98 + 10 * beat + 6 * math.sin(t * 2.3)), handOpen: 0.9);
      case 'openBoth':
        return ArmPose(upper: _rad(34 + 3 * math.sin(t * 1.9 + (left ? 0 : 1))), fore: _rad(92 + 8 * beat), handOpen: 1);
      case 'point':
        if (left) return restLeft;
        return ArmPose(upper: _rad(22), fore: _rad(150 + 5 * beat), handOpen: 0.2, point: 1);
      default: // beats
        if (left) return restLeft;
        return ArmPose(upper: _rad(20), fore: _rad(48 + 22 * beat), handOpen: 0.6);
    }
  }

  ArmPose _armAt(int ms, {required bool left}) {
    final rest = left ? restLeft : restRight;
    final intensity = settings.gestureIntensity.clamp(0.0, 2.0);
    var pose = rest;
    for (final g in _gestures) {
      if (ms < g.start - 400 || ms > g.end + 700) continue;
      final attack = g.kind == 'beats' ? 250 : 380;
      final w = math.min(_smooth((ms - g.start + 200) / attack), 1 - _smooth((ms - g.end) / 520));
      if (w <= 0) continue;
      final target = _gesturePose(g.kind, ms, g, left: left);
      final k = (w * math.min(1.0, intensity)).clamp(0.0, 1.0);
      pose = ArmPose.lerp(rest, target, k);
      if (intensity > 1) {
        pose = ArmPose(upper: pose.upper * (1 + (intensity - 1) * 0.25), fore: pose.fore * (1 + (intensity - 1) * 0.15), handOpen: pose.handOpen, point: pose.point);
      }
    }
    // Idle micro-motion so resting arms are never frozen.
    final s = ms / 1000.0;
    final idle = 0.02 * math.sin(s * 0.9 + _phases[left ? 3 : 4]);
    return ArmPose(upper: pose.upper + idle, fore: pose.fore + idle * 1.5, handOpen: pose.handOpen, point: pose.point);
  }

  CharacterPose poseAt(int ms) {
    final s = ms / 1000.0;
    final h = settings.headMotion.clamp(0.0, 2.0);
    final e = settings.expressiveness.clamp(0.0, 2.0);
    final speaking = timeline?.isSpeakingAt(ms) ?? false;
    final level = timeline?.levelAt(ms) ?? 0;

    final end = _phraseEnd(ms);
    final start = _phraseStart(ms);
    final smile = (0.62 + (speaking ? -0.22 : 0.0) + 0.3 * end * e).clamp(0.0, 1.0);
    final mouth = _mouthAt(ms, smile);

    final (gx, gy) = _gazeAt(ms);
    final nod = _nodAt(ms);
    // Several unrelated slow sines: organic drift that does not visibly loop.
    final drift = math.sin(s * 0.83 + _phases[0]) * 0.6 + math.sin(s * 0.37 + _phases[1]) * 0.4;
    final drift2 = math.sin(s * 0.61 + _phases[2]) * 0.6 + math.sin(s * 1.13 + _phases[5]) * 0.4;
    final breath = math.sin(s * 2 * math.pi / 3.9);

    return CharacterPose(
      mouth: mouth,
      smile: smile,
      blink: _blinkAt(ms),
      gazeX: gx,
      gazeY: gy,
      eyeOpen: (1 + 0.1 * start * e - 0.08 * end * e).clamp(0.8, 1.15),
      headRot: _rad((1.3 * drift + 3.2 * _tiltAt(ms) + (speaking ? 0.8 * math.sin(s * 3.1) * level : 0)) * h),
      headDx: (5 * drift2 + 3 * gx) * h,
      headDy: (9 * nod + 2.5 * drift - 3 * level) * h,
      bodyDy: -5 * breath - 2 * level,
      bodyRot: _rad(0.6 * drift2 * h),
      leftArm: _armAt(ms, left: true),
      rightArm: _armAt(ms, left: false),
      blush: (0.55 + 0.25 * end * e).clamp(0.0, 1.0),
    );
  }
}

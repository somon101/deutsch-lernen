import 'dart:math' as math;

/// Bit-exact port of src/content/textUtils.ts's seededRandom/hashString/
/// shuffle (mulberry32 PRNG) — used only by MatchExercise's left/right
/// column ordering (MatchView.tsx), which deliberately derives two
/// different-but-stable shuffles from the exercise id so the board doesn't
/// reorder itself on every rebuild. Mirrors the same int32 arithmetic
/// helpers already verified bit-exact in backend/app/legacy_parser/text_utils.py.
const _mask32 = 0xffffffff;

int _toInt32(int x) {
  x &= _mask32;
  return x >= 0x80000000 ? x - 0x100000000 : x;
}

int _toUint32(int x) => x & _mask32;

int _imul(int a, int b) => _toInt32((_toUint32(a) * _toUint32(b)) & _mask32);

typedef RandomFn = double Function();

/// Deterministic PRNG (mulberry32): the same seed always produces the same
/// sequence, so a given exercise id always shuffles the same way.
RandomFn seededRandom(int seed) {
  var a = _toUint32(seed);

  double next() {
    a = _toInt32(a);
    a = _toInt32(a + 0x6d2b79f5);
    var t = _imul(_toInt32(_toUint32(a) ^ (_toUint32(a) >> 15)), _toInt32(1 | a));
    t = _toInt32(_toInt32(t + _imul(_toInt32(_toUint32(t) ^ (_toUint32(t) >> 7)), _toInt32(61 | t))) ^ t);
    return _toUint32(_toUint32(t) ^ (_toUint32(t) >> 14)) / 4294967296;
  }

  return next;
}

int hashString(String input) {
  var hash = 2166136261;
  for (final codeUnit in input.codeUnits) {
    hash = _toUint32(hash ^ codeUnit);
    hash = _imul(hash, 16777619);
  }
  return _toUint32(hash);
}

List<T> shuffleSeeded<T>(List<T> items, RandomFn rand) {
  final copy = List<T>.from(items);
  for (var i = copy.length - 1; i > 0; i--) {
    final j = (rand() * (i + 1)).floor();
    final tmp = copy[i];
    copy[i] = copy[j];
    copy[j] = tmp;
  }
  return copy;
}

/// Genuinely-random (non-seeded) Fisher-Yates shuffle — mirrors
/// ChoiceView.tsx/ClozeView.tsx's `shuffle(options, Math.random)`, reshuffled
/// fresh on every question mount so the correct answer's position isn't
/// memorizable.
List<T> shuffleRandom<T>(List<T> items) => shuffleSeeded(items, () => _random.nextDouble());

final _random = math.Random();


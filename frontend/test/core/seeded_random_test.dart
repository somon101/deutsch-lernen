import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/core/utils/seeded_random.dart';

// Reference values computed from backend/app/legacy_parser/text_utils.py —
// itself already verified bit-exact against the original
// src/content/textUtils.ts via the Phase 2 TS-vs-Python diff harness. This
// Dart port is checked directly against the Python port rather than a fresh
// TS invocation (tsx isn't installed in this repo), which is transitively
// just as strong a guarantee of TS fidelity.
void main() {
  group('hashString', () {
    test('matches the verified Python/TS reference for several inputs', () {
      expect(hashString('m1-left'), 1104021151);
      expect(hashString('m1-right'), 1331255248);
      expect(hashString(''), 2166136261);
      expect(hashString('Hallo Welt'), 3023526897);
    });
  });

  group('seededRandom', () {
    test('produces the exact mulberry32 sequence for a hash-derived seed', () {
      final rand = seededRandom(hashString('m1-left'));
      final values = List.generate(5, (_) => double.parse(rand().toStringAsFixed(10)));
      expect(values, [0.642911555, 0.3809402282, 0.6302374722, 0.8293646181, 0.6007866301]);
    });

    test('produces the exact mulberry32 sequence for a plain integer seed', () {
      final rand = seededRandom(12345);
      final values = List.generate(5, (_) => double.parse(rand().toStringAsFixed(10)));
      expect(values, [0.9797282678, 0.3067522645, 0.4842054215, 0.8179344125, 0.5094283693]);
    });
  });

  group('shuffleSeeded', () {
    test('matches the verified reference ordering for two different seeds', () {
      const items = ['a', 'b', 'c', 'd', 'e'];
      expect(shuffleSeeded(items, seededRandom(hashString('m1-left'))), ['a', 'c', 'e', 'b', 'd']);
      expect(shuffleSeeded(items, seededRandom(hashString('m1-right'))), ['a', 'd', 'b', 'c', 'e']);
    });

    test('does not mutate the input list', () {
      const items = ['a', 'b', 'c'];
      shuffleSeeded(items, seededRandom(1));
      expect(items, ['a', 'b', 'c']);
    });
  });

  group('shuffleRandom', () {
    test('is a permutation of the input (non-seeded, so only shape is checked)', () {
      const items = [1, 2, 3, 4, 5];
      final result = shuffleRandom(items);
      expect(result..sort(), items);
    });
  });
}

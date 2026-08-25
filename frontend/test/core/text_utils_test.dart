import 'package:flutter_test/flutter_test.dart';

import 'package:deutsch_lernen/core/utils/text_utils.dart';

void main() {
  group('normalizeAnswer', () {
    test('strips edge punctuation and lowercases', () {
      expect(normalizeAnswer('Hallo!'), 'hallo');
      expect(normalizeAnswer('hallo'), 'hallo');
      expect(normalizeAnswer('Hallo'), 'hallo');
    });

    test('strips curly double quotation marks (U+201C/U+201D)', () {
      // The exact regression this file's comments describe guarding against.
      expect(normalizeAnswer('“Hallo”'), 'hallo');
    });

    test('strips guillemets and the German low quote', () {
      expect(normalizeAnswer('«Hallo»'), 'hallo');
      expect(normalizeAnswer('„Hallo'), 'hallo');
    });

    test('collapses internal whitespace', () {
      expect(normalizeAnswer('Guten   Tag'), 'guten tag');
    });

    test('leaves umlauts untouched so different words stay different', () {
      expect(normalizeAnswer('schön') == normalizeAnswer('schon'), isFalse);
    });
  });

  group('answersMatch', () {
    test('true for punctuation/case variants of the same answer', () {
      expect(answersMatch('Hallo', 'hallo!'), isTrue);
      expect(answersMatch('“Hallo”', 'Hallo'), isTrue);
    });

    test('false for genuinely different answers', () {
      expect(answersMatch('Hallo', 'Tschüss'), isFalse);
    });
  });
}

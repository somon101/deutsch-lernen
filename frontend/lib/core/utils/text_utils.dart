/// Port of the comparison-relevant parts of src/content/textUtils.ts —
/// normalizeAnswer/answersMatch are the only pieces the grading logic
/// needs (parsing/shuffling stays server-side, see the migration plan's
/// Phase 5 notes on app/services/material.py).
///
/// The punctuation set is built from an explicit codepoint list rather
/// than literal characters in source, on purpose: this exact character
/// class was already mistyped once while porting the same regex to Python
/// (see backend/app/legacy_parser/text_utils.py's history) — the wrong
/// and right characters (straight `"` vs curly U+201C/U+201D) render
/// almost identically in a terminal, so literal characters here would
/// carry the same silent-mistake risk. This list was extracted directly
/// from src/content/textUtils.ts's normalizeAnswer via codepoint dump, not
/// transcribed by eye: . , ! ? ; : … " ' « » „ U+201C U+201D ( )
const _normalizeAnswerPunctuationCodes = [
  0x2e, // .
  0x2c, // ,
  0x21, // !
  0x3f, // ?
  0x3b, // ;
  0x3a, // :
  0x2026, // …
  0x22, // "
  0x27, // '
  0xab, // «
  0xbb, // »
  0x201e, // „
  0x201c, // U+201C LEFT DOUBLE QUOTATION MARK
  0x201d, // U+201D RIGHT DOUBLE QUOTATION MARK
  0x28, // (
  0x29, // )
];

final _normalizeAnswerPunctuation = RegExp('[${String.fromCharCodes(_normalizeAnswerPunctuationCodes)}]');
final _whitespace = RegExp(r'\s+');

/// Normalizes an answer for comparison: case, surrounding whitespace and
/// incidental punctuation are ignored, so "Hallo", "hallo" and "Hallo!"
/// all count as the same answer. Letters — umlauts included — are left
/// untouched, so a genuinely different word still compares as different.
String normalizeAnswer(String value) {
  var result = value.toLowerCase();
  result = result.replaceAll(_normalizeAnswerPunctuation, '');
  result = result.replaceAll(_whitespace, ' ');
  return result.trim();
}

/// True when two answers match under [normalizeAnswer].
bool answersMatch(String a, String b) => normalizeAnswer(a) == normalizeAnswer(b);

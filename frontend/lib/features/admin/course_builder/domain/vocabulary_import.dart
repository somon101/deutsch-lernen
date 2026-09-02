import 'dart:convert';

/// Parsing and validating the dictionary JSON a teacher pastes into the
/// bulk-import panel (§ vocabulary import errors, 2026-09-02).
///
/// Split out of the panel so it can be tested directly, and validated on the
/// client rather than left to the server. The server does enforce the same
/// three required fields, but it answers with a pydantic report that the API
/// client collapses to its first line — so a missing transcription reached
/// the teacher as a bare English "Field required", naming neither the field,
/// nor the word, nor the row. Everything needed to say it precisely is
/// already here, before any request is sent.

/// The required fields, mapped to what to call them in a message a teacher
/// reads. All three are mandatory — the same rule the per-word form already
/// enforces, so a word that couldn't be typed by hand can't slip in through
/// the import either.
const requiredImportFields = {
  'original': 'слово',
  'transcription': 'транскрипция',
  'translation': 'перевод',
};

/// Shown above the input, and kept in one place so the example a teacher
/// copies can never drift from the fields actually required.
const vocabularyImportExample = '[\n'
    '  {"original": "der Tisch", "transcription": "дер тиш", "translation": "стол"},\n'
    '  {"original": "der Stuhl", "transcription": "дер штуль", "translation": "стул"}\n'
    ']';

/// Either the words ready to send, or a message explaining what to fix —
/// never both.
typedef VocabularyImportParse = ({List<Map<String, String>> words, String? error});

const _maxProblemsShown = 5;

VocabularyImportParse parseVocabularyImport(String source) {
  dynamic parsed;
  try {
    parsed = jsonDecode(source);
  } catch (_) {
    return (words: const [], error: 'Некорректный JSON: не удалось разобрать текст. Проверьте синтаксис.');
  }

  if (parsed is! List) {
    return (
      words: const [],
      error: parsed is Map
          // The single most common near-miss: one correct object, no brackets.
          // Saying what to do beats saying what is wrong.
          ? 'Корневой элемент должен быть массивом. Оберните объект в квадратные скобки: [ { ... } ]'
          : 'Корневой элемент JSON должен быть массивом.',
    );
  }
  if (parsed.isEmpty) {
    return (words: const [], error: 'Список пуст — добавьте хотя бы одно слово.');
  }

  final words = <Map<String, String>>[];
  final problems = <String>[];

  for (var i = 0; i < parsed.length; i++) {
    final item = parsed[i];
    final at = 'Слово №${i + 1}';

    if (item is! Map) {
      problems.add('$at: должно быть объектом вида {"original": …, "transcription": …, "translation": …}');
      continue;
    }

    final word = {
      for (final field in requiredImportFields.keys) field: (item[field] ?? '').toString().trim(),
    };
    final missing = requiredImportFields.entries.where((e) => word[e.key]!.isEmpty).map((e) => e.value).toList();

    if (missing.isEmpty) {
      words.add(word);
      continue;
    }

    // Say what is missing, and — when the row also carries names the import
    // doesn't know — say that too. A row with "word"/"de"/"слово" instead of
    // "original" is the common case, and it can arrive alongside one correct
    // key, so "no known keys at all" is too narrow a condition to hang the
    // hint on: the teacher needs to see the unrecognised name whenever there
    // is one.
    final unknown = item.keys.where((k) => !requiredImportFields.containsKey(k)).toList();
    final buffer = StringBuffer('$at: не заполнено — ${missing.join(', ')}');
    if (unknown.isNotEmpty) {
      buffer.write('. Поля ${unknown.take(4).map((k) => '"$k"').join(', ')} не используются; '
          'ожидаются "original", "transcription", "translation"');
    }
    problems.add(buffer.toString());
  }

  if (problems.isEmpty) return (words: words, error: null);

  // A hundred broken rows must not produce a hundred lines of red text.
  final shown = problems.take(_maxProblemsShown).join('\n');
  final rest = problems.length - _maxProblemsShown;
  return (words: const [], error: rest > 0 ? '$shown\n…и ещё $rest' : shown);
}

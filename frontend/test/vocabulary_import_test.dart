// What a teacher pasting a dictionary JSON is told (§ vocabulary import
// errors, 2026-09-02). Required fields: original, translation (Russian) and
// translation_tg (Tajik); transcription is optional. A rejection names the
// field, the word and the row.
import 'package:payroha/features/admin/course_builder/domain/vocabulary_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('принимается', () {
    test('все три поля заполнены', () {
      final r = parseVocabularyImport(
        '[{"original":"der Tisch","translation":"стол","translation_tg":"миз"}]',
      );
      expect(r.error, isNull);
      expect(r.words, [
        {'original': 'der Tisch', 'translation': 'стол', 'translation_tg': 'миз'},
      ]);
    });

    test('транскрипция необязательна, но сохраняется если указана', () {
      final r = parseVocabularyImport(
        '[{"original":"der Tisch","translation":"стол","translation_tg":"миз","transcription":" дер тиш "}]',
      );
      expect(r.error, isNull);
      expect(r.words.single['transcription'], 'дер тиш');
    });

    test('несколько слов', () {
      final r = parseVocabularyImport(vocabularyImportExample);
      expect(r.error, isNull);
      expect(r.words.length, 2);
    });

    test('лишние поля игнорируются, а не ломают импорт', () {
      final r = parseVocabularyImport(
        '[{"original":"a","translation":"c","translation_tg":"d","example":"x","note":1}]',
      );
      expect(r.error, isNull);
      expect(r.words.single.keys.toSet(), {'original', 'translation', 'translation_tg'});
    });

    test('пробелы по краям обрезаются', () {
      final r = parseVocabularyImport(
        '[{"original":"  der Tisch  ","translation":" стол ","translation_tg":" миз "}]',
      );
      expect(r.words.single['original'], 'der Tisch');
      expect(r.words.single['translation'], 'стол');
      expect(r.words.single['translation_tg'], 'миз');
    });

    test('нестроковые значения приводятся к тексту', () {
      final r = parseVocabularyImport('[{"original":42,"translation":"x","translation_tg":"y"}]');
      expect(r.error, isNull);
      expect(r.words.single['original'], '42');
    });
  });

  group('отклоняется — и объясняет чем именно', () {
    test('нет таджикского перевода — названы и поле, и номер слова', () {
      final r = parseVocabularyImport('[{"original":"der Stuhl","translation":"стул"}]');
      expect(r.words, isEmpty);
      expect(r.error, contains('Слово №1'));
      expect(r.error, contains('перевод на таджикский'));
    });

    test('пустой русский перевод считается незаполненным', () {
      final r = parseVocabularyImport('[{"original":"a","translation":"   ","translation_tg":"c"}]');
      expect(r.error, contains('перевод на русский'));
    });

    test('номер строки указывает на нужное слово', () {
      final r = parseVocabularyImport('['
          '{"original":"a","translation":"b","translation_tg":"c"},'
          '{"original":"d","translation":"e","translation_tg":"f"},'
          '{"original":"g","translation":"i"}]');
      expect(r.error, contains('Слово №3'));
      expect(r.error, isNot(contains('Слово №1')));
    });

    test('чужие имена ключей — подсказываются правильные', () {
      final r = parseVocabularyImport('[{"word":"der Stuhl","translation":"стул"}]');
      expect(r.error, contains('original'));
      expect(r.error, contains('"word"'));
    });

    test('транскрипция не считается чужим ключом', () {
      final r = parseVocabularyImport('[{"original":"a","transcription":"b","translation":"c"}]');
      expect(r.error, isNot(contains('"transcription"')));
    });

    test('русские ключи тоже распознаются как чужие', () {
      final r = parseVocabularyImport('[{"слово":"der Stuhl","перевод":"стул"}]');
      expect(r.error, contains('ожидаются'));
      expect(r.error, contains('"слово"'));
    });

    test('объект без скобок — сказано, что делать', () {
      final r = parseVocabularyImport('{"original":"a","translation":"b","translation_tg":"c"}');
      expect(r.error, contains('квадратные скобки'));
    });

    test('пустой массив', () {
      expect(parseVocabularyImport('[]').error, contains('пуст'));
    });

    test('сломанный синтаксис', () {
      expect(parseVocabularyImport('[{"original": ').error, contains('синтаксис'));
    });

    test('элемент не объект', () {
      expect(parseVocabularyImport('["der Tisch"]').error, contains('объектом'));
    });

    test('много ошибок — список обрезается, но количество названо', () {
      final rows = List.generate(9, (i) => '{"original":"w$i"}').join(',');
      final r = parseVocabularyImport('[$rows]');
      expect('\n'.allMatches(r.error!).length, lessThanOrEqualTo(5));
      expect(r.error, contains('…и ещё 4'));
    });

    test('ни одно слово не проходит, если хотя бы одно сломано', () {
      final r = parseVocabularyImport('['
          '{"original":"a","translation":"b","translation_tg":"c"},'
          '{"original":"d"}]');
      expect(r.words, isEmpty, reason: 'частичный импорт молча потерял бы половину списка');
    });
  });
}

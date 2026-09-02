// What a teacher pasting a dictionary JSON is told (§ vocabulary import
// errors, 2026-09-02).
//
// The rule itself is unchanged — original, transcription and translation all
// stay required, matching the per-word form. What these tests pin down is
// that a rejection now names the field, the word and the row, instead of the
// bare English "Field required" the server's report used to collapse into.
import 'package:deutsch_lernen/features/admin/course_builder/domain/vocabulary_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('принимается', () {
    test('все три поля заполнены', () {
      final r = parseVocabularyImport(
        '[{"original":"der Tisch","transcription":"дер тиш","translation":"стол"}]',
      );
      expect(r.error, isNull);
      expect(r.words, [
        {'original': 'der Tisch', 'transcription': 'дер тиш', 'translation': 'стол'},
      ]);
    });

    test('несколько слов', () {
      final r = parseVocabularyImport(vocabularyImportExample);
      expect(r.error, isNull);
      expect(r.words.length, 2);
    });

    test('лишние поля игнорируются, а не ломают импорт', () {
      final r = parseVocabularyImport(
        '[{"original":"a","transcription":"b","translation":"c","example":"x","note":1}]',
      );
      expect(r.error, isNull);
      expect(r.words.single.keys.toSet(), {'original', 'transcription', 'translation'});
    });

    test('пробелы по краям обрезаются', () {
      final r = parseVocabularyImport(
        '[{"original":"  der Tisch  ","transcription":" дер тиш ","translation":" стол "}]',
      );
      expect(r.words.single['original'], 'der Tisch');
      expect(r.words.single['translation'], 'стол');
    });

    test('нестроковые значения приводятся к тексту', () {
      final r = parseVocabularyImport('[{"original":42,"transcription":"x","translation":"y"}]');
      expect(r.error, isNull);
      expect(r.words.single['original'], '42');
    });
  });

  group('отклоняется — и объясняет чем именно', () {
    test('нет транскрипции — названы и поле, и номер слова', () {
      final r = parseVocabularyImport('[{"original":"der Stuhl","translation":"стул"}]');
      expect(r.words, isEmpty);
      expect(r.error, contains('Слово №1'));
      expect(r.error, contains('транскрипция'));
    });

    test('пустая транскрипция считается незаполненной', () {
      final r = parseVocabularyImport('[{"original":"a","transcription":"   ","translation":"c"}]');
      expect(r.error, contains('транскрипция'));
    });

    test('номер строки указывает на нужное слово', () {
      final r = parseVocabularyImport('['
          '{"original":"a","transcription":"b","translation":"c"},'
          '{"original":"d","transcription":"e","translation":"f"},'
          '{"original":"g","translation":"i"}]');
      expect(r.error, contains('Слово №3'));
      expect(r.error, isNot(contains('Слово №1')));
    });

    test('чужие имена ключей — подсказываются правильные', () {
      final r = parseVocabularyImport('[{"word":"der Stuhl","translation":"стул"}]');
      expect(r.error, contains('original'));
      expect(r.error, contains('"word"'));
    });

    test('русские ключи тоже распознаются как чужие', () {
      final r = parseVocabularyImport('[{"слово":"der Stuhl","перевод":"стул"}]');
      expect(r.error, contains('ожидаются'));
      expect(r.error, contains('"слово"'));
    });

    test('объект без скобок — сказано, что делать', () {
      final r = parseVocabularyImport('{"original":"a","transcription":"b","translation":"c"}');
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
          '{"original":"a","transcription":"b","translation":"c"},'
          '{"original":"d"}]');
      expect(r.words, isEmpty, reason: 'частичный импорт молча потерял бы половину списка');
    });
  });
}

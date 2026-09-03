// Frontend format check for the email-change modal (§ security & privacy
// rework, 2026-09-03). This is UX-only — the backend's EmailStr
// (email-validator) is the actual authority and was separately confirmed to
// reject every one of these same malformed shapes without a DNS lookup.
// These cases mirror that backend check so the two never quietly disagree
// about what counts as "obviously wrong".
import 'package:deutsch_lernen/features/settings/presentation/security_privacy_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('принимается', () {
    for (final v in [
      'user@example.com',
      'user.name+tag@example.co.uk',
      'a@example.com',
      'user@example.c',
      'USER@EXAMPLE.COM',
    ]) {
      test(v, () => expect(looksLikeValidEmail(v), isTrue));
    }
  });

  group('отклоняется', () {
    final cases = {
      'нет @': 'userexample.com',
      'нет домена': 'user@',
      'двойной @': 'user@@example.com',
      'нет TLD': 'user@example',
      'пробел в локальной части': 'user @example.com',
      'пробел в домене': 'user@exa mple.com',
      'двойная точка в локальной части': 'user..name@example.com',
      'домен начинается с точки': 'user@.example.com',
      'двойная точка в домене': 'user@example..com',
      'локальная часть начинается с точки': '.user@example.com',
      'локальная часть заканчивается точкой': 'user.@example.com',
      'домен начинается с дефиса': 'user@-example.com',
      'пустая строка': '',
      'только пробелы': '   ',
      'запрещённый символ (кавычка)': 'us"er@example.com',
    };
    cases.forEach((name, v) {
      test(name, () => expect(looksLikeValidEmail(v), isFalse, reason: v));
    });
  });

  test('пробелы по краям обрезаются перед проверкой', () {
    expect(looksLikeValidEmail('  user@example.com  '), isTrue);
  });
}

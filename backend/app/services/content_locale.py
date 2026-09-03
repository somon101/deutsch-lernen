"""Shared helpers for course CONTENT locale (§ course content language,
2026-09-04) — the language a course's own text/media is written IN (RU/TG),
never to be confused with:

  - the system UI language (frontend-only, ARB files, not this module);
  - `selectedLanguageId` on User (statistics scope — a real Language row,
    e.g. German, the language being TAUGHT);
  - `Course.levelId -> Level.languageId` (same "language being taught"
    dimension as above, reached through a course's Level).

A content locale is deliberately NOT a Language row: "ru"/"tg" are not
languages anyone's course teaches, so putting them in the Language table
would let someone create a "Russian" or "Tajik" *course* by mistake. It is
just a short allow-listed string, validated here, extensible by adding to
this tuple — never a schema/migration when the third locale (e.g. "de")
arrives, exactly as required.
"""

SUPPORTED_CONTENT_LOCALES: tuple[str, ...] = ("ru", "tg")
DEFAULT_CONTENT_LOCALE = "ru"


def is_supported_content_locale(locale: str | None) -> bool:
    return locale is not None and locale in SUPPORTED_CONTENT_LOCALES


def translations_by_locale(rows: list, id_field: str = "locale") -> dict[str, object]:
    """Small shared shape: a list of `*Translation` rows -> {locale: row}.
    Every translation table has a unique (parentId, locale) constraint, so
    this is always at most one row per locale — never a list to flatten."""
    return {getattr(row, id_field): row for row in rows}

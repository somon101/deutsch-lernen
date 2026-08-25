"""Exact port of src/content/parseVocabulary.ts — see text_utils.py's module
docstring for why bit-for-bit fidelity matters here."""

import regex

_BRACKETED_LINE = regex.compile(r"^\[.*\]$")


def parse_vocabulary(raw: str, lesson_id: str) -> list[dict]:
    lines = [line.strip() for line in regex.split(r"\r\n|\n", raw)]
    lines = [line for line in lines if line]

    entries: list[dict] = []
    i = 0
    index = 0

    while i < len(lines):
        german = lines[i]
        i += 1
        if i >= len(lines):
            break  # dangling word with no translation — drop it
        translation = lines[i]
        i += 1

        pronunciation = None
        if i < len(lines) and _BRACKETED_LINE.match(lines[i]):
            pronunciation = lines[i][1:-1].strip()
            i += 1

        entries.append(
            {
                "id": f"{lesson_id}-vocab-{index}",
                "german": german,
                "translation": translation,
                "pronunciation": pronunciation,
            }
        )
        index += 1

    return entries

"""Exact port of src/content/parseLessonText.ts — see text_utils.py's module
docstring for why bit-for-bit fidelity matters here."""

import regex

from app.legacy_parser.text_utils import (
    clean_quiz_text,
    extract_bracket_pronunciation,
    leading_emoji,
    looks_like_continuation,
    normalize_answer,
    strip_leading_emoji,
)

_STEP_RE = regex.compile(r"^Шаг\s+(\d+)\.\s*(.*)$")
_DASH_SPLIT = " — "

_HORIZONTAL_RULE = regex.compile(r"^\s*([-*_])\1{2,}\s*$")
_TABLE_SEPARATOR = regex.compile(r"^\s*\|?[\s:|-]*-{2,}[\s:|-]*\|?\s*$")
_TABLE_ROW = regex.compile(r"^\s*\|(.+)\|\s*$")
_HEADING = regex.compile(r"^(#{1,6})\s+(.*)$")
_NUMBERED_HEADING = regex.compile(r"^(\d+)\.\s*(.+)$")

_BOLD_STAR = regex.compile(r"\*\*(.+?)\*\*")
_BOLD_UNDERSCORE = regex.compile(r"__(.+?)__")
_ITALIC_STAR = regex.compile(r"(^|\s)\*(\S(?:.*?\S)?)\*(?=\s|$)")


def _strip_emphasis(text: str) -> str:
    text = _BOLD_STAR.sub(r"\1", text)
    text = _BOLD_UNDERSCORE.sub(r"\1", text)
    text = _ITALIC_STAR.sub(r"\1\2", text)
    return text


def _table_cells(line: str) -> list[str]:
    m = _TABLE_ROW.match(line)
    if not m:
        return []
    cells = [c.strip() for c in m.group(1).split("|")]
    return [c for c in cells if c]


def parse_lesson_text(raw: str) -> dict:
    """Turns raw lesson text into a sequence of typed blocks plus a
    deduplicated phrase pool, mirroring parseLessonText.ts's two return
    values exactly (block order and phrase order/ids both matter for the
    diff-verification step)."""
    lines = [line.strip() for line in regex.split(r"\r\n|\n", raw)]
    lines = [line for line in lines if line]

    blocks: list[dict] = []
    phrases: list[dict] = []
    seen_phrases: set[str] = set()
    phrase_index = 0
    title_taken = False

    def push_phrase(icon: str | None, left: str, translation: str) -> None:
        nonlocal phrase_index
        german, pronunciation = extract_bracket_pronunciation(left)
        # The material card keeps the exact text as written.
        blocks.append({"type": "phrase", "icon": icon, "german": german, "pronunciation": pronunciation, "translation": translation})

        key = f"{normalize_answer(german)}::{normalize_answer(translation)}"
        clean_german = clean_quiz_text(german)
        clean_translation = clean_quiz_text(translation)
        if clean_german and clean_translation and key not in seen_phrases:
            seen_phrases.add(key)
            phrases.append(
                {
                    "id": f"phrase-{phrase_index}",
                    "german": clean_german,
                    "pronunciation": pronunciation,
                    "translation": clean_translation,
                }
            )
            phrase_index += 1

    for i, raw_line in enumerate(lines):
        # Structural Markdown noise carries no lesson content.
        if _HORIZONTAL_RULE.match(raw_line) or _TABLE_SEPARATOR.match(raw_line):
            continue

        cells = _table_cells(raw_line)
        if cells:
            next_line = lines[i + 1] if i + 1 < len(lines) else None
            is_header = next_line is not None and _TABLE_SEPARATOR.match(next_line) is not None
            if is_header:
                blocks.append({"type": "subheading", "text": _strip_emphasis(" · ".join(cells))})
                continue
            if len(cells) >= 2:
                push_phrase(None, _strip_emphasis(cells[0]), _strip_emphasis(" ".join(cells[1:])))
                continue
            blocks.append({"type": "line", "text": _strip_emphasis(cells[0])})
            continue

        heading_match = _HEADING.match(raw_line)
        line = _strip_emphasis(heading_match.group(2).strip() if heading_match else raw_line)
        if not line:
            continue

        if not title_taken:
            title_taken = True
            blocks.append({"type": "title", "text": line})
            continue

        if heading_match:
            numbered = _NUMBERED_HEADING.match(line)
            if len(heading_match.group(1)) == 1 and numbered:
                blocks.append({"type": "step", "number": int(numbered.group(1)), "title": numbered.group(2)})
                continue
            icon = leading_emoji(line)
            blocks.append({"type": "subheading", "icon": icon, "text": strip_leading_emoji(line) if icon else line})
            continue

        step_match = _STEP_RE.match(line)
        if step_match:
            blocks.append({"type": "step", "number": int(step_match.group(1)), "title": step_match.group(2)})
            continue

        if _DASH_SPLIT in line:
            dash_index = line.index(_DASH_SPLIT)
            left_raw = line[:dash_index]
            translation = line[dash_index + len(_DASH_SPLIT) :].strip()
            icon = leading_emoji(left_raw)
            push_phrase(icon, strip_leading_emoji(left_raw) if icon else left_raw.strip(), translation)
            continue

        icon = leading_emoji(line)
        if icon:
            blocks.append({"type": "subheading", "icon": icon, "text": strip_leading_emoji(line)})
            continue

        blocks.append({"type": "line", "text": line, "tight": looks_like_continuation(line)})

    return {"blocks": blocks, "phrases": phrases}

"""Exact port of src/content/textUtils.ts — used ONLY by the one-time legacy
content import script (scripts/import_legacy_content.py). Every function
here must match its TypeScript counterpart bit-for-bit; the import script's
own verification step diffs this module's output against the real
TypeScript parser's output before anything is written to the database."""

import regex

_MASK32 = 0xFFFFFFFF


def _to_int32(x: int) -> int:
    x &= _MASK32
    return x - 0x100000000 if x >= 0x80000000 else x


def _to_uint32(x: int) -> int:
    return x & _MASK32


def _imul(a: int, b: int) -> int:
    """Math.imul: 32-bit integer multiplication, wraps, returns signed int32."""
    return _to_int32((_to_uint32(a) * _to_uint32(b)) & _MASK32)


# True if a leading pictographic symbol (emoji) starts the string.
_LEADING_EMOJI = regex.compile(r"^\p{Extended_Pictographic}(️)?")


def leading_emoji(text: str) -> str | None:
    m = _LEADING_EMOJI.match(text)
    return m.group(0) if m else None


def strip_leading_emoji(text: str) -> str:
    return _LEADING_EMOJI.sub("", text, count=1).strip()


# A line that starts with a lowercase letter or a "hanging" punctuation mark
# is very likely the tail end of the previous line rather than a new
# thought — used only for tightening vertical spacing, never for merging text.
_CONTINUATION_START = regex.compile(r"^[.,:;!)/–—]|^\p{Ll}")


def looks_like_continuation(text: str) -> bool:
    return _CONTINUATION_START.match(text) is not None


_BRACKET = regex.compile(r"\[([^\]]+)\]")
_WHITESPACE = regex.compile(r"\s+")


def extract_bracket_pronunciation(text: str) -> tuple[str, str | None]:
    m = _BRACKET.search(text)
    if not m:
        return text.strip(), None
    stripped = text.replace(m.group(0), "")
    stripped = _WHITESPACE.sub(" ", stripped).strip()
    return stripped, m.group(1).strip()


def seeded_random(seed: int):
    """Deterministic PRNG (mulberry32) — bit-for-bit port of the JS version,
    so exercise shuffling for a given seed produces the exact same sequence."""
    a = _to_uint32(seed)

    def next_value() -> float:
        nonlocal a
        a = _to_int32(a)
        a = _to_int32(a + 0x6D2B79F5)
        t = _imul(_to_int32(_to_uint32(a) ^ (_to_uint32(a) >> 15)), _to_int32(1 | a))
        t = _to_int32(_to_int32(t + _imul(_to_int32(_to_uint32(t) ^ (_to_uint32(t) >> 7)), _to_int32(61 | t))) ^ t)
        return _to_uint32(_to_uint32(t) ^ (_to_uint32(t) >> 14)) / 4294967296

    return next_value


def hash_string(input_str: str) -> int:
    h = 2166136261
    for ch in input_str:
        h = _to_uint32(h ^ ord(ch))
        h = _imul(h, 16777619)
    return _to_uint32(h)


def shuffle(items: list, rand) -> list:
    copy = list(items)
    i = len(copy) - 1
    while i > 0:
        j = int(rand() * (i + 1))
        copy[i], copy[j] = copy[j], copy[i]
        i -= 1
    return copy


def pick_n(items: list, n: int, rand) -> list:
    return shuffle(items, rand)[: min(n, len(items))]


# Mirrors src/content/textUtils.ts's normalizeAnswer character class exactly
# — note this is the CLIENT-side pattern (curly “” quotes), which
# genuinely differs from the SERVER-side content.ts's pattern (duplicated
# straight quotes instead) in the original codebase; both are ported
# faithfully to their own counterpart rather than unified, since neither
# side of that pre-existing discrepancy was asked to be "fixed" here.
_NORMALIZE_ANSWER_PUNCTUATION = regex.compile(
    "[.,!?;:…\"'«»„“”()]"
)


def normalize_answer(value: str) -> str:
    value = value.lower()
    value = _NORMALIZE_ANSWER_PUNCTUATION.sub("", value)
    value = _WHITESPACE.sub(" ", value)
    return value.strip()


def answers_match(a: str, b: str) -> bool:
    return normalize_answer(a) == normalize_answer(b)


# Same client-vs-server discrepancy note as above applies here too.
_QUIZ_EDGE_PUNCTUATION = regex.compile(
    "^[.!?;:…\"'«»„“”()/]+|[.!?;:…\"'«»„“”()/]+$"
)


def clean_quiz_text(value: str) -> str:
    value = _QUIZ_EDGE_PUNCTUATION.sub("", value)
    value = _WHITESPACE.sub(" ", value)
    return value.strip()

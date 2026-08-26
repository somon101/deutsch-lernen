"""Standalone duplicate-question similarity checker — no external/AI API,
per the approved plan (§25-28): plain text normalization + a proven
string-similarity algorithm, combined with structured signals (kind, topic,
material) so a shared correct answer or common word alone never counts as a
"duplicate" (§26's own example: "Haus" appears in many unrelated questions).

Deliberately generic (`compare_similarity` takes two plain dicts, not a
Question object) so it can be reused for other objects later, per §24.
"""

import difflib
import re

_WHITESPACE = re.compile(r"\s+")
_PUNCTUATION = re.compile(r"""[.,!?;:…"'«»„“”()\-–—]""")

# Weights sum to 1.0 — text similarity dominates but is never the sole
# signal (§26/§28: two questions can share an answer/word without being
# duplicates, and two materials can cover the same Topic with completely
# different wording).
_WEIGHT_TEXT = 0.45
_WEIGHT_ANSWER = 0.20
_WEIGHT_KIND = 0.10
_WEIGHT_TOPIC = 0.15
_WEIGHT_MATERIAL = 0.10


def normalize_text(value: str) -> str:
    value = value.lower()
    value = _PUNCTUATION.sub(" ", value)
    value = _WHITESPACE.sub(" ", value)
    return value.strip()


def _token_jaccard(a: str, b: str) -> float:
    tokens_a = set(normalize_text(a).split())
    tokens_b = set(normalize_text(b).split())
    if not tokens_a and not tokens_b:
        return 1.0
    if not tokens_a or not tokens_b:
        return 0.0
    return len(tokens_a & tokens_b) / len(tokens_a | tokens_b)


def _sequence_ratio(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, normalize_text(a), normalize_text(b)).ratio()


def compare_similarity(a: dict, b: dict) -> int:
    """0-100. `a`/`b` are plain dicts with `prompt`, `correctAnswer`, `kind`,
    and optionally `topicId`/`materialId` — matches Question's own fields so
    a Question row can be passed in directly via `.__dict__`-style access,
    but nothing here depends on the ORM model."""
    prompt_a, prompt_b = a.get("prompt") or "", b.get("prompt") or ""
    text_score = (_token_jaccard(prompt_a, prompt_b) + _sequence_ratio(prompt_a, prompt_b)) / 2

    answer_a, answer_b = normalize_text(a.get("correctAnswer") or ""), normalize_text(b.get("correctAnswer") or "")
    answer_score = 1.0 if answer_a and answer_a == answer_b else 0.0

    kind_score = 1.0 if a.get("kind") and a.get("kind") == b.get("kind") else 0.0
    topic_score = 1.0 if a.get("topicId") and a.get("topicId") == b.get("topicId") else 0.0
    material_score = 1.0 if a.get("materialId") and a.get("materialId") == b.get("materialId") else 0.0

    weighted = (
        text_score * _WEIGHT_TEXT
        + answer_score * _WEIGHT_ANSWER
        + kind_score * _WEIGHT_KIND
        + topic_score * _WEIGHT_TOPIC
        + material_score * _WEIGHT_MATERIAL
    )
    return round(weighted * 100)

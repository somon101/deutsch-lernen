"""Parses a lesson's raw materialText into the structured {blocks, phrases}
shape every client renders — reuses the same bit-exact-verified parser from
app/legacy_parser (see that package's docstring for how it was validated
against the real TypeScript parser). Promoted here from "one-time import
script helper" to a real request-time service: any client (the existing
React app already parses client-side; Flutter has no such parser and
shouldn't need one — see the migration plan's Phase 5 notes) can now get
pre-parsed content instead of raw text, without a second parser
implementation existing anywhere.
"""

from app.legacy_parser.parse_lesson_text import parse_lesson_text
from app.legacy_parser.text_utils import normalize_answer


def parse_material(material_text: str, vocabulary: list[dict]) -> dict:
    """Mirrors loader.ts's post-parse step exactly: blocks/phrases come from
    parse_lesson_text, then any phrase missing a pronunciation gets one
    backfilled from the lesson's own vocabulary list (matched by lowercased
    german word) — the parser alone only catches inline [bracket] hints."""
    if not material_text:
        return {"blocks": [], "phrases": []}

    parsed = parse_lesson_text(material_text)
    pronunciation_by_word = {v["german"].lower(): v.get("pronunciation") for v in vocabulary if v.get("pronunciation")}

    def with_pronunciation(item: dict) -> dict:
        if item.get("pronunciation"):
            return item
        fallback = pronunciation_by_word.get(item["german"].lower())
        return {**item, "pronunciation": fallback} if fallback else item

    blocks = [with_pronunciation(b) if b["type"] == "phrase" else b for b in parsed["blocks"]]
    phrases = [with_pronunciation(p) for p in parsed["phrases"]]
    return {"blocks": blocks, "phrases": phrases}


def filter_new_vocabulary(vocabulary: list[dict], taught_before_keys: set[str]) -> list[dict]:
    """Same list minus any word already taught as a new word in an earlier
    lesson of the same course (compared case/punctuation-insensitively) —
    mirrors loader.ts's newVocabulary filter exactly."""
    return [v for v in vocabulary if normalize_answer(v["german"]) not in taught_before_keys]

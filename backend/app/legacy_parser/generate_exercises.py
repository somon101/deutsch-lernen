"""Exact port of src/content/exerciseGenerators.ts's generation path (the
procedural, seeded-PRNG branch — legacy lessons have no admin-authored
blocks today, confirmed via a live DB check, so this is the only branch
that ever actually runs for lesson1/lesson2). See text_utils.py's module
docstring for why bit-for-bit fidelity matters here.

Per the user's explicit, approved decision: freezing these into normal
LessonQuestion rows loses two purely cosmetic pieces of the *generated*
presentation that the DB schema has no column for — a cloze exercise's
"Перевод: «...»" hint, and a true/false exercise's specific
"Правильный перевод «X» — «Y»" explanation (it becomes the generic
"Утверждение верно/неверно: «X»" once read back as an authored question).
Correctness of every question is unaffected — only this surrounding text.
"""

from app.legacy_parser.text_utils import (
    answers_match,
    clean_quiz_text,
    hash_string,
    normalize_answer,
    pick_n,
    seeded_random,
    shuffle,
)


class Pair:
    __slots__ = ("german", "translation")

    def __init__(self, german: str, translation: str):
        self.german = german
        self.translation = translation


def _pool(vocabulary: list[dict], phrases: list[dict]) -> list[Pair]:
    seen: set[str] = set()
    items: list[Pair] = []
    # Vocabulary entries come first so the curated spelling wins over a
    # material phrase that writes the same word with different punctuation.
    for entry in [*vocabulary, *phrases]:
        key = f"{normalize_answer(entry['german'])}::{normalize_answer(entry['translation'])}"
        if key in seen:
            continue
        seen.add(key)
        items.append(Pair(clean_quiz_text(entry["german"]), clean_quiz_text(entry["translation"])))
    return items


def _build_choice_questions(items: list[Pair], count: int, seed: int, id_prefix: str) -> list[dict]:
    if len(items) < 2:
        return []
    rand = seeded_random(seed)
    ordered = shuffle(items, rand)
    questions = []

    for i in range(min(count, len(ordered))):
        item = ordered[i]
        german_to_russian = i % 2 == 0
        prompt = f"Как переводится «{item.german}»?" if german_to_russian else f"Как будет по-немецки «{item.translation}»?"
        correct = item.translation if german_to_russian else item.german

        correct_key = normalize_answer(correct)
        seen_keys: set[str] = set()
        distractor_values = []
        for other in items:
            if other is item:
                continue
            value = other.translation if german_to_russian else other.german
            value_key = normalize_answer(value)
            if value_key == correct_key or value_key in seen_keys:
                continue
            seen_keys.add(value_key)
            distractor_values.append(value)

        distractors = pick_n(distractor_values, min(3, len(distractor_values)), rand)
        options = [correct, *distractors]

        questions.append(
            {"kind": "choice", "id": f"{id_prefix}-choice-{i}", "prompt": prompt, "options": options, "correctAnswer": correct}
        )

    return questions


def _build_truefalse_questions(items: list[Pair], count: int, seed: int, id_prefix: str) -> list[dict]:
    if len(items) < 2:
        return []
    rand = seeded_random(seed)
    ordered = shuffle(items, rand)
    questions = []

    for i in range(min(count, len(ordered))):
        item = ordered[i]
        is_true = rand() < 0.5
        shown_translation = item.translation

        if not is_true:
            others = [other for other in items if not answers_match(other.translation, item.translation)]
            if not others:
                continue
            shown_translation = pick_n(others, 1, rand)[0].translation

        questions.append(
            {
                "kind": "truefalse",
                "id": f"{id_prefix}-tf-{i}",
                "statement": f"«{item.german}» переводится как «{shown_translation}»",
                "correct": is_true,
                "explanation": f"Правильный перевод «{item.german}» — «{item.translation}».",
            }
        )

    return questions


def _build_match_exercises(items: list[Pair], size: int, seed: int, id_prefix: str) -> list[dict]:
    if len(items) < 3:
        return []
    rand = seeded_random(seed)
    chosen = pick_n(items, min(size, len(items)), rand)
    return [
        {
            "kind": "match",
            "id": f"{id_prefix}-match-0",
            "pairs": [
                {"id": f"{id_prefix}-match-0-{i}", "left": item.german, "right": item.translation}
                for i, item in enumerate(chosen)
            ],
        }
    ]


def _tokenize(text: str) -> list[str]:
    return [t for t in text.split() if t]


def _build_scramble_exercises(phrases: list[dict], count: int, seed: int, id_prefix: str) -> list[dict]:
    rand = seeded_random(seed)
    candidates = [p for p in phrases if len(_tokenize(p["german"])) >= 2]
    chosen = pick_n(candidates, min(count, len(candidates)), rand)

    results = []
    for i, phrase in enumerate(chosen):
        answer = _tokenize(phrase["german"])
        tokens = shuffle(answer, rand)
        attempts = 0
        while tokens == answer and attempts < 5:
            tokens = shuffle(answer, rand)
            attempts += 1
        results.append({"kind": "scramble", "id": f"{id_prefix}-scramble-{i}", "translation": phrase["translation"], "tokens": tokens, "answer": answer})
    return results


def _build_cloze_exercises(phrases: list[dict], vocab_words: list[str], count: int, seed: int, id_prefix: str) -> list[dict]:
    rand = seeded_random(seed)
    candidates = [p for p in phrases if len(_tokenize(p["german"])) >= 2]
    chosen = pick_n(candidates, min(count, len(candidates)), rand)

    results = []
    for i, phrase in enumerate(chosen):
        tokens = _tokenize(phrase["german"])
        blank_index = int(rand() * len(tokens))
        answer = tokens[blank_index]

        other_words = [t for idx, t in enumerate(tokens) if idx != blank_index] + vocab_words
        other_words = [w for w in other_words if not answers_match(w, answer)]
        seen_keys: set[str] = set()
        unique_others = []
        for w in other_words:
            w_key = normalize_answer(w)
            if w_key in seen_keys:
                continue
            seen_keys.add(w_key)
            unique_others.append(w)

        distractors = pick_n(unique_others, min(3, len(unique_others)), rand)
        options = shuffle([answer, *distractors], rand)

        results.append(
            {
                "kind": "cloze",
                "id": f"{id_prefix}-cloze-{i}",
                "translation": phrase["translation"],
                "before": " ".join(tokens[:blank_index]),
                "after": " ".join(tokens[blank_index + 1 :]),
                "options": options,
                "answer": answer,
            }
        )
    return results


def build_lesson_exercises(lesson_id: str, vocabulary: list[dict], phrases: list[dict]) -> dict:
    """Mirrors buildLessonExercises exactly for the generated (no
    admin-authored blocks) path — the only path that ever runs for
    lesson1/lesson2 today."""
    items = _pool(vocabulary, phrases)
    vocab_words = [clean_quiz_text(v["german"]) for v in vocabulary]

    mini_test_seed = hash_string(f"{lesson_id}:minitest")
    mini_test = [
        *_build_choice_questions(items, 4, mini_test_seed, "minitest"),
        *_build_truefalse_questions(items, 2, mini_test_seed + 1, "minitest"),
    ]

    practice_seed = hash_string(f"{lesson_id}:practice")
    practice = [
        *_build_choice_questions(items, 6, practice_seed, "practice"),
        *_build_cloze_exercises(phrases, vocab_words, 4, practice_seed + 1, "practice"),
        *_build_scramble_exercises(phrases, 4, practice_seed + 2, "practice"),
        *_build_match_exercises(items, 8, practice_seed + 3, "practice"),
        *_build_truefalse_questions(items, 4, practice_seed + 4, "practice"),
    ]

    review_seed = hash_string(f"{lesson_id}:review")
    review = _build_choice_questions(items, len(items), review_seed, "review")

    return {"minitest": mini_test, "practice": practice, "review": review}


def exercise_to_db_row(exercise: dict) -> dict:
    """Converts one generated Exercise into the flat {prompt, options,
    correctAnswer, kind, data} shape LessonQuestion rows use — the same
    shape saveBlockQuestions() writes for admin-authored questions, so a
    frozen question is indistinguishable in storage from a hand-authored
    one. See this module's docstring for the two known, approved,
    cosmetic-only losses (cloze translation hint, truefalse explanation
    wording)."""
    kind = exercise["kind"]
    if kind == "choice":
        return {"kind": "choice", "prompt": exercise["prompt"], "options": exercise["options"], "correctAnswer": exercise["correctAnswer"], "data": None}
    if kind == "truefalse":
        return {"kind": "truefalse", "prompt": exercise["statement"], "options": [], "correctAnswer": "true" if exercise["correct"] else "false", "data": None}
    if kind == "cloze":
        prompt = f"{exercise['before']} ___ {exercise['after']}".strip()
        return {"kind": "cloze", "prompt": prompt, "options": exercise["options"], "correctAnswer": exercise["answer"], "data": None}
    if kind == "scramble":
        # toExercise() treats an authored scramble's `prompt` as the
        # translation hint and re-shuffles `options` fresh on every read —
        # so the canonical (unshuffled) answer order is what should be
        # stored, not the frozen `tokens` shuffle order.
        return {
            "kind": "scramble",
            "prompt": exercise["translation"],
            "options": exercise["answer"],
            "correctAnswer": " ".join(exercise["answer"]),
            "data": None,
        }
    if kind == "match":
        # Admin-authored match pairs never carry an id (see
        # blockQuestionSchema — only left/right) — toExercise() synthesizes
        # one fresh at read time from the *question's* id. Strip it here so
        # a frozen row is storage-shape-identical to a hand-authored one.
        pairs = [{"left": p["left"], "right": p["right"]} for p in exercise["pairs"]]
        return {"kind": "match", "prompt": "", "options": [], "correctAnswer": "", "data": pairs}
    raise ValueError(f"unknown exercise kind: {kind}")

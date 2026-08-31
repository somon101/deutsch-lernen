"""Auto-generated "missing word" exercises (§ auto blank, 2026-08-31) — the
teacher saves only full sentences (Question.kind="auto_blank", phrases
stored in the existing `data` JSONB); everything else is resolved fresh,
per learner, at serve time:

- WHICH phrase: sequential by phraseIndex (§10, clarified in conversation —
  slot 0 always phrase 0, slot 1 always phrase 1, ... so every phrase the
  teacher wrote actually gets used, never skipped/repeated by chance).
- WHICH word to blank: random, chosen from the phrase's own words as plain
  TEXT — the blanked word does NOT need a matching word card (clarified in
  conversation: only the WRONG options need to be real learned-word cards;
  the correct answer is just the text that was actually removed).
- Wrong options: random, real word cards from the learner's own
  UserWordProgress (§ word cards, 2026-08-31), same language as the
  exercise, deduplicated, excluding the correct text.

Nothing here writes to the database — generation is pure and stateless
(§11/§12: preparing a question is not the same as answering it). What
WOULD need to persist doesn't exist until the learner actually answers
(see grade_blank_answer), at which point it's one ordinary AnswerLog row,
same table every other exercise kind already uses — not a second history
system.

The generated question's answer key travels to the client as a signed
(not encrypted) token — same as every other exercise kind, the correct
answer is visible to a technically curious client (that's already true for
choice/cloze/scramble too), but it can't be TAMPERED WITH: grading re-reads
the signed payload server-side rather than trusting a client-asserted
`correct` boolean (§25).
"""

import random
import re
from datetime import datetime, timedelta, timezone

import jwt as pyjwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.lesson_block import LessonBlock
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.services.content import LEGACY_COURSE_ID, normalize_word
from app.services.courses import derive_language_id
from app.services.progress import submit_answer
from app.services.vocabulary import get_random_learned_words

_TOKEN_TYP = "auto_blank_v1"
_TOKEN_EXPIRY = timedelta(minutes=30)
_WRONG_OPTION_COUNT = 3
_WORD_RE = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿА-Яа-яЁё]+")


def _tokenize(phrase: str) -> list[dict]:
    """Word spans only (§5/§22 — never a punctuation mark, digit, or
    special character as a blank candidate); everything else in the
    phrase (spaces, punctuation) stays exactly where it is when the blank
    is spliced in."""
    return [{"text": m.group(), "start": m.start(), "end": m.end()} for m in _WORD_RE.finditer(phrase)]


def _sign_token(payload: dict) -> str:
    body = {**payload, "typ": _TOKEN_TYP, "exp": datetime.now(timezone.utc) + _TOKEN_EXPIRY}
    return pyjwt.encode(body, settings.jwt_secret, algorithm="HS256")


def _verify_token(token: str) -> dict | None:
    """Returns the payload, or None on ANY failure (expired, tampered,
    wrong type, malformed) — mirrors auth/jwt.py's verify_token, which
    swallows every error into null rather than raising."""
    try:
        payload = pyjwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except pyjwt.PyJWTError:
        return None
    if payload.get("typ") != _TOKEN_TYP:
        return None
    return payload


async def get_question_language_id(db: AsyncSession, question_id: str) -> str | None:
    """Same derivation the word-cards migration used for VocabularyItem
    (course -> level -> language), just walked from whichever placement
    this question happens to be attached to (§ "можем сортировать по
    языку", clarified in conversation) — computed on demand rather than
    stored, since a Question can in principle have several placements and
    there's no existing column to keep in sync."""
    placement = (
        await db.execute(select(QuestionPlacement).where(QuestionPlacement.questionId == question_id).limit(1))
    ).scalar_one_or_none()
    if not placement:
        return None

    course_id: str | None = None
    if placement.lessonBlockId:
        course_id = await db.scalar(select(LessonBlock.courseId).where(LessonBlock.id == placement.lessonBlockId))
    elif placement.materialBlockId:
        course_id = await db.scalar(
            select(Material.courseId).join(MaterialBlock, MaterialBlock.materialId == Material.id).where(MaterialBlock.id == placement.materialBlockId)
        )
    elif placement.legacyLessonId:
        course_id = LEGACY_COURSE_ID
    if not course_id:
        return None
    return await derive_language_id(db, course_id)


async def generate_blank_question(db: AsyncSession, question_id: str, phrase_index: int, user_id: str) -> dict | None:
    """None means "can't safely generate this one" (§5/§9) — the caller
    must not show anything to the learner in that case, not a broken
    exercise."""
    question = await db.get(Question, question_id)
    if not question or question.kind != "auto_blank":
        return None
    phrases = (question.data or {}).get("phrases", [])
    if not (0 <= phrase_index < len(phrases)):
        return None
    phrase = phrases[phrase_index]

    candidates = _tokenize(phrase)
    if len(candidates) < 2:
        # Fewer than 2 real words left nothing sensible behind after a
        # blank (§5/§22: a 1-word phrase, or a phrase with no real words
        # at all — just numbers/punctuation).
        return None
    blank = random.choice(candidates)
    correct_text = blank["text"]
    prompt_with_blank = f"{phrase[: blank['start']]}______{phrase[blank['end'] :]}"

    language_id = await get_question_language_id(db, question_id)
    wrong_words = await get_random_learned_words(db, user_id, count=_WRONG_OPTION_COUNT, language_id=language_id, exclude_text=correct_text)
    if not wrong_words:
        # §9: not enough learned vocabulary to safely offer even one wrong
        # option — don't show a 1-option "exercise".
        return None

    options = [{"text": correct_text, "wordId": None}] + [{"text": w["word"], "wordId": w["wordId"]} for w in wrong_words]
    random.shuffle(options)

    token_payload = {
        "questionId": question_id,
        "phraseIndex": phrase_index,
        "sourcePhrase": phrase,
        "promptWithBlank": prompt_with_blank,
        "correctText": correct_text,
        "options": options,
    }
    return {"generatedQuestionId": _sign_token(token_payload), "promptWithBlank": prompt_with_blank, "options": options}


async def grade_blank_answer(db: AsyncSession, *, user_id: str, question_id: str, token: str, selected_text: str, placement_id: str | None) -> dict | None:
    """Re-derives correctness from the SIGNED payload, never from a
    client-asserted boolean (§25) — a tampered or expired token is
    rejected outright (None), same as an unrecognized question id would
    be. Writes exactly one AnswerLog row via the existing submit_answer
    (§13/§14 — no second history table), with the full generated-question
    snapshot as answerData so any later reconstruction never has to
    re-generate anything (§15)."""
    payload = _verify_token(token)
    if not payload or payload.get("questionId") != question_id:
        return None

    correct = normalize_word(selected_text) == normalize_word(payload["correctText"])
    answer_data = {
        "sourcePhrase": payload["sourcePhrase"],
        "promptWithBlank": payload["promptWithBlank"],
        "phraseIndex": payload["phraseIndex"],
        "correctAnswerText": payload["correctText"],
        "options": payload["options"],
        "selectedText": selected_text,
    }
    log = await submit_answer(db, user_id, question_id, placement_id, answer_data, correct)
    if not log:
        return None
    # Safe to reveal now (unlike the generate response, which never states
    # which option is correct) — this generated version has just been
    # spent, the learner already committed their pick, matching every
    # other exercise kind's own "show me the right answer once I've
    # answered" feedback convention.
    return {"ok": True, "correct": correct, "correctText": payload["correctText"]}

"""Auto-generated "translate the word" exercises (§ auto translate,
2026-09-02).

The teacher stores only a source and how many questions they want
(Question.kind="auto_translate", both in the existing `data` JSONB). Which
words those turn into is decided here, per learner, per session — nothing
about a selection is written to the database, and no word is ever copied:
questions reference the existing VocabularyItem cards by id.

This module is the GENERATOR half of `SOURCE -> WORD POOL -> EXERCISE
GENERATOR`. It asks app/services/word_pool for a list of cards and knows
nothing about why they are in it — not that "learned" currently means every
learned word, not that a future practice algorithm might hand back fifteen
prioritised ones instead. Swapping or adding a source needs no change here.

Two blocks drawing on the same source never repeat a word inside one
session: every such question in the lesson is ordered the way the learner
meets it, and each takes its own consecutive slice of one shuffled pool. The
shuffle is seeded, so the same learner and session always get the same
allocation (a re-read, a refresh, a prefetch), while a later attempt reseeds
and may draw differently.

The answer key travels to the client as a signed (not encrypted) token, the
same way auto_blank's does, so grading re-reads a server-signed payload
instead of trusting a client-asserted `correct`.
"""

import hashlib
import random
from datetime import datetime, timedelta, timezone

import jwt as pyjwt
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.lesson_block import LessonBlock
from app.models.lesson_state import LessonAttempt
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.services.content import normalize_word
from app.services.progress import submit_answer
from app.services.word_pool import build_word_pool

_TOKEN_TYP = "auto_translate_v1"
_TOKEN_EXPIRY = timedelta(minutes=30)
_WRONG_OPTION_COUNT = 3

# The order the learner actually meets the stages in, so two blocks' slices
# of the pool line up with the order they are answered.
_STAGE_RANK = {"minitest": 0, "practice": 1, "review": 2}


def _sign_token(payload: dict) -> str:
    body = {**payload, "typ": _TOKEN_TYP, "exp": datetime.now(timezone.utc) + _TOKEN_EXPIRY}
    return pyjwt.encode(body, settings.jwt_secret, algorithm="HS256")


def _verify_token(token: str) -> dict | None:
    try:
        payload = pyjwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except pyjwt.PyJWTError:
        return None
    if payload.get("typ") != _TOKEN_TYP:
        return None
    return payload


def _seed(*parts: str) -> int:
    """A stable seed. Deliberately not built on hash(), which Python salts
    per process — the same learner and session must reproduce the same
    allocation across requests and restarts."""
    digest = hashlib.sha256("\x1f".join(parts).encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def read_config(question: Question) -> tuple[str, int]:
    """The stored (source, count). Count is clamped at zero here so a bad
    stored value can never turn into a negative slice."""
    data = question.data or {}
    source = data.get("source") or "lesson"
    try:
        count = int(data.get("count") or 0)
    except (TypeError, ValueError):
        count = 0
    return source, max(0, count)


async def _locate_question(db: AsyncSession, question_id: str) -> tuple[str | None, str | None]:
    """(courseId, lessonId) of the quiz block this question is placed in.
    Only lessonBlock placements matter — an auto_translate question is a
    quiz-stage exercise, and its pool is scoped to the lesson it sits in."""
    placement = (
        await db.execute(
            select(QuestionPlacement).where(QuestionPlacement.questionId == question_id, QuestionPlacement.lessonBlockId.isnot(None)).limit(1)
        )
    ).scalar_one_or_none()
    if not placement:
        return None, None
    block = await db.get(LessonBlock, placement.lessonBlockId)
    if not block:
        return None, None
    return block.courseId, block.lessonId


async def _session_index(db: AsyncSession, user_id: str, lesson_id: str) -> int:
    """How many times this learner has already finished this lesson. Stable
    for the whole of one pass (an attempt row is only written on
    completion) and one higher on the next, which is what makes a repeat
    pass able to draw a different set."""
    return int(await db.scalar(select(func.count()).select_from(LessonAttempt).where(LessonAttempt.userId == user_id, LessonAttempt.lessonId == lesson_id)) or 0)


async def _allocation(db: AsyncSession, *, question: Question, source: str, lesson_id: str, user_id: str) -> list[dict]:
    """The words this question owns for this session.

    Every auto_translate question in the lesson drawing on the same source
    is put in the learner's own order and given a consecutive slice of one
    shuffled pool, so no two of them can land on the same word. A question
    whose slice runs past the end of the pool simply gets fewer words —
    the pool is never padded and a word is never reused to hit a count.
    """
    pool = await build_word_pool(db, source=source, user_id=user_id, lesson_id=lesson_id)
    if not pool:
        return []

    session = await _session_index(db, user_id, lesson_id)
    shuffled = list(pool)
    random.Random(_seed(user_id, lesson_id, source, str(session))).shuffle(shuffled)

    offset = 0
    for sibling_id, sibling_count in await _siblings(db, lesson_id=lesson_id, source=source):
        if sibling_id == question.id:
            return shuffled[offset : offset + sibling_count]
        offset += sibling_count
    return []


async def _siblings(db: AsyncSession, *, lesson_id: str, source: str) -> list[tuple[str, int]]:
    """Every auto_translate question in this lesson using this source, as
    (questionId, count), in the order the learner meets them: stage, then
    block position, then position within the block."""
    blocks = (await db.execute(select(LessonBlock).where(LessonBlock.lessonId == lesson_id))).scalars().all()
    if not blocks:
        return []
    block_by_id = {b.id: b for b in blocks}

    rows = (
        await db.execute(
            select(QuestionPlacement, Question)
            .join(Question, Question.id == QuestionPlacement.questionId)
            .where(QuestionPlacement.lessonBlockId.in_(list(block_by_id)), Question.kind == "auto_translate")
        )
    ).all()

    ordered = []
    for placement, question in rows:
        block = block_by_id[placement.lessonBlockId]
        q_source, q_count = read_config(question)
        if q_source != source or q_count <= 0:
            continue
        ordered.append(((_STAGE_RANK.get(block.stage, 99), block.position, placement.position, question.id), question.id, q_count))
    ordered.sort(key=lambda t: t[0])
    return [(qid, count) for _, qid, count in ordered]


def _build_options(pool: list[dict], correct: dict) -> list[dict]:
    """The correct translation plus up to three others from the same pool.

    Deduplicated by normalized translation, not by word: two different words
    that mean the same thing would otherwise show up as two identical-looking
    options, one of which is silently also right.
    """
    correct_key = normalize_word(correct["translation"])
    seen = {correct_key}
    wrong = []
    for card in pool:
        if card["wordId"] == correct["wordId"]:
            continue
        key = normalize_word(card["translation"])
        if not key or key in seen:
            continue
        seen.add(key)
        wrong.append(card)

    random.shuffle(wrong)
    options = [{"text": correct["translation"], "wordId": correct["wordId"]}] + [
        {"text": c["translation"], "wordId": c["wordId"]} for c in wrong[:_WRONG_OPTION_COUNT]
    ]
    random.shuffle(options)
    return options


async def generate_translate_question(db: AsyncSession, question_id: str, slot_index: int, user_id: str) -> dict | None:
    """None means this slot can't be shown — the pool is smaller than the
    requested count, or there aren't enough distinct translations to offer a
    choice at all. The caller must skip it rather than render something
    broken."""
    question = await db.get(Question, question_id)
    if not question or question.kind != "auto_translate":
        return None

    source, count = read_config(question)
    if slot_index < 0 or slot_index >= count:
        return None

    _, lesson_id = await _locate_question(db, question_id)
    if not lesson_id:
        return None

    words = await _allocation(db, question=question, source=source, lesson_id=lesson_id, user_id=user_id)
    if slot_index >= len(words):
        # Fewer words in the pool than the teacher asked for. Never padded
        # and never repeated to make up the number.
        return None
    correct = words[slot_index]

    pool = await build_word_pool(db, source=source, user_id=user_id, lesson_id=lesson_id)
    options = _build_options(pool, correct)
    if len(options) < 2:
        # A single option isn't a question.
        return None

    prompt = f"Как переводится слово «{correct['word']}»?"
    token_payload = {
        "questionId": question_id,
        "slotIndex": slot_index,
        "wordId": correct["wordId"],
        "word": correct["word"],
        "prompt": prompt,
        "correctText": correct["translation"],
        "options": options,
        "source": source,
    }
    return {"generatedQuestionId": _sign_token(token_payload), "prompt": prompt, "word": correct["word"], "options": options}


async def grade_translate_answer(
    db: AsyncSession, *, user_id: str, question_id: str, token: str, selected_text: str, placement_id: str | None
) -> dict | None:
    """Correctness is re-derived from the signed payload, never from the
    client. Writes exactly one AnswerLog row through the same submit_answer
    every other exercise kind uses — no second history."""
    payload = _verify_token(token)
    if not payload or payload.get("questionId") != question_id:
        return None

    correct = normalize_word(selected_text) == normalize_word(payload["correctText"])
    answer_data = {
        "wordId": payload["wordId"],
        "word": payload["word"],
        "prompt": payload["prompt"],
        "slotIndex": payload["slotIndex"],
        "source": payload["source"],
        "correctAnswerText": payload["correctText"],
        "options": payload["options"],
        "selectedText": selected_text,
    }
    log = await submit_answer(db, user_id, question_id, placement_id, answer_data, correct)
    if not log:
        return None
    return {"ok": True, "correct": correct, "correctText": payload["correctText"]}

"""Auto-generated "matching" exercises (§ auto match, 2026-09-02).

The teacher stores only how many pairs to show (2, 4, 6 or 8); which words
those become is decided per learner, per session, at serve time. No word is
copied — pairs reference the existing VocabularyItem cards by id — and no
selection is persisted, so a later attempt can draw differently.

Keeps the `SOURCE -> WORD POOL -> EXERCISE GENERATOR` split. The source
registered below answers only "which cards may this exercise draw from, best
first"; the generator takes that list and never learns why a word is in it.
When the adaptive algorithm arrives (weak words, long-unrevised words, words
with many mistakes) it replaces this provider and the generator is untouched.

The source's ordering is its whole contribution, and the generator preserves
it: words learned TODAY that the lesson's "Переведи слово" exercises have not
already claimed come first, then everything else the learner has learned. So
a run only falls back to older vocabulary once today's suitable words run
out, which is exactly the rule this exercise exists to follow.
"""

import hashlib
import random
from datetime import datetime, timedelta, timezone

import jwt as pyjwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.question import Question
from app.models.user_word_progress import UserWordProgress
from app.services.auto_translate import _locate_question, _session_index, words_used_by_translate_word
from app.services.content import normalize_word
from app.services.progress import submit_answer
from app.services.vocabulary import get_words
from app.services.word_pool import build_word_pool, register_source
from app.utils import utcnow

_TOKEN_TYP = "auto_match_v1"
_TOKEN_EXPIRY = timedelta(minutes=30)

# The only pair counts a teacher may choose. Enforced by the schema on save
# and again here at serve time, so a value smuggled past the form still
# cannot produce an exercise.
ALLOWED_PAIR_COUNTS: tuple[int, ...] = (2, 4, 6, 8)

# The name this exercise's source is registered under.
SOURCE_TODAY_FIRST = "today_unused_by_translate_then_earlier"


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
    digest = hashlib.sha256("\x1f".join(parts).encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def read_config(question: Question) -> int:
    """The stored pair count, or 0 if it isn't one of the allowed values.

    Strict on purpose: a value that isn't already a whole number is rejected
    rather than coerced, so a stored 2.5 can't quietly become a 2 the
    teacher never chose. The schema refuses such values on save; this is the
    second line for anything that reached the row another way. bool is
    excluded explicitly — in Python it would otherwise pass as an int.
    """
    raw = (question.data or {}).get("count")
    if isinstance(raw, bool) or not isinstance(raw, int):
        return 0
    return raw if raw in ALLOWED_PAIR_COUNTS else 0


# ---------------------------------------------------------------------------
# SOURCE
# ---------------------------------------------------------------------------


async def _today_first_pool(db: AsyncSession, *, user_id: str, lesson_id: str) -> list[dict]:
    """Today's still-free words first, then everything learned earlier.

    "Free" means not claimed by this lesson's "Переведи слово" exercises —
    and only those. Every other exercise kind is ignored on purpose: a word
    shown by manual matching, by "Пропущенное слово" or by anything else
    stays fully available here.

    The same exclusion is applied to the fallback tier as well. The rule only
    names today's words, but a word the lesson is already spending on
    "Переведи слово" would be just as duplicated coming back as an older one,
    and leaving it out can only shrink the pool, never corrupt it.
    """
    used_by_translate = await words_used_by_translate_word(db, user_id=user_id, lesson_id=lesson_id)
    today = utcnow().date()

    rows = (
        await db.execute(
            select(UserWordProgress.wordId, UserWordProgress.learnedAt)
            .where(UserWordProgress.userId == user_id)
            .order_by(UserWordProgress.learnedAt.desc())
        )
    ).all()

    today_ids, earlier_ids = [], []
    for word_id, learned_at in rows:
        if word_id in used_by_translate:
            continue
        (today_ids if learned_at and learned_at.date() == today else earlier_ids).append(word_id)

    # One lookup for both tiers, then split back — the card data is the same
    # either way, only the order differs.
    cards = {c["wordId"]: c for c in await get_words(db, today_ids + earlier_ids)}
    ordered = [cards[i] for i in today_ids if i in cards] + [cards[i] for i in earlier_ids if i in cards]

    seen: set[str] = set()
    pool = []
    for c in ordered:
        key = normalize_word(c["word"])
        if not key or key in seen or not (c.get("translation") or "").strip():
            continue
        seen.add(key)
        pool.append(c)
    return pool


register_source(SOURCE_TODAY_FIRST, _today_first_pool)


async def today_pool_breakdown(db: AsyncSession, *, user_id: str, lesson_id: str) -> dict:
    """How the pool splits between the two tiers — for the builder's hint and
    for tests that need to see the rule working, not just its result."""
    used = await words_used_by_translate_word(db, user_id=user_id, lesson_id=lesson_id)
    today = utcnow().date()
    rows = (await db.execute(select(UserWordProgress.wordId, UserWordProgress.learnedAt).where(UserWordProgress.userId == user_id))).all()
    today_all = [w for w, at in rows if at and at.date() == today]
    return {
        "learnedToday": len(today_all),
        "usedByTranslateWord": len(used),
        "todayUnusedByTranslateWord": len([w for w in today_all if w not in used]),
        "total": len(await build_word_pool(db, source=SOURCE_TODAY_FIRST, user_id=user_id, lesson_id=lesson_id)),
    }


# ---------------------------------------------------------------------------
# GENERATOR
# ---------------------------------------------------------------------------


async def _siblings(db: AsyncSession, *, lesson_id: str, user_id: str) -> list[tuple[str, int]]:
    """Every auto_match question in this lesson, as (questionId, count), in
    the order the learner meets them — so two blocks can be given
    non-overlapping slices exactly the way the translate exercises are."""
    from app.models.lesson_block import LessonBlock
    from app.models.question_placement import QuestionPlacement

    blocks = (await db.execute(select(LessonBlock).where(LessonBlock.lessonId == lesson_id))).scalars().all()
    if not blocks:
        return []
    block_by_id = {b.id: b for b in blocks}
    rank = {"minitest": 0, "practice": 1, "review": 2}

    rows = (
        await db.execute(
            select(QuestionPlacement, Question)
            .join(Question, Question.id == QuestionPlacement.questionId)
            .where(QuestionPlacement.lessonBlockId.in_(list(block_by_id)), Question.kind == "auto_match")
        )
    ).all()

    ordered = []
    for placement, question in rows:
        count = read_config(question)
        if count <= 0:
            continue
        block = block_by_id[placement.lessonBlockId]
        ordered.append(((rank.get(block.stage, 99), block.position, placement.position, question.id), question.id, count))
    ordered.sort(key=lambda t: t[0])
    return [(qid, c) for _, qid, c in ordered]


async def _allocation(db: AsyncSession, *, question_id: str, lesson_id: str, user_id: str) -> list[dict]:
    """The cards one auto_match question owns for this session.

    The pool arrives priority-ordered, and that order is what makes the rule
    work, so it is never shuffled as a whole. Instead each tier is shuffled
    within itself — today's words stay ahead of the older ones, but which of
    them a session picks still varies. Blocks then take consecutive slices,
    so two of them in one lesson can't collide.
    """
    pool = await build_word_pool(db, source=SOURCE_TODAY_FIRST, user_id=user_id, lesson_id=lesson_id)
    if not pool:
        return []

    used_by_translate = await words_used_by_translate_word(db, user_id=user_id, lesson_id=lesson_id)
    today = utcnow().date()
    today_ids = {
        w
        for w, at in (
            await db.execute(select(UserWordProgress.wordId, UserWordProgress.learnedAt).where(UserWordProgress.userId == user_id))
        ).all()
        if at and at.date() == today and w not in used_by_translate
    }

    session = await _session_index(db, user_id, lesson_id)
    rng = random.Random(_seed(user_id, lesson_id, "auto_match", str(session)))
    tier_today = [c for c in pool if c["wordId"] in today_ids]
    tier_earlier = [c for c in pool if c["wordId"] not in today_ids]
    rng.shuffle(tier_today)
    rng.shuffle(tier_earlier)
    ordered = tier_today + tier_earlier

    offset = 0
    for sibling_id, sibling_count in await _siblings(db, lesson_id=lesson_id, user_id=user_id):
        if sibling_id == question_id:
            return ordered[offset : offset + sibling_count]
        offset += sibling_count
    return []


async def generate_match_question(db: AsyncSession, question_id: str, user_id: str) -> dict | None:
    """None means this exercise can't be shown — the configured count isn't
    an allowed one, or the learner doesn't have enough distinct words yet.
    Never returns a short exercise: asking for 6 pairs and showing 4 would be
    a different exercise from the one the teacher configured."""
    question = await db.get(Question, question_id)
    if not question or question.kind != "auto_match":
        return None

    count = read_config(question)
    if count <= 0:
        return None

    _, lesson_id = await _locate_question(db, question_id)
    if not lesson_id:
        return None

    cards = await _allocation(db, question_id=question_id, lesson_id=lesson_id, user_id=user_id)
    if len(cards) < count:
        # Not enough distinct words. Same contract as the other automatic
        # exercises: report "can't generate" and let the runner skip it,
        # rather than padding or repeating a word.
        return None
    cards = cards[:count]

    session = await _session_index(db, user_id, lesson_id)
    rng = random.Random(_seed(user_id, lesson_id, "auto_match_display", question_id, str(session)))
    left = [{"wordId": c["wordId"], "text": c["word"]} for c in cards]
    right = [{"wordId": c["wordId"], "text": c["translation"]} for c in cards]
    rng.shuffle(left)
    rng.shuffle(right)

    token_payload = {
        "questionId": question_id,
        "pairs": [{"wordId": c["wordId"], "left": c["word"], "right": c["translation"]} for c in cards],
    }
    return {"generatedQuestionId": _sign_token(token_payload), "count": count, "left": left, "right": right}


async def grade_match_answer(
    db: AsyncSession, *, user_id: str, question_id: str, token: str, pairs: list[dict], placement_id: str | None
) -> dict | None:
    """Correctness is re-derived from the signed pairs, never from anything
    the client asserts. Writes exactly one AnswerLog row through the same
    submit_answer every other exercise uses — the attempt history keeps its
    single shape."""
    payload = _verify_token(token)
    if not payload or payload.get("questionId") != question_id:
        return None

    expected = {p["wordId"]: p["right"] for p in payload["pairs"]}
    submitted = {p.get("wordId"): (p.get("right") or "") for p in pairs if isinstance(p, dict)}
    correct = len(submitted) == len(expected) and all(
        wid in submitted and normalize_word(submitted[wid]) == normalize_word(right) for wid, right in expected.items()
    )

    answer_data = {
        "pairs": payload["pairs"],
        "submitted": pairs,
        "wordIds": [p["wordId"] for p in payload["pairs"]],
    }
    log = await submit_answer(db, user_id, question_id, placement_id, answer_data, correct)
    if not log:
        return None
    return {"ok": True, "correct": correct, "pairs": payload["pairs"]}

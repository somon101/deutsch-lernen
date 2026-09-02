"""Word pools for auto-generated exercises (§ auto translate, 2026-09-02).

This is the SOURCE half of `SOURCE -> WORD POOL -> EXERCISE GENERATOR`. A
source answers exactly one question — "which word cards may this exercise
draw from, for this learner, right now" — and hands back a plain ordered
list of cards. It never decides how many are used, which one is correct, or
what the wrong options are; that is the generator's job.

The split exists so the reason a word is in the pool stays out of the
exercise. Today "learned" means every word the learner has learned. The
planned practice algorithm ("these 15 are due for review") becomes one more
entry in [_PROVIDERS] returning a shorter, prioritised list, and every
generator built on this keeps working untouched — no exercise reads
UserWordProgress itself, so none of them encode "learned = all learned".

Pools are deduplicated by normalized word, so a card repeated across lessons
can't turn into two versions of the same question, and are returned in a
stable order (the caller applies its own seeded shuffle) so that a given
learner and session always see the same allocation.
"""

from typing import Awaitable, Callable, Literal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course_lesson import CourseLesson
from app.models.vocabulary_item import VocabularyItem
from app.services.content import normalize_word
from app.services.courses import derive_language_id
from app.services.vocabulary import get_my_words, get_words

# Kept as plain strings rather than an enum so the stored question `data`
# round-trips as ordinary JSON, the same way every other question kind's
# data already does.
WordPoolSource = Literal["lesson", "learned"]

WORD_POOL_SOURCES: tuple[str, ...] = ("lesson", "learned")

# Used when a stored question somehow carries no source at all. It lives
# here, not in any generator: which sources exist, and which one stands in
# for a missing value, is this layer's business — a generator that hardcoded
# a source name would be encoding knowledge it is supposed not to have.
DEFAULT_SOURCE = "lesson"

SOURCE_LABELS = {
    "lesson": "Из этого урока",
    "learned": "Из изученных слов пользователя",
}


def _dedupe(cards: list[dict]) -> list[dict]:
    """One entry per distinct word. Two cards that render as the same word
    (the same vocabulary repeated in another lesson, or differing only by
    punctuation/case) would otherwise become two identical questions, and
    could collide as a question's own distractor."""
    seen: set[str] = set()
    out = []
    for c in cards:
        key = normalize_word(c["word"])
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(c)
    return out


async def _lesson_pool(db: AsyncSession, *, user_id: str, lesson_id: str) -> list[dict]:
    """Every word taught by this lesson. Independent of the learner — two
    people on the same lesson draw from the same set."""
    word_ids = (
        await db.execute(select(VocabularyItem.id).where(VocabularyItem.lessonId == lesson_id).order_by(VocabularyItem.position, VocabularyItem.id))
    ).scalars().all()
    return _dedupe(await get_words(db, list(word_ids)))


async def _learned_pool(db: AsyncSession, *, user_id: str, lesson_id: str) -> list[dict]:
    """Every word this learner has learned, in the lesson's own language.

    No special case brings the current lesson's words in: they arrive here
    the moment the existing rules count them as learned (completing the
    lesson links them via mark_lesson_words_learned), which is exactly the
    behaviour asked for — one definition of "learned", not two.
    """
    cards = await get_my_words(db, user_id)
    lesson = await db.get(CourseLesson, lesson_id)
    language_id = await derive_language_id(db, lesson.courseId) if lesson else None
    if language_id:
        # A card with no language predates the language column; keep it
        # rather than silently shrinking an existing learner's pool.
        cards = [c for c in cards if c.get("languageId") in (language_id, None)]
    cards.sort(key=lambda c: c["wordId"])
    return _dedupe(cards)


_PROVIDERS: dict[str, Callable[..., Awaitable[list[dict]]]] = {
    "lesson": _lesson_pool,
    "learned": _learned_pool,
}


def register_source(name: str, provider: Callable[..., Awaitable[list[dict]]]) -> None:
    """Adds a source at import time.

    The extension point for sources this module must not depend on: a
    provider that needs to know what another exercise is doing (or, later,
    what an adaptive algorithm decided) lives with that code and registers
    itself here, so this module keeps knowing nothing about exercises and
    no import cycle appears. Every generator keeps drawing through
    [build_word_pool] and is unaffected.
    """
    _PROVIDERS[name] = provider


def source_exists(name: str) -> bool:
    return name in _PROVIDERS


async def build_word_pool(db: AsyncSession, *, source: str, user_id: str, lesson_id: str) -> list[dict]:
    """The pool for one source, or an empty list for an unknown source — a
    generator asking for a source that no longer exists should render
    nothing, not raise."""
    provider = _PROVIDERS.get(source)
    if provider is None:
        return []
    return await provider(db, user_id=user_id, lesson_id=lesson_id)


async def word_pool_size(db: AsyncSession, *, source: str, user_id: str, lesson_id: str) -> int:
    """How many distinct questions this source could support at most — the
    cap the teacher's requested count is measured against."""
    return len(await build_word_pool(db, source=source, user_id=user_id, lesson_id=lesson_id))

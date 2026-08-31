"""Word cards (§ word cards, 2026-08-31) — VocabularyItem already IS the
one-per-word card (unique id, stored once, referenced by lessons/exercises/
users through that id rather than copied); this module is everything built
on top of it: category get-or-create, universal lookup by wordId (single or
batch — one query, not N+1), marking a lesson's words learned on completion,
and grouping a user's learned words by category for "Мои слова".

Nothing here duplicates a word card anywhere — a category is a small shared
row words point at, and a user's "learned" state is a bare (userId, wordId)
link, never a copy of the word itself.
"""

import random

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.category import Category
from app.models.user_word_progress import UserWordProgress
from app.models.vocabulary_item import VocabularyItem
from app.services.content import normalize_word


def _word_card_dto(item: VocabularyItem, category: Category | None = None) -> dict:
    """The universal shape any future feature gets back for a wordId —
    everything a card currently has, plus enough to trace where it's used
    (lessonId) without a second lookup. Adding a new card field later means
    adding one line here, not touching every caller."""
    return {
        "wordId": item.id,
        "word": item.german,
        "translation": item.translation,
        "pronunciation": item.pronunciation,
        "audioUrl": item.audioUrl,
        "imageUrl": item.imageUrl,
        "categoryId": item.categoryId,
        "categoryName": category.name if category else None,
        "languageId": item.languageId,
        "lessonId": item.lessonId,
        "courseId": item.courseId,
    }


async def get_word(db: AsyncSession, word_id: str) -> dict | None:
    item = await db.get(VocabularyItem, word_id)
    if not item:
        return None
    category = await db.get(Category, item.categoryId) if item.categoryId else None
    return _word_card_dto(item, category)


async def get_words(db: AsyncSession, word_ids: list[str]) -> list[dict]:
    """Batch lookup — one query for the cards, one for their categories,
    regardless of how many ids are asked for (§ performance, no N+1)."""
    if not word_ids:
        return []
    items = (await db.execute(select(VocabularyItem).where(VocabularyItem.id.in_(word_ids)))).scalars().all()
    category_ids = {i.categoryId for i in items if i.categoryId}
    categories = {}
    if category_ids:
        rows = (await db.execute(select(Category).where(Category.id.in_(category_ids)))).scalars().all()
        categories = {c.id: c for c in rows}
    by_id = {i.id: _word_card_dto(i, categories.get(i.categoryId)) for i in items}
    # Preserve the caller's requested order; silently skip any id that
    # doesn't exist (a stale/bad id shouldn't fail the whole batch).
    return [by_id[wid] for wid in word_ids if wid in by_id]


async def get_or_create_category(db: AsyncSession, name: str) -> Category:
    """Reuses an existing category by name (case/punctuation-insensitive,
    same normalize_word idea VocabularyItem.germanKey already uses for
    words) instead of ever creating a near-duplicate. Race-safe: two
    concurrent requests creating "Еда" for the first time both attempt an
    insert, the DB's unique constraint on nameKey rejects the loser, which
    re-queries and returns the winner's row instead of erroring — the exact
    same pattern add_vocabulary_word already uses for word-clash races."""
    name = name.strip()
    key = normalize_word(name)
    existing = (await db.execute(select(Category).where(Category.nameKey == key))).scalar_one_or_none()
    if existing:
        return existing

    category = Category(name=name, nameKey=key)
    db.add(category)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        existing = (await db.execute(select(Category).where(Category.nameKey == key))).scalar_one_or_none()
        if existing:
            return existing
        raise
    await db.refresh(category)
    return category


async def list_categories(db: AsyncSession) -> list[dict]:
    """For a "pick an existing category" list in the word-authoring UI."""
    rows = (await db.execute(select(Category).order_by(Category.name))).scalars().all()
    return [{"categoryId": c.id, "name": c.name} for c in rows]


async def mark_lesson_words_learned(db: AsyncSession, user_id: str, lesson_id: str) -> int:
    """Links every word in this lesson to the user as learned (§6: a lesson
    fully completed = its words are learned) — idempotent, so re-completing
    the same lesson links nothing twice. Returns how many NEW links were
    created (0 on a repeat completion or a lesson with no vocabulary)."""
    word_ids = (await db.execute(select(VocabularyItem.id).where(VocabularyItem.lessonId == lesson_id))).scalars().all()
    if not word_ids:
        return 0

    already = set(
        (
            await db.execute(
                select(UserWordProgress.wordId).where(UserWordProgress.userId == user_id, UserWordProgress.wordId.in_(word_ids))
            )
        )
        .scalars()
        .all()
    )
    missing = [wid for wid in word_ids if wid not in already]
    if not missing:
        return 0

    for wid in missing:
        db.add(UserWordProgress(userId=user_id, wordId=wid))
    try:
        await db.commit()
    except IntegrityError:
        # Two concurrent completions of the same lesson (e.g. a duplicate
        # request) racing on the same (userId, wordId) unique pair - the
        # loser's insert is rejected, which is exactly the desired outcome
        # (no duplicate link), not an error to surface.
        await db.rollback()
        return 0
    return len(missing)


async def get_my_words(db: AsyncSession, user_id: str) -> list[dict]:
    """"Мои слова" (§7) - every word this user has learned, each with its
    full card, grouped by category name (words with no category come back
    under `categoryName: None`, which the frontend buckets as "Без
    категории"). One query for the links, one for the cards, one for the
    categories - never one query per word."""
    word_ids = (await db.execute(select(UserWordProgress.wordId).where(UserWordProgress.userId == user_id))).scalars().all()
    return await get_words(db, list(word_ids))


async def get_random_learned_words(db: AsyncSession, user_id: str, count: int, language_id: str | None = None, exclude_text: str | None = None) -> list[dict]:
    """Random wrong-answer candidates for an auto-generated exercise (§
    auto blank, 2026-08-31) — up to `count` of the user's learned words,
    same language, deduplicated by normalized text (two cards that render
    as the same word never both become options), never including
    `exclude_text` (the correct answer). Returns FEWER than `count` if the
    user hasn't learned enough distinct words yet — never pads with
    duplicates, never errors; the caller decides whether that's still
    enough to show a valid exercise."""
    all_words = await get_my_words(db, user_id)
    exclude_key = normalize_word(exclude_text) if exclude_text else None
    seen: set[str] = set()
    candidates = []
    for w in all_words:
        if language_id and w["languageId"] not in (language_id, None):
            continue
        key = normalize_word(w["word"])
        if exclude_key and key == exclude_key:
            continue
        if key in seen:
            continue
        seen.add(key)
        candidates.append(w)
    random.shuffle(candidates)
    return candidates[:count]

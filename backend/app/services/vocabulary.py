"""Word cards (§ word cards, 2026-08-31) — VocabularyItem already IS the
one-per-word card (unique id, stored once, referenced by lessons/exercises/
users through that id rather than copied); this module is everything built
on top of it: category get-or-create, universal lookup by wordId (single or
batch — one query, not N+1), marking a lesson's words learned on completion,
and grouping a user's learned words by category for "Мои слова".

Nothing here duplicates a word card anywhere — a category is a small shared
row words point at, and a user's "learned" state is a bare (userId, wordId)
link, never a copy of the word itself.

§ shared dictionary, 2026-09-14: this module also now owns the
course/lesson-agnostic half of the word — browsing/searching every word
that exists (`list_dictionary_words`, for the admin "Словарь" screen) and
resolving how many places a word is actually used before letting it be
deleted outright (`get_word_usage`/`delete_word_globally`). The lesson-
scoped authoring endpoints (add/edit/delete a word FROM one lesson) stay in
services/courses.py exactly as they were; this is only the cross-lesson view
on top of the same VocabularyItem rows.
"""

import random

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.category import Category
from app.models.lesson_vocabulary_link import LessonVocabularyLink
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


async def get_linked_items_by_lesson(db: AsyncSession, lesson_ids: list[str]) -> dict[str, list[VocabularyItem]]:
    """lessonId -> ordered list of VocabularyItem rows reused into it via
    LessonVocabularyLink (§ shared dictionary, 2026-09-14) — words the
    lesson teaches without owning (its native words are still the plain
    `WHERE VocabularyItem.lessonId == X` query every caller already had).
    Empty for any lesson that's never had a word attached this way — every
    lesson that existed before this table did — so a caller that just adds
    this on top of its existing native-word query behaves exactly as
    before for them."""
    if not lesson_ids:
        return {}
    links = (
        await db.execute(
            select(LessonVocabularyLink.lessonId, LessonVocabularyLink.wordId)
            .where(LessonVocabularyLink.lessonId.in_(lesson_ids))
            .order_by(LessonVocabularyLink.position)
        )
    ).all()
    if not links:
        return {}
    word_ids = [wid for _, wid in links]
    items = (await db.execute(select(VocabularyItem).where(VocabularyItem.id.in_(word_ids)))).scalars().all()
    by_id = {i.id: i for i in items}
    by_lesson: dict[str, list[VocabularyItem]] = {}
    for lid, wid in links:
        item = by_id.get(wid)
        if item:
            by_lesson.setdefault(lid, []).append(item)
    return by_lesson


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
    native_ids = (await db.execute(select(VocabularyItem.id).where(VocabularyItem.lessonId == lesson_id))).scalars().all()
    linked_ids = [w.id for w in (await get_linked_items_by_lesson(db, [lesson_id])).get(lesson_id, [])]
    word_ids = list(native_ids) + linked_ids
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


# ---------------------------------------------------------------------------
# Admin "Словарь" — every word, regardless of which lesson it lives in
# (§ shared dictionary, 2026-09-14). Read/delete only; creating and editing
# a word both stay on the existing lesson-scoped endpoints in
# services/courses.py — the dictionary screen just calls those with
# whichever course/lesson the word already reports as its own.
# ---------------------------------------------------------------------------


async def list_dictionary_words(
    db: AsyncSession, *, query: str | None = None, language_id: str | None = None, category_id: str | None = None, limit: int = 50, offset: int = 0
) -> dict:
    """The admin "Словарь" screen's one and only data source. No new
    storage: a plain filtered/paginated read over the same VocabularyItem
    rows every lesson editor already writes — nothing here can create a
    word, so it can never diverge from what the lesson editors see."""
    filters = []
    if query and query.strip():
        q = f"%{query.strip()}%"
        filters.append(or_(VocabularyItem.german.ilike(q), VocabularyItem.translation.ilike(q)))
    if language_id:
        filters.append(VocabularyItem.languageId == language_id)
    if category_id:
        filters.append(VocabularyItem.categoryId == category_id)

    count_query = select(func.count()).select_from(VocabularyItem)
    list_query = select(VocabularyItem).order_by(VocabularyItem.german)
    for f in filters:
        count_query = count_query.where(f)
        list_query = list_query.where(f)

    total = await db.scalar(count_query)
    items = (await db.execute(list_query.limit(limit).offset(offset))).scalars().all()

    category_ids = {i.categoryId for i in items if i.categoryId}
    categories: dict[str, Category] = {}
    if category_ids:
        rows = (await db.execute(select(Category).where(Category.id.in_(category_ids)))).scalars().all()
        categories = {c.id: c for c in rows}

    # How many OTHER lessons each of these words is reused into, for a
    # small "used in N lessons" badge — one extra grouped query for the
    # whole page, not one per word.
    word_ids = [i.id for i in items]
    link_counts: dict[str, int] = {}
    if word_ids:
        rows = (
            await db.execute(
                select(LessonVocabularyLink.wordId, func.count())
                .where(LessonVocabularyLink.wordId.in_(word_ids))
                .group_by(LessonVocabularyLink.wordId)
            )
        ).all()
        link_counts = dict(rows)

    words = []
    for item in items:
        dto = _word_card_dto(item, categories.get(item.categoryId))
        dto["usedInLessonsCount"] = 1 + link_counts.get(item.id, 0)  # native lesson + every link
        words.append(dto)

    return {"words": words, "total": total or 0}


async def get_word_usage(db: AsyncSession, word_id: str) -> dict | None:
    """Every place a word is actually placed/known (§ shared dictionary,
    2026-09-14) — its native lesson, every lesson it's been reused into via
    LessonVocabularyLink, and how many learners already have it in "Мои
    слова". Computed before a global delete so the admin sees exactly what
    deleting it would take with it, instead of a blind confirm dialog."""
    item = await db.get(VocabularyItem, word_id)
    if not item:
        return None
    links = (
        await db.execute(select(LessonVocabularyLink.lessonId, LessonVocabularyLink.courseId).where(LessonVocabularyLink.wordId == word_id))
    ).all()
    learner_count = await db.scalar(select(func.count()).select_from(UserWordProgress).where(UserWordProgress.wordId == word_id))
    return {
        "wordId": word_id,
        "nativeLessonId": item.lessonId,
        "nativeCourseId": item.courseId,
        "linkedLessons": [{"lessonId": lid, "courseId": cid} for lid, cid in links],
        "learnerCount": learner_count or 0,
    }


async def delete_word_globally(db: AsyncSession, word_id: str, force: bool = False) -> dict:
    """Removes a word from the dictionary entirely (§ shared dictionary,
    2026-09-14) — the ONE place a word can be deleted regardless of where
    it's used, unlike the deliberately conservative lesson-scoped
    delete_vocabulary_word in services/courses.py (which refuses to delete
    a word that's reused elsewhere, treating that request as "remove from
    THIS lesson" instead — see that function's own docstring).

    Without `force`, refuses and returns the word's usage if it's linked
    into any other lesson or already learned by someone, so the caller can
    show a real confirmation ("используется в 3 уроках, изучено 12
    учениками — удалить всё равно?") instead of silently breaking those.
    `force=True` deletes regardless — ON DELETE CASCADE on
    LessonVocabularyLink.wordId and UserWordProgress.wordId cleans up both
    automatically, so no separate cleanup step is needed here."""
    usage = await get_word_usage(db, word_id)
    if usage is None:
        return {"ok": False, "reason": "not_found"}
    in_use = bool(usage["linkedLessons"]) or usage["learnerCount"] > 0
    if in_use and not force:
        return {"ok": False, "reason": "in_use", "usage": usage}

    item = await db.get(VocabularyItem, word_id)
    await db.delete(item)
    await db.commit()
    return {"ok": True}

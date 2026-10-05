"""Shared phrase base (§ phrase base, 2026-10-03) — the phrase counterpart
of the word dictionary (services/vocabulary.py). Phrases belong to a
language, not to a lesson; lessons and the AI lesson generator reference
them by id."""

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.language import Language
from app.models.phrase import Phrase, PhraseTranslation
from app.models.topic import Topic
from app.services.content_locale import SUPPORTED_CONTENT_LOCALES
from app.services.taxonomy import find_topic_by_name


async def _translations_for(db: AsyncSession, phrase_ids: list[str]) -> dict[str, dict[str, str]]:
    if not phrase_ids:
        return {}
    rows = (await db.execute(select(PhraseTranslation).where(PhraseTranslation.phraseId.in_(phrase_ids)))).scalars().all()
    out: dict[str, dict[str, str]] = {}
    for r in rows:
        out.setdefault(r.phraseId, {})[r.locale] = r.translation
    return out


def phrase_dto(p: Phrase, translations: dict[str, str] | None = None, topic_name: str | None = None) -> dict:
    return {
        "id": p.id,
        "languageId": p.languageId,
        "text": p.text,
        "translation": p.translation,
        "translations": translations or {},
        "topicId": p.topicId,
        "topicName": topic_name,
    }


async def _dtos(db: AsyncSession, phrases: list[Phrase]) -> list[dict]:
    translations = await _translations_for(db, [p.id for p in phrases])
    topic_ids = {p.topicId for p in phrases if p.topicId}
    topics: dict[str, str] = {}
    if topic_ids:
        topics = {t.id: t.name for t in (await db.execute(select(Topic).where(Topic.id.in_(topic_ids)))).scalars().all()}
    return [phrase_dto(p, translations.get(p.id), topics.get(p.topicId) if p.topicId else None) for p in phrases]


async def used_phrase_ids(db: AsyncSession) -> set[str]:
    """Phrases placed in at least one lesson's «Фразы» step."""
    from app.models.lesson_node import LessonNode

    rows = (await db.execute(select(LessonNode.phraseIds).where(LessonNode.type == "phrases"))).scalars().all()
    return {pid for ids in rows for pid in (ids or []) if isinstance(pid, str)}


async def list_phrases(
    db: AsyncSession, *, language_id: str | None = None, query: str | None = None, limit: int = 50, offset: int = 0, used: bool | None = None
) -> dict:
    """`used`: True = only phrases placed in some lesson, False = only the
    rest, None = all; usedCount/unusedCount ignore `used` (for the chips)."""
    filters = []
    if language_id:
        filters.append(Phrase.languageId == language_id)
    if query and query.strip():
        q = f"%{query.strip()}%"
        filters.append(or_(Phrase.text.ilike(q), Phrase.translation.ilike(q)))
    count_query = select(func.count()).select_from(Phrase)
    for f in filters:
        count_query = count_query.where(f)
    in_lessons = await used_phrase_ids(db)
    used_filter = Phrase.id.in_(in_lessons) if in_lessons else Phrase.id.is_(None)
    all_count = await db.scalar(count_query) or 0
    used_count = await db.scalar(count_query.where(used_filter)) or 0
    if used is True:
        filters.append(used_filter)
    elif used is False:
        filters.append(~used_filter)
    list_query = select(Phrase).order_by(Phrase.text)
    for f in filters:
        list_query = list_query.where(f)
    total = used_count if used is True else (all_count - used_count if used is False else all_count)
    phrases = (await db.execute(list_query.limit(limit).offset(offset))).scalars().all()
    return {"phrases": await _dtos(db, list(phrases)), "total": total, "usedCount": used_count, "unusedCount": all_count - used_count}


async def get_phrases_by_ids(db: AsyncSession, ids: list[str]) -> list[Phrase]:
    if not ids:
        return []
    return list((await db.execute(select(Phrase).where(Phrase.id.in_(ids)))).scalars().all())


async def _set_translation(db: AsyncSession, phrase_id: str, locale: str, translation: str | None) -> None:
    existing = (
        await db.execute(select(PhraseTranslation).where(PhraseTranslation.phraseId == phrase_id, PhraseTranslation.locale == locale))
    ).scalar_one_or_none()
    text = (translation or "").strip()
    if not text:
        if existing:
            await db.delete(existing)
    elif existing:
        existing.translation = text
    else:
        db.add(PhraseTranslation(phraseId=phrase_id, locale=locale, translation=text))


async def topic_id_for_name(db: AsyncSession, language_id: str, topic_name: str | None) -> str | None:
    """Existing Topic of that name (case-insensitive) or a new one; flushes,
    never commits. Shared with the AI lesson generator."""
    if not topic_name or not topic_name.strip():
        return None
    topic = await find_topic_by_name(db, language_id, topic_name)
    if topic is None:
        topic = Topic(languageId=language_id, name=topic_name.strip())
        db.add(topic)
        await db.flush()
    return topic.id


async def create_phrase(db: AsyncSession, *, language_id: str, text: str, translation: str, translations: dict[str, str] | None = None, topic_id: str | None = None) -> dict:
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    text = text.strip()
    if not text:
        raise ApiError(400, "Фраза не может быть пустой")
    phrase = Phrase(languageId=language_id, text=text, translation=translation.strip(), topicId=topic_id)
    db.add(phrase)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, "Такая фраза уже есть в базе")
    for locale, value in (translations or {}).items():
        if locale in SUPPORTED_CONTENT_LOCALES:
            await _set_translation(db, phrase.id, locale, value)
    await db.commit()
    await db.refresh(phrase)
    return (await _dtos(db, [phrase]))[0]


async def update_phrase(db: AsyncSession, phrase_id: str, changes: dict) -> dict | None:
    phrase = await db.get(Phrase, phrase_id)
    if not phrase:
        return None
    if "text" in changes and changes["text"] is not None:
        if not changes["text"].strip():
            raise ApiError(400, "Фраза не может быть пустой")
        phrase.text = changes["text"].strip()
    if "translation" in changes and changes["translation"] is not None:
        phrase.translation = changes["translation"].strip()
    if "topicId" in changes:
        phrase.topicId = changes["topicId"] or None
    for locale, value in (changes.get("translations") or {}).items():
        if locale in SUPPORTED_CONTENT_LOCALES:
            await _set_translation(db, phrase.id, locale, value)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, "Такая фраза уже есть в базе")
    await db.refresh(phrase)
    return (await _dtos(db, [phrase]))[0]


async def delete_phrase(db: AsyncSession, phrase_id: str) -> bool:
    phrase = await db.get(Phrase, phrase_id)
    if not phrase:
        return False
    await db.delete(phrase)
    await db.commit()
    return True


async def import_phrases(db: AsyncSession, language_id: str, items: list[dict]) -> dict:
    """Bulk add: [{text, translation, translation_tg?, topic?}]. A phrase
    already in the base (same text, case-insensitive) is skipped, never
    duplicated or overwritten."""
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    existing = {
        t.lower()
        for t in (await db.execute(select(Phrase.text).where(Phrase.languageId == language_id))).scalars().all()
    }
    added = skipped = 0
    for item in items:
        text = (item.get("text") or "").strip()
        if not text or text.lower() in existing:
            skipped += 1
            continue
        phrase = Phrase(
            languageId=language_id,
            text=text,
            translation=(item.get("translation") or "").strip(),
            topicId=await topic_id_for_name(db, language_id, item.get("topic")),
        )
        db.add(phrase)
        await db.flush()
        if item.get("translation_tg"):
            await _set_translation(db, phrase.id, "tg", item["translation_tg"])
        existing.add(text.lower())
        added += 1
    await db.commit()
    return {"added": added, "skipped": skipped}

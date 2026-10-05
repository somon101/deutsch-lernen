"""Topic management for the language workspace «Темы» tab and the public
API. Works on the very same Topic rows the lesson's material picker uses
(services/taxonomy.py create_topic/delete_topic), so a topic created here
is immediately selectable when building a lesson, and vice versa."""

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.language import Language
from app.models.material import Material
from app.models.phrase import Phrase
from app.models.question import Question
from app.models.topic import Topic


def topic_dto(t: Topic, usage: int = 0) -> dict:
    return {"id": t.id, "languageId": t.languageId, "name": t.name, "usage": usage}


async def _usage(db: AsyncSession, topic_ids: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    if not topic_ids:
        return out
    for model in (Material, Question, Phrase):
        rows = (await db.execute(select(model.topicId, func.count()).where(model.topicId.in_(topic_ids)).group_by(model.topicId))).all()
        for topic_id, n in rows:
            out[topic_id] = out.get(topic_id, 0) + n
    return out


async def list_topics_page(db: AsyncSession, *, language_id: str | None, query: str | None, limit: int, offset: int) -> dict:
    filters = []
    if language_id:
        filters.append(Topic.languageId == language_id)
    if query and query.strip():
        filters.append(Topic.name.ilike(f"%{query.strip()}%"))
    count_q = select(func.count()).select_from(Topic)
    list_q = select(Topic).order_by(Topic.name)
    for f in filters:
        count_q, list_q = count_q.where(f), list_q.where(f)
    total = await db.scalar(count_q)
    topics = (await db.execute(list_q.limit(limit).offset(offset))).scalars().all()
    usage = await _usage(db, [t.id for t in topics])
    return {"topics": [topic_dto(t, usage.get(t.id, 0)) for t in topics], "total": total or 0}


async def _exists(db: AsyncSession, language_id: str, name: str, exclude_id: str | None = None) -> bool:
    q = select(Topic.id).where(Topic.languageId == language_id, func.lower(Topic.name) == name.strip().lower())
    if exclude_id:
        q = q.where(Topic.id != exclude_id)
    return await db.scalar(q.limit(1)) is not None


async def create_topic(db: AsyncSession, language_id: str, name: str) -> dict:
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    if await _exists(db, language_id, name):
        raise ApiError(409, "Такая тема уже есть")
    topic = Topic(languageId=language_id, name=name.strip())
    db.add(topic)
    await db.commit()
    await db.refresh(topic)
    return topic_dto(topic)


async def rename_topic(db: AsyncSession, topic_id: str, name: str) -> dict | None:
    topic = await db.get(Topic, topic_id)
    if not topic:
        return None
    if await _exists(db, topic.languageId, name, exclude_id=topic.id):
        raise ApiError(409, "Такая тема уже есть")
    topic.name = name.strip()
    await db.commit()
    await db.refresh(topic)
    return topic_dto(topic, (await _usage(db, [topic.id])).get(topic.id, 0))


async def delete_topic(db: AsyncSession, topic_id: str) -> bool:
    """Content tagged with the topic stays; only the tag goes (FK SET NULL)."""
    topic = await db.get(Topic, topic_id)
    if not topic:
        return False
    await db.delete(topic)
    await db.commit()
    return True


async def import_topics(db: AsyncSession, language_id: str, names: list[str]) -> dict:
    """Adds only topics not already in this language (or repeated earlier
    in the same file); existing ones are left untouched."""
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    existing = {n.lower() for n in (await db.execute(select(Topic.name).where(Topic.languageId == language_id))).scalars().all()}
    added = skipped = 0
    for raw in names:
        name = raw.strip()
        if not name or name.lower() in existing:
            skipped += 1
            continue
        db.add(Topic(languageId=language_id, name=name))
        existing.add(name.lower())
        added += 1
    await db.commit()
    return {"added": added, "skipped": skipped}

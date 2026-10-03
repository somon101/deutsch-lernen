"""Rule base: one-sentence rules per studied language, managed like the
phrase base (services/phrases.py). A rule with the same text (ignoring
case) in the same language is never stored twice."""

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.language import Language
from app.models.rule import Rule


def rule_dto(r: Rule) -> dict:
    return {"id": r.id, "languageId": r.languageId, "text": r.text}


async def list_rules(db: AsyncSession, *, language_id: str | None = None, query: str | None = None, limit: int = 50, offset: int = 0) -> dict:
    filters = []
    if language_id:
        filters.append(Rule.languageId == language_id)
    if query and query.strip():
        filters.append(Rule.text.ilike(f"%{query.strip()}%"))
    count_query = select(func.count()).select_from(Rule)
    list_query = select(Rule).order_by(Rule.text)
    for f in filters:
        count_query = count_query.where(f)
        list_query = list_query.where(f)
    total = await db.scalar(count_query)
    rules = (await db.execute(list_query.limit(limit).offset(offset))).scalars().all()
    return {"rules": [rule_dto(r) for r in rules], "total": total or 0}


async def _exists(db: AsyncSession, language_id: str, text: str, exclude_id: str | None = None) -> bool:
    q = select(Rule.id).where(Rule.languageId == language_id, func.lower(Rule.text) == text.lower())
    if exclude_id:
        q = q.where(Rule.id != exclude_id)
    return await db.scalar(q.limit(1)) is not None


async def create_rule(db: AsyncSession, *, language_id: str, text: str) -> dict:
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    if await _exists(db, language_id, text):
        raise ApiError(409, "Такое правило уже есть")
    rule = Rule(languageId=language_id, text=text)
    db.add(rule)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, "Такое правило уже есть")
    await db.refresh(rule)
    return rule_dto(rule)


async def update_rule(db: AsyncSession, rule_id: str, text: str) -> dict | None:
    rule = await db.get(Rule, rule_id)
    if not rule:
        return None
    if await _exists(db, rule.languageId, text, exclude_id=rule.id):
        raise ApiError(409, "Такое правило уже есть")
    rule.text = text
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise ApiError(409, "Такое правило уже есть")
    await db.refresh(rule)
    return rule_dto(rule)


async def delete_rule(db: AsyncSession, rule_id: str) -> bool:
    rule = await db.get(Rule, rule_id)
    if not rule:
        return False
    await db.delete(rule)
    await db.commit()
    return True


async def import_rules(db: AsyncSession, language_id: str, texts: list[str]) -> dict:
    """Adds only rules not already in the base for this language (and not
    repeated earlier in the same file); existing ones are left untouched."""
    if not await db.get(Language, language_id):
        raise ApiError(404, "Язык не найден")
    existing = {t.lower() for t in (await db.execute(select(Rule.text).where(Rule.languageId == language_id))).scalars().all()}
    added = skipped = 0
    for text in texts:
        if not text or text.lower() in existing:
            skipped += 1
            continue
        db.add(Rule(languageId=language_id, text=text))
        existing.add(text.lower())
        added += 1
    await db.commit()
    return {"added": added, "skipped": skipped}

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.errors import ApiError
from app.models.language import Language
from app.models.level import Level
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.models.topic import Topic
from app.services.courses import _block_question_to_row
from app.services.material import to_question_dto
from app.services.similarity import compare_similarity

DUPLICATE_WARNING_THRESHOLD = 60

# ---------------------------------------------------------------------------
# Language / Level / Topic
# ---------------------------------------------------------------------------


async def list_languages(db: AsyncSession) -> list[Language]:
    return (await db.execute(select(Language).order_by(Language.name))).scalars().all()


async def list_levels(db: AsyncSession, language_id: str | None) -> list[Level]:
    query = select(Level).order_by(Level.position)
    if language_id:
        query = query.where(Level.languageId == language_id)
    return (await db.execute(query)).scalars().all()


async def create_level(db: AsyncSession, body) -> Level:
    if not await db.get(Language, body.languageId):
        raise ApiError(404, "Язык не найден")
    existing = (
        await db.execute(select(Level).where(Level.languageId == body.languageId, Level.code == body.code))
    ).scalar_one_or_none()
    if existing:
        raise ApiError(409, f"Уровень «{body.code}» уже существует для этого языка")
    level = Level(languageId=body.languageId, code=body.code, name=body.name, position=body.position)
    db.add(level)
    await db.commit()
    await db.refresh(level)
    return level


async def list_topics(db: AsyncSession, language_id: str | None) -> list[Topic]:
    query = select(Topic).order_by(Topic.name)
    if language_id:
        query = query.where(Topic.languageId == language_id)
    return (await db.execute(query)).scalars().all()


async def find_topic_by_name(db: AsyncSession, language_id: str, name: str) -> Topic | None:
    """Used by the Material editor to offer "use the existing Topic" instead
    of silently creating a duplicate with the same name (§32)."""
    return (
        await db.execute(select(Topic).where(Topic.languageId == language_id, Topic.name.ilike(name.strip())))
    ).scalar_one_or_none()


async def create_topic(db: AsyncSession, body) -> tuple[Topic, bool]:
    """Returns (topic, existing) — `existing` is True when an already-there
    Topic with the same name was returned instead of creating a duplicate
    (§32), which only happens when `body.force` is False."""
    if not await db.get(Language, body.languageId):
        raise ApiError(404, "Язык не найден")
    if not body.force:
        found = await find_topic_by_name(db, body.languageId, body.name)
        if found:
            return found, True
    topic = Topic(languageId=body.languageId, name=body.name)
    db.add(topic)
    await db.commit()
    await db.refresh(topic)
    return topic, False


async def delete_topic(db: AsyncSession, topic_id: str) -> bool:
    """Materials/Questions tagged with this Topic keep existing (their
    topicId is set NULL by the FK, per the model's ondelete="SET NULL") —
    deleting a Topic never deletes content, only the tag."""
    topic = await db.get(Topic, topic_id)
    if not topic:
        return False
    await db.delete(topic)
    await db.commit()
    return True


# ---------------------------------------------------------------------------
# Material / MaterialBlock
# ---------------------------------------------------------------------------


async def list_materials(db: AsyncSession, lesson_id: str) -> list[Material]:
    return (await db.execute(select(Material).where(Material.lessonId == lesson_id).order_by(Material.position))).scalars().all()


async def create_material(db: AsyncSession, body) -> Material:
    existing = (await db.execute(select(Material).where(Material.lessonId == body.lessonId))).scalars().all()
    material = Material(
        courseId=body.courseId,
        lessonId=body.lessonId,
        materialType=body.materialType,
        title=body.title,
        topicId=body.topicId,
        position=len(existing),
    )
    db.add(material)
    await db.commit()
    await db.refresh(material)
    return material


async def update_material(db: AsyncSession, material_id: str, body) -> Material | None:
    material = await db.get(Material, material_id)
    if not material:
        return None
    if body.title is not None:
        material.title = body.title
    if "topicId" in body.model_fields_set:
        material.topicId = body.topicId
    await db.commit()
    await db.refresh(material)
    return material


async def delete_material(db: AsyncSession, material_id: str) -> bool:
    material = await db.get(Material, material_id)
    if not material:
        return False
    await db.delete(material)
    await db.commit()
    return True


async def list_material_blocks(db: AsyncSession, material_id: str) -> list[MaterialBlock]:
    return (
        await db.execute(select(MaterialBlock).where(MaterialBlock.materialId == material_id).order_by(MaterialBlock.position))
    ).scalars().all()


async def add_material_block(db: AsyncSession, material_id: str, body) -> MaterialBlock | None:
    if not await db.get(Material, material_id):
        return None
    existing = await list_material_blocks(db, material_id)
    block = MaterialBlock(materialId=material_id, title=body.title, content=body.content, position=len(existing))
    db.add(block)
    await db.commit()
    await db.refresh(block)
    return block


async def update_material_block(db: AsyncSession, block_id: str, body) -> MaterialBlock | None:
    block = await db.get(MaterialBlock, block_id)
    if not block:
        return None
    block.title = body.title
    block.content = body.content
    await db.commit()
    await db.refresh(block)
    return block


async def delete_material_block(db: AsyncSession, block_id: str) -> bool:
    block = await db.get(MaterialBlock, block_id)
    if not block:
        return False
    await db.delete(block)
    await db.commit()
    return True


async def reorder_material_blocks(db: AsyncSession, material_id: str, block_ids: list[str]) -> None:
    """Only `position` changes — `id` (and therefore every QuestionPlacement
    pointing at a block) is untouched, so reordering can never silently move
    a question to the wrong place (§8/§53)."""
    for index, block_id in enumerate(block_ids):
        block = await db.get(MaterialBlock, block_id)
        if block and block.materialId == material_id:
            block.position = index
    await db.commit()


# ---------------------------------------------------------------------------
# Reusable question pool
# ---------------------------------------------------------------------------


def _question_row_fields(question_input: dict) -> dict:
    row = _block_question_to_row(question_input)
    return {"kind": question_input["kind"], **row}


async def check_similarity(db: AsyncSession, draft: dict, topic_id: str | None, material_id: str | None) -> list[dict]:
    """Returns existing questions scoring >= DUPLICATE_WARNING_THRESHOLD,
    highest first — the caller decides what to do with the warning (§29/§30),
    this never blocks creation by itself."""
    row = _question_row_fields(draft)
    candidates = (await db.execute(select(Question))).scalars().all()
    scored = []
    for c in candidates:
        score = compare_similarity(
            {"prompt": row["prompt"], "correctAnswer": row["correctAnswer"], "kind": row["kind"], "topicId": topic_id, "materialId": material_id},
            {"prompt": c.prompt, "correctAnswer": c.correctAnswer, "kind": c.kind, "topicId": c.topicId, "materialId": None},
        )
        if score >= DUPLICATE_WARNING_THRESHOLD:
            scored.append({"question": c, "score": score})
    scored.sort(key=lambda item: -item["score"])
    return scored[:5]


async def create_question(db: AsyncSession, body) -> tuple[Question, list[dict]]:
    """Returns (question, similarWarnings) — the question is ALWAYS created
    (the teacher already decided via `force` or by acting on a prior
    /similarity-check call, per §30: the system warns, it never silently
    refuses)."""
    draft = body.question.model_dump()
    similar = [] if body.force else await check_similarity(db, draft, body.topicId, body.materialBlockId)

    row = _question_row_fields(draft)
    question = Question(kind=row["kind"], prompt=row["prompt"], options=row["options"], correctAnswer=row["correctAnswer"], data=row["data"], topicId=body.topicId)
    db.add(question)
    await db.flush()

    existing_count = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.questionId == question.id))).scalars().all()
    db.add(
        QuestionPlacement(
            questionId=question.id,
            materialBlockId=body.materialBlockId,
            lessonBlockId=body.lessonBlockId,
            legacyLessonId=body.legacyLessonId,
            legacySetName=body.legacySetName,
            position=len(existing_count),
        )
    )
    await db.commit()
    await db.refresh(question)
    return question, [{"question": to_question_dto(s["question"].kind, s["question"].prompt, s["question"].options, s["question"].correctAnswer, s["question"].data), "questionId": s["question"].id, "score": s["score"]} for s in similar]


async def reuse_question(db: AsyncSession, body) -> QuestionPlacement | None:
    """Attaches an EXISTING Question by reference — question_id stays the
    same, no copy (§16/§17)."""
    question = await db.get(Question, body.questionId)
    if not question:
        return None
    existing = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.questionId == question.id))).scalars().all()
    placement = QuestionPlacement(
        questionId=question.id,
        materialBlockId=body.materialBlockId,
        lessonBlockId=body.lessonBlockId,
        legacyLessonId=body.legacyLessonId,
        legacySetName=body.legacySetName,
        position=len(existing),
    )
    db.add(placement)
    await db.commit()
    await db.refresh(placement)
    return placement


async def search_questions(db: AsyncSession, query: str, topic_id: str | None, kind: str | None) -> list[Question]:
    """Manual search for an existing question to reuse (§31) — text
    substring plus optional topic/kind filters, distinct from the automatic
    similarity check."""
    q = query.strip()
    if len(q) < 2 and not topic_id and not kind:
        return []
    stmt = select(Question)
    if q:
        stmt = stmt.where(Question.prompt.ilike(f"%{q}%"))
    if topic_id:
        stmt = stmt.where(Question.topicId == topic_id)
    if kind:
        stmt = stmt.where(Question.kind == kind)
    return (await db.execute(stmt.limit(20))).scalars().all()


def question_dto(question: Question) -> dict:
    return {
        "id": question.id,
        "topicId": question.topicId,
        **to_question_dto(question.kind, question.prompt, question.options, question.correctAnswer, question.data),
    }


async def list_block_questions(
    db: AsyncSession, *, material_block_id: str | None = None, lesson_block_id: str | None = None
) -> list[tuple[QuestionPlacement, Question]]:
    """Every question actually attached to one block, in placement order —
    the admin editor uses this to show the teacher what's already linked
    here. Works for either a MaterialBlock (the "Материал" stage) or a
    LessonBlock (minitest/practice/review) — same reusable-pool mechanism,
    just a different placement column, exactly like create/reuse already
    accept either one."""
    condition = QuestionPlacement.materialBlockId == material_block_id if material_block_id else QuestionPlacement.lessonBlockId == lesson_block_id
    rows = (
        await db.execute(
            select(QuestionPlacement, Question).join(Question, Question.id == QuestionPlacement.questionId).where(condition).order_by(QuestionPlacement.position)
        )
    ).all()
    return [(p, q) for p, q in rows]


async def remove_placement(db: AsyncSession, placement_id: str) -> bool:
    """Unlinks a question from wherever this placement points it — the
    Question itself (and any other placement of it) is untouched, matching
    reuse-by-reference: removing one link never deletes the shared question."""
    placement = await db.get(QuestionPlacement, placement_id)
    if not placement:
        return False
    await db.delete(placement)
    await db.commit()
    return True


def pass_threshold() -> int:
    return settings.pass_threshold_percent

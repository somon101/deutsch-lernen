import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.errors import ApiError
from app.models.course import Course
from app.models.course_lesson import CourseLesson
from app.models.enums import CourseStatus
from app.models.language import Language
from app.models.lesson_block import LessonBlock
from app.models.lesson_question import LessonQuestion
from app.models.level import Level
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.material_block_translation import MaterialBlockTranslation
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.models.question_translation import QuestionTranslation
from app.models.topic import Topic
from app.services.content import LEGACY_COURSE_ID
from app.services.courses import STAGE_TITLES, _block_question_to_row
from app.services.material import to_question_dto
from app.services.similarity import compare_similarity

DUPLICATE_WARNING_THRESHOLD = 60

# ---------------------------------------------------------------------------
# Language / Level / Topic
# ---------------------------------------------------------------------------


async def list_languages(db: AsyncSession, with_courses_only: bool = False) -> list[Language]:
    """`with_courses_only` is what feeds the student-facing language picker
    (§ per-language overall progress, 2026-08-29): a Language row can exist
    with no course under it yet (just created via the builder), and such a
    language has nothing for a learner to ever have progress in, so it's
    filtered out there rather than shown as a dead-end choice."""
    if not with_courses_only:
        return (await db.execute(select(Language).order_by(Language.name))).scalars().all()
    stmt = (
        select(Language)
        .join(Level, Level.languageId == Language.id)
        .join(Course, Course.levelId == Level.id)
        .where(Course.status == CourseStatus.PUBLISHED)
        .distinct()
        .order_by(Language.name)
    )
    return (await db.execute(stmt)).scalars().all()


async def create_language(db: AsyncSession, body) -> tuple[Language, bool]:
    """Returns (language, existing) — same "reuse instead of duplicate"
    convention as create_topic below: a language with this name (case-
    insensitive) is returned as-is rather than creating a second row,
    unless the caller has already seen that and explicitly wants a new one
    anyway (force=True). Language.id has no DB-level default (unlike every
    other model here) — it's generated explicitly."""
    if not body.force:
        found = (
            await db.execute(select(Language).where(Language.name.ilike(body.name.strip())))
        ).scalar_one_or_none()
        if found:
            return found, True
    language = Language(id=str(uuid.uuid4()), name=body.name)
    db.add(language)
    await db.commit()
    await db.refresh(language)
    return language, False


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


async def set_material_block_translation(db: AsyncSession, block_id: str, locale: str, title: str, content: str) -> MaterialBlock | None:
    """Upsert (§ course content language, 2026-09-04), same pattern as
    services/courses.py's set_course_translation."""
    block = await db.get(MaterialBlock, block_id)
    if not block:
        return None
    existing = (
        await db.execute(
            select(MaterialBlockTranslation).where(MaterialBlockTranslation.materialBlockId == block_id, MaterialBlockTranslation.locale == locale)
        )
    ).scalar_one_or_none()
    if existing:
        existing.title = title
        existing.content = content
    else:
        db.add(MaterialBlockTranslation(materialBlockId=block_id, locale=locale, title=title, content=content))
    await db.commit()
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


async def _first_location_label(db: AsyncSession, question_id: str) -> str | None:
    """One human-readable "where this already lives" hint for a similarity
    match (§ course-builder redesign, "Похоже на существующее задание"
    dialog, 2026-09-01) — just the FIRST placement, not the full chain
    list_question_placements builds: this is a lightweight nudge in a
    result list capped at 5 matches, not the question's own detail view."""
    placement = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.questionId == question_id).limit(1))).scalars().first()
    if not placement:
        return None
    if placement.lessonBlockId:
        block = await db.get(LessonBlock, placement.lessonBlockId)
        if not block:
            return None
        title = await _resolve_lesson_title(db, block.courseId, block.lessonId)
        return f"Урок «{title}» → {STAGE_TITLES.get(block.stage, block.stage)}"
    if placement.materialBlockId:
        block = await db.get(MaterialBlock, placement.materialBlockId)
        material = await db.get(Material, block.materialId) if block else None
        if not material:
            return None
        title = await _resolve_lesson_title(db, material.courseId, material.lessonId)
        return f"Урок «{title}» → Материал"
    if placement.legacyLessonId:
        return f"Урок «{placement.legacyLessonId}» (устаревший курс)"
    return None


async def check_similarity(db: AsyncSession, draft: dict, topic_id: str | None, material_id: str | None) -> list[dict]:
    """Returns existing questions scoring >= DUPLICATE_WARNING_THRESHOLD,
    highest first — the caller decides what to do with the warning (§29/§30),
    this never blocks creation by itself.

    Skipped entirely for "auto_blank" (§ auto blank, 2026-08-31) — that
    kind has no author-provided prompt/correctAnswer at all (both are
    always ""), so compare_similarity's text/answer signals would compare
    "" against every other auto_blank question's "" and read as a near-
    perfect match regardless of what phrases either one actually holds —
    a guaranteed false positive, not a real duplicate signal."""
    if draft.get("kind") == "auto_blank":
        return []
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
    top = scored[:5]
    for item in top:
        item["location"] = await _first_location_label(db, item["question"].id)
    return top


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


async def set_question_translation(
    db: AsyncSession, question_id: str, locale: str, prompt: str | None, options: list[str] | None, correct_answer: str | None, data
) -> Question | None:
    """Upsert (§ course content language, 2026-09-04) — see
    QuestionTranslationInput's docstring for why every field is optional."""
    question = await db.get(Question, question_id)
    if not question:
        return None
    existing = (
        await db.execute(select(QuestionTranslation).where(QuestionTranslation.questionId == question_id, QuestionTranslation.locale == locale))
    ).scalar_one_or_none()
    if existing:
        existing.prompt = prompt
        existing.options = options
        existing.correctAnswer = correct_answer
        existing.data = data
    else:
        db.add(QuestionTranslation(questionId=question_id, locale=locale, prompt=prompt, options=options, correctAnswer=correct_answer, data=data))
    await db.commit()
    return question


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
) -> list[dict]:
    """Every question actually attached to one block, in placement order —
    the admin editor uses this to show the teacher what's already linked
    here. Works for either a MaterialBlock (the "Материал" stage) or a
    LessonBlock (minitest/practice/review) — same reusable-pool mechanism,
    just a different placement column, exactly like create/reuse already
    accept either one.

    Also resolves the Topic name (§ approved rule, 2026-08-27: the teacher
    must see the full chain, not just a bare id) and, for a LessonBlock
    listing only, the title of the MaterialBlock this placement is tagged
    as "verifying" (§4 of the same rule) — a quiz-stage placement can
    optionally point at a reading-content block it tests, purely as a
    label, independent of where it's actually shown.

    A material_block_id lookup additionally requires lessonBlockId IS NULL
    (§ course-builder redesign bugfix, 2026-09-01): materialBlockId alone
    isn't enough to mean "placed here" — a quiz-stage placement can carry
    the SAME materialBlockId purely as its "verifies" tag while its real
    home is that lessonBlockId. Without this, a quiz question tagged as
    verifying block X would show up as if actually attached to block X's
    own Материал editor, and its "Открепить" there would delete the row
    that's really the question's live placement in the quiz stage."""
    condition = (
        (QuestionPlacement.materialBlockId == material_block_id) & (QuestionPlacement.lessonBlockId.is_(None))
        if material_block_id
        else QuestionPlacement.lessonBlockId == lesson_block_id
    )
    rows = (
        await db.execute(
            select(QuestionPlacement, Question).join(Question, Question.id == QuestionPlacement.questionId).where(condition).order_by(QuestionPlacement.position)
        )
    ).all()

    topic_ids = {q.topicId for _, q in rows if q.topicId}
    topics_by_id = {t.id: t.name for t in (await db.execute(select(Topic).where(Topic.id.in_(topic_ids)))).scalars().all()} if topic_ids else {}

    verifies_titles: dict[str, str] = {}
    if lesson_block_id:
        verify_block_ids = {p.materialBlockId for p, _ in rows if p.materialBlockId}
        if verify_block_ids:
            verifies_titles = {
                b.id: b.title for b in (await db.execute(select(MaterialBlock).where(MaterialBlock.id.in_(verify_block_ids)))).scalars().all()
            }

    # How many places each question is actually placed (§ course-builder
    # redesign, "в пуле · N мест" chip, 2026-09-01) — a question attached
    # here once (the common case) reads as "только здесь"; 2+ means it's
    # genuinely reused elsewhere too. One row per DISTINCT questionId in
    # this listing, so a single grouped count query covers all of them.
    question_ids = {q.id for _, q in rows}
    placement_counts: dict[str, int] = {}
    if question_ids:
        count_rows = (
            await db.execute(
                select(QuestionPlacement.questionId, func.count())
                .where(QuestionPlacement.questionId.in_(question_ids))
                .group_by(QuestionPlacement.questionId)
            )
        ).all()
        placement_counts = dict(count_rows)

    return [
        {
            "placementId": p.id,
            "question": q,
            "topicName": topics_by_id.get(q.topicId),
            "verifiesBlockId": p.materialBlockId if lesson_block_id else None,
            "verifiesBlockTitle": verifies_titles.get(p.materialBlockId) if lesson_block_id and p.materialBlockId else None,
            "placementCount": placement_counts.get(q.id, 1),
        }
        for p, q in rows
    ]


async def _resolve_lesson_title(db: AsyncSession, course_id: str, lesson_id: str) -> str:
    if course_id == LEGACY_COURSE_ID:
        return lesson_id
    lesson = await db.get(CourseLesson, lesson_id)
    return lesson.title if lesson else lesson_id


async def list_verifying_questions(db: AsyncSession, material_block_id: str) -> list[dict]:
    """The reverse of list_block_questions's material_block_id case: every
    quiz-stage question tagged as "verifying" this reading block (§4 of the
    approved rule, 2026-08-27) — materialBlockId == material_block_id AND
    lessonBlockId IS NOT NULL, the exact complement of the lessonBlockId-IS-
    NULL filter added to list_block_questions in the same bugfix (§
    course-builder redesign, 2026-09-01). Powers the new "Проверяет этот
    блок" read-only section on a MaterialBlock's own card — every row here
    is a question that actually LIVES elsewhere (a minitest/practice/review
    LessonBlock), shown purely as a label with enough of the chain
    (stage/lesson/block) for the teacher to click through to it."""
    rows = (
        await db.execute(
            select(QuestionPlacement, Question)
            .join(Question, Question.id == QuestionPlacement.questionId)
            .where(QuestionPlacement.materialBlockId == material_block_id, QuestionPlacement.lessonBlockId.isnot(None))
            .order_by(QuestionPlacement.position)
        )
    ).all()

    result = []
    for p, q in rows:
        block = await db.get(LessonBlock, p.lessonBlockId)
        result.append(
            {
                "placementId": p.id,
                "question": q,
                "courseId": block.courseId if block else None,
                "lessonId": block.lessonId if block else None,
                "blockId": block.id if block else None,
                "stage": block.stage if block else None,
                "stageLabel": STAGE_TITLES.get(block.stage) if block else None,
                "lessonTitle": await _resolve_lesson_title(db, block.courseId, block.lessonId) if block else None,
                "blockTitle": block.title if block else None,
            }
        )
    return result


async def get_lesson_connections_map(db: AsyncSession, course_id: str, lesson_id: str) -> dict:
    """Read-only overview for the "Карта урока" screen (§8 of the
    course-builder redesign, 2026-09-01) — every reading (MaterialBlock)
    and every quiz-stage question in one lesson, with the "verifies" edges
    between them (§3's second connection type) surfaced together. Composes
    only relations that already exist (the same ones list_verifying_questions
    and list_block_questions already expose one block at a time) — no new
    stored data, no schema change, purely a bird's-eye read.

    Quiz questions are numbered continuously across minitest → practice →
    review, block order then item order within a block (legacy
    LessonQuestion rows first, then pool questions) — matching the running
    numbering the teacher already sees inside each block's own editor, and
    the spec's own diagram (§8) which numbers 1..N straight across stages."""
    materials = (
        await db.execute(
            select(Material).where(Material.courseId == course_id, Material.lessonId == lesson_id, Material.materialType == "text")
        )
    ).scalars().all()
    material_blocks: list[MaterialBlock] = []
    if materials:
        material_blocks = (
            await db.execute(
                select(MaterialBlock)
                .where(MaterialBlock.materialId.in_([m.id for m in materials]))
                .order_by(MaterialBlock.materialId, MaterialBlock.position)
            )
        ).scalars().all()

    materials_out = []
    for b in material_blocks:
        verifying = await list_verifying_questions(db, b.id)
        materials_out.append(
            {
                "id": b.id,
                "title": b.title,
                "verifiedBy": [
                    {
                        "questionId": r["question"].id,
                        "stage": r["stage"],
                        "stageLabel": r["stageLabel"],
                        "blockId": r["blockId"],
                        "blockTitle": r["blockTitle"],
                    }
                    for r in verifying
                ],
            }
        )

    lesson_blocks = (
        await db.execute(
            select(LessonBlock)
            .where(LessonBlock.courseId == course_id, LessonBlock.lessonId == lesson_id)
            .order_by(LessonBlock.stage, LessonBlock.position)
        )
    ).scalars().all()

    legacy_by_block: dict[str, list[LessonQuestion]] = {}
    if lesson_blocks:
        legacy_rows = (
            await db.execute(
                select(LessonQuestion)
                .where(LessonQuestion.lessonId == lesson_id, LessonQuestion.blockId.in_([b.id for b in lesson_blocks]))
                .order_by(LessonQuestion.blockId, LessonQuestion.position)
            )
        ).scalars().all()
        for q in legacy_rows:
            legacy_by_block.setdefault(q.blockId, []).append(q)

    counter = 0
    stages_out: dict[str, dict] = {}
    for block in lesson_blocks:
        pool_rows = await list_block_questions(db, lesson_block_id=block.id)
        items = []
        for q in legacy_by_block.get(block.id, []):
            counter += 1
            items.append(
                {
                    "id": q.id,
                    "number": counter,
                    "kind": q.kind,
                    "prompt": q.prompt,
                    "source": "legacy",
                    "verifiesBlockId": None,
                    "verifiesBlockTitle": None,
                }
            )
        for r in pool_rows:
            counter += 1
            items.append(
                {
                    "id": r["question"].id,
                    "number": counter,
                    "kind": r["question"].kind,
                    "prompt": r["question"].prompt,
                    "source": "pool",
                    "verifiesBlockId": r["verifiesBlockId"],
                    "verifiesBlockTitle": r["verifiesBlockTitle"],
                }
            )
        stage_entry = stages_out.setdefault(
            block.stage, {"stage": block.stage, "stageLabel": STAGE_TITLES.get(block.stage, block.stage), "blocks": []}
        )
        stage_entry["blocks"].append({"id": block.id, "title": block.title, "questions": items})

    return {"materials": materials_out, "stages": list(stages_out.values())}


async def get_course_connections_map(db: AsyncSession, course_id: str) -> dict:
    """Course-level rollup of get_lesson_connections_map (§8 of the
    course-builder redesign, 2026-09-01: "Карта доступна и на уровне
    курса — тогда строки это уроки, и видно, какой урок недособран, без
    захода внутрь") — one row per lesson with just the warning counts, so
    the teacher can spot an under-built lesson without opening it."""
    lessons = (
        await db.execute(select(CourseLesson).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position))
    ).scalars().all()

    rows = []
    for lesson in lessons:
        lesson_map = await get_lesson_connections_map(db, course_id, lesson.id)
        material_warnings = sum(1 for m in lesson_map["materials"] for _ in [None] if not m["verifiedBy"])
        question_warnings = sum(
            1 for stage in lesson_map["stages"] for block in stage["blocks"] for q in block["questions"] if q["verifiesBlockId"] is None
        )
        rows.append(
            {
                "id": lesson.id,
                "title": lesson.title,
                "materialCount": len(lesson_map["materials"]),
                "materialWarnings": material_warnings,
                "questionCount": sum(len(block["questions"]) for stage in lesson_map["stages"] for block in stage["blocks"]),
                "questionWarnings": question_warnings,
            }
        )
    return {"lessons": rows}


async def list_question_placements(db: AsyncSession, question_id: str) -> list[dict]:
    """Every place a Question is actually used, resolved to a human-readable
    chain (§5/§6/§7 of the approved rule, 2026-08-27: "неважно, где вопрос
    был создан — преподаватель должен видеть, где он фактически
    показывается"). One question can appear here multiple times if it's
    been reused."""
    placements = (await db.execute(select(QuestionPlacement).where(QuestionPlacement.questionId == question_id))).scalars().all()
    result = []
    for p in placements:
        # lessonBlockId determines WHERE it's shown even when materialBlockId
        # is also set on the same row — that combination means "shown in
        # this quiz stage, tagged as verifying that reading block" (§4),
        # never "shown inline in the material". Check lessonBlockId first.
        if p.lessonBlockId:
            block = await db.get(LessonBlock, p.lessonBlockId)
            result.append(
                {
                    "placementId": p.id,
                    "location": "lessonBlock",
                    "stage": block.stage if block else None,
                    "stageLabel": STAGE_TITLES.get(block.stage) if block else None,
                    "lessonTitle": await _resolve_lesson_title(db, block.courseId, block.lessonId) if block else None,
                    "blockTitle": block.title if block else None,
                    "verifiesBlockId": p.materialBlockId,
                }
            )
        elif p.materialBlockId:
            block = await db.get(MaterialBlock, p.materialBlockId)
            material = await db.get(Material, block.materialId) if block else None
            result.append(
                {
                    "placementId": p.id,
                    "location": "material",
                    "lessonTitle": await _resolve_lesson_title(db, material.courseId, material.lessonId) if material else None,
                    "blockTitle": block.title if block else None,
                }
            )
        elif p.legacyLessonId:
            result.append({"placementId": p.id, "location": "legacy", "lessonTitle": p.legacyLessonId, "setName": p.legacySetName})
    return result


async def set_placement_verifies_block(db: AsyncSession, placement_id: str, material_block_id: str | None) -> QuestionPlacement | None:
    """Sets/changes/clears the "verifies this reading block" tag on an
    EXISTING quiz-stage placement (§ course-builder redesign, "+ привязать"
    chip on an already-attached question, 2026-09-01) — previously this tag
    could only be set at creation/reuse time via QuestionCreateInput/
    QuestionReuseInput's own materialBlockId, with no way to add or change
    it afterward. Only meaningful on a placement that already has a
    lessonBlockId (a quiz-stage placement) — setting materialBlockId on a
    materialBlockId-only placement would turn it into the exact ambiguous
    shape list_block_questions's bugfix (2026-09-01) exists to filter back
    out, so that case is rejected rather than silently corrupting the
    placement's own "where it lives" meaning."""
    placement = await db.get(QuestionPlacement, placement_id)
    if not placement or not placement.lessonBlockId:
        return None
    placement.materialBlockId = material_block_id
    await db.commit()
    await db.refresh(placement)
    return placement


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

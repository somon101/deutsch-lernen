"""Exact port of server/src/courses.ts — course/lesson CRUD, vocabulary CRUD
with cross-lesson duplicate detection, question blocks, and the 3
cross-course "library" search functions. Courses built in the admin panel
live entirely in the database and are independent of the original
file-based course and of each other — nothing is ever copied between them.
"""

import hashlib
import uuid

from sqlalchemy import and_, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.course import Course
from app.models.course_lesson_media import CourseLessonMedia
from app.models.course_lesson_translation import CourseLessonTranslation
from app.models.course_translation import CourseTranslation
from app.models.enums import CourseStatus
from app.models.course_lesson import CourseLesson
from app.models.language import Language
from app.models.lesson_block import LessonBlock
from app.models.lesson_content import LessonContent
from app.models.lesson_edge import LessonEdge
from app.models.lesson_node import LessonNode
from app.models.lesson_node_media import LessonNodeMedia
from app.models.lesson_question import LessonQuestion
from app.models.level import Level
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.material_block_translation import MaterialBlockTranslation
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.models.question_translation import QuestionTranslation
from app.models.vocabulary_item import VocabularyItem
from app.models.vocabulary_translation import VocabularyTranslation
from app.services.content import LEGACY_COURSE_ID, DuplicateWordError, clean_quiz_text, lesson_label, normalize_word
from app.services.content_locale import DEFAULT_CONTENT_LOCALE, SUPPORTED_CONTENT_LOCALES, translations_by_locale
from app.services.lesson_graph import bulk_graphs_for_lessons
from app.services.material import filter_new_vocabulary, get_new_material_blocks, get_pool_questions_for_lesson_blocks, parse_material, to_question_dto
from app.services.vocabulary import get_or_create_category
from app.utils import to_iso_z, utcnow

STAGE_TITLES = {"minitest": "Мини-тест", "practice": "Практика", "review": "Закрепление"}


async def _owned_lesson(db: AsyncSession, course_id: str, lesson_id: str) -> str | None:
    """"Does this lesson exist and belong to this course?" — for a real
    course that's a CourseLesson row lookup. The legacy course has no such
    row, so for courseId == "legacy" this trusts the given lessonId, exactly
    like content.ts's own legacy functions do. Used only by operations that
    create a NEW child row (add word, add block) — edits to an EXISTING row
    check that row's own courseId/lessonId columns directly instead."""
    if course_id == LEGACY_COURSE_ID:
        return lesson_id
    result = await db.execute(select(CourseLesson.id).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    return result.scalar_one_or_none()


# ---------------------------------------------------------------------------
# Course / lesson CRUD
# ---------------------------------------------------------------------------


async def list_courses(db: AsyncSession, language_id: str | None = None) -> list[dict]:
    """`language_id` (§ Home lesson list, 2026-08-29) scopes the result to
    courses whose Level belongs to that Language, via the existing
    Course.levelId -> Level.languageId chain — omitted, this is the
    original, all-courses list every existing caller still gets."""
    query = select(Course).order_by(Course.position)
    if language_id:
        query = query.join(Level, Level.id == Course.levelId).where(Level.languageId == language_id)
    result = await db.execute(query)
    courses = result.scalars().all()

    lesson_counts_result = await db.execute(
        select(CourseLesson.courseId, func.count()).group_by(CourseLesson.courseId)
    )
    lesson_counts = dict(lesson_counts_result.all())

    words_result = await db.execute(select(VocabularyItem.courseId, func.count()).group_by(VocabularyItem.courseId))
    words_by = dict(words_result.all())
    questions_result = await db.execute(select(LessonQuestion.courseId, func.count()).group_by(LessonQuestion.courseId))
    questions_by = dict(questions_result.all())

    return [
        {
            "id": c.id,
            "title": c.title,
            "description": c.description,
            "coverUrl": c.coverUrl,
            "status": c.status.value,
            "position": c.position,
            "lessonCount": lesson_counts.get(c.id, 0),
            "wordCount": words_by.get(c.id, 0),
            "questionCount": questions_by.get(c.id, 0),
            "updatedAt": to_iso_z(c.updatedAt),
            "levelId": c.levelId,
        }
        for c in courses
    ]


async def get_course(db: AsyncSession, course_id: str, locale: str | None = None) -> dict | None:
    """`locale` (§ course content language, 2026-09-04) is optional and
    additive: omitted (every existing caller, e.g. the admin course
    builder), the returned "title"/"description"/"materialText" fields are
    exactly the base Course/CourseLesson columns, byte-for-byte as before —
    just with a new "translations" dict alongside them so an editor can see
    every locale at once. Passed (the student-facing path), those three
    fields are overridden with the requested locale's text where a
    CourseTranslation/CourseLessonTranslation row exists; where one does
    not, the base (original-language) text is used as a visible, flagged
    fallback (see "contentLocaleComplete") rather than a blank field —
    required text a learner has never seen a real translation for is still
    better shown than hidden, but the incompleteness is never silent."""
    course = await db.get(Course, course_id)
    if not course:
        return None
    lessons_result = await db.execute(select(CourseLesson).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position))
    lessons = lessons_result.scalars().all()
    lesson_ids = [l.id for l in lessons]

    course_translations = translations_by_locale(
        (await db.execute(select(CourseTranslation).where(CourseTranslation.courseId == course_id))).scalars().all()
    )
    lesson_translations_result = (
        (await db.execute(select(CourseLessonTranslation).where(CourseLessonTranslation.courseLessonId.in_(lesson_ids))))
        .scalars()
        .all()
        if lesson_ids
        else []
    )
    lesson_translations_by_lesson: dict[str, dict[str, CourseLessonTranslation]] = {}
    for row in lesson_translations_result:
        lesson_translations_by_lesson.setdefault(row.courseLessonId, {})[row.locale] = row

    # CourseLessonMedia (§ course content language, 2026-09-04) — only for
    # the requested locale, keyed by (lessonId, mediaType), since that's all
    # a resolved read ever needs (unlike translations, no admin editor for
    # this exists yet, so there is no "every locale" case to support here).
    lesson_media_by_lesson_type: dict[tuple[str, str], str] = {}
    if locale and lesson_ids:
        media_rows = (
            await db.execute(
                select(CourseLessonMedia).where(CourseLessonMedia.courseLessonId.in_(lesson_ids), CourseLessonMedia.locale == locale)
            )
        ).scalars().all()
        lesson_media_by_lesson_type = {(m.courseLessonId, m.mediaType): m.url for m in media_rows}

    words = (
        (await db.execute(select(VocabularyItem).where(VocabularyItem.lessonId.in_(lesson_ids)).order_by(VocabularyItem.position)))
        .scalars()
        .all()
        if lesson_ids
        else []
    )
    word_ids = [w.id for w in words]
    word_translations_result = (
        (await db.execute(select(VocabularyTranslation).where(VocabularyTranslation.vocabularyItemId.in_(word_ids))))
        .scalars()
        .all()
        if word_ids
        else []
    )
    word_translations_by_word: dict[str, dict[str, VocabularyTranslation]] = {}
    for row in word_translations_result:
        word_translations_by_word.setdefault(row.vocabularyItemId, {})[row.locale] = row
    questions = (
        (
            await db.execute(
                select(LessonQuestion).where(LessonQuestion.lessonId.in_(lesson_ids)).order_by(LessonQuestion.setName, LessonQuestion.position)
            )
        )
        .scalars()
        .all()
        if lesson_ids
        else []
    )
    blocks = (
        (await db.execute(select(LessonBlock).where(LessonBlock.lessonId.in_(lesson_ids)).order_by(LessonBlock.stage, LessonBlock.position)))
        .scalars()
        .all()
        if lesson_ids
        else []
    )

    # Cross-lesson "already taught" tracking, in position order — mirrors
    # loader.ts's wordsTaughtBeforeLesson exactly, just computed once here
    # instead of once per lesson (all the words for the whole course are
    # already loaded above).
    taught_so_far: set[str] = set()
    new_vocab_keys_by_lesson: dict[str, set[str]] = {}
    for lesson in lessons:
        new_vocab_keys_by_lesson[lesson.id] = set(taught_so_far)
        taught_so_far |= {w.germanKey for w in words if w.lessonId == lesson.id}

    new_material_by_lesson = await get_new_material_blocks(db, course_id, lesson_ids, locale)
    pool_questions_by_lesson_block = await get_pool_questions_for_lesson_blocks(db, [b.id for b in blocks], locale)
    graphs_by_lesson = await bulk_graphs_for_lessons(db, lesson_ids, locale)

    def lesson_dto(lesson: CourseLesson) -> dict:
        lesson_words = [w for w in words if w.lessonId == lesson.id]
        lesson_questions = [q for q in questions if q.lessonId == lesson.id]
        lesson_blocks = [b for b in blocks if b.lessonId == lesson.id]
        def word_dto(w: VocabularyItem) -> dict:
            w_t = word_translations_by_word.get(w.id, {})
            w_resolved = w_t.get(locale) if locale else None
            return {
                "id": w.id,
                "german": w.german,
                "translation": w_resolved.translation if w_resolved else w.translation,
                "pronunciation": w.pronunciation,
                "audioUrl": w.audioUrl,
                "imageUrl": w.imageUrl,
                "translations": {loc: {"translation": row.translation} for loc, row in w_t.items()},
                # RU is always "complete" via the base column itself, even
                # with no explicit VocabularyTranslation('ru') row — that
                # column IS today's Russian text, not a fallback standing in
                # for one. Only a non-default locale needs an explicit row.
                "contentLocaleComplete": (locale == DEFAULT_CONTENT_LOCALE or w_resolved is not None) if locale else None,
            }

        vocabulary_dtos = [word_dto(w) for w in lesson_words]
        parsed_material = parse_material(lesson.materialText, vocabulary_dtos)
        new_blocks = new_material_by_lesson.get(lesson.id)
        lesson_t = lesson_translations_by_lesson.get(lesson.id, {})
        resolved = lesson_t.get(locale) if locale else None
        title = resolved.title if resolved else lesson.title
        description = resolved.description if resolved else lesson.description
        material_text = resolved.materialText if resolved else lesson.materialText
        if resolved and resolved.materialText:
            parsed_material = parse_material(resolved.materialText, vocabulary_dtos)
        return {
            "id": lesson.id,
            "title": title,
            "description": description,
            "materialText": material_text,
            "translations": {
                loc: {"title": row.title, "description": row.description, "materialText": row.materialText}
                for loc, row in lesson_t.items()
            },
            # See the identical comment on the word-level flag above.
            "contentLocaleComplete": (locale == DEFAULT_CONTENT_LOCALE or resolved is not None) if locale else None,
            "material": new_blocks if new_blocks is not None else parsed_material["blocks"],
            "phrases": parsed_material["phrases"],
            "videoUrl": lesson_media_by_lesson_type.get((lesson.id, "video"), lesson.videoUrl),
            "audioUrl": lesson_media_by_lesson_type.get((lesson.id, "audio"), lesson.audioUrl),
            "position": lesson.position,
            # None means this lesson is still on the old fixed 8-stage chain
            # (never converted) — the client's existing Stage-enum runner and
            # rail builder read every other field above exactly as before and
            # never look at this one. Present only once a teacher has
            # explicitly converted the lesson (§ lesson graph, 2026-09-03).
            "graph": graphs_by_lesson.get(lesson.id),
            "vocabulary": vocabulary_dtos,
            "newVocabulary": filter_new_vocabulary(vocabulary_dtos, new_vocab_keys_by_lesson[lesson.id]),
            "questions": [
                {"setName": q.setName, **to_question_dto(q.kind, q.prompt, q.options, q.correctAnswer, q.data)} for q in lesson_questions
            ],
            "blocks": [
                {
                    "id": b.id,
                    "stage": b.stage,
                    "title": b.title,
                    "position": b.position,
                    # LessonQuestion rows (old full-replace quiz path) plus any
                    # reusable-pool Questions placed here (§ approved rule 4,
                    # 2026-08-27) — merged, never one replacing the other.
                    # "source" tags which is which (§ course-builder redesign
                    # bugfix, 2026-09-01) — see to_question_dtos's own comment
                    # for why the admin builder needs this to not duplicate a
                    # pool question into a real LessonQuestion row on save.
                    "questions": [
                        {"id": q.id, "source": "legacy", **to_question_dto(q.kind, q.prompt, q.options, q.correctAnswer, q.data)}
                        for q in lesson_questions
                        if q.blockId == b.id
                    ]
                    + pool_questions_by_lesson_block.get(b.id, []),
                }
                for b in lesson_blocks
            ],
        }

    course_resolved = course_translations.get(locale) if locale else None
    return {
        "id": course.id,
        "title": course_resolved.title if course_resolved else course.title,
        "description": course_resolved.description if course_resolved else course.description,
        "translations": {loc: {"title": row.title, "description": row.description} for loc, row in course_translations.items()},
        # See the identical comment on the word-level flag above.
        "contentLocaleComplete": (locale == DEFAULT_CONTENT_LOCALE or course_resolved is not None) if locale else None,
        "coverUrl": course.coverUrl,
        "status": course.status.value,
        "position": course.position,
        "updatedAt": to_iso_z(course.updatedAt),
        "levelId": course.levelId,
        "lessons": [lesson_dto(l) for l in lessons],
    }


async def get_course_version(db: AsyncSession, course_id: str) -> str | None:
    """A cheap, opaque fingerprint of everything a learner's course view
    depends on (frontend caching plan, 2026-08-29) — the client compares
    this to what it has cached and skips re-downloading the whole course
    when nothing changed. Deliberately COMPUTED, not a stored/maintained
    column: several nested tables (CourseLesson, LessonBlock,
    VocabularyItem, QuestionPlacement) have no updatedAt of their own, so
    a stored "course version" would need every mutation path across two
    services to remember to bump it — a single derived read here is safer
    and touches none of that existing write code.

    Not byte-perfect (e.g. renaming a lesson without adding/removing
    anything changes no count and no tracked updatedAt), but it catches
    every add/remove and every content/material/question edit, which is
    what actually matters for cache correctness; a missed rename just
    means the client shows last-known content one refresh cycle longer,
    self-correcting whenever anything else about the course changes."""
    course = await db.get(Course, course_id)
    if not course:
        return None

    lesson_count = await db.scalar(select(func.count()).select_from(CourseLesson).where(CourseLesson.courseId == course_id))
    vocab_count = await db.scalar(
        select(func.count())
        .select_from(VocabularyItem)
        .join(CourseLesson, CourseLesson.id == VocabularyItem.lessonId)
        .where(CourseLesson.courseId == course_id)
    )
    legacy_question_count = await db.scalar(select(func.count()).select_from(LessonQuestion).where(LessonQuestion.courseId == course_id))
    block_count = await db.scalar(select(func.count()).select_from(LessonBlock).where(LessonBlock.courseId == course_id))
    material_max_updated = await db.scalar(select(func.max(Material.updatedAt)).where(Material.courseId == course_id))
    material_block_count = await db.scalar(
        select(func.count())
        .select_from(MaterialBlock)
        .join(Material, Material.id == MaterialBlock.materialId)
        .where(Material.courseId == course_id)
    )
    pool_question_query = (
        select(func.max(Question.updatedAt), func.count())
        .select_from(Question)
        .join(QuestionPlacement, QuestionPlacement.questionId == Question.id)
        .outerjoin(LessonBlock, LessonBlock.id == QuestionPlacement.lessonBlockId)
        .outerjoin(MaterialBlock, MaterialBlock.id == QuestionPlacement.materialBlockId)
        .outerjoin(Material, Material.id == MaterialBlock.materialId)
        .where(or_(LessonBlock.courseId == course_id, Material.courseId == course_id))
    )
    pool_question_max_updated, pool_question_count = (await db.execute(pool_question_query)).one()

    # Lesson graph (§ lesson graph, 2026-09-03) — a converted lesson's node
    # positions/refs and edges have their own updatedAt/createdAt, untracked
    # by anything above, so a graph edit (move a node, add/remove a
    # connection) would otherwise never bust the client's cache.
    node_max_updated = await db.scalar(select(func.max(LessonNode.updatedAt)).where(LessonNode.courseId == course_id))
    node_count = await db.scalar(select(func.count()).select_from(LessonNode).where(LessonNode.courseId == course_id))
    edge_query = select(func.max(LessonEdge.createdAt), func.count()).select_from(LessonEdge).join(LessonNode, LessonNode.id == LessonEdge.fromNodeId).where(LessonNode.courseId == course_id)
    edge_max_created, edge_count = (await db.execute(edge_query)).one()

    # Course content language (§ course content language, 2026-09-04) — a
    # translation/media-variant edit touches none of the columns/counts
    # above, so without this a client's cached course would never notice a
    # teacher adding or updating a Tajik translation.
    translation_max_updated = await db.scalar(
        select(func.max(CourseTranslation.updatedAt)).where(CourseTranslation.courseId == course_id)
    )
    lesson_translation_max_updated = await db.scalar(
        select(func.max(CourseLessonTranslation.updatedAt))
        .join(CourseLesson, CourseLesson.id == CourseLessonTranslation.courseLessonId)
        .where(CourseLesson.courseId == course_id)
    )
    vocab_translation_max_updated = await db.scalar(
        select(func.max(VocabularyTranslation.updatedAt))
        .join(VocabularyItem, VocabularyItem.id == VocabularyTranslation.vocabularyItemId)
        .where(VocabularyItem.courseId == course_id)
    )
    block_translation_max_updated = await db.scalar(
        select(func.max(MaterialBlockTranslation.updatedAt))
        .join(MaterialBlock, MaterialBlock.id == MaterialBlockTranslation.materialBlockId)
        .join(Material, Material.id == MaterialBlock.materialId)
        .where(Material.courseId == course_id)
    )
    question_translation_max_updated = await db.scalar(
        select(func.max(QuestionTranslation.updatedAt))
        .select_from(QuestionTranslation)
        .join(QuestionPlacement, QuestionPlacement.questionId == QuestionTranslation.questionId)
        .outerjoin(LessonBlock, LessonBlock.id == QuestionPlacement.lessonBlockId)
        .outerjoin(MaterialBlock, MaterialBlock.id == QuestionPlacement.materialBlockId)
        .outerjoin(Material, Material.id == MaterialBlock.materialId)
        .where(or_(LessonBlock.courseId == course_id, Material.courseId == course_id))
    )
    node_media_max_updated = await db.scalar(
        select(func.max(LessonNodeMedia.updatedAt)).join(LessonNode, LessonNode.id == LessonNodeMedia.lessonNodeId).where(LessonNode.courseId == course_id)
    )
    lesson_media_max_updated = await db.scalar(
        select(func.max(CourseLessonMedia.updatedAt))
        .join(CourseLesson, CourseLesson.id == CourseLessonMedia.courseLessonId)
        .where(CourseLesson.courseId == course_id)
    )

    fingerprint = "|".join(
        str(v)
        for v in (
            course.updatedAt,
            lesson_count,
            vocab_count,
            legacy_question_count,
            block_count,
            material_max_updated,
            material_block_count,
            pool_question_max_updated,
            pool_question_count,
            translation_max_updated,
            lesson_translation_max_updated,
            vocab_translation_max_updated,
            block_translation_max_updated,
            question_translation_max_updated,
            node_media_max_updated,
            lesson_media_max_updated,
            node_max_updated,
            node_count,
            edge_max_created,
            edge_count,
        )
    )
    return hashlib.sha256(fingerprint.encode()).hexdigest()


async def create_course(db: AsyncSession, title: str, description: str | None, status, created_by_id: str, level_id: str | None = None) -> dict:
    if level_id and not await db.get(Level, level_id):
        raise ApiError(404, "Уровень не найден")
    # Same rule as update_course, closing the other way in: creating a course
    # straight into PUBLISHED must not skip the level check.
    if (status or CourseStatus.DRAFT) == CourseStatus.PUBLISHED and not level_id:
        raise ApiError(400, "Укажите уровень курса — без него ученики не увидят курс")
    # A brand-new course cannot have a CourseTranslation row yet (that needs
    # the course's own id first) — so this can never actually be satisfied,
    # meaning a course can never be created directly as PUBLISHED, only
    # DRAFT then published later once its Tajik title exists. See
    # update_course's identical check for the real rule and rationale.
    if (status or CourseStatus.DRAFT) == CourseStatus.PUBLISHED:
        raise ApiError(400, "Добавьте таджикский перевод названия курса — без него курс нельзя опубликовать")
    last = await db.scalar(select(Course.position).order_by(Course.position.desc()).limit(1))
    course = Course(
        title=title,
        description=description or "",
        status=status or CourseStatus.DRAFT,
        position=(last if last is not None else -1) + 1,
        createdById=created_by_id,
        levelId=level_id,
    )
    db.add(course)
    await db.commit()
    return await get_course(db, course.id)


async def update_course(db: AsyncSession, course_id: str, changes: dict) -> dict | None:
    course = await db.get(Course, course_id)
    if not course:
        return None
    if changes.get("levelId") and not await db.get(Level, changes["levelId"]):
        raise ApiError(404, "Уровень не найден")

    # A published course with no Level is invisible to every learner: the
    # home screen always asks for one language, and that filter is an inner
    # join Course -> Level -> Language, so a course with no levelId matches
    # nothing. Publishing one looks like it worked and silently reaches
    # nobody, so the publish is refused instead (§ course level required to
    # publish, 2026-09-02). Drafts stay allowed without a level — the rule
    # bites exactly where the harm appears.
    #
    # Only a request that actually touches status or levelId is judged. A
    # course that is ALREADY published without a level (data from before this
    # rule) must stay editable: refusing to rename it would lock the teacher
    # out of the very screen where the level is assigned.
    if "status" in changes or "levelId" in changes:
        resulting_status = changes.get("status", course.status)
        resulting_level = changes["levelId"] if "levelId" in changes else course.levelId
        if resulting_status == "PUBLISHED" and not resulting_level:
            raise ApiError(400, "Укажите уровень курса — без него ученики не увидят курс")

    # Course content language (§ course content language, 2026-09-04) —
    # same grandfathering shape as the levelId rule just above: only the
    # ACT of transitioning into PUBLISHED is judged (course.status was not
    # already PUBLISHED), never a later, unrelated edit to an already-live
    # course. RU needs no explicit row (Course.title/description already
    # ARE the Russian text); only TG must exist and be non-empty. This
    # blocks the course level only — lesson/word/material/question
    # completeness is surfaced to the admin UI via "contentLocaleComplete"
    # but not yet enforced as a hard publish gate (§ see push report).
    if changes.get("status") == "PUBLISHED" and course.status != CourseStatus.PUBLISHED:
        tg = (
            await db.execute(select(CourseTranslation).where(CourseTranslation.courseId == course_id, CourseTranslation.locale == "tg"))
        ).scalar_one_or_none()
        if not tg or not tg.title.strip():
            raise ApiError(400, "Добавьте таджикский перевод названия курса — без него курс нельзя опубликовать")

    for field, value in changes.items():
        setattr(course, field, value)
    await db.commit()
    return await get_course(db, course_id)


async def delete_course(db: AsyncSession, course_id: str) -> bool:
    course = await db.get(Course, course_id)
    if not course:
        return False
    lesson_ids_result = await db.execute(select(CourseLesson.id).where(CourseLesson.courseId == course_id))
    lesson_ids = [r[0] for r in lesson_ids_result.all()]
    if lesson_ids:
        await db.execute(VocabularyItem.__table__.delete().where(VocabularyItem.lessonId.in_(lesson_ids)))
        await db.execute(LessonQuestion.__table__.delete().where(LessonQuestion.lessonId.in_(lesson_ids)))
        await db.execute(LessonBlock.__table__.delete().where(LessonBlock.lessonId.in_(lesson_ids)))
    await db.delete(course)  # lessons cascade via the real FK
    await db.commit()
    return True


async def reorder_courses(db: AsyncSession, ids: list[str]) -> None:
    for index, course_id in enumerate(ids):
        course = await db.get(Course, course_id)
        if course:
            course.position = index
    await db.commit()


async def create_lesson(db: AsyncSession, course_id: str, title: str, description: str | None, material_text: str | None) -> dict | None:
    course = await db.get(Course, course_id)
    if not course:
        return None
    last = await db.scalar(select(CourseLesson.position).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position.desc()).limit(1))
    lesson = CourseLesson(
        courseId=course_id,
        title=title,
        description=description or "",
        materialText=material_text or "",
        position=(last if last is not None else -1) + 1,
    )
    db.add(lesson)
    await db.commit()

    # Push notifications, event "lesson_created" (§ generic mechanism,
    # 2026-08-29): a lesson only actually reaches learners once its course
    # is PUBLISHED, so a lesson added to a still-DRAFT course is silent —
    # nothing to notify about yet. Never allowed to break lesson creation
    # itself: send_notification() already swallows its own errors, this
    # try/except is only for the settings lookup around it.
    if course.status == CourseStatus.PUBLISHED:
        try:
            from app.services import push as push_svc

            if (await push_svc.get_settings(db)).autoSendOnNewLesson:
                await push_svc.notify_lesson_created(
                    db, course_id=course_id, course_title=course.title, lesson_id=lesson.id, lesson_title=lesson.title, created_by_id=None
                )
        except Exception as exc:  # noqa: BLE001 — a push failure must never break lesson creation
            print(f"Push: auto-notify on lesson creation failed: {exc!r}")

    return await get_course(db, course_id)


async def update_lesson(db: AsyncSession, course_id: str, lesson_id: str, changes: dict) -> dict | None:
    result = await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        return None
    for field, value in changes.items():
        setattr(lesson, field, value)
    await db.commit()
    return await get_course(db, course_id)


async def delete_lesson(db: AsyncSession, course_id: str, lesson_id: str) -> dict | None:
    result = await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        return None
    await db.execute(VocabularyItem.__table__.delete().where(VocabularyItem.lessonId == lesson_id))
    await db.execute(LessonQuestion.__table__.delete().where(LessonQuestion.lessonId == lesson_id))
    await db.execute(LessonBlock.__table__.delete().where(LessonBlock.lessonId == lesson_id))
    await db.delete(lesson)
    await db.commit()
    return await get_course(db, course_id)


async def reorder_lessons(db: AsyncSession, course_id: str, ids: list[str]) -> dict | None:
    result = await db.execute(select(CourseLesson.id).where(CourseLesson.courseId == course_id))
    owned = {r[0] for r in result.all()}
    if not all(i in owned for i in ids):
        return None
    for index, lesson_id in enumerate(ids):
        lesson = await db.get(CourseLesson, lesson_id)
        if lesson:
            lesson.position = index
    await db.commit()
    return await get_course(db, course_id)


async def set_lesson_media(db: AsyncSession, course_id: str, lesson_id: str, kind: str, url: str | None) -> dict | None:
    result = await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    lesson = result.scalar_one_or_none()
    if not lesson:
        return None
    if kind == "video":
        lesson.videoUrl = url
    else:
        lesson.audioUrl = url
    await db.commit()
    return await get_course(db, course_id)


async def set_lesson_media_translation(
    db: AsyncSession, course_id: str, lesson_id: str, kind: str, locale: str, url: str | None
) -> dict | None:
    """One locale's variant of a legacy-flat-field lesson's video/audio (§
    course content language, 2026-09-04) — writes CourseLessonMedia, never
    the base videoUrl/audioUrl column itself. See LessonNodeMedia's
    docstring for the identical clone-as-placeholder convention this
    mirrors for the non-graph lesson path."""
    lesson = (
        await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    ).scalar_one_or_none()
    if not lesson:
        return None
    existing = (
        await db.execute(
            select(CourseLessonMedia).where(
                CourseLessonMedia.courseLessonId == lesson_id, CourseLessonMedia.mediaType == kind, CourseLessonMedia.locale == locale
            )
        )
    ).scalar_one_or_none()
    if url is None:
        if existing:
            await db.delete(existing)
    elif existing:
        existing.url = url
    else:
        db.add(CourseLessonMedia(courseLessonId=lesson_id, mediaType=kind, locale=locale, url=url))
    await db.commit()
    return await get_course(db, course_id)


async def set_course_cover(db: AsyncSession, course_id: str, url: str | None) -> dict | None:
    course = await db.get(Course, course_id)
    if not course:
        return None
    course.coverUrl = url
    await db.commit()
    return await get_course(db, course_id)


async def set_course_translation(db: AsyncSession, course_id: str, locale: str, title: str, description: str) -> dict | None:
    """Upsert (§ course content language, 2026-09-04) — a teacher re-saving
    the same locale's tab just overwrites its own row; the unique
    (courseId, locale) constraint is what makes "does a row already exist"
    safe to check-then-write without a race, since only one admin edits a
    given course at a time in practice and a lost update here just means
    re-saving."""
    course = await db.get(Course, course_id)
    if not course:
        return None
    existing = (
        await db.execute(select(CourseTranslation).where(CourseTranslation.courseId == course_id, CourseTranslation.locale == locale))
    ).scalar_one_or_none()
    if existing:
        existing.title = title
        existing.description = description
    else:
        db.add(CourseTranslation(courseId=course_id, locale=locale, title=title, description=description))
    await db.commit()
    return await get_course(db, course_id)


async def set_lesson_translation(
    db: AsyncSession, course_id: str, lesson_id: str, locale: str, title: str, description: str, material_text: str
) -> dict | None:
    lesson = (
        await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    ).scalar_one_or_none()
    if not lesson:
        return None
    existing = (
        await db.execute(
            select(CourseLessonTranslation).where(
                CourseLessonTranslation.courseLessonId == lesson_id, CourseLessonTranslation.locale == locale
            )
        )
    ).scalar_one_or_none()
    if existing:
        existing.title = title
        existing.description = description
        existing.materialText = material_text
    else:
        db.add(
            CourseLessonTranslation(
                courseLessonId=lesson_id, locale=locale, title=title, description=description, materialText=material_text
            )
        )
    await db.commit()
    return await get_course(db, course_id)


# ---------------------------------------------------------------------------
# Media library (read over existing video/audio URLs — not a separate table)
# ---------------------------------------------------------------------------


async def list_media_library(db: AsyncSession, kind: str) -> list[dict]:
    field = CourseLesson.videoUrl if kind == "video" else CourseLesson.audioUrl
    lessons_result = await db.execute(
        select(CourseLesson.videoUrl, CourseLesson.audioUrl, CourseLesson.title, Course.title)
        .join(Course, Course.id == CourseLesson.courseId)
        .where(field.isnot(None))
    )
    lessons = lessons_result.all()

    legacy_field = LessonContent.videoUrl if kind == "video" else LessonContent.audioUrl
    legacy_result = await db.execute(select(LessonContent.videoUrl, LessonContent.audioUrl, LessonContent.lessonId).where(legacy_field.isnot(None)))
    legacy_rows = legacy_result.all()

    by_url: dict[str, str] = {}
    for video_url, audio_url, lesson_title, course_title in lessons:
        url = video_url if kind == "video" else audio_url
        if url and url not in by_url:
            by_url[url] = f"{course_title} — {lesson_title}"
    for video_url, audio_url, lesson_id in legacy_rows:
        url = video_url if kind == "video" else audio_url
        if url and url not in by_url:
            by_url[url] = f"Немецкий с нуля — {lesson_label(lesson_id)}"

    return [{"url": url, "label": label} for url, label in by_url.items()]


async def media_url_still_in_use(db: AsyncSession, url: str, course_lesson_id: str | None = None, legacy_lesson_id: str | None = None) -> bool:
    lesson_query = select(func.count()).select_from(CourseLesson).where(or_(CourseLesson.videoUrl == url, CourseLesson.audioUrl == url))
    if course_lesson_id:
        lesson_query = lesson_query.where(CourseLesson.id != course_lesson_id)
    content_query = select(func.count()).select_from(LessonContent).where(or_(LessonContent.videoUrl == url, LessonContent.audioUrl == url))
    if legacy_lesson_id:
        content_query = content_query.where(LessonContent.lessonId != legacy_lesson_id)

    lesson_count = await db.scalar(lesson_query)
    content_count = await db.scalar(content_query)
    return (lesson_count or 0) + (content_count or 0) > 0


# ---------------------------------------------------------------------------
# Vocabulary — add / edit / delete one word at a time, plus bulk JSON import.
# Every write path funnels through find_word_clashes.
# ---------------------------------------------------------------------------


def _is_unique_violation(e: IntegrityError) -> bool:
    return "unique" in str(e.orig).lower() or "duplicate key" in str(e.orig).lower()


async def _find_word_clashes(db: AsyncSession, course_id: str, keys: list[str], exclude_word_id: str | None = None) -> list[dict]:
    if not keys:
        return []
    query = select(VocabularyItem.germanKey, VocabularyItem.german, VocabularyItem.lessonId).where(
        VocabularyItem.courseId == course_id, VocabularyItem.germanKey.in_(keys)
    )
    if exclude_word_id:
        query = query.where(VocabularyItem.id != exclude_word_id)
    rows = (await db.execute(query)).all()
    if not rows:
        return []

    if course_id == LEGACY_COURSE_ID:
        label_for = lesson_label
    else:
        lessons_result = await db.execute(select(CourseLesson.id, CourseLesson.title).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position))
        lessons = lessons_result.all()
        index_by_id = {lid: i for i, (lid, _) in enumerate(lessons)}
        title_by_id = dict(lessons)

        def label_for(lesson_id: str) -> str:
            if lesson_id in index_by_id:
                return f"Урок {index_by_id[lesson_id] + 1} «{title_by_id[lesson_id]}»"
            return "другом уроке"

    return [{"germanKey": gk, "german": g, "lessonId": lid, "lessonLabel": label_for(lid)} for gk, g, lid in rows]


def _clash_message(clashes: list[dict]) -> str:
    if len(clashes) <= 1:
        label = clashes[0]["lessonLabel"] if clashes else "другом уроке"
        return f"Это слово уже добавлено в словарь курса. Оно изучается в {label}."
    labels = ", ".join(c["lessonLabel"] for c in clashes)
    return f"Это слово уже добавлено в словарь курса. Оно изучается в: {labels}."


async def search_question_library(db: AsyncSession, query: str) -> list[dict]:
    q = query.strip()
    if len(q) < 2:
        return []
    result = await db.execute(select(LessonQuestion).where(LessonQuestion.prompt.ilike(f"%{q}%")).limit(15))
    return [to_question_dto(r.kind, r.prompt, r.options, r.correctAnswer, r.data) for r in result.scalars().all()]


async def search_material_library(db: AsyncSession, query: str) -> list[dict]:
    q = query.strip()
    if len(q) < 2:
        return []
    result = await db.execute(
        select(CourseLesson.title, CourseLesson.materialText, Course.title)
        .join(Course, Course.id == CourseLesson.courseId)
        .where(CourseLesson.materialText.ilike(f"%{q}%"))
        .limit(10)
    )
    rows = result.all()
    return [
        {
            "label": f"{course_title} — {lesson_title}",
            "snippet": (material_text[:140] + "…") if len(material_text) > 140 else material_text,
            "materialText": material_text,
        }
        for lesson_title, material_text, course_title in rows
    ]


async def search_word_library(db: AsyncSession, query: str) -> list[dict]:
    q = query.strip()
    if len(q) < 2:
        return []
    result = await db.execute(
        select(VocabularyItem.german, VocabularyItem.translation, VocabularyItem.pronunciation, VocabularyItem.germanKey)
        .where(or_(VocabularyItem.german.ilike(f"%{q}%"), VocabularyItem.translation.ilike(f"%{q}%")))
        .order_by(VocabularyItem.german)
        .limit(300)
    )
    by_key: dict[str, dict] = {}
    for german, translation, pronunciation, german_key in result.all():
        if german_key not in by_key:
            by_key[german_key] = {"german": german, "translation": translation, "pronunciation": pronunciation}
    return list(by_key.values())[:20]


async def derive_language_id(db: AsyncSession, course_id: str) -> str | None:
    """Same "legacy = German" backfill rule the word-cards migration used
    for existing rows (§ word cards, 2026-08-31) — a new word gets a real
    languageId the same way, not left null just because it's new."""
    if course_id == LEGACY_COURSE_ID:
        return await db.scalar(select(Language.id).where(func.lower(func.trim(Language.name)) == "немецкий"))
    return await db.scalar(select(Level.languageId).join(Course, Course.levelId == Level.id).where(Course.id == course_id))


async def add_vocabulary_word(
    db: AsyncSession, course_id: str, lesson_id: str, german: str, translation: str, pronunciation: str, category_name: str | None = None, image_url: str | None = None
) -> dict | None:
    if not await _owned_lesson(db, course_id, lesson_id):
        return None

    german_key = normalize_word(german)
    clashes = await _find_word_clashes(db, course_id, [german_key])
    if clashes:
        raise DuplicateWordError(_clash_message(clashes))

    category_id = (await get_or_create_category(db, category_name)).id if category_name else None
    language_id = await derive_language_id(db, course_id)

    last = await db.scalar(select(VocabularyItem.position).where(VocabularyItem.lessonId == lesson_id).order_by(VocabularyItem.position.desc()).limit(1))
    db.add(
        VocabularyItem(
            courseId=course_id,
            lessonId=lesson_id,
            german=german,
            translation=translation,
            pronunciation=pronunciation,
            position=(last if last is not None else -1) + 1,
            germanKey=german_key,
            categoryId=category_id,
            imageUrl=image_url,
            languageId=language_id,
        )
    )
    try:
        await db.commit()
    except IntegrityError as e:
        await db.rollback()
        if not _is_unique_violation(e):
            raise
        clashes_now = await _find_word_clashes(db, course_id, [german_key])
        raise DuplicateWordError(_clash_message(clashes_now))
    return {"ok": True}


async def update_vocabulary_word(db: AsyncSession, course_id: str, lesson_id: str, word_id: str, changes: dict) -> dict | None:
    result = await db.execute(select(VocabularyItem).where(VocabularyItem.id == word_id, VocabularyItem.lessonId == lesson_id, VocabularyItem.courseId == course_id))
    word = result.scalar_one_or_none()
    if not word:
        return None

    new_german_key = None
    if "german" in changes and changes["german"] is not None:
        new_german_key = normalize_word(changes["german"])
        if new_german_key != word.germanKey:
            clashes = await _find_word_clashes(db, course_id, [new_german_key], word_id)
            if clashes:
                raise DuplicateWordError(_clash_message(clashes))

    if "translation" in changes and changes["translation"] is not None:
        word.translation = changes["translation"]
    if "pronunciation" in changes and changes["pronunciation"] is not None:
        word.pronunciation = changes["pronunciation"]
    if "imageUrl" in changes and changes["imageUrl"] is not None:
        word.imageUrl = changes["imageUrl"]
    if "categoryName" in changes and changes["categoryName"] is not None:
        word.categoryId = (await get_or_create_category(db, changes["categoryName"])).id
    if new_german_key is not None:
        word.german = changes["german"]
        word.germanKey = new_german_key

    try:
        await db.commit()
    except IntegrityError as e:
        await db.rollback()
        if not _is_unique_violation(e):
            raise
        clashes_now = await _find_word_clashes(db, course_id, [new_german_key or word.germanKey], word_id)
        raise DuplicateWordError(_clash_message(clashes_now))
    return {"ok": True}


async def set_vocabulary_translation(
    db: AsyncSession, course_id: str, lesson_id: str, word_id: str, locale: str, translation: str
) -> dict | None:
    """Only `translation` varies by locale — see VocabularyTranslation's
    docstring for why `german`/`pronunciation` stay put. Same upsert
    pattern as set_course_translation."""
    result = await db.execute(select(VocabularyItem).where(VocabularyItem.id == word_id, VocabularyItem.lessonId == lesson_id, VocabularyItem.courseId == course_id))
    word = result.scalar_one_or_none()
    if not word:
        return None
    existing = (
        await db.execute(
            select(VocabularyTranslation).where(VocabularyTranslation.vocabularyItemId == word_id, VocabularyTranslation.locale == locale)
        )
    ).scalar_one_or_none()
    if existing:
        existing.translation = translation
    else:
        db.add(VocabularyTranslation(vocabularyItemId=word_id, locale=locale, translation=translation))
    await db.commit()
    return {"ok": True}


async def delete_vocabulary_word(db: AsyncSession, course_id: str, lesson_id: str, word_id: str) -> dict | None:
    result = await db.execute(select(VocabularyItem).where(VocabularyItem.id == word_id, VocabularyItem.lessonId == lesson_id, VocabularyItem.courseId == course_id))
    word = result.scalar_one_or_none()
    if not word:
        return None
    await db.delete(word)
    await db.commit()
    return {"ok": True}


async def set_vocabulary_word_audio(db: AsyncSession, course_id: str, lesson_id: str, word_id: str, audio_url: str | None) -> dict | None:
    result = await db.execute(select(VocabularyItem).where(VocabularyItem.id == word_id, VocabularyItem.lessonId == lesson_id, VocabularyItem.courseId == course_id))
    word = result.scalar_one_or_none()
    if not word:
        return None
    previous = word.audioUrl
    word.audioUrl = audio_url
    await db.commit()
    return {"ok": True, "previousAudioUrl": previous}


async def set_vocabulary_word_image(db: AsyncSession, course_id: str, lesson_id: str, word_id: str, image_url: str | None) -> dict | None:
    """Same shape as set_vocabulary_word_audio above (§ word cards,
    2026-08-31) - a word's photo upload/removal, mirrored one-for-one."""
    result = await db.execute(select(VocabularyItem).where(VocabularyItem.id == word_id, VocabularyItem.lessonId == lesson_id, VocabularyItem.courseId == course_id))
    word = result.scalar_one_or_none()
    if not word:
        return None
    previous = word.imageUrl
    word.imageUrl = image_url
    await db.commit()
    return {"ok": True, "previousImageUrl": previous}


# ---------------------------------------------------------------------------
# Vocabulary JSON import
# ---------------------------------------------------------------------------


async def _evaluate_vocabulary_import(db: AsyncSession, course_id: str, words: list[dict]) -> dict:
    seen_in_payload: dict[str, int] = {}
    items = []
    for index, w in enumerate(words):
        german_key = normalize_word(w["original"])
        first_index = seen_in_payload.get(german_key)
        if first_index is not None:
            items.append(
                {
                    "index": index,
                    "original": w["original"],
                    "status": "duplicate-in-json",
                    "message": f"Слово «{w['original']}» повторяется в этом же JSON (уже указано в строке {first_index + 1}).",
                }
            )
            continue
        seen_in_payload[german_key] = index
        items.append({"index": index, "original": w["original"], "status": "new"})

    candidate_keys = list({normalize_word(words[i["index"]]["original"]) for i in items if i["status"] == "new"})
    clashes = await _find_word_clashes(db, course_id, candidate_keys)
    clashes_by_key: dict[str, list[dict]] = {}
    for c in clashes:
        clashes_by_key.setdefault(c["germanKey"], []).append(c)

    final_items = []
    for item in items:
        if item["status"] != "new":
            final_items.append(item)
            continue
        course_clashes = clashes_by_key.get(normalize_word(words[item["index"]]["original"]))
        if not course_clashes:
            final_items.append(item)
            continue
        final_items.append(
            {
                **item,
                "status": "duplicate-in-course",
                "message": _clash_message(course_clashes),
                "existingLessons": [c["lessonLabel"] for c in course_clashes],
            }
        )

    return {
        "total": len(words),
        "newCount": sum(1 for i in final_items if i["status"] == "new"),
        "duplicateCount": sum(1 for i in final_items if i["status"] != "new"),
        "errorCount": 0,
        "items": final_items,
    }


async def preview_vocabulary_import(db: AsyncSession, course_id: str, lesson_id: str, words: list[dict]) -> dict | None:
    if not await _owned_lesson(db, course_id, lesson_id):
        return None
    return await _evaluate_vocabulary_import(db, course_id, words)


async def import_vocabulary_words(db: AsyncSession, course_id: str, lesson_id: str, words: list[dict]) -> dict | None:
    if not await _owned_lesson(db, course_id, lesson_id):
        return None

    preview = await _evaluate_vocabulary_import(db, course_id, words)
    to_insert = [i for i in preview["items"] if i["status"] == "new"]
    skipped = [i for i in preview["items"] if i["status"] != "new"]

    if to_insert:
        last = await db.scalar(select(VocabularyItem.position).where(VocabularyItem.lessonId == lesson_id).order_by(VocabularyItem.position.desc()).limit(1))
        start_position = (last if last is not None else -1) + 1

        for i, item in enumerate(to_insert):
            w = words[item["index"]]
            db.add(
                VocabularyItem(
                    courseId=course_id,
                    lessonId=lesson_id,
                    german=w["original"],
                    translation=w["translation"],
                    pronunciation=w["transcription"],
                    position=start_position + i,
                    germanKey=normalize_word(w["original"]),
                )
            )
        try:
            await db.commit()
        except IntegrityError as e:
            await db.rollback()
            if not _is_unique_violation(e):
                raise
            keys = [normalize_word(words[i["index"]]["original"]) for i in to_insert]
            clashes_now = await _find_word_clashes(db, course_id, keys)
            raise DuplicateWordError(_clash_message(clashes_now))

    return {"addedCount": len(to_insert), "skipped": skipped}


# ---------------------------------------------------------------------------
# Legacy-style flat question set save (superseded by blocks; kept because
# the route still exists for parity)
# ---------------------------------------------------------------------------


async def save_lesson_questions(db: AsyncSession, course_id: str, lesson_id: str, questions: list[dict]) -> dict | None:
    result = await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))
    if not result.scalar_one_or_none():
        return None

    old_rows = (await db.execute(select(LessonQuestion).where(LessonQuestion.lessonId == lesson_id))).scalars().all()
    for row in old_rows:
        await db.delete(row)
    await db.flush()

    counters: dict[str, int] = {}
    for q in questions:
        position = counters.get(q["setName"], 0)
        counters[q["setName"]] = position + 1
        db.add(
            LessonQuestion(
                courseId=course_id,
                lessonId=lesson_id,
                setName=q["setName"],
                prompt=q["prompt"],
                options=q["options"],
                correctAnswer=q["correctAnswer"],
                position=position,
            )
        )
    await db.commit()
    return await get_course(db, course_id)


# ---------------------------------------------------------------------------
# Question blocks
# ---------------------------------------------------------------------------


def clean_questions_payload(raw: dict) -> dict:
    """Strips formal edge punctuation from every answer-bearing field before
    validation — mirrors cleanQuestionsPayload() in courses.ts exactly,
    including running BEFORE schema validation so "options must not repeat"
    naturally rejects near-duplicates that only differed by punctuation."""
    if not isinstance(raw, dict) or "questions" not in raw or not isinstance(raw["questions"], list):
        return raw

    def clean_field(v):
        return clean_quiz_text(v) if isinstance(v, str) else v

    cleaned = []
    for q in raw["questions"]:
        if not isinstance(q, dict):
            cleaned.append(q)
            continue
        kind = q.get("kind")
        if kind in ("choice", "cloze", "scramble"):
            # Only rewrite `options` when it actually is a list. A scramble in
            # auto mode may legitimately omit it (§ auto scramble,
            # 2026-09-02), and forcing a None in here would turn "absent, use
            # the schema default" into an explicit null that fails validation.
            cleaned_q = {**q, "correctAnswer": clean_field(q.get("correctAnswer"))}
            if isinstance(q.get("options"), list):
                cleaned_q["options"] = [clean_field(o) for o in q["options"]]
            cleaned.append(cleaned_q)
        elif kind == "match":
            pairs = q.get("pairs")
            cleaned.append(
                {
                    **q,
                    "pairs": [
                        {**p, "left": clean_field(p.get("left")), "right": clean_field(p.get("right"))} if isinstance(p, dict) else p
                        for p in pairs
                    ]
                    if isinstance(pairs, list)
                    else pairs,
                }
            )
        else:
            # truefalse has no answer-candidate fields to clean.
            cleaned.append(q)

    return {**raw, "questions": cleaned}


async def create_block(db: AsyncSession, course_id: str, lesson_id: str, stage: str, title: str) -> dict | None:
    if not await _owned_lesson(db, course_id, lesson_id):
        return None
    last = await db.scalar(
        select(LessonBlock.position).where(LessonBlock.lessonId == lesson_id, LessonBlock.stage == stage).order_by(LessonBlock.position.desc()).limit(1)
    )
    db.add(LessonBlock(id=str(uuid.uuid4()), courseId=course_id, lessonId=lesson_id, stage=stage, title=title, position=(last if last is not None else -1) + 1))
    await db.commit()
    return {"ok": True}


async def update_block(db: AsyncSession, course_id: str, lesson_id: str, block_id: str, title: str) -> dict | None:
    result = await db.execute(select(LessonBlock).where(LessonBlock.id == block_id, LessonBlock.lessonId == lesson_id, LessonBlock.courseId == course_id))
    block = result.scalar_one_or_none()
    if not block:
        return None
    block.title = title
    await db.commit()
    return {"ok": True}


async def delete_block(db: AsyncSession, course_id: str, lesson_id: str, block_id: str) -> dict | None:
    result = await db.execute(select(LessonBlock).where(LessonBlock.id == block_id, LessonBlock.lessonId == lesson_id, LessonBlock.courseId == course_id))
    block = result.scalar_one_or_none()
    if not block:
        return None
    await db.execute(LessonQuestion.__table__.delete().where(LessonQuestion.blockId == block_id))
    await db.delete(block)
    await db.commit()
    return {"ok": True}


async def reorder_blocks(db: AsyncSession, course_id: str, lesson_id: str, stage: str, ids: list[str]) -> dict | None:
    result = await db.execute(select(LessonBlock.id).where(LessonBlock.lessonId == lesson_id, LessonBlock.courseId == course_id, LessonBlock.stage == stage))
    owned = {r[0] for r in result.all()}
    if len(ids) != len(owned) or not all(i in owned for i in ids):
        return None
    for index, block_id in enumerate(ids):
        block = await db.get(LessonBlock, block_id)
        if block:
            block.position = index
    await db.commit()
    return {"ok": True}


def _block_question_to_row(q: dict) -> dict:
    kind = q["kind"]
    if kind == "truefalse":
        return {"prompt": q["prompt"], "options": [], "correctAnswer": "true" if q["correct"] else "false", "data": None}
    if kind == "match":
        pairs = [{"left": p["left"], "right": p["right"]} for p in q["pairs"]]
        return {"prompt": q.get("prompt") or "", "options": [], "correctAnswer": "", "data": pairs}
    if kind == "auto_blank":
        # No author-provided prompt/options/correctAnswer at all (§ auto
        # blank, 2026-08-31) - just the phrases the blank/options get
        # generated from per-user, per-request. Stored in the existing
        # `data` JSONB (already used for "match"'s pairs) rather than a new
        # column or a child table.
        phrases = [p.strip() for p in q["phrases"] if p.strip()]
        return {"prompt": "", "options": [], "correctAnswer": "", "data": {"phrases": phrases}}
    if kind == "auto_translate":
        # Same shape as auto_blank above (§ auto translate, 2026-09-02): the
        # teacher's whole configuration is the source and the count, stored
        # in `data`. No word ids are stored — the selection belongs to a
        # session, not to the block.
        return {"prompt": "", "options": [], "correctAnswer": "", "data": {"source": q["source"], "count": q["count"]}}
    if kind == "auto_match":
        # Only the pair count is the teacher's (§ auto match, 2026-09-02) —
        # the words are chosen per learner, per session, at serve time.
        return {"prompt": "", "options": [], "correctAnswer": "", "data": {"count": q["count"]}}
    # choice / cloze / scramble all fit prompt + options + correctAnswer as-is.
    return {"prompt": q["prompt"], "options": q["options"], "correctAnswer": q["correctAnswer"], "data": None}


async def save_block_questions(db: AsyncSession, course_id: str, lesson_id: str, block_id: str, questions: list[dict]) -> dict | None:
    result = await db.execute(select(LessonBlock).where(LessonBlock.id == block_id, LessonBlock.lessonId == lesson_id, LessonBlock.courseId == course_id))
    block = result.scalar_one_or_none()
    if not block:
        return None

    old_rows = (await db.execute(select(LessonQuestion).where(LessonQuestion.blockId == block_id))).scalars().all()
    for row in old_rows:
        await db.delete(row)
    await db.flush()

    for index, q in enumerate(questions):
        row = _block_question_to_row(q)
        db.add(
            LessonQuestion(
                courseId=course_id,
                lessonId=lesson_id,
                blockId=block_id,
                setName=block.stage,
                position=index,
                kind=q["kind"],
                prompt=row["prompt"],
                options=row["options"],
                correctAnswer=row["correctAnswer"],
                data=row["data"],
            )
        )
    await db.commit()
    return {"ok": True}

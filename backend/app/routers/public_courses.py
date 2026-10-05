"""Public API, course building (§ API-key permissions, 2026-10-05): courses,
modules, lessons, their words, steps and route — for the API key's ONE
language. `courses:read` reads, `courses:write` creates and edits,
`courses:delete` deletes (courses, modules, lessons, steps). A course is
always created as a draft and the API cannot publish it: publishing stays
a person's decision in the constructor. Anything from another language
answers 404, exactly like a missing id."""

from typing import Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.errors import ApiError
from app.models.api_key import ApiKey
from app.models.course import Course
from app.models.course_lesson import CourseLesson
from app.models.course_module import CourseModule
from app.models.lesson_node import LessonNode
from app.models.lesson_vocabulary_link import LessonVocabularyLink
from app.models.level import Level
from app.models.vocabulary_item import VocabularyItem
from app.services import course_modules
from app.services import courses as courses_svc
from app.services import lesson_graph
from app.services.api_keys import need
from app.uploads.storage import COURSE_MEDIA_DIR, delete_file

router = APIRouter(prefix="/api/v1", tags=["public-api"])

StepType = Literal["vocabulary", "phrases", "material", "video", "audio", "minitest", "practice", "review"]


class _Body(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)


class CourseCreate(_Body):
    title: str = Field(min_length=1, max_length=200)
    title_tg: str | None = Field(default=None, max_length=200)
    description: str = Field(default="", max_length=4000)
    levelId: str = Field(min_length=1)


class CourseUpdate(_Body):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    title_tg: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=4000)
    levelId: str | None = None


class ModuleCreate(_Body):
    title: str = Field(min_length=1, max_length=200)
    title_tg: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=4000)


class ModuleUpdate(_Body):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    title_tg: str | None = Field(default=None, max_length=200)
    description: str | None = Field(default=None, max_length=4000)


class OrderBody(BaseModel):
    ids: list[str] = Field(min_length=1, max_length=200)


class LessonCreate(_Body):
    title: str = Field(min_length=1, max_length=200)
    title_tg: str | None = Field(default=None, max_length=200)
    moduleId: str | None = None
    planEn: str | None = Field(default=None, max_length=20000)
    planRu: str | None = Field(default=None, max_length=20000)


class LessonUpdate(_Body):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    title_tg: str | None = Field(default=None, max_length=200)
    # "" moves the lesson out of every module.
    moduleId: str | None = None
    planEn: str | None = Field(default=None, max_length=20000)
    planRu: str | None = Field(default=None, max_length=20000)


class WordsBody(BaseModel):
    wordIds: list[str] = Field(min_length=1, max_length=100)


class StepCreate(_Body):
    type: StepType
    title: str | None = Field(default=None, max_length=200)
    aiTask: str | None = Field(default=None, max_length=4000)
    aiTaskRu: str | None = Field(default=None, max_length=4000)
    aiPending: bool = False
    phraseIds: list[str] | None = Field(default=None, max_length=100)
    # A question step testing an audio/video step of the same lesson.
    forStepId: str | None = None
    # Material steps: name of an existing topic from «Темы».
    topic: str | None = Field(default=None, max_length=300)


class StepUpdate(_Body):
    title: str | None = Field(default=None, max_length=200)
    aiTask: str | None = Field(default=None, max_length=4000)
    aiTaskRu: str | None = Field(default=None, max_length=4000)
    aiPending: bool | None = None
    phraseIds: list[str] | None = Field(default=None, max_length=100)
    forStepId: str | None = None
    topic: str | None = Field(default=None, max_length=300)


class RouteBody(BaseModel):
    stepIds: list[str] = Field(max_length=100)


# ------------------------------------------------------------------ helpers


async def _own_level(db: AsyncSession, key: ApiKey, level_id: str) -> Level:
    level = await db.get(Level, level_id)
    if not level or level.languageId != key.languageId:
        raise ApiError(404, "Уровень не найден")
    return level


async def _own_course(db: AsyncSession, key: ApiKey, course_id: str) -> Course:
    course = await db.get(Course, course_id)
    level = await db.get(Level, course.levelId) if course and course.levelId else None
    if not course or not level or level.languageId != key.languageId:
        raise ApiError(404, "Курс не найден")
    return course


async def _own_lesson(db: AsyncSession, key: ApiKey, lesson_id: str) -> CourseLesson:
    lesson = await db.get(CourseLesson, lesson_id)
    if not lesson:
        raise ApiError(404, "Урок не найден")
    try:
        await _own_course(db, key, lesson.courseId)
    except ApiError:
        raise ApiError(404, "Урок не найден")
    return lesson


async def _own_step(db: AsyncSession, key: ApiKey, step_id: str) -> tuple[CourseLesson, LessonNode]:
    node = await db.get(LessonNode, step_id)
    if not node:
        raise ApiError(404, "Шаг не найден")
    try:
        lesson = await _own_lesson(db, key, node.lessonId)
    except ApiError:
        raise ApiError(404, "Шаг не найден")
    return lesson, node


def _step_out(n: dict) -> dict:
    return {
        "id": n["id"],
        "type": n["type"],
        "title": n["title"],
        "aiTask": n.get("aiTask"),
        "aiTaskRu": n.get("aiTaskRu"),
        "aiPending": n.get("aiPending", False),
        "forStepId": n.get("forNodeId"),
        "phrases": [{"id": p["id"], "text": p["text"], "translation": p["translation"]} for p in n.get("phrases") or []],
    }


def _route(graph: dict) -> list[str]:
    nxt = {e["fromNodeId"]: e["toNodeId"] for e in graph["edges"]}
    has_in = {e["toNodeId"] for e in graph["edges"]}
    order: list[str] = []
    for n in graph["nodes"]:
        if n["id"] in has_in:
            continue
        current = n["id"]
        while current and current not in order:
            order.append(current)
            current = nxt.get(current)
    return order


def _lesson_out(lesson: dict) -> dict:
    graph = lesson.get("graph") or {"nodes": [], "edges": []}
    return {
        "id": lesson["id"],
        "title": lesson["title"],
        "title_tg": (lesson.get("translations") or {}).get("tg", {}).get("title"),
        "moduleId": lesson.get("moduleId"),
        "position": lesson["position"],
        "planEn": lesson.get("planEn"),
        "planRu": lesson.get("planRu"),
        "words": [{"id": w["id"], "word": w["german"], "translation": w["translation"]} for w in lesson.get("vocabulary") or []],
        "steps": [_step_out(n) for n in graph["nodes"]],
        "route": _route(graph),
    }


async def _course_out(db: AsyncSession, course_id: str) -> dict:
    course = await courses_svc.get_course(db, course_id)
    return {
        "id": course["id"],
        "title": course["title"],
        "title_tg": (course.get("translations") or {}).get("tg", {}).get("title"),
        "description": course["description"],
        "status": course["status"],
        "levelId": course["levelId"],
        "modules": [{"id": m["id"], "title": m["title"], "title_tg": m["titleTg"], "description": m["description"], "position": m["position"]} for m in course["modules"]],
        "lessons": [_lesson_out(l) for l in course["lessons"]],
    }


async def _lesson_full(db: AsyncSession, lesson: CourseLesson) -> dict:
    course = await courses_svc.get_course(db, lesson.courseId)
    return next(_lesson_out(l) for l in course["lessons"] if l["id"] == lesson.id)


# ---------------------------------------------------------- levels/courses


@router.get("/levels")
async def list_levels(key: ApiKey = Depends(need("courses:read")), db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(select(Level).where(Level.languageId == key.languageId).order_by(Level.position))).scalars().all()
    return {"levels": [{"id": l.id, "code": l.code, "name": l.name} for l in rows]}


@router.get("/courses")
async def list_courses(key: ApiKey = Depends(need("courses:read")), db: AsyncSession = Depends(get_db)):
    rows = await courses_svc.list_courses(db, language_id=key.languageId)
    return {"courses": [{k: c[k] for k in ("id", "title", "description", "status", "levelId", "lessonCount")} for c in rows]}


@router.get("/courses/{course_id}")
async def get_course(course_id: str, key: ApiKey = Depends(need("courses:read")), db: AsyncSession = Depends(get_db)):
    await _own_course(db, key, course_id)
    return {"course": await _course_out(db, course_id)}


@router.post("/courses", status_code=201)
async def create_course(body: CourseCreate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    await _own_level(db, key, body.levelId)
    created = await courses_svc.create_course(db, body.title, body.description, None, None, body.levelId)
    if body.title_tg:
        await courses_svc.set_course_translation(db, created["id"], "tg", body.title_tg, "")
    return {"course": await _course_out(db, created["id"])}


@router.patch("/courses/{course_id}")
async def update_course(course_id: str, body: CourseUpdate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    await _own_course(db, key, course_id)
    changes = {k: v for k, v in (("title", body.title), ("description", body.description)) if v is not None}
    if body.levelId is not None:
        await _own_level(db, key, body.levelId)
        changes["levelId"] = body.levelId
    if changes:
        await courses_svc.update_course(db, course_id, changes)
    if body.title_tg is not None:
        await courses_svc.set_course_translation(db, course_id, "tg", body.title_tg, "")
    return {"course": await _course_out(db, course_id)}


@router.delete("/courses/{course_id}")
async def delete_course(course_id: str, key: ApiKey = Depends(need("courses:delete")), db: AsyncSession = Depends(get_db)):
    course = await _own_course(db, key, course_id)
    if course.status.value == "PUBLISHED":
        raise ApiError(409, "Опубликованный курс через API удалить нельзя — снимите его с публикации в конструкторе")
    await courses_svc.delete_course(db, course_id)
    return {"ok": True}


# ----------------------------------------------------------------- modules


@router.post("/courses/{course_id}/modules", status_code=201)
async def create_module(course_id: str, body: ModuleCreate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    await _own_course(db, key, course_id)
    module = await course_modules.create_module(db, course_id, body.title, body.title_tg, body.description)
    return {"module": course_modules.module_dto(module)}


@router.put("/courses/{course_id}/modules/order")
async def order_modules(course_id: str, body: OrderBody, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    await _own_course(db, key, course_id)
    await course_modules.reorder_modules(db, course_id, body.ids)
    return {"course": await _course_out(db, course_id)}


async def _own_module(db: AsyncSession, key: ApiKey, module_id: str) -> CourseModule:
    module = await db.get(CourseModule, module_id)
    if not module:
        raise ApiError(404, "Модуль не найден")
    try:
        await _own_course(db, key, module.courseId)
    except ApiError:
        raise ApiError(404, "Модуль не найден")
    return module


@router.patch("/modules/{module_id}")
async def update_module(module_id: str, body: ModuleUpdate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    module = await _own_module(db, key, module_id)
    changes = body.model_dump(exclude_unset=True)
    if "title_tg" in changes:
        changes["titleTg"] = changes.pop("title_tg")
    module = await course_modules.update_module(db, module.courseId, module_id, changes)
    return {"module": course_modules.module_dto(module)}


@router.delete("/modules/{module_id}")
async def delete_module(module_id: str, key: ApiKey = Depends(need("courses:delete")), db: AsyncSession = Depends(get_db)):
    module = await _own_module(db, key, module_id)
    await course_modules.delete_module(db, module.courseId, module_id)
    return {"ok": True}


# ----------------------------------------------------------------- lessons


@router.post("/courses/{course_id}/lessons", status_code=201)
async def create_lesson(course_id: str, body: LessonCreate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    await _own_course(db, key, course_id)
    if body.moduleId:
        await _own_module(db, key, body.moduleId)
    before = set((await db.execute(select(CourseLesson.id).where(CourseLesson.courseId == course_id))).scalars().all())
    await courses_svc.create_lesson(db, course_id, body.title, None, None, notify=False, module_id=body.moduleId, plan_en=body.planEn, plan_ru=body.planRu)
    new_id = next(i for i in (await db.execute(select(CourseLesson.id).where(CourseLesson.courseId == course_id))).scalars().all() if i not in before)
    created = await db.get(CourseLesson, new_id)
    if body.title_tg:
        await courses_svc.set_lesson_translation(db, course_id, created.id, "tg", body.title_tg, "", "")
    return {"lesson": await _lesson_full(db, created)}


@router.get("/lessons/{lesson_id}")
async def get_lesson(lesson_id: str, key: ApiKey = Depends(need("courses:read")), db: AsyncSession = Depends(get_db)):
    return {"lesson": await _lesson_full(db, await _own_lesson(db, key, lesson_id))}


@router.patch("/lessons/{lesson_id}")
async def update_lesson(lesson_id: str, body: LessonUpdate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    lesson = await _own_lesson(db, key, lesson_id)
    changes = {k: v for k, v in (("title", body.title), ("planEn", body.planEn), ("planRu", body.planRu)) if v is not None}
    if changes:
        await courses_svc.update_lesson(db, lesson.courseId, lesson.id, changes)
    if body.moduleId is not None:
        if body.moduleId:
            await _own_module(db, key, body.moduleId)
        await course_modules.set_lesson_module(db, lesson.courseId, lesson.id, body.moduleId or None)
    if body.title_tg is not None:
        await courses_svc.set_lesson_translation(db, lesson.courseId, lesson.id, "tg", body.title_tg, "", "")
    await db.refresh(lesson)
    return {"lesson": await _lesson_full(db, lesson)}


@router.delete("/lessons/{lesson_id}")
async def delete_lesson(lesson_id: str, key: ApiKey = Depends(need("courses:delete")), db: AsyncSession = Depends(get_db)):
    lesson = await _own_lesson(db, key, lesson_id)
    await courses_svc.delete_lesson(db, lesson.courseId, lesson.id)
    return {"ok": True}


@router.post("/lessons/{lesson_id}/words")
async def add_lesson_words(lesson_id: str, body: WordsBody, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    """Attaches existing dictionary words of this language to the lesson
    (never copies them). Already attached words are skipped."""
    lesson = await _own_lesson(db, key, lesson_id)
    ids = list(dict.fromkeys(body.wordIds))
    found = set((await db.execute(select(VocabularyItem.id).where(VocabularyItem.id.in_(ids), VocabularyItem.languageId == key.languageId))).scalars().all())
    missing = [i for i in ids if i not in found]
    if missing:
        raise ApiError(404, f"Слово не найдено в словаре этого языка: {missing[0]}")
    added = 0
    for word_id in ids:
        result = await courses_svc.link_existing_word_to_lesson(db, lesson.courseId, lesson.id, word_id)
        if result and not result.get("alreadyPresent"):
            added += 1
    await lesson_graph.sync_graph_with_content(db, lesson.id, words_changed=True)
    return {"added": added, "lesson": await _lesson_full(db, lesson)}


@router.delete("/lessons/{lesson_id}/words/{word_id}")
async def remove_lesson_word(lesson_id: str, word_id: str, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    """Detaches a word from the lesson; the word stays in the dictionary."""
    lesson = await _own_lesson(db, key, lesson_id)
    link = (
        await db.execute(select(LessonVocabularyLink).where(LessonVocabularyLink.lessonId == lesson.id, LessonVocabularyLink.wordId == word_id))
    ).scalar_one_or_none()
    if not link:
        word = await db.get(VocabularyItem, word_id)
        if word and word.lessonId == lesson.id:
            raise ApiError(409, "Это слово создано в самом уроке — уберите его в конструкторе")
        raise ApiError(404, "Слово не прикреплено к уроку")
    await db.delete(link)
    await db.commit()
    return {"ok": True}


# ------------------------------------------------------------------- steps


@router.post("/lessons/{lesson_id}/steps", status_code=201)
async def create_step(lesson_id: str, body: StepCreate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    lesson = await _own_lesson(db, key, lesson_id)
    count = len((await db.execute(select(LessonNode.id).where(LessonNode.lessonId == lesson.id))).scalars().all())
    node = await lesson_graph.create_node(
        db, lesson.courseId, lesson.id, body.type, body.title, count * 260.0, 160.0, ai_task=body.aiTask, ai_pending=body.aiPending, phrase_ids=body.phraseIds,
        ai_task_ru=body.aiTaskRu, for_node_id=body.forStepId, topic=body.topic,
    )
    return {"step": _step_out(node)}


@router.patch("/steps/{step_id}")
async def update_step(step_id: str, body: StepUpdate, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    lesson, node = await _own_step(db, key, step_id)
    changes = body.model_dump(exclude_unset=True)
    if "title" in changes:
        changes["title"] = (changes["title"] or "").strip() or None
    if "forStepId" in changes:
        changes["forNodeId"] = changes.pop("forStepId")
    return {"step": _step_out(await lesson_graph.update_node(db, lesson.id, node.id, changes))}


@router.delete("/steps/{step_id}")
async def delete_step(step_id: str, key: ApiKey = Depends(need("courses:delete")), db: AsyncSession = Depends(get_db)):
    lesson, node = await _own_step(db, key, step_id)
    removed = await lesson_graph.delete_node(db, lesson.courseId, lesson.id, node.id)
    if removed:
        delete_file(COURSE_MEDIA_DIR, removed)
    return {"ok": True}


@router.put("/lessons/{lesson_id}/route")
async def set_route(lesson_id: str, body: RouteBody, key: ApiKey = Depends(need("courses:write")), db: AsyncSession = Depends(get_db)):
    """The learner route at once: step ids in walking order."""
    lesson = await _own_lesson(db, key, lesson_id)
    await lesson_graph.set_route(db, lesson.courseId, lesson.id, body.stepIds)
    return {"lesson": await _lesson_full(db, lesson)}

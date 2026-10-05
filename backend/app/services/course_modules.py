"""Course modules and lesson plans (§ course modules, 2026-10-05).

A module groups lessons of one course under a title (usually a topic).
CourseLesson.position stays the single learner order everything else
already relies on (unlocking, "words taught before", the runner) — this
module only keeps it in step with the grouping: lessons are numbered module
by module, in module order, and lessons without a module come last."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.course import Course
from app.models.course_lesson import CourseLesson
from app.models.course_module import CourseModule


def module_dto(m: CourseModule, locale: str | None = None) -> dict:
    title = m.titleTg if locale == "tg" and m.titleTg else m.title
    return {"id": m.id, "title": title, "titleTg": m.titleTg, "description": m.description, "position": m.position}


async def list_modules(db: AsyncSession, course_id: str) -> list[CourseModule]:
    return list(
        (await db.execute(select(CourseModule).where(CourseModule.courseId == course_id).order_by(CourseModule.position, CourseModule.createdAt)))
        .scalars()
        .all()
    )


async def renumber_lessons(db: AsyncSession, course_id: str) -> None:
    """Rewrites CourseLesson.position so lessons follow module order (each
    module's lessons keep their relative order; lessons with no module, or a
    module that no longer exists, go last). Flushes, never commits."""
    modules = await list_modules(db, course_id)
    module_rank = {m.id: i for i, m in enumerate(modules)}
    lessons = (await db.execute(select(CourseLesson).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position))).scalars().all()
    ordered = sorted(lessons, key=lambda l: (module_rank.get(l.moduleId, len(modules)), l.position))
    for index, lesson in enumerate(ordered):
        if lesson.moduleId and lesson.moduleId not in module_rank:
            lesson.moduleId = None
        lesson.position = index
    await db.flush()


async def _course(db: AsyncSession, course_id: str) -> Course:
    course = await db.get(Course, course_id)
    if not course:
        raise ApiError(404, "Курс не найден")
    return course


async def _module(db: AsyncSession, course_id: str, module_id: str) -> CourseModule:
    module = await db.get(CourseModule, module_id)
    if not module or module.courseId != course_id:
        raise ApiError(404, "Модуль не найден")
    return module


async def create_module(db: AsyncSession, course_id: str, title: str, title_tg: str | None = None, description: str | None = None) -> CourseModule:
    await _course(db, course_id)
    title = (title or "").strip()
    if not title:
        raise ApiError(400, "Укажите название модуля")
    modules = await list_modules(db, course_id)
    module = CourseModule(
        courseId=course_id,
        title=title[:200],
        titleTg=(title_tg or "").strip()[:200] or None,
        description=(description or "").strip(),
        position=len(modules),
    )
    db.add(module)
    await db.commit()
    await db.refresh(module)
    return module


async def update_module(db: AsyncSession, course_id: str, module_id: str, changes: dict) -> CourseModule:
    module = await _module(db, course_id, module_id)
    if "title" in changes:
        title = (changes["title"] or "").strip()
        if not title:
            raise ApiError(400, "Укажите название модуля")
        module.title = title[:200]
    if "titleTg" in changes:
        module.titleTg = (changes["titleTg"] or "").strip()[:200] or None
    if "description" in changes:
        module.description = (changes["description"] or "").strip()
    await db.commit()
    await db.refresh(module)
    return module


async def delete_module(db: AsyncSession, course_id: str, module_id: str) -> None:
    """Deletes the module only — its lessons stay, without a module."""
    module = await _module(db, course_id, module_id)
    lessons = (await db.execute(select(CourseLesson).where(CourseLesson.moduleId == module.id))).scalars().all()
    for lesson in lessons:
        lesson.moduleId = None
    await db.delete(module)
    await db.flush()
    remaining = [m for m in await list_modules(db, course_id) if m.id != module_id]
    for i, m in enumerate(remaining):
        m.position = i
    await renumber_lessons(db, course_id)
    await db.commit()


async def reorder_modules(db: AsyncSession, course_id: str, ids: list[str]) -> None:
    modules = await list_modules(db, course_id)
    by_id = {m.id: m for m in modules}
    if set(ids) != set(by_id):
        raise ApiError(400, "Список модулей не совпадает с модулями курса")
    for i, module_id in enumerate(ids):
        by_id[module_id].position = i
    await renumber_lessons(db, course_id)
    await db.commit()


async def set_lesson_module(db: AsyncSession, course_id: str, lesson_id: str, module_id: str | None) -> None:
    """Moves a lesson into a module (at its end) or out of every module."""
    lesson = (await db.execute(select(CourseLesson).where(CourseLesson.id == lesson_id, CourseLesson.courseId == course_id))).scalar_one_or_none()
    if not lesson:
        raise ApiError(404, "Урок не найден")
    if module_id:
        await _module(db, course_id, module_id)
    if lesson.moduleId == (module_id or None):
        return
    lesson.moduleId = module_id or None
    # Last inside its new group: after every other lesson of the course,
    # renumber_lessons then pulls it back to the end of that module.
    last = await db.scalar(select(CourseLesson.position).where(CourseLesson.courseId == course_id).order_by(CourseLesson.position.desc()).limit(1))
    lesson.position = (last or 0) + 1
    await db.flush()
    await renumber_lessons(db, course_id)
    await db.commit()


def clean_plan(value: str | None) -> str | None:
    return (value or "").strip()[:20000] or None

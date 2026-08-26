"""One-time backfill for the Language/Level/Material/MaterialBlock/Question/
QuestionPlacement tables (see the migration plan approved 2026-08-26).

Purely additive — never touches or deletes the old materialText/videoUrl/
audioUrl fields or LessonQuestion rows, which keep serving exactly as before.

Scope, deliberately: only DB-resident material text is split into
Material/MaterialBlock rows here — CourseLesson.materialText (course
builder) and LessonContent.materialText (legacy admin overrides). Legacy
lessons that have never had an admin override saved keep serving their
original on-disk text exactly as before; that on-disk content is NOT
imported into MaterialBlock by this script (a separate, bigger decision if
ever wanted — see the final report).

Safe to re-run: skipped entirely (with a message) if any Language/Question
row already exists, since this is a genuine one-time migration step, not an
incremental sync.

Run from backend/: venv/Scripts/python.exe scripts/backfill_content_taxonomy.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.db import async_session  # noqa: E402
from app.legacy_parser.parse_lesson_text import parse_lesson_text  # noqa: E402
from app.models.course import Course  # noqa: E402
from app.models.course_lesson import CourseLesson  # noqa: E402
from app.models.language import Language  # noqa: E402
from app.models.lesson_content import LessonContent  # noqa: E402
from app.models.lesson_question import LessonQuestion  # noqa: E402
from app.models.level import Level  # noqa: E402
from app.models.material import Material  # noqa: E402
from app.models.material_block import MaterialBlock  # noqa: E402
from app.models.question import Question  # noqa: E402
from app.models.question_placement import QuestionPlacement  # noqa: E402

DEFAULT_LANGUAGE_ID = "de"
DEFAULT_LEVEL_CODE = "A1"


def _blocks_to_material_blocks(parsed_blocks: list[dict]) -> list[tuple[str, str]]:
    """Groups the fine-grained parser output (one entry per line/phrase/
    subheading) into (title, content) pairs at each "Шаг N." boundary —
    matching the spec's own example ("Блок 1: Что такое Präteritum?", "Блок
    2: Когда используется?", ...). Content before the first step (if any)
    becomes an "Введение" block."""

    def render(block: dict) -> str:
        if block["type"] == "phrase":
            german = block.get("german", "")
            pronunciation = block.get("pronunciation")
            translation = block.get("translation", "")
            word = f"{german} [{pronunciation}]" if pronunciation else german
            return f"{word} — {translation}"
        if block["type"] == "subheading":
            return f"## {block.get('text', '')}"
        if block["type"] == "line":
            return block.get("text", "")
        return ""

    groups: list[tuple[str, list[str]]] = []
    for block in parsed_blocks:
        if block["type"] == "title":
            continue
        if block["type"] == "step":
            groups.append((block["title"], []))
            continue
        text = render(block)
        if not text:
            continue
        if not groups:
            groups.append(("Введение", []))
        groups[-1][1].append(text)

    return [(title, "\n".join(lines)) for title, lines in groups if lines]


async def _backfill_material(db, *, course_id: str, lesson_id: str, material_text: str, title: str) -> None:
    if not material_text.strip():
        return
    parsed = parse_lesson_text(material_text)
    block_pairs = _blocks_to_material_blocks(parsed["blocks"])
    if not block_pairs:
        return
    material = Material(courseId=course_id, lessonId=lesson_id, materialType="text", title=title, position=0)
    db.add(material)
    await db.flush()
    for i, (block_title, content) in enumerate(block_pairs):
        db.add(MaterialBlock(materialId=material.id, title=block_title, content=content, position=i))


async def main() -> None:
    async with async_session() as db:
        if (await db.execute(select(Language.id))).first() is not None:
            print("Language already seeded — assuming this backfill already ran. Exiting without changes.")
            return

        language = Language(id=DEFAULT_LANGUAGE_ID, name="Немецкий")
        db.add(language)
        level = Level(languageId=DEFAULT_LANGUAGE_ID, code=DEFAULT_LEVEL_CODE, name="Начальный уровень", position=1)
        db.add(level)
        await db.flush()
        print(f"Seeded Language({DEFAULT_LANGUAGE_ID}) and Level({DEFAULT_LEVEL_CODE}) = {level.id}")

        courses = (await db.execute(select(Course))).scalars().all()
        for course in courses:
            course.levelId = level.id
        print(f"Assigned {len(courses)} existing course(s) to the default level.")

        lessons = (await db.execute(select(CourseLesson))).scalars().all()
        for lesson in lessons:
            await _backfill_material(
                db, course_id=lesson.courseId, lesson_id=lesson.id, material_text=lesson.materialText, title=lesson.title
            )
        print(f"Backfilled Material/MaterialBlock for {len(lessons)} course-builder lesson(s).")

        legacy_overrides = (await db.execute(select(LessonContent).where(LessonContent.materialText.is_not(None)))).scalars().all()
        for content in legacy_overrides:
            await _backfill_material(
                db, course_id="legacy", lesson_id=content.lessonId, material_text=content.materialText or "", title=content.lessonId
            )
        print(f"Backfilled Material/MaterialBlock for {len(legacy_overrides)} legacy admin-override lesson(s).")

        questions = (await db.execute(select(LessonQuestion))).scalars().all()
        count = 0
        for lq in questions:
            question = Question(kind=lq.kind, prompt=lq.prompt, options=lq.options, correctAnswer=lq.correctAnswer, data=lq.data)
            db.add(question)
            await db.flush()
            placement = QuestionPlacement(questionId=question.id, position=lq.position)
            if lq.courseId == "legacy":
                placement.legacyLessonId = lq.lessonId
                placement.legacySetName = lq.setName
            else:
                placement.lessonBlockId = lq.blockId
            db.add(placement)
            count += 1
        print(f"Copied {count} LessonQuestion row(s) into Question + QuestionPlacement.")

        await db.commit()
    print("Done.")


if __name__ == "__main__":
    asyncio.run(main())

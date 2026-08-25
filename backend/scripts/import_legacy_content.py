"""One-time import: moves lesson1/lesson2's file-based content (material
text, vocabulary, generated exercises) into the DB override tables that
already exist for exactly this purpose (LessonContent/VocabularyItem/
LessonQuestion, courseId="legacy") — see the migration plan §3, Decisions
1 and 2 (both explicitly approved by the user).

Safe to re-run: every write is skipped (not overwritten) if the target
already has real content, so it never clobbers an admin's own edit or
double-inserts. Scope is TEXT content only — video/audio files are a
separate, simpler file-copy step (see the migration plan follow-up notes),
not part of this script.

Run from backend/: venv/Scripts/python.exe scripts/import_legacy_content.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.db import async_session  # noqa: E402
from app.legacy_parser.generate_exercises import build_lesson_exercises, exercise_to_db_row  # noqa: E402
from app.legacy_parser.parse_lesson_text import parse_lesson_text  # noqa: E402
from app.models.lesson_block import LessonBlock  # noqa: E402
from app.models.lesson_content import LessonContent  # noqa: E402
from app.models.lesson_question import LessonQuestion  # noqa: E402
from app.models.vocabulary_item import VocabularyItem  # noqa: E402
from app.utils import utcnow  # noqa: E402
import uuid  # noqa: E402

STAGE_TITLES = {"minitest": "Мини-тест", "practice": "Практика", "review": "Закрепление"}

LESSONS_DIR = Path(__file__).resolve().parent.parent.parent
LESSONS = [
    {"id": "lesson1", "dir": LESSONS_DIR / "lesson1", "material_file": "урок1.txt"},
    {"id": "lesson2", "dir": LESSONS_DIR / "lessons" / "lesson2", "material_file": "урок.txt"},
]


async def import_lesson(db, lesson: dict) -> None:
    lesson_id = lesson["id"]
    material_path = lesson["dir"] / lesson["material_file"]
    material_raw = material_path.read_text(encoding="utf-8")

    # --- materialText override ------------------------------------------------
    content = await db.get(LessonContent, lesson_id)
    if content is not None and content.materialText:
        print(f"[{lesson_id}] materialText already set — skipping (not overwriting)")
    else:
        if content is None:
            db.add(LessonContent(lessonId=lesson_id, materialText=material_raw, updatedAt=utcnow()))
        else:
            content.materialText = material_raw
        print(f"[{lesson_id}] materialText imported ({len(material_raw)} chars)")

    # --- vocabulary (needed here only to build the exercise pool; the DB
    # rows themselves are already correctly seeded — confirmed via a direct
    # diff against the parser output before this script was written) --------
    vocab_rows = (
        (await db.execute(select(VocabularyItem).where(VocabularyItem.lessonId == lesson_id).order_by(VocabularyItem.position)))
        .scalars()
        .all()
    )
    vocabulary = [{"german": v.german, "translation": v.translation} for v in vocab_rows]

    parsed = parse_lesson_text(material_raw)
    phrases = parsed["phrases"]

    # --- generated exercises, frozen as a named LessonBlock (one per stage)
    # holding real LessonQuestion rows with a blockId set. This is NOT
    # optional — content/loader.ts's authoredFor() only reads content.blocks
    # through the full 5-kind toQuestionDTO/toExercise mapping; its flat
    # content.authoredQuestions fallback (used when blocks is empty)
    # hardcodes kind:"choice" for every question and has no `data` column
    # for match pairs. Freezing as flat, blockless questions would silently
    # render every true/false, cloze, scramble, and match question as a
    # broken multiple-choice question in the live app — caught and fixed
    # before this script's first real run (see git history / conversation).
    existing_block = await db.scalar(select(LessonBlock.id).where(LessonBlock.lessonId == lesson_id).limit(1))
    if existing_block is not None:
        print(f"[{lesson_id}] blocks already exist — skipping (not duplicating)")
        return

    exercises = build_lesson_exercises(lesson_id, vocabulary, phrases)
    total = 0
    for block_position, (set_name, items) in enumerate(
        [("minitest", exercises["minitest"]), ("practice", exercises["practice"]), ("review", exercises["review"])]
    ):
        block_id = str(uuid.uuid4())
        db.add(LessonBlock(id=block_id, courseId="legacy", lessonId=lesson_id, stage=set_name, title=STAGE_TITLES[set_name], position=block_position))
        for position, exercise in enumerate(items):
            row = exercise_to_db_row(exercise)
            db.add(
                LessonQuestion(
                    lessonId=lesson_id,
                    setName=set_name,
                    prompt=row["prompt"],
                    options=row["options"],
                    correctAnswer=row["correctAnswer"],
                    position=position,
                    courseId="legacy",
                    kind=row["kind"],
                    data=row["data"],
                    blockId=block_id,
                )
            )
            total += 1
    print(f"[{lesson_id}] {total} exercise questions imported across 3 blocks (minitest={len(exercises['minitest'])}, practice={len(exercises['practice'])}, review={len(exercises['review'])})")


async def main() -> None:
    async with async_session() as db:
        for lesson in LESSONS:
            await import_lesson(db, lesson)
        await db.commit()
    print("Done.")


if __name__ == "__main__":
    asyncio.run(main())

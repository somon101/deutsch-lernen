import re

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.lesson_block import LessonBlock
from app.models.lesson_content import LessonContent
from app.models.lesson_question import LessonQuestion
from app.models.vocabulary_item import VocabularyItem
from app.schemas.content import ContentPayload
from app.services.material import filter_new_vocabulary, parse_material
from app.utils import to_iso_z, utcnow

# The original, file-based course. Courses made in the builder use their own
# Course id, so words never clash across independent courses.
LEGACY_COURSE_ID = "legacy"

_NORMALIZE_PUNCTUATION = re.compile(r"""[.,!?;:…"'«»„""()]""")
_WHITESPACE = re.compile(r"\s+")
_QUIZ_EDGE_PUNCTUATION = re.compile(r"""^[.!?;:…"'«»„""()/]+|[.!?;:…"'«»„""()/]+$""")
_TRAILING_DIGITS = re.compile(r"(\d+)$")


def normalize_word(german: str) -> str:
    """Case- and punctuation-insensitive form of a word, used as the
    course-wide uniqueness key. "Hallo", "hallo" and "Hallo!" all normalize
    to the same value, so none of them can be added twice under a different
    spelling."""
    value = german.lower()
    value = _NORMALIZE_PUNCTUATION.sub("", value)
    value = _WHITESPACE.sub(" ", value)
    return value.strip()


def clean_quiz_text(value: str) -> str:
    """Formal marks stripped only from the edges of a quiz answer/option —
    never from the middle. Mirrors the client's cleanQuizText exactly."""
    value = _QUIZ_EDGE_PUNCTUATION.sub("", value)
    value = _WHITESPACE.sub(" ", value)
    return value.strip()


def lesson_label(lesson_id: str) -> str:
    """Human-readable lesson name for duplicate messages ("lesson2" ->
    "Урок 2")."""
    m = _TRAILING_DIGITS.search(lesson_id)
    return f"Урок {m.group(1)}" if m else lesson_id


class DuplicateWordError(Exception):
    """Raised when a word would end up in two lessons of the same course."""


def to_question_dto(kind: str, prompt: str, options: list[str] | None, correct_answer: str, data) -> dict:
    if kind == "truefalse":
        return {"kind": "truefalse", "prompt": prompt, "correct": correct_answer == "true"}
    if kind == "cloze":
        return {"kind": "cloze", "prompt": prompt, "options": options or [], "correctAnswer": correct_answer}
    if kind == "scramble":
        return {"kind": "scramble", "prompt": prompt, "options": options or [], "correctAnswer": correct_answer}
    if kind == "match":
        return {"kind": "match", "prompt": prompt, "pairs": data or []}
    return {"kind": "choice", "prompt": prompt, "options": options or [], "correctAnswer": correct_answer}


async def _legacy_lesson_order(db: AsyncSession) -> list[str]:
    """Legacy lessons have no CourseLesson rows to order by position — the
    frontend's own file-discovery sorts by the trailing digit in the id
    (lesson1, lesson2, ...); replicated here from the set of lessonIds that
    actually have vocabulary, since that's the only place the backend can
    observe "which legacy lessons exist" without scanning files itself."""
    result = await db.execute(select(VocabularyItem.lessonId).where(VocabularyItem.courseId == LEGACY_COURSE_ID).distinct())
    ids = [r[0] for r in result.all()]

    def sort_key(lesson_id: str) -> int:
        m = _TRAILING_DIGITS.search(lesson_id)
        return int(m.group(1)) if m else 0

    return sorted(ids, key=sort_key)


async def _words_taught_before_legacy_lesson(db: AsyncSession, lesson_id: str) -> set[str]:
    order = await _legacy_lesson_order(db)
    if lesson_id not in order:
        return set()
    earlier_ids = order[: order.index(lesson_id)]
    if not earlier_ids:
        return set()
    result = await db.execute(
        select(VocabularyItem.germanKey).where(VocabularyItem.courseId == LEGACY_COURSE_ID, VocabularyItem.lessonId.in_(earlier_ids))
    )
    return {r[0] for r in result.all()}


def _title_from_blocks(blocks: list[dict]) -> str | None:
    for b in blocks:
        if b.get("type") == "title":
            return b.get("text")
    return None


async def list_legacy_lessons(db: AsyncSession) -> list[dict]:
    """All legacy lesson ids, in the same numeric order the old React
    client's file-discovery used to list them in. Needed by any Flutter
    screen that has to enumerate "every legacy lesson" (e.g. the profile
    screen's lesson-history section) now that content is DB-resident rather
    than discovered from files on disk — the old client never needed this as
    an endpoint because it did that discovery itself via Vite's import.meta.glob."""
    ids = await _legacy_lesson_order(db)
    lessons = []
    for lesson_id in ids:
        content = await db.get(LessonContent, lesson_id)
        material_text = content.materialText if content else None
        parsed = parse_material(material_text or "", [])
        title = _title_from_blocks(parsed["blocks"]) or lesson_label(lesson_id)
        vocab_count = (
            await db.execute(select(func.count()).select_from(VocabularyItem).where(VocabularyItem.lessonId == lesson_id))
        ).scalar_one()
        lessons.append({"lessonId": lesson_id, "title": title, "vocabularyCount": vocab_count})
    return lessons


async def get_lesson_content(db: AsyncSession, lesson_id: str) -> dict:
    content = await db.get(LessonContent, lesson_id)
    vocab_result = await db.execute(
        select(VocabularyItem).where(VocabularyItem.lessonId == lesson_id).order_by(VocabularyItem.position)
    )
    vocabulary = vocab_result.scalars().all()
    q_result = await db.execute(
        select(LessonQuestion).where(LessonQuestion.lessonId == lesson_id).order_by(LessonQuestion.setName, LessonQuestion.position)
    )
    questions = q_result.scalars().all()
    b_result = await db.execute(
        select(LessonBlock).where(LessonBlock.lessonId == lesson_id).order_by(LessonBlock.stage, LessonBlock.position)
    )
    blocks = b_result.scalars().all()

    vocabulary_dtos = [
        {"id": v.id, "german": v.german, "translation": v.translation, "pronunciation": v.pronunciation, "audioUrl": v.audioUrl}
        for v in vocabulary
    ]
    material_text = content.materialText if content else None
    parsed_material = parse_material(material_text or "", vocabulary_dtos)
    taught_before = await _words_taught_before_legacy_lesson(db, lesson_id)
    new_vocabulary = filter_new_vocabulary(vocabulary_dtos, taught_before)

    return {
        "lessonId": lesson_id,
        "materialText": material_text,
        "material": parsed_material["blocks"],
        "phrases": parsed_material["phrases"],
        "videoUrl": content.videoUrl if content else None,
        "audioUrl": content.audioUrl if content else None,
        "vocabulary": vocabulary_dtos,
        "newVocabulary": new_vocabulary,
        "questions": [
            {"setName": q.setName, "prompt": q.prompt, "options": q.options, "correctAnswer": q.correctAnswer}
            for q in questions
        ],
        "blocks": [
            {
                "id": b.id,
                "stage": b.stage,
                "title": b.title,
                "position": b.position,
                "questions": [
                    to_question_dto(q.kind, q.prompt, q.options, q.correctAnswer, q.data)
                    for q in questions
                    if q.blockId == b.id
                ],
            }
            for b in blocks
        ],
        "hasOverrides": content is not None or len(vocabulary) > 0 or len(questions) > 0,
        "updatedAt": to_iso_z(content.updatedAt) if content else None,
    }


async def save_lesson_content(db: AsyncSession, lesson_id: str, payload: ContentPayload, editor_id: str, set_fields: set[str]) -> dict:
    """Saves whichever sections were supplied (set_fields = the request
    body's actually-present top-level keys, since Pydantic can't natively
    distinguish "omitted" from "explicitly null" the way the Zod schema's
    .optional() did). Each section is replaced wholesale in one transaction,
    so a half-applied vocabulary list can never reach learners."""

    if "materialText" in set_fields:
        content = await db.get(LessonContent, lesson_id)
        if content is None:
            db.add(LessonContent(lessonId=lesson_id, materialText=payload.materialText, updatedById=editor_id, updatedAt=utcnow()))
        else:
            content.materialText = payload.materialText
            content.updatedById = editor_id

    if "vocabulary" in set_fields:
        vocabulary = payload.vocabulary or []
        # A word may only belong to one lesson of the course. Reject the
        # whole save (rather than silently dropping a word) and name the
        # lesson the word already lives in, so the admin knows where to look.
        keys = [normalize_word(item.german) for item in vocabulary]
        seen: dict[str, int] = {}
        duplicate_in_payload = None
        for i, key in enumerate(keys):
            if key in seen:
                duplicate_in_payload = key
                break
            seen[key] = i
        if duplicate_in_payload:
            word = vocabulary[keys.index(duplicate_in_payload)].german
            raise DuplicateWordError(f"Слово «{word}» указано в этом уроке дважды")

        if keys:
            clash_result = await db.execute(
                select(VocabularyItem.german, VocabularyItem.lessonId).where(
                    and_(
                        VocabularyItem.courseId == LEGACY_COURSE_ID,
                        VocabularyItem.germanKey.in_(keys),
                        VocabularyItem.lessonId != lesson_id,
                    )
                )
            )
            clashes = clash_result.all()
            if clashes:
                clash_list = "; ".join(f"«{german}» — уже в уроке «{lesson_label(lid)}»" for german, lid in clashes)
                raise DuplicateWordError(f"Это слово уже используется в другом уроке: {clash_list}")

        # Recorded pronunciations are attached to the word, so they survive a
        # full rewrite of the lesson's list.
        existing_result = await db.execute(
            select(VocabularyItem.germanKey, VocabularyItem.audioUrl).where(VocabularyItem.lessonId == lesson_id)
        )
        audio_by_key = dict(existing_result.all())

        old_rows = (await db.execute(select(VocabularyItem).where(VocabularyItem.lessonId == lesson_id))).scalars().all()
        for row in old_rows:
            await db.delete(row)
        await db.flush()

        for index, item in enumerate(vocabulary):
            german_key = normalize_word(item.german)
            pronunciation = item.pronunciation.strip() if item.pronunciation and item.pronunciation.strip() else None
            audio_url = item.audioUrl.strip() if item.audioUrl and item.audioUrl.strip() else audio_by_key.get(german_key)
            db.add(
                VocabularyItem(
                    lessonId=lesson_id,
                    german=item.german,
                    translation=item.translation,
                    pronunciation=pronunciation,
                    audioUrl=audio_url,
                    position=index,
                    germanKey=german_key,
                    courseId=LEGACY_COURSE_ID,
                )
            )

    if "questions" in set_fields:
        questions = payload.questions or []
        old_rows = (await db.execute(select(LessonQuestion).where(LessonQuestion.lessonId == lesson_id))).scalars().all()
        for row in old_rows:
            await db.delete(row)
        await db.flush()

        # Positions are per-set so each stage keeps its own ordering.
        counters: dict[str, int] = {}
        for q in questions:
            position = counters.get(q.setName, 0)
            counters[q.setName] = position + 1
            db.add(
                LessonQuestion(
                    lessonId=lesson_id,
                    setName=q.setName,
                    prompt=q.prompt,
                    options=q.options,
                    correctAnswer=q.correctAnswer,
                    position=position,
                    courseId=LEGACY_COURSE_ID,
                )
            )

    await db.commit()
    return await get_lesson_content(db, lesson_id)


async def set_legacy_lesson_media(db: AsyncSession, lesson_id: str, kind: str, url: str | None) -> dict:
    """Overrides (or clears, with url=None) the bundled video/audio file for
    a legacy lesson. Upserts because a lesson may not have a LessonContent
    row yet."""
    field = "videoUrl" if kind == "video" else "audioUrl"
    content = await db.get(LessonContent, lesson_id)
    if content is None:
        db.add(LessonContent(lessonId=lesson_id, **{field: url}, updatedAt=utcnow()))
    else:
        setattr(content, field, url)
    await db.commit()
    return await get_lesson_content(db, lesson_id)

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_staff
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.schemas.block import BlockInput, BlockQuestionsPayload, BlockUpdateInput
from app.schemas.course import CourseInput, CourseUpdateInput, LessonInput, LessonUpdateInput, MediaReuseInput, ReorderInput
from app.schemas.vocabulary import VocabularyImportPayload, VocabularyWordInput, VocabularyWordUpdateInput
from app.services import courses as svc
from app.services.content import DuplicateWordError
from app.services.vocabulary import list_categories
from app.uploads.storage import COURSE_MEDIA_DIR, WORD_AUDIO_DIR, delete_file, save_course_media, save_word_audio

router = APIRouter(prefix="/api/builder", tags=["builder"], dependencies=[Depends(require_staff)])


# ---------------------------------------------------------------------------
# Courses
# ---------------------------------------------------------------------------


@router.get("/courses")
async def list_courses(db: AsyncSession = Depends(get_db)):
    return {"courses": await svc.list_courses(db)}


@router.post("/courses", status_code=201)
async def create_course(body: CourseInput, user: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    course = await svc.create_course(db, body.title, body.description, body.status, user.id, body.levelId)
    return {"course": course}


@router.post("/courses/reorder")
async def reorder_courses(body: ReorderInput, db: AsyncSession = Depends(get_db)):
    await svc.reorder_courses(db, body.ids)
    return {"courses": await svc.list_courses(db)}


@router.get("/courses/{course_id}")
async def get_course(course_id: str, db: AsyncSession = Depends(get_db)):
    course = await svc.get_course(db, course_id)
    if not course:
        raise ApiError(404, "Курс не найден")
    return {"course": course}


@router.patch("/courses/{course_id}")
async def update_course(course_id: str, body: CourseUpdateInput, db: AsyncSession = Depends(get_db)):
    course = await svc.update_course(db, course_id, body.model_dump(exclude_unset=True))
    if not course:
        raise ApiError(404, "Курс не найден")
    return {"course": course}


@router.delete("/courses/{course_id}")
async def delete_course(course_id: str, db: AsyncSession = Depends(get_db)):
    ok = await svc.delete_course(db, course_id)
    if not ok:
        raise ApiError(404, "Курс не найден")
    return {"ok": True}


@router.post("/courses/{course_id}/cover")
async def upload_cover(course_id: str, file: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    existing = await svc.get_course(db, course_id)
    if not existing:
        raise ApiError(404, "Курс не найден")
    stored_url = await save_course_media(file)
    course = await svc.set_course_cover(db, course_id, stored_url)
    # Covers are 1:1 with a course, never shared via the library — deleted
    # unconditionally, no "still in use" check needed.
    if existing["coverUrl"]:
        delete_file(COURSE_MEDIA_DIR, existing["coverUrl"])
    return {"course": course}


@router.delete("/courses/{course_id}/cover")
async def delete_cover(course_id: str, db: AsyncSession = Depends(get_db)):
    existing = await svc.get_course(db, course_id)
    if not existing:
        raise ApiError(404, "Курс не найден")
    if existing["coverUrl"]:
        delete_file(COURSE_MEDIA_DIR, existing["coverUrl"])
    course = await svc.set_course_cover(db, course_id, None)
    return {"course": course}


# ---------------------------------------------------------------------------
# Lessons
# ---------------------------------------------------------------------------


@router.post("/courses/{course_id}/lessons", status_code=201)
async def create_lesson(course_id: str, body: LessonInput, db: AsyncSession = Depends(get_db)):
    course = await svc.create_lesson(db, course_id, body.title, body.description, body.materialText)
    if not course:
        raise ApiError(404, "Курс не найден")
    return {"course": course}


@router.post("/courses/{course_id}/lessons/reorder")
async def reorder_lessons(course_id: str, body: ReorderInput, db: AsyncSession = Depends(get_db)):
    course = await svc.reorder_lessons(db, course_id, body.ids)
    if not course:
        raise ApiError(400, "Некорректный список уроков")
    return {"course": course}


@router.patch("/courses/{course_id}/lessons/{lesson_id}")
async def update_lesson(course_id: str, lesson_id: str, body: LessonUpdateInput, db: AsyncSession = Depends(get_db)):
    course = await svc.update_lesson(db, course_id, lesson_id, body.model_dump(exclude_unset=True))
    if not course:
        raise ApiError(404, "Урок не найден")
    return {"course": course}


@router.delete("/courses/{course_id}/lessons/{lesson_id}")
async def delete_lesson(course_id: str, lesson_id: str, db: AsyncSession = Depends(get_db)):
    course = await svc.delete_lesson(db, course_id, lesson_id)
    if not course:
        raise ApiError(404, "Урок не найден")
    return {"course": course}


@router.post("/courses/{course_id}/lessons/{lesson_id}/notify", status_code=201)
async def notify_lesson(course_id: str, lesson_id: str, user: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    """Manual "Отправить уведомление" — always sends regardless of the
    auto-send setting (that toggle only gates the automatic call from
    create_lesson)."""
    from app.services import push as push_svc

    course = await svc.get_course(db, course_id)
    if not course:
        raise ApiError(404, "Курс не найден")
    lesson = next((l for l in course["lessons"] if l["id"] == lesson_id), None)
    if not lesson:
        raise ApiError(404, "Урок не найден")
    notification = await push_svc.notify_lesson_created(
        db, course_id=course_id, course_title=course["title"], lesson_id=lesson_id, lesson_title=lesson["title"], created_by_id=user.id
    )
    return {"notification": notification}


@router.post("/courses/{course_id}/lessons/{lesson_id}/media")
async def upload_lesson_media(
    course_id: str,
    lesson_id: str,
    kind: str = Form(...),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    if kind not in ("video", "audio"):
        raise ApiError(400, "Укажите тип файла: video или audio")
    existing = await svc.get_course(db, course_id)
    if not existing:
        raise ApiError(404, "Урок не найден")
    lesson = next((l for l in existing["lessons"] if l["id"] == lesson_id), None)
    if not lesson:
        raise ApiError(404, "Урок не найден")
    previous_url = lesson["videoUrl"] if kind == "video" else lesson["audioUrl"]

    stored_url = await save_course_media(file)
    course = await svc.set_lesson_media(db, course_id, lesson_id, kind, stored_url)
    # Only delete the old file if no other lesson reuses it (see
    # list_media_library) — otherwise this would silently break playback
    # wherever else it's used.
    if previous_url and not await svc.media_url_still_in_use(db, previous_url, course_lesson_id=lesson_id):
        delete_file(COURSE_MEDIA_DIR, previous_url)
    return {"course": course}


@router.delete("/courses/{course_id}/lessons/{lesson_id}/media")
async def delete_lesson_media(course_id: str, lesson_id: str, kind: str = Query(...), db: AsyncSession = Depends(get_db)):
    if kind not in ("video", "audio"):
        raise ApiError(400, "Укажите тип файла: video или audio")
    existing = await svc.get_course(db, course_id)
    if not existing:
        raise ApiError(404, "Урок не найден")
    lesson = next((l for l in existing["lessons"] if l["id"] == lesson_id), None)
    if not lesson:
        raise ApiError(404, "Урок не найден")
    previous_url = lesson["videoUrl"] if kind == "video" else lesson["audioUrl"]

    course = await svc.set_lesson_media(db, course_id, lesson_id, kind, None)
    if previous_url and not await svc.media_url_still_in_use(db, previous_url, course_lesson_id=lesson_id):
        delete_file(COURSE_MEDIA_DIR, previous_url)
    return {"course": course}


@router.put("/courses/{course_id}/lessons/{lesson_id}/media/reuse")
async def reuse_lesson_media(course_id: str, lesson_id: str, body: MediaReuseInput, db: AsyncSession = Depends(get_db)):
    library = await svc.list_media_library(db, body.kind)
    if not any(entry["url"] == body.url for entry in library):
        raise ApiError(400, "Файл не найден в библиотеке")
    course = await svc.set_lesson_media(db, course_id, lesson_id, body.kind, body.url)
    if not course:
        raise ApiError(404, "Урок не найден")
    return {"course": course}


# ---------------------------------------------------------------------------
# Library search (global — not scoped to one course)
# ---------------------------------------------------------------------------


@router.get("/words/search")
async def search_words(q: str = "", db: AsyncSession = Depends(get_db)):
    return {"words": await svc.search_word_library(db, q)}


@router.get("/media/library")
async def media_library(kind: str = Query(...), db: AsyncSession = Depends(get_db)):
    if kind not in ("video", "audio"):
        raise ApiError(400, "Укажите тип файла: video или audio")
    return {"items": await svc.list_media_library(db, kind)}


@router.get("/questions/search")
async def search_questions(q: str = "", db: AsyncSession = Depends(get_db)):
    return {"questions": await svc.search_question_library(db, q)}


@router.get("/materials/search")
async def search_materials(q: str = "", db: AsyncSession = Depends(get_db)):
    return {"materials": await svc.search_material_library(db, q)}


# ---------------------------------------------------------------------------
# Vocabulary
# ---------------------------------------------------------------------------


@router.get("/vocabulary/categories")
async def get_categories(db: AsyncSession = Depends(get_db)):
    """For a word-authoring "pick an existing category, or type a new one"
    picker (§ word cards, 2026-08-31) — every category that already exists,
    so the caller can offer them before falling back to creating a new one
    via `categoryName` on add/update."""
    return {"categories": await list_categories(db)}


@router.post("/courses/{course_id}/lessons/{lesson_id}/vocabulary", status_code=201)
async def add_vocabulary(course_id: str, lesson_id: str, body: VocabularyWordInput, db: AsyncSession = Depends(get_db)):
    try:
        result = await svc.add_vocabulary_word(
            db, course_id, lesson_id, body.german, body.translation, body.pronunciation, category_name=body.categoryName, image_url=body.imageUrl
        )
    except DuplicateWordError as e:
        raise ApiError(409, str(e))
    if not result:
        raise ApiError(404, "Урок не найден")
    return result


@router.patch("/courses/{course_id}/lessons/{lesson_id}/vocabulary/{word_id}")
async def update_vocabulary(course_id: str, lesson_id: str, word_id: str, body: VocabularyWordUpdateInput, db: AsyncSession = Depends(get_db)):
    try:
        result = await svc.update_vocabulary_word(db, course_id, lesson_id, word_id, body.model_dump(exclude_unset=True))
    except DuplicateWordError as e:
        raise ApiError(409, str(e))
    if not result:
        raise ApiError(404, "Слово не найдено")
    return result


@router.delete("/courses/{course_id}/lessons/{lesson_id}/vocabulary/{word_id}")
async def delete_vocabulary(course_id: str, lesson_id: str, word_id: str, db: AsyncSession = Depends(get_db)):
    result = await svc.delete_vocabulary_word(db, course_id, lesson_id, word_id)
    if not result:
        raise ApiError(404, "Слово не найдено")
    return result


@router.post("/courses/{course_id}/lessons/{lesson_id}/vocabulary/{word_id}/audio")
async def upload_vocabulary_audio(
    course_id: str,
    lesson_id: str,
    word_id: str,
    audio: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    stored_url = await save_word_audio(audio)
    result = await svc.set_vocabulary_word_audio(db, course_id, lesson_id, word_id, stored_url)
    if not result:
        delete_file(WORD_AUDIO_DIR, stored_url)
        raise ApiError(404, "Слово не найдено")
    if result["previousAudioUrl"]:
        delete_file(WORD_AUDIO_DIR, result["previousAudioUrl"])
    return {"ok": True}


@router.delete("/courses/{course_id}/lessons/{lesson_id}/vocabulary/{word_id}/audio")
async def delete_vocabulary_audio(course_id: str, lesson_id: str, word_id: str, db: AsyncSession = Depends(get_db)):
    result = await svc.set_vocabulary_word_audio(db, course_id, lesson_id, word_id, None)
    if not result:
        raise ApiError(404, "Слово не найдено")
    if result["previousAudioUrl"]:
        delete_file(WORD_AUDIO_DIR, result["previousAudioUrl"])
    return {"ok": True}


@router.post("/courses/{course_id}/lessons/{lesson_id}/vocabulary/import/preview")
async def preview_import(course_id: str, lesson_id: str, body: VocabularyImportPayload, db: AsyncSession = Depends(get_db)):
    preview = await svc.preview_vocabulary_import(db, course_id, lesson_id, [w.model_dump() for w in body.words])
    if preview is None:
        raise ApiError(404, "Урок не найден")
    return {"preview": preview}


@router.post("/courses/{course_id}/lessons/{lesson_id}/vocabulary/import")
async def import_vocabulary(course_id: str, lesson_id: str, body: VocabularyImportPayload, db: AsyncSession = Depends(get_db)):
    try:
        result = await svc.import_vocabulary_words(db, course_id, lesson_id, [w.model_dump() for w in body.words])
    except DuplicateWordError as e:
        raise ApiError(409, str(e))
    if result is None:
        raise ApiError(404, "Урок не найден")
    return result


# ---------------------------------------------------------------------------
# Legacy-style flat question set (superseded by blocks)
# ---------------------------------------------------------------------------


@router.put("/courses/{course_id}/lessons/{lesson_id}/questions")
async def save_questions(course_id: str, lesson_id: str, body: dict, db: AsyncSession = Depends(get_db)):
    from app.schemas.content import QuestionInput

    questions = [QuestionInput(**q).model_dump() for q in body.get("questions", [])]
    course = await svc.save_lesson_questions(db, course_id, lesson_id, questions)
    if not course:
        raise ApiError(404, "Урок не найден")
    return {"course": course}


# ---------------------------------------------------------------------------
# Question blocks
# ---------------------------------------------------------------------------


@router.post("/courses/{course_id}/lessons/{lesson_id}/blocks", status_code=201)
async def create_block(course_id: str, lesson_id: str, body: BlockInput, db: AsyncSession = Depends(get_db)):
    result = await svc.create_block(db, course_id, lesson_id, body.stage, body.title)
    if not result:
        raise ApiError(404, "Урок не найден")
    return result


@router.post("/courses/{course_id}/lessons/{lesson_id}/blocks/reorder")
async def reorder_blocks_route(course_id: str, lesson_id: str, body: dict, db: AsyncSession = Depends(get_db)):
    stage = body.get("stage")
    ids = body.get("ids", [])
    result = await svc.reorder_blocks(db, course_id, lesson_id, stage, ids)
    if not result:
        raise ApiError(400, "Некорректный список блоков")
    return result


@router.patch("/courses/{course_id}/lessons/{lesson_id}/blocks/{block_id}")
async def update_block(course_id: str, lesson_id: str, block_id: str, body: BlockUpdateInput, db: AsyncSession = Depends(get_db)):
    result = await svc.update_block(db, course_id, lesson_id, block_id, body.title)
    if not result:
        raise ApiError(404, "Блок не найден")
    return result


@router.delete("/courses/{course_id}/lessons/{lesson_id}/blocks/{block_id}")
async def delete_block(course_id: str, lesson_id: str, block_id: str, db: AsyncSession = Depends(get_db)):
    result = await svc.delete_block(db, course_id, lesson_id, block_id)
    if not result:
        raise ApiError(404, "Блок не найден")
    return result


@router.put("/courses/{course_id}/lessons/{lesson_id}/blocks/{block_id}/questions")
async def save_block_questions(course_id: str, lesson_id: str, block_id: str, body: dict, db: AsyncSession = Depends(get_db)):
    cleaned = svc.clean_questions_payload(body)
    payload = BlockQuestionsPayload(**cleaned)
    result = await svc.save_block_questions(db, course_id, lesson_id, block_id, [q.model_dump() for q in payload.questions])
    if not result:
        raise ApiError(404, "Блок не найден")
    return result

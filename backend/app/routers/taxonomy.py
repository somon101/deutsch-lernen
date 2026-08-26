from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth, require_staff
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.schemas.taxonomy import (
    AnswerSubmitInput,
    MaterialBlockInput,
    MaterialBlockReorderInput,
    MaterialInput,
    MaterialUpdateInput,
    QuestionCreateInput,
    QuestionReuseInput,
    SimilarityCheckInput,
    LevelInput,
    TopicInput,
)
from app.services import taxonomy as svc
from app.services.progress import get_lesson_progress_from_answers, get_level_progress, get_overall_progress, submit_answer

router = APIRouter(prefix="/api", tags=["taxonomy"])


def _level_dto(level) -> dict:
    return {"id": level.id, "languageId": level.languageId, "code": level.code, "name": level.name, "position": level.position}


def _topic_dto(topic) -> dict:
    return {"id": topic.id, "languageId": topic.languageId, "name": topic.name}


def _material_dto(material) -> dict:
    return {
        "id": material.id,
        "courseId": material.courseId,
        "lessonId": material.lessonId,
        "materialType": material.materialType,
        "title": material.title,
        "topicId": material.topicId,
        "position": material.position,
    }


def _material_block_dto(block) -> dict:
    return {"id": block.id, "materialId": block.materialId, "title": block.title, "content": block.content, "position": block.position}


def _placement_dto(placement) -> dict:
    return {
        "id": placement.id,
        "questionId": placement.questionId,
        "materialBlockId": placement.materialBlockId,
        "lessonBlockId": placement.lessonBlockId,
        "legacyLessonId": placement.legacyLessonId,
        "legacySetName": placement.legacySetName,
        "position": placement.position,
    }


# ---------------------------------------------------------------------------
# Language / Level / Topic
# ---------------------------------------------------------------------------


@router.get("/languages")
async def list_languages(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    languages = await svc.list_languages(db)
    return {"languages": [{"id": lang.id, "name": lang.name} for lang in languages]}


@router.get("/levels")
async def list_levels(languageId: str | None = Query(default=None), user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    levels = await svc.list_levels(db, languageId)
    return {"levels": [_level_dto(l) for l in levels]}


@router.post("/levels", status_code=201)
async def create_level(body: LevelInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    level = await svc.create_level(db, body)
    return {"level": _level_dto(level)}


@router.get("/topics")
async def list_topics(languageId: str | None = Query(default=None), user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    topics = await svc.list_topics(db, languageId)
    return {"topics": [_topic_dto(t) for t in topics]}


@router.post("/topics", status_code=201)
async def create_topic(body: TopicInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    topic, existing = await svc.create_topic(db, body)
    return {"topic": _topic_dto(topic), "existing": existing}


# ---------------------------------------------------------------------------
# Material / MaterialBlock
# ---------------------------------------------------------------------------


@router.get("/materials")
async def list_materials(lessonId: str = Query(...), user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    materials = await svc.list_materials(db, lessonId)
    return {"materials": [_material_dto(m) for m in materials]}


@router.post("/materials", status_code=201)
async def create_material(body: MaterialInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    material = await svc.create_material(db, body)
    return {"material": _material_dto(material)}


@router.patch("/materials/{material_id}")
async def update_material(material_id: str, body: MaterialUpdateInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    material = await svc.update_material(db, material_id, body)
    if not material:
        raise ApiError(404, "Материал не найден")
    return {"material": _material_dto(material)}


@router.delete("/materials/{material_id}")
async def delete_material(material_id: str, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    ok = await svc.delete_material(db, material_id)
    if not ok:
        raise ApiError(404, "Материал не найден")
    return {"ok": True}


@router.get("/materials/{material_id}/blocks")
async def list_material_blocks(material_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    blocks = await svc.list_material_blocks(db, material_id)
    return {"blocks": [_material_block_dto(b) for b in blocks]}


@router.post("/materials/{material_id}/blocks", status_code=201)
async def add_material_block(material_id: str, body: MaterialBlockInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    block = await svc.add_material_block(db, material_id, body)
    if not block:
        raise ApiError(404, "Материал не найден")
    return {"block": _material_block_dto(block)}


@router.patch("/materials/blocks/{block_id}")
async def update_material_block(block_id: str, body: MaterialBlockInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    block = await svc.update_material_block(db, block_id, body)
    if not block:
        raise ApiError(404, "Блок не найден")
    return {"block": _material_block_dto(block)}


@router.delete("/materials/blocks/{block_id}")
async def delete_material_block(block_id: str, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    ok = await svc.delete_material_block(db, block_id)
    if not ok:
        raise ApiError(404, "Блок не найден")
    return {"ok": True}


@router.put("/materials/{material_id}/blocks/reorder")
async def reorder_material_blocks(material_id: str, body: MaterialBlockReorderInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    await svc.reorder_material_blocks(db, material_id, body.blockIds)
    return {"ok": True}


@router.get("/materials/blocks/{block_id}/questions")
async def list_block_questions(block_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    rows = await svc.list_block_questions(db, block_id)
    return {"questions": [{"placementId": p.id, **svc.question_dto(q)} for p, q in rows]}


@router.delete("/placements/{placement_id}")
async def remove_placement(placement_id: str, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    ok = await svc.remove_placement(db, placement_id)
    if not ok:
        raise ApiError(404, "Связь не найдена")
    return {"ok": True}


# ---------------------------------------------------------------------------
# Reusable question pool
# ---------------------------------------------------------------------------


@router.post("/questions/similarity-check")
async def similarity_check(body: SimilarityCheckInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    draft = body.question.model_dump()
    similar = await svc.check_similarity(db, draft, body.topicId, body.materialId)
    return {
        "similar": [
            {"questionId": s["question"].id, "question": svc.question_dto(s["question"]), "score": s["score"]} for s in similar
        ]
    }


@router.get("/questions/search")
async def search_questions(
    query: str = Query(default=""),
    topicId: str | None = Query(default=None),
    kind: str | None = Query(default=None),
    admin: User = Depends(require_staff),
    db: AsyncSession = Depends(get_db),
):
    results = await svc.search_questions(db, query, topicId, kind)
    return {"questions": [svc.question_dto(q) for q in results]}


@router.post("/questions", status_code=201)
async def create_question(body: QuestionCreateInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    question, similar = await svc.create_question(db, body)
    return {"question": svc.question_dto(question), "similarWarnings": similar}


@router.post("/questions/reuse", status_code=201)
async def reuse_question(body: QuestionReuseInput, admin: User = Depends(require_staff), db: AsyncSession = Depends(get_db)):
    placement = await svc.reuse_question(db, body)
    if not placement:
        raise ApiError(404, "Вопрос не найден")
    return {"placement": _placement_dto(placement)}


# ---------------------------------------------------------------------------
# Per-question answers + progress
# ---------------------------------------------------------------------------


@router.post("/me/answers", status_code=201)
async def submit_answer_route(body: AnswerSubmitInput, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    log = await submit_answer(db, user.id, body.questionId, body.placementId, body.answerData, body.correct)
    if not log:
        raise ApiError(404, "Вопрос не найден")
    return {"ok": True}


@router.get("/me/progress/lesson/{lesson_id}")
async def lesson_progress_route(lesson_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    progress = await get_lesson_progress_from_answers(db, lesson_id, user.id)
    return {"progress": progress}


@router.get("/me/progress/level/{level_id}")
async def level_progress_route(level_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    progress = await get_level_progress(db, user.id, level_id)
    if progress is None:
        raise ApiError(404, "Уровень не найден")
    return {"progress": progress}


@router.get("/me/progress/overall")
async def overall_progress_route(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    progress = await get_overall_progress(db, user.id)
    return {"progress": progress}

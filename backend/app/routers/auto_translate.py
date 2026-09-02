from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services.auto_translate import generate_translate_question, grade_translate_answer
from app.services.word_pool import word_pool_size

router = APIRouter(prefix="/api/questions", tags=["auto-translate"])


@router.get("/{question_id}/translate/{slot_index}")
async def generate_translate_route(question_id: str, slot_index: int, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """One generated question for this slot, resolved against the learner's
    own pool for this session. Nothing is written here — generating is not
    answering."""
    result = await generate_translate_question(db, question_id, slot_index, user.id)
    if result is None:
        raise ApiError(404, "Не удалось сформировать вопрос")
    return result


class TranslateAnswerInput(BaseModel):
    generatedQuestionId: str
    selectedText: str
    placementId: str | None = None


@router.post("/{question_id}/translate/answer", status_code=201)
async def submit_translate_answer_route(
    question_id: str, body: TranslateAnswerInput, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)
):
    """The server re-reads the signed question to decide `correct`, then
    records it through the same submit_answer every other exercise uses."""
    result = await grade_translate_answer(
        db, user_id=user.id, question_id=question_id, token=body.generatedQuestionId, selected_text=body.selectedText, placement_id=body.placementId
    )
    if result is None:
        raise ApiError(400, "Некорректный или просроченный вопрос")
    return result


word_pool_router = APIRouter(prefix="/api/word-pools", tags=["auto-translate"])


@word_pool_router.get("/size")
async def word_pool_size_route(
    source: str, lessonId: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)
):
    """How many distinct words a source can currently offer, so the builder
    can tell the teacher what the ceiling is. Advisory only — the count is
    still validated server-side on save, and the real cap is applied when
    the exercise is generated."""
    return {"source": source, "lessonId": lessonId, "size": await word_pool_size(db, source=source, user_id=user.id, lesson_id=lessonId)}

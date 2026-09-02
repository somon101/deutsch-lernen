from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services.auto_match import generate_match_question, grade_match_answer, today_pool_breakdown

router = APIRouter(prefix="/api/questions", tags=["auto-match"])


@router.get("/{question_id}/match")
async def generate_match_route(question_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """One generated matching exercise, resolved against this learner's own
    pool for this session. Nothing is written here."""
    result = await generate_match_question(db, question_id, user.id)
    if result is None:
        raise ApiError(404, "Не удалось сформировать упражнение")
    return result


class MatchPairInput(BaseModel):
    wordId: str
    right: str


class MatchAnswerInput(BaseModel):
    generatedQuestionId: str
    pairs: list[MatchPairInput]
    placementId: str | None = None


@router.post("/{question_id}/match/answer", status_code=201)
async def submit_match_answer_route(question_id: str, body: MatchAnswerInput, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """The server re-reads the signed pairs to decide `correct`, then records
    it through the same submit_answer every other exercise uses."""
    result = await grade_match_answer(
        db,
        user_id=user.id,
        question_id=question_id,
        token=body.generatedQuestionId,
        pairs=[p.model_dump() for p in body.pairs],
        placement_id=body.placementId,
    )
    if result is None:
        raise ApiError(400, "Некорректное или просроченное упражнение")
    return result


breakdown_router = APIRouter(prefix="/api/word-pools", tags=["auto-match"])


@breakdown_router.get("/match-breakdown")
async def match_breakdown_route(lessonId: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """How this learner's pool splits between "learned today and still free"
    and everything earlier — shown in the builder as a hint, and the plainest
    way to see the selection rule actually working."""
    return await today_pool_breakdown(db, user_id=user.id, lesson_id=lessonId)

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services.auto_blank import generate_blank_question, grade_blank_answer

router = APIRouter(prefix="/api/questions", tags=["auto-blank"])


@router.get("/{question_id}/blank/{phrase_index}")
async def generate_blank_route(question_id: str, phrase_index: int, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """Generates ONE version of this phrase slot — the blanked word and the
    wrong-answer options are fresh and random every call (§8/§10), and
    nothing here is written to the database (§11/§12: generating a
    question is not the same as answering it)."""
    result = await generate_blank_question(db, question_id, phrase_index, user.id)
    if result is None:
        raise ApiError(404, "Не удалось сформировать вопрос")
    return result


class BlankAnswerInput(BaseModel):
    generatedQuestionId: str
    selectedText: str
    placementId: str | None = None


@router.post("/{question_id}/blank/answer", status_code=201)
async def submit_blank_answer_route(question_id: str, body: BlankAnswerInput, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """The server, not the client, decides `correct` (§25) — it re-reads
    the signed `generatedQuestionId` rather than trusting anything else in
    the request body. Writes one AnswerLog row via the same submit_answer
    every other exercise kind already uses (§13/§14/§26)."""
    result = await grade_blank_answer(
        db, user_id=user.id, question_id=question_id, token=body.generatedQuestionId, selected_text=body.selectedText, placement_id=body.placementId
    )
    if result is None:
        raise ApiError(400, "Некорректный или просроченный вопрос")
    return result

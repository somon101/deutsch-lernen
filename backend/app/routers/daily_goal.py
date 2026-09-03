from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.models.user import User
from app.schemas.daily_goal import DailyGoalInput
from app.services import daily_goal as svc

router = APIRouter(prefix="/api/me/daily-goal", tags=["daily-goal"])


class GoalResponse(BaseModel):
    goalMinutes: int


@router.get("")
async def get_daily_goal_route(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """Today's goal, today's measured study time, and whether the reward has
    been paid. Reading also settles a reward that became due while nothing
    was asking — evaluate() is idempotent, so a GET can never pay twice."""
    return await svc.evaluate(db, user.id)


@router.put("")
async def set_daily_goal_route(body: DailyGoalInput, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """Changes the goal, then re-evaluates.

    Re-evaluating matters: lowering the goal to something today's study time
    already exceeds should complete the day then and there, without waiting
    for the next time report. It cannot pay twice — a day that has already
    been rewarded keeps its one row, whatever the goal is changed to
    afterwards.
    """
    await svc.set_goal_minutes(db, user.id, body.dailyGoalMinutes)
    return await svc.evaluate(db, user.id)

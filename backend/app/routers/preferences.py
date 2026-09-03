from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Literal

from app.auth.deps import require_auth
from app.db import get_db
from app.models.user import User
from app.services import preferences as svc

router = APIRouter(prefix="/api/me/preferences", tags=["preferences"])


class PreferencesPatch(BaseModel):
    """Every field optional, so a client changes one switch without having to
    restate the others — and cannot overwrite a setting it never touched with
    a stale copy of its own.

    The goal keeps the same Literal the daily-goal endpoint uses, so there is
    one definition of "an allowed goal" no matter which route sets it.
    """

    dailyGoalMinutes: Literal[3, 5, 10, 15, 20] | None = None
    lessonSoundEnabled: bool | None = None
    wordAudioEnabled: bool | None = None


@router.get("")
async def get_preferences_route(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return await svc.get_preferences(db, user.id)


@router.patch("")
async def patch_preferences_route(body: PreferencesPatch, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """`exclude_unset` is what makes this a partial update: a field the
    client did not send is absent from `changes`, not present as None."""
    return await svc.update_preferences(db, user.id, body.model_dump(exclude_unset=True))

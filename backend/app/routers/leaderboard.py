from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.models.user import User
from app.services.leaderboard import get_leaderboard, get_my_rank_summary

router = APIRouter(prefix="/api", tags=["leaderboard"])

_TOP_N = 100


def _entry_dto(row: dict) -> dict:
    return {
        "userId": row["userId"],
        "firstName": row["firstName"],
        "lastName": row["lastName"],
        "username": row["username"],
        "avatarUrl": row["avatarUrl"],
        "points": row["points"],
        "rank": row["rank"],
    }


@router.get("/leaderboard")
async def leaderboard_route(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    entries, total = await get_leaderboard(db, limit=_TOP_N)
    return {"entries": [_entry_dto(r) for r in entries], "total": total}


@router.get("/me/rank")
async def my_rank_route(user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return await get_my_rank_summary(db, user.id)

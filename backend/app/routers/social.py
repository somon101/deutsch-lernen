from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services.social import follow_user, get_user_profile, search_users

router = APIRouter(prefix="/api/users", tags=["social"])


@router.get("/search")
async def search_users_route(q: str = Query(default=""), user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    """By username (substring) or publicId (exact) — the same 9-digit code
    already shown on the QR-share card, not the internal UUID id, which
    nobody could realistically type in."""
    return {"users": await search_users(db, q)}


@router.get("/{user_id}/profile")
async def get_user_profile_route(user_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    profile = await get_user_profile(db, user_id, viewer_id=user.id)
    if not profile:
        raise ApiError(404, "Пользователь не найден")
    return profile


@router.post("/{user_id}/follow", status_code=201)
async def follow_user_route(user_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return await follow_user(db, follower_id=user.id, following_id=user_id)

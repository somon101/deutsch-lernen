from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_auth
from app.db import get_db
from app.errors import ApiError
from app.models.user import User
from app.services.social import (
    follow_user,
    get_user_profile,
    get_user_stats,
    list_followers,
    list_following,
    list_mutual,
    search_users,
    unfollow_user,
)

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


@router.delete("/{user_id}/follow")
async def unfollow_user_route(user_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return await unfollow_user(db, follower_id=user.id, following_id=user_id)


@router.get("/{user_id}/followers")
async def list_followers_route(user_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return {"users": await list_followers(db, user_id)}


@router.get("/{user_id}/following")
async def list_following_route(user_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return {"users": await list_following(db, user_id)}


@router.get("/{user_id}/mutual")
async def list_mutual_route(user_id: str, user: User = Depends(require_auth), db: AsyncSession = Depends(get_db)):
    return {"users": await list_mutual(db, user_id)}


@router.get("/{user_id}/stats")
async def get_user_stats_route(
    user_id: str,
    languageId: str | None = Query(default=None),
    user: User = Depends(require_auth),
    db: AsyncSession = Depends(get_db),
):
    """The same real progress/time/streak/points/activity a profile shows
    about its own owner (§ subscriptions follow-up, 2026-08-30) — available
    for any user id since it's the same data the leaderboard/search already
    make visible, just gathered into one place for a profile screen."""
    target = await db.get(User, user_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")
    return await get_user_stats(db, user_id, languageId)

"""Follows/subscriptions (§ subscriptions, 2026-08-30) — a small, new,
self-contained concern, same shape as leaderboard.py: one new table
(Follow), everything else (counts, mutual-ness) computed fresh from it on
every read, exactly like progress/time/streak/points already work. Search
is by username (substring) or publicId (exact) — the existing
human-shareable identifier from the QR-card feature, not the internal
UUID id, which nobody could realistically type in.
"""

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.follow import Follow
from app.models.user import User

_SEARCH_LIMIT = 20


def _public_user_dto(user: User) -> dict:
    """Safe-to-show-to-anyone fields — deliberately NOT serialize.public_user
    (that one includes email/phone/birthDate, fine for a user reading their
    own account, never appropriate to hand back about a different user)."""
    return {
        "id": user.id,
        "publicId": user.publicId,
        "firstName": user.firstName,
        "lastName": user.lastName,
        "username": user.username,
        "avatarUrl": user.avatarUrl,
    }


async def is_following(db: AsyncSession, follower_id: str, following_id: str) -> bool:
    return (
        await db.execute(select(Follow.id).where(Follow.followerId == follower_id, Follow.followingId == following_id))
    ).scalar_one_or_none() is not None


async def get_follow_counts(db: AsyncSession, user_id: str) -> dict:
    followers = (await db.execute(select(func.count()).select_from(Follow).where(Follow.followingId == user_id))).scalar_one()
    following = (await db.execute(select(func.count()).select_from(Follow).where(Follow.followerId == user_id))).scalar_one()

    following_ids = (await db.execute(select(Follow.followingId).where(Follow.followerId == user_id))).scalars().all()
    if following_ids:
        mutual = (
            await db.execute(
                select(func.count())
                .select_from(Follow)
                .where(Follow.followerId.in_(following_ids), Follow.followingId == user_id)
            )
        ).scalar_one()
    else:
        mutual = 0

    return {"followers": followers, "following": following, "mutual": mutual}


async def get_user_profile(db: AsyncSession, user_id: str, viewer_id: str) -> dict | None:
    """The profile shape both "my own profile" (StatRow) and "someone else's
    profile" (leaderboard tap-through) use — `isSelf`/`isFollowing` are
    relative to `viewer_id`, the currently-authenticated caller."""
    user = await db.get(User, user_id)
    if not user:
        return None
    counts = await get_follow_counts(db, user_id)
    is_self = user_id == viewer_id
    return {
        **_public_user_dto(user),
        "followersCount": counts["followers"],
        "followingCount": counts["following"],
        "mutualCount": counts["mutual"],
        "isSelf": is_self,
        "isFollowing": False if is_self else await is_following(db, viewer_id, user_id),
    }


async def follow_user(db: AsyncSession, follower_id: str, following_id: str) -> dict:
    """Idempotent — a second "Подписаться" on an already-followed user just
    returns the current state rather than erroring or duplicating (§2/§6,
    2026-08-30: no duplicate subscriptions)."""
    if follower_id == following_id:
        raise ApiError(400, "Нельзя подписаться на самого себя")
    target = await db.get(User, following_id)
    if not target:
        raise ApiError(404, "Пользователь не найден")

    if not await is_following(db, follower_id, following_id):
        db.add(Follow(followerId=follower_id, followingId=following_id))
        await db.commit()

    return await get_user_profile(db, following_id, follower_id)


async def search_users(db: AsyncSession, query: str) -> list[dict]:
    q = query.strip()
    if len(q) < 2:
        return []
    stmt = select(User).where(or_(User.username.ilike(f"%{q}%"), User.publicId == q)).limit(_SEARCH_LIMIT)
    users = (await db.execute(stmt)).scalars().all()
    return [_public_user_dto(u) for u in users]

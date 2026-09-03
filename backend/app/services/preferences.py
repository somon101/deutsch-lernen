"""Account-level user preferences (§ sound settings, 2026-09-03).

The UserPreference row already existed for the daily goal; this is the
general way to read and change everything on it. Settings that live here
follow the account rather than the device, which is the whole reason for
moving them off the phone's own SharedPreferences.

Partial updates only: a PATCH names the settings it means to change and
leaves the rest alone. A client that sends the whole object would otherwise
overwrite, with its own stale copy, a setting changed a moment earlier on
another device.
"""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.daily_goal import UserPreference
from app.services.daily_goal import DEFAULT_GOAL_MINUTES, is_allowed_goal

# What a user who has never opened Settings gets. Both sounds on, because
# that is exactly how the app behaved before these switches existed — adding
# a setting must not silently change anyone's experience.
DEFAULTS = {
    "dailyGoalMinutes": DEFAULT_GOAL_MINUTES,
    "lessonSoundEnabled": True,
    "wordAudioEnabled": True,
}


def _serialize(row: UserPreference | None) -> dict:
    if row is None:
        return dict(DEFAULTS)
    return {
        # A stored goal outside the allowed set is not a goal anyone picked
        # (it can only predate the rule, or have been written by hand), so it
        # reads as the default rather than being honoured.
        "dailyGoalMinutes": row.dailyGoalMinutes if is_allowed_goal(row.dailyGoalMinutes) else DEFAULT_GOAL_MINUTES,
        "lessonSoundEnabled": bool(row.lessonSoundEnabled),
        "wordAudioEnabled": bool(row.wordAudioEnabled),
    }


async def get_preferences(db: AsyncSession, user_id: str) -> dict:
    row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one_or_none()
    return _serialize(row)


async def update_preferences(db: AsyncSession, user_id: str, changes: dict) -> dict:
    """Applies only the keys actually present in `changes`.

    Validation has already happened in the schema — the values arriving here
    are booleans, and the goal is one of the five allowed numbers.
    """
    row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one_or_none()
    if row is None:
        row = UserPreference(userId=user_id, **DEFAULTS)
        db.add(row)

    for field in ("dailyGoalMinutes", "lessonSoundEnabled", "wordAudioEnabled"):
        if field in changes:
            setattr(row, field, changes[field])

    await db.commit()
    await db.refresh(row)
    return _serialize(row)

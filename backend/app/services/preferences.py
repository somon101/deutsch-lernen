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

from zoneinfo import available_timezones

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.daily_goal import UserPreference
from app.services.daily_goal import DEFAULT_GOAL_MINUTES, is_allowed_goal

# What a user who has never opened Settings gets. Both sounds on, because
# that is exactly how the app behaved before these switches existed — adding
# a setting must not silently change anyone's experience. pushEnabled/
# lessonReminderEnabled/lessonReminderHour/lessonReminderMinute mirror
# SettingsPrefs.defaults in the (now-retired for these fields) frontend
# settings_repository.dart exactly, so migrating a user who never touches
# Settings again changes nothing about what they'd see.
DEFAULTS = {
    "dailyGoalMinutes": DEFAULT_GOAL_MINUTES,
    "lessonSoundEnabled": True,
    "wordAudioEnabled": True,
    "pushEnabled": True,
    "lessonReminderEnabled": False,
    "lessonReminderHour": 19,
    "lessonReminderMinute": 0,
    "timezone": None,
}

_FIELDS = ("dailyGoalMinutes", "lessonSoundEnabled", "wordAudioEnabled", "pushEnabled", "lessonReminderEnabled", "lessonReminderHour", "lessonReminderMinute", "timezone")

# Computed once at import time — available_timezones() reads a data file
# every call; nothing about the valid IANA name set changes while the
# process is running.
_VALID_TIMEZONES = available_timezones()


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
        "pushEnabled": bool(row.pushEnabled),
        "lessonReminderEnabled": bool(row.lessonReminderEnabled),
        "lessonReminderHour": row.lessonReminderHour,
        "lessonReminderMinute": row.lessonReminderMinute,
        "timezone": row.timezone,
    }


async def get_preferences(db: AsyncSession, user_id: str) -> dict:
    row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one_or_none()
    return _serialize(row)


async def update_preferences(db: AsyncSession, user_id: str, changes: dict) -> dict:
    """Applies only the keys actually present in `changes`.

    Validation has already happened in the schema for every field except
    `timezone` — a plain string that has to be checked against the real IANA
    database here, since pydantic has no built-in "is this a real zone name"
    type. An unrecognized value is rejected outright rather than silently
    stored: a bad timezone would otherwise make the reminder tick either
    skip the user forever or compute the wrong local time for them.
    """
    if "timezone" in changes and changes["timezone"] not in _VALID_TIMEZONES:
        raise ApiError(400, f"Неизвестный часовой пояс: {changes['timezone']!r}")

    row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one_or_none()
    creating = row is None
    if row is None:
        row = UserPreference(userId=user_id, **DEFAULTS)
        db.add(row)

    for field in _FIELDS:
        if field in changes:
            setattr(row, field, changes[field])

    if not creating:
        await db.commit()
        await db.refresh(row)
        return _serialize(row)

    # Only a first-ever preferences write for this user can race: two
    # requests both see "no row yet" and both try to INSERT one, but
    # UserPreference_userId_key allows exactly one to succeed. Found by the
    # sound-preferences concurrency test — two tabs each flipping a
    # different switch for the very first time hit this. Same shape as
    # daily_goal.evaluate's own award-insert race: the loser rolls back and
    # re-applies its own change on top of the row the winner just created,
    # rather than losing the change or surfacing a raw 500.
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one()
        for field in _FIELDS:
            if field in changes:
                setattr(row, field, changes[field])
        await db.commit()

    await db.refresh(row)
    return _serialize(row)

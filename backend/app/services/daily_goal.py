"""The daily study goal (§ daily goal, 2026-09-03).

The learner picks how many minutes a day they mean to study; the system
counts the study time they actually accumulate that day, and pays a one-off
bonus the first time the day's total reaches the goal.

Three deliberate decisions the rest of this module rests on:

1. Study time is NOT measured here. It is read from ActivityTime, the table
   the lesson runner already fills — per vocabulary card, per material
   section, per exercise, and (for video and audio) only while the media is
   actually playing, each with its own per-unit ceiling. A second timer
   would produce a second, disagreeing answer to "how long did they study
   today", and would be the easier of the two to inflate.

2. The day is the UTC calendar day, because that is what ActivityTime,
   DailyActivity, the streak and the weekly-activity card already use. A
   local-time day here would mean two different notions of "today" inside
   one app — a goal met on a day whose streak did not count. Moving all of
   them to a per-user timezone is a coherent change; moving one is not.

3. Paying the reward is a plain INSERT protected by a UNIQUE index, never a
   read-then-write. Two requests can both read "not yet awarded" before
   either writes; only one of them can insert.

Only a time-based goal exists today. The shape here — chosen goal, measured
progress, completion, one-off reward — is what another kind of goal (words
learned, exercises answered) would slot into by replacing the "measured
progress" step, which is why that step is its own function.
"""

from datetime import date

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import ApiError
from app.models.activity_time import ActivityTime
from app.models.daily_goal import DailyGoalAward, UserPreference
from app.utils import utcnow

# The only goals a learner may choose. Enforced by the schema on the way in
# and again here, so a value smuggled past the form still cannot take effect.
ALLOWED_GOAL_MINUTES: tuple[int, ...] = (3, 5, 10, 15, 20)

# Points paid for completing each goal. Business logic, not a display table:
# nothing in the frontend decides what a completed goal is worth.
GOAL_POINTS: dict[int, int] = {3: 5, 5: 10, 10: 20, 15: 30, 20: 50}

DEFAULT_GOAL_MINUTES = 10


def is_allowed_goal(minutes: object) -> bool:
    """bool is excluded explicitly — in Python it would otherwise pass as an
    int, and True would read as the goal 1."""
    if isinstance(minutes, bool) or not isinstance(minutes, int):
        return False
    return minutes in ALLOWED_GOAL_MINUTES


def today_utc() -> date:
    return utcnow().date()


# ---------------------------------------------------------------------------
# The chosen goal
# ---------------------------------------------------------------------------


async def get_goal_minutes(db: AsyncSession, user_id: str) -> int:
    row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one_or_none()
    if row is None or not is_allowed_goal(row.dailyGoalMinutes):
        # A missing row simply means "never chose one". A stored value outside
        # the allowed set can only come from data written before this rule
        # existed, or by hand; either way it is not a goal the learner picked,
        # so it reads as the default rather than being honoured.
        return DEFAULT_GOAL_MINUTES
    return row.dailyGoalMinutes


async def set_goal_minutes(db: AsyncSession, user_id: str, minutes: int) -> int:
    if not is_allowed_goal(minutes):
        raise ApiError(400, "Недопустимая цель. Выберите 3, 5, 10, 15 или 20 минут")
    row = (await db.execute(select(UserPreference).where(UserPreference.userId == user_id))).scalar_one_or_none()
    if row is None:
        db.add(UserPreference(userId=user_id, dailyGoalMinutes=minutes))
    else:
        row.dailyGoalMinutes = minutes
    await db.commit()
    return minutes


# ---------------------------------------------------------------------------
# Measured progress
# ---------------------------------------------------------------------------


async def seconds_studied_on(db: AsyncSession, user_id: str, day: date) -> int:
    """Study seconds recorded for this user on one calendar day, across every
    language and course — the same all-languages scope the streak and the
    weekly-activity card use, so switching language never changes it."""
    total = (
        await db.execute(select(func.sum(ActivityTime.seconds)).where(ActivityTime.userId == user_id, ActivityTime.activityDate == day))
    ).scalar_one()
    return int(total or 0)


# ---------------------------------------------------------------------------
# The one-off reward
# ---------------------------------------------------------------------------


async def get_award(db: AsyncSession, user_id: str, day: date) -> DailyGoalAward | None:
    return (
        await db.execute(select(DailyGoalAward).where(DailyGoalAward.userId == user_id, DailyGoalAward.awardDate == day))
    ).scalar_one_or_none()


async def evaluate(db: AsyncSession, user_id: str) -> dict:
    """The whole feature in one call: where today stands, and pay the reward
    if this is the moment it became due.

    Safe to call as often as anything likes — after a time report, when the
    goal changes, or when a screen simply asks. Calling it a hundred times
    after the goal is met pays nothing further.
    """
    day = today_utc()
    goal_minutes = await get_goal_minutes(db, user_id)
    seconds = await seconds_studied_on(db, user_id, day)
    goal_seconds = goal_minutes * 60

    existing = await get_award(db, user_id, day)
    awarded_now = 0

    if existing is None and seconds >= goal_seconds:
        points = GOAL_POINTS[goal_minutes]
        db.add(
            DailyGoalAward(
                userId=user_id,
                awardDate=day,
                goalMinutes=goal_minutes,
                points=points,
                secondsAtAward=seconds,
            )
        )
        try:
            await db.commit()
            awarded_now = points
            existing = await get_award(db, user_id, day)
        except IntegrityError:
            # Someone else inserted today's row between our read and our
            # write — a second tab, a second device, a second server
            # instance. Their row is as valid as ours would have been, so
            # roll back and report theirs. This is exactly the case a
            # read-then-write check cannot cover.
            await db.rollback()
            existing = await get_award(db, user_id, day)
            awarded_now = 0

    return {
        "date": day.isoformat(),
        "goalMinutes": goal_minutes,
        "goalSeconds": goal_seconds,
        "secondsToday": seconds,
        # Capped so a progress bar never reads 130%. `secondsToday` above
        # keeps the uncapped truth for anything that needs it.
        "progressSeconds": min(seconds, goal_seconds),
        "completed": existing is not None,
        "pointsAwarded": existing.points if existing else 0,
        "awardedGoalMinutes": existing.goalMinutes if existing else None,
        "pointsAwardedNow": awarded_now,
    }


async def total_award_points(db: AsyncSession) -> dict[str, int]:
    """Daily-goal points per user, for the leaderboard to fold into the score
    it already computes. Kept here rather than in leaderboard.py so this
    module owns every rule about what a daily goal is worth."""
    rows = (await db.execute(select(DailyGoalAward.userId, func.sum(DailyGoalAward.points)).group_by(DailyGoalAward.userId))).all()
    return {user_id: int(points or 0) for user_id, points in rows}

"""Global points leaderboard (§ rating system, 2026-08-30) — deliberately a
new, small, self-contained service: points/ranking is a new concern, but
every number it uses comes from data that already exists (AnswerLog,
LessonState). No new points-earning triggers, no new storage of history —
points are computed fresh from the existing log every time, exactly like
progress/time/streak already are.

Points formula (confirmed with the project owner, since no points system
existed to reuse): 10 points per distinct correctly-answered "scoring unit"
(the same latest-answer-wins idea used everywhere else in progress.py, keyed
per QuestionPlacement — or per bare LessonQuestion when there's no
placement, since those aren't reusable to begin with) + 50 points per
lesson the user has actually completed (LessonState.completedAt not null,
the same field CompleteStage already sets). Deliberately global across every
language — a language switch (Главное screen or the profile's own progress
language) never touches this.

Period tabs (§ leaderboard periods, 2026-09-04): day/week/month rank by
points EARNED inside that window, not cumulative all-time points as of its
end — `_period_since` turns a period name into the matching lower bound
(UTC calendar day/ISO week/calendar month, same "UTC calendar day" convention
daily_goal.py already uses), and `_points_by_user` gained a `since` alongside
the pre-existing `as_of` to filter every source table by it. `as_of` alone
(no `since`) stays exactly what it was: a historical "as of a point in time"
cumulative snapshot, still used unchanged by get_my_rank_summary's own
week-old comparison. Leagues would be a `.where(User.leagueId == ...)` added
to `_ranked_users`'s own user query - the points computation underneath
doesn't change either way.
"""

from datetime import datetime, time, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.answer_log import AnswerLog
from app.models.lesson_state import LessonState
from app.models.question import Question
from app.models.user import User
from app.services import daily_goal
from app.utils import utcnow

_POINTS_PER_CORRECT_ANSWER = 10
_POINTS_PER_COMPLETED_LESSON = 50


def _period_since(period: str, now: datetime) -> datetime | None:
    """Lower bound for `period`'s window, ending at `now` — None for
    "allTime" (unbounded, the original behavior). Weeks start Monday, months
    start on the 1st, both in UTC, matching the UTC-calendar-day convention
    `daily_goal.py` already documents."""
    start_of_today = datetime.combine(now.date(), time.min, tzinfo=now.tzinfo)
    if period == "day":
        return start_of_today
    if period == "week":
        return start_of_today - timedelta(days=now.weekday())
    if period == "month":
        return start_of_today.replace(day=1)
    return None


async def _points_by_user(db: AsyncSession, since: datetime | None = None, as_of: datetime | None = None) -> dict[str, int]:
    answer_query = select(AnswerLog.userId, AnswerLog.placementId, AnswerLog.questionId, AnswerLog.correct, AnswerLog.answerData).order_by(
        AnswerLog.createdAt.asc()
    )
    if as_of is not None:
        answer_query = answer_query.where(AnswerLog.createdAt <= as_of)
    if since is not None:
        answer_query = answer_query.where(AnswerLog.createdAt >= since)
    answer_rows = (await db.execute(answer_query)).all()

    # An auto_blank Question's phrases (§ auto blank, 2026-08-31) all share
    # ONE placement, so `placement_id or question_id` alone would collapse
    # every phrase of the same question into a single scoring unit - fold
    # in the phraseIndex every auto_blank AnswerLog.answerData carries so
    # each phrase still earns its own points, same as any other question.
    auto_blank_ids = set((await db.execute(select(Question.id).where(Question.kind == "auto_blank"))).scalars().all())

    # Latest answer per (user, scoring unit) wins — same principle
    # _weighted_progress_for_scope uses per lesson, just applied globally:
    # a placement is already scoped to exactly one lesson on its own, so
    # this gives the identical count a per-lesson loop would, without one.
    latest: dict[tuple[str, str], bool] = {}
    for user_id, placement_id, question_id, correct, answer_data in answer_rows:
        unit = placement_id or question_id
        if question_id in auto_blank_ids and isinstance(answer_data, dict):
            unit = f"{unit}::{answer_data.get('phraseIndex')}"
        key = (user_id, unit)
        latest[key] = correct

    correct_counts: dict[str, int] = {}
    for (user_id, _unit), correct in latest.items():
        if correct:
            correct_counts[user_id] = correct_counts.get(user_id, 0) + 1

    completed_query = select(LessonState.userId, func.count()).where(LessonState.completedAt.is_not(None))
    if as_of is not None:
        completed_query = completed_query.where(LessonState.completedAt <= as_of)
    if since is not None:
        completed_query = completed_query.where(LessonState.completedAt >= since)
    completed_query = completed_query.group_by(LessonState.userId)
    completed_by_user = dict((await db.execute(completed_query)).all())

    # Daily-goal bonuses are the one part of the score that IS stored rather
    # than derived (§ daily goal, 2026-09-03): "reward paid once" is a fact
    # about a moment, and cannot be recomputed from the answer log. Folded in
    # here so the app still has a single points number rather than a second,
    # parallel one. `DailyGoalAward` carries a date, not the finer timestamp
    # the rest of this function compares against, so a bare historical
    # `as_of` snapshot (get_my_rank_summary's week-old comparison) still
    # ignores bonuses rather than dating them wrongly — but a real `since`
    # window (a period tab) bounds it by date, same as everything else here.
    if since is not None:
        award_points = await daily_goal.total_award_points(db, since=since.date(), as_of=as_of.date() if as_of is not None else None)
    elif as_of is None:
        award_points = await daily_goal.total_award_points(db)
    else:
        award_points = {}

    points: dict[str, int] = {}
    for user_id in set(correct_counts) | set(completed_by_user) | set(award_points):
        points[user_id] = (
            correct_counts.get(user_id, 0) * _POINTS_PER_CORRECT_ANSWER
            + completed_by_user.get(user_id, 0) * _POINTS_PER_COMPLETED_LESSON
            + award_points.get(user_id, 0)
        )
    return points


async def _ranked_users(db: AsyncSession, since: datetime | None = None, as_of: datetime | None = None) -> list[dict]:
    """Every user, ranked by points (highest first); ties broken by whoever
    joined earlier, so the order is stable and deterministic rather than
    depending on incidental row order. Users with zero points are included
    (ranked last), not excluded."""
    points_by_user = await _points_by_user(db, since=since, as_of=as_of)
    users = (await db.execute(select(User.id, User.firstName, User.lastName, User.username, User.avatarUrl, User.createdAt))).all()

    rows = [
        {
            "userId": u.id,
            "firstName": u.firstName,
            "lastName": u.lastName,
            "username": u.username,
            "avatarUrl": u.avatarUrl,
            "createdAt": u.createdAt,
            "points": points_by_user.get(u.id, 0),
        }
        for u in users
    ]
    rows.sort(key=lambda r: (-r["points"], r["createdAt"]))
    for index, row in enumerate(rows):
        row["rank"] = index + 1
    return rows


async def get_leaderboard(db: AsyncSession, limit: int = 100, period: str = "allTime") -> tuple[list[dict], int]:
    """Top `limit` users by points within `period` ("day"/"week"/"month"/
    "allTime"), plus the true total participant count (which can be larger
    than `limit` — the caller still needs the real total, not just how many
    rows were returned)."""
    now = utcnow()
    since = _period_since(period, now)
    rows = await _ranked_users(db, since=since, as_of=now if since is not None else None)
    return rows[:limit], len(rows)


async def get_my_rank_summary(db: AsyncSession, user_id: str, period: str = "allTime") -> dict:
    """This user's current standing within `period`, plus how their
    ALL-TIME rank changed over the last 7 days — reconstructed from the same
    raw logs at an earlier cutoff, not a stored snapshot, since AnswerLog/
    LessonState already carry real timestamps for every event. `weeklyChange`
    is null when `period` isn't "allTime" (comparing a day/week/month rank
    now against an all-time rank a week ago wouldn't mean anything), and also
    null — not a fabricated 0 or a misleading jump — when the user had no
    points at all 7 days ago, since there's no meaningful "before" rank to
    compare against yet."""
    now = utcnow()
    since = _period_since(period, now)
    now_rows = await _ranked_users(db, since=since, as_of=now if since is not None else None)
    total = len(now_rows)
    mine_now = next((r for r in now_rows if r["userId"] == user_id), None)
    rank_now = mine_now["rank"] if mine_now else total
    points_now = mine_now["points"] if mine_now else 0

    weekly_change = None
    if period == "allTime":
        week_ago = now - timedelta(days=7)
        then_rows = await _ranked_users(db, as_of=week_ago)
        mine_then = next((r for r in then_rows if r["userId"] == user_id), None)
        if mine_then is not None and mine_then["points"] > 0:
            # Rank going DOWN in number is an improvement, so the sign is
            # flipped: was #10, now #3 -> +7.
            weekly_change = mine_then["rank"] - rank_now

    return {"rank": rank_now, "totalParticipants": total, "points": points_now, "weeklyChange": weekly_change}

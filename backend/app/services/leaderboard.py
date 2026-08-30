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

Future-proofing (§7/§8 of the request): `as_of` already makes "rank as of
a point in time" reusable for a real period filter later (day/week/month/
year - a period would just add a matching lower bound alongside `as_of`'s
upper bound, not a rewrite). Leagues would be a `.where(User.leagueId == ...)`
added to `_ranked_users`'s own user query - the points computation
underneath doesn't change either way.
"""

from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.answer_log import AnswerLog
from app.models.lesson_state import LessonState
from app.models.user import User
from app.utils import utcnow

_POINTS_PER_CORRECT_ANSWER = 10
_POINTS_PER_COMPLETED_LESSON = 50


async def _points_by_user(db: AsyncSession, as_of: datetime | None = None) -> dict[str, int]:
    answer_query = select(AnswerLog.userId, AnswerLog.placementId, AnswerLog.questionId, AnswerLog.correct).order_by(AnswerLog.createdAt.asc())
    if as_of is not None:
        answer_query = answer_query.where(AnswerLog.createdAt <= as_of)
    answer_rows = (await db.execute(answer_query)).all()

    # Latest answer per (user, scoring unit) wins — same principle
    # _weighted_progress_for_scope uses per lesson, just applied globally:
    # a placement is already scoped to exactly one lesson on its own, so
    # this gives the identical count a per-lesson loop would, without one.
    latest: dict[tuple[str, str], bool] = {}
    for user_id, placement_id, question_id, correct in answer_rows:
        key = (user_id, placement_id or question_id)
        latest[key] = correct

    correct_counts: dict[str, int] = {}
    for (user_id, _unit), correct in latest.items():
        if correct:
            correct_counts[user_id] = correct_counts.get(user_id, 0) + 1

    completed_query = select(LessonState.userId, func.count()).where(LessonState.completedAt.is_not(None))
    if as_of is not None:
        completed_query = completed_query.where(LessonState.completedAt <= as_of)
    completed_query = completed_query.group_by(LessonState.userId)
    completed_by_user = dict((await db.execute(completed_query)).all())

    points: dict[str, int] = {}
    for user_id in set(correct_counts) | set(completed_by_user):
        points[user_id] = (
            correct_counts.get(user_id, 0) * _POINTS_PER_CORRECT_ANSWER + completed_by_user.get(user_id, 0) * _POINTS_PER_COMPLETED_LESSON
        )
    return points


async def _ranked_users(db: AsyncSession, as_of: datetime | None = None) -> list[dict]:
    """Every user, ranked by points (highest first); ties broken by whoever
    joined earlier, so the order is stable and deterministic rather than
    depending on incidental row order. Users with zero points are included
    (ranked last), not excluded."""
    points_by_user = await _points_by_user(db, as_of)
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


async def get_leaderboard(db: AsyncSession, limit: int = 100) -> tuple[list[dict], int]:
    """Top `limit` users by points, plus the true total participant count
    (which can be larger than `limit` — the caller still needs the real
    total, not just how many rows were returned)."""
    rows = await _ranked_users(db)
    return rows[:limit], len(rows)


async def get_my_rank_summary(db: AsyncSession, user_id: str) -> dict:
    """This user's current standing plus how their rank changed over the
    last 7 days — reconstructed from the same raw logs at an earlier cutoff,
    not a stored snapshot, since AnswerLog/LessonState already carry real
    timestamps for every event. `weeklyChange` is null (not a fabricated 0
    or a misleading jump) when the user had no points at all 7 days ago —
    there's no meaningful "before" rank to compare against yet."""
    now_rows = await _ranked_users(db)
    total = len(now_rows)
    mine_now = next((r for r in now_rows if r["userId"] == user_id), None)
    rank_now = mine_now["rank"] if mine_now else total
    points_now = mine_now["points"] if mine_now else 0

    week_ago = utcnow() - timedelta(days=7)
    then_rows = await _ranked_users(db, as_of=week_ago)
    mine_then = next((r for r in then_rows if r["userId"] == user_id), None)

    weekly_change = None
    if mine_then is not None and mine_then["points"] > 0:
        # Rank going DOWN in number is an improvement, so the sign is
        # flipped: was #10, now #3 -> +7.
        weekly_change = mine_then["rank"] - rank_now

    return {"rank": rank_now, "totalParticipants": total, "points": points_now, "weeklyChange": weekly_change}

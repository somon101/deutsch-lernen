from collections import defaultdict
from datetime import timedelta

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.activity_time import ActivityTime
from app.models.answer_log import AnswerLog
from app.models.course import Course
from app.models.course_lesson import CourseLesson
from app.models.daily_activity import DailyActivity
from app.models.language import Language
from app.models.lesson_block import LessonBlock
from app.models.lesson_state import LessonAttempt
from app.models.lesson_question import LessonQuestion
from app.models.level import Level
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.utils import to_iso_z, utcnow


class AttemptInput:
    def __init__(
        self,
        miniTestCorrect: int,
        miniTestTotal: int,
        practiceCorrect: int,
        practiceTotal: int,
        reviewCorrect: int,
        reviewTotal: int,
    ):
        self.miniTestCorrect = miniTestCorrect
        self.miniTestTotal = miniTestTotal
        self.practiceCorrect = practiceCorrect
        self.practiceTotal = practiceTotal
        self.reviewCorrect = reviewCorrect
        self.reviewTotal = reviewTotal


def compute_score(input: AttemptInput) -> int:
    """Same idea as the existing client-side per-stage percentage in
    CompleteStage.tsx, just summed across the three scored stages instead of
    one — not a new/arbitrary formula, a direct generalization of it."""
    correct = input.miniTestCorrect + input.practiceCorrect + input.reviewCorrect
    total = input.miniTestTotal + input.practiceTotal + input.reviewTotal
    if total <= 0:
        return 0
    return round((correct / total) * 100)


async def get_progress_summary_for_user(db: AsyncSession, user_id: str) -> list[dict]:
    """Best/last/attempt-count are always derived from the attempts log,
    never stored redundantly — the log is the single source of truth."""
    result = await db.execute(
        select(LessonAttempt.lessonId, LessonAttempt.score, LessonAttempt.createdAt)
        .where(LessonAttempt.userId == user_id)
        .order_by(LessonAttempt.createdAt.asc())
    )
    by_lesson: dict[str, dict] = {}
    for lesson_id, score, created_at in result.all():
        existing = by_lesson.get(lesson_id)
        if existing is None:
            by_lesson[lesson_id] = {
                "lessonId": lesson_id,
                "attempts": 1,
                "bestScore": score,
                "lastScore": score,
                "lastAttemptAt": to_iso_z(created_at),
            }
        else:
            existing["attempts"] += 1
            existing["bestScore"] = max(existing["bestScore"], score)
            existing["lastScore"] = score  # attempts are ordered oldest -> newest
            existing["lastAttemptAt"] = to_iso_z(created_at)

    return list(by_lesson.values())


# ---------------------------------------------------------------------------
# Real, per-question progress (AnswerLog-based) — additive, parallel to the
# LessonAttempt-based summary above, which keeps working exactly as before.
# Percentages are always computed fresh from AnswerLog here, never cached as
# the sole source of truth (§23): correct / ALL questions in scope, matching
# the plan's own worked examples (§18/§21) — an unanswered question counts
# as not-yet-correct, it isn't excluded from the denominator.
# ---------------------------------------------------------------------------


async def submit_answer(
    db: AsyncSession, user_id: str, question_id: str, placement_id: str | None, answer_data, correct: bool
) -> AnswerLog | None:
    # questionId is a loose reference (§ answerlog_loose_question_ref) — it
    # names either a reusable pool Question or an old quiz LessonQuestion,
    # so accept whichever one actually exists rather than assuming one table.
    if not await db.get(Question, question_id) and not await db.get(LessonQuestion, question_id):
        return None
    prior = (
        await db.execute(select(func.count()).select_from(AnswerLog).where(AnswerLog.userId == user_id, AnswerLog.questionId == question_id))
    ).scalar_one()
    log = AnswerLog(userId=user_id, questionId=question_id, placementId=placement_id, answerData=answer_data, correct=correct, attemptNumber=prior + 1)
    db.add(log)
    await db.commit()
    await db.refresh(log)
    return log


async def _weighted_progress(db: AsyncSession, user_id: str, question_ids: list[str]) -> dict:
    """Global, cross-lesson mastery: the latest answer to a question ANYWHERE
    it was ever placed, no matter which lesson. Deliberately used only for
    Topic progress now (§ approved rule 8/9, 2026-08-27) — a Topic is a
    statistic about the knowledge itself, not about finishing one lesson's
    copy of it. Lesson/level progress use `_weighted_progress_for_scope`
    below instead, which never lets one lesson's answer count for another."""
    if not question_ids:
        return {"correct": 0, "total": 0, "answered": 0, "percent": 0, "passed": False}
    result = await db.execute(
        select(AnswerLog).where(AnswerLog.userId == user_id, AnswerLog.questionId.in_(question_ids)).order_by(AnswerLog.createdAt.asc())
    )
    # Later rows overwrite earlier ones — "correct" reflects the most recent
    # attempt at each question, i.e. current mastery, not "ever got it right
    # once".
    latest_by_question: dict[str, bool] = {}
    for log in result.scalars().all():
        latest_by_question[log.questionId] = log.correct

    total = len(question_ids)
    correct = sum(1 for v in latest_by_question.values() if v)
    percent = round((correct / total) * 100) if total else 0
    return {
        "correct": correct,
        "total": total,
        "answered": len(latest_by_question),
        "percent": percent,
        "passed": percent >= settings.pass_threshold_percent,
    }


async def _lesson_progress_scope(db: AsyncSession, lesson_id: str) -> tuple[set[str], dict[str, list[str]]]:
    """The atomic units of progress for one lesson (§ approved rule
    4/5/6, 2026-08-27):
      - quiz_question_ids: old LessonQuestion rows — always 1:1 with this
        lesson, never reusable elsewhere, so no placement scoping needed.
      - placement_ids_by_question: every reusable-pool Question placed
        ANYWHERE in this lesson (a material block, a quiz block, or the
        legacy bare-lessonId path), keyed by questionId — a question placed
        twice in the same lesson (e.g. once in Практика, once in
        Закрепление) still gets exactly ONE denominator slot, backed by
        every placement that could have been answered."""
    material_ids = (await db.execute(select(Material.id).where(Material.lessonId == lesson_id))).scalars().all()
    material_block_ids = (
        (await db.execute(select(MaterialBlock.id).where(MaterialBlock.materialId.in_(material_ids)))).scalars().all() if material_ids else []
    )
    lesson_block_ids = (await db.execute(select(LessonBlock.id).where(LessonBlock.lessonId == lesson_id))).scalars().all()

    conditions = [QuestionPlacement.legacyLessonId == lesson_id]
    if material_block_ids:
        conditions.append(QuestionPlacement.materialBlockId.in_(material_block_ids))
    if lesson_block_ids:
        conditions.append(QuestionPlacement.lessonBlockId.in_(lesson_block_ids))
    placement_rows = (
        await db.execute(
            select(QuestionPlacement.id, QuestionPlacement.questionId, Question.kind, Question.data)
            .join(Question, Question.id == QuestionPlacement.questionId)
            .where(or_(*conditions))
        )
    ).all()

    placement_ids_by_question: dict[str, list[str]] = defaultdict(list)
    for placement_id, question_id, kind, data in placement_rows:
        if kind == "auto_blank":
            # One placement, N independent learner-facing phrase slots (§
            # auto blank, 2026-08-31) - each phrase is its own denominator
            # entry, keyed the same way to_question_dtos already keys its
            # per-phrase DTO ids, so a 5-phrase question is worth 5 here,
            # not 1 (see _weighted_progress_for_scope for how the shared
            # placementId gets disambiguated back to a single phrase).
            phrase_count = len((data or {}).get("phrases", []))
            for i in range(phrase_count):
                placement_ids_by_question[f"{question_id}::{i}"].append(placement_id)
        else:
            placement_ids_by_question[question_id].append(placement_id)

    quiz_question_ids = set((await db.execute(select(LessonQuestion.id).where(LessonQuestion.lessonId == lesson_id))).scalars().all())
    return quiz_question_ids, dict(placement_ids_by_question)


async def _weighted_progress_for_scope(
    db: AsyncSession, user_id: str, quiz_question_ids: set[str], placement_ids_by_question: dict[str, list[str]]
) -> dict:
    """Same "latest answer per question wins" idea as `_weighted_progress`,
    but the AnswerLog lookup is scoped to THIS lesson's own placements — an
    answer given under a different lesson's placement of the same question
    never counts here (§ approved rule 6). Quiz questions are matched by
    `questionId` with `placementId IS NULL` (they never carry a placement,
    since they're not reusable to begin with).

    An auto_blank Question's phrases (§ auto blank, 2026-08-31) all share
    ONE placement, so `placement_ids_by_question` keys them as N separate
    "{questionId}::{phraseIndex}" scoring units that all resolve to the SAME
    placementId — the one place that's ambiguous, disambiguated below using
    the phraseIndex every auto_blank AnswerLog.answerData already carries.
    Every other kind still has exactly one scoring unit per placementId, so
    this collapses back to the original direct lookup for them."""
    total = len(quiz_question_ids) + len(placement_ids_by_question)
    if total == 0:
        return {"correct": 0, "total": 0, "answered": 0, "percent": 0, "passed": False}

    placement_to_subquestions: dict[str, list[str]] = defaultdict(list)
    for sub_id, pids in placement_ids_by_question.items():
        for pid in pids:
            placement_to_subquestions[pid].append(sub_id)

    conditions = []
    if placement_to_subquestions:
        conditions.append(AnswerLog.placementId.in_(list(placement_to_subquestions)))
    if quiz_question_ids:
        conditions.append(and_(AnswerLog.questionId.in_(quiz_question_ids), AnswerLog.placementId.is_(None)))

    latest_by_question: dict[str, bool] = {}
    if conditions:
        result = await db.execute(
            select(AnswerLog).where(AnswerLog.userId == user_id, or_(*conditions)).order_by(AnswerLog.createdAt.asc())
        )
        for log in result.scalars().all():
            subs = placement_to_subquestions.get(log.placementId)
            if subs:
                if len(subs) == 1:
                    latest_by_question[subs[0]] = log.correct
                else:
                    phrase_index = log.answerData.get("phraseIndex") if isinstance(log.answerData, dict) else None
                    sub_id = next((s for s in subs if s.endswith(f"::{phrase_index}")), None)
                    if sub_id is not None:
                        latest_by_question[sub_id] = log.correct
            elif log.questionId in quiz_question_ids:
                latest_by_question[log.questionId] = log.correct

    correct = sum(1 for v in latest_by_question.values() if v)
    percent = round((correct / total) * 100) if total else 0
    return {
        "correct": correct,
        "total": total,
        "answered": len(latest_by_question),
        "percent": percent,
        "passed": percent >= settings.pass_threshold_percent,
    }


async def get_lesson_progress_from_answers(db: AsyncSession, lesson_id: str, user_id: str) -> dict:
    quiz_question_ids, placement_ids_by_question = await _lesson_progress_scope(db, lesson_id)
    return await _weighted_progress_for_scope(db, user_id, quiz_question_ids, placement_ids_by_question)


async def get_level_progress(db: AsyncSession, user_id: str, level_id: str) -> dict | None:
    """Sums each of the level's lessons' own, already lesson-scoped results
    (§ approved rule 7) — never re-dedupes a question across lessons: if the
    same Question is placed in two lessons of this level, it contributes one
    independently-graded denominator slot per lesson, not one for the
    level."""
    level = await db.get(Level, level_id)
    if not level:
        return None
    course_ids = (await db.execute(select(Course.id).where(Course.levelId == level_id))).scalars().all()
    lesson_ids = (await db.execute(select(CourseLesson.id).where(CourseLesson.courseId.in_(course_ids)))).scalars().all() if course_ids else []

    total_correct = total_all = total_answered = 0
    for lesson_id in lesson_ids:
        p = await get_lesson_progress_from_answers(db, lesson_id, user_id)
        total_correct += p["correct"]
        total_all += p["total"]
        total_answered += p["answered"]

    percent = round((total_correct / total_all) * 100) if total_all else 0
    return {
        "correct": total_correct,
        "total": total_all,
        "answered": total_answered,
        "percent": percent,
        "passed": percent >= settings.pass_threshold_percent,
    }


async def get_overall_progress(db: AsyncSession, user_id: str, language_id: str | None = None) -> dict:
    """Only levels the user has actually started count (§22: "не учитывай
    будущие уровни, которые пользователь ещё не проходил") — a level whose
    lessons sum to zero answered questions is skipped entirely rather than
    dragging the average down with an implicit 0%.

    `language_id` (§ per-language overall progress, 2026-08-29) scopes the
    whole sum to one Language's own levels, so answers under a different
    language's courses never contribute — omitted, this is the original
    all-levels total."""
    query = select(Level)
    if language_id:
        query = query.where(Level.languageId == language_id)
    levels = (await db.execute(query)).scalars().all()
    total_correct = 0
    total_all = 0
    included = []
    for level in levels:
        progress = await get_level_progress(db, user_id, level.id)
        if not progress or progress["total"] == 0 or progress["answered"] == 0:
            continue
        total_correct += progress["correct"]
        total_all += progress["total"]
        included.append({"levelId": level.id, "code": level.code, "name": level.name, **progress})

    percent = round((total_correct / total_all) * 100) if total_all else 0
    return {"correct": total_correct, "total": total_all, "percent": percent, "passed": percent >= settings.pass_threshold_percent, "levels": included}


async def add_activity_time(db: AsyncSession, user_id: str, course_id: str | None, lesson_id: str, activity_type: str, seconds: int) -> None:
    """Accumulates an already-capped delta into TODAY's row (§ time tracking,
    2026-08-29; day granularity § streak mode, 2026-08-29) — upserts by
    (userId, lessonId, activityType, today), same "increment on report"
    contract as attemptNumber counting in submit_answer above, not an
    ever-growing event log. All-time totals (get_total_time_seconds) are
    unaffected by this — summing across days gives the exact same number
    summing one running total used to."""
    today = utcnow().date()
    existing = (
        await db.execute(
            select(ActivityTime).where(
                ActivityTime.userId == user_id,
                ActivityTime.lessonId == lesson_id,
                ActivityTime.activityType == activity_type,
                ActivityTime.activityDate == today,
            )
        )
    ).scalar_one_or_none()
    if existing:
        existing.seconds += seconds
    else:
        db.add(ActivityTime(userId=user_id, courseId=course_id, lessonId=lesson_id, activityType=activity_type, activityDate=today, seconds=seconds))
    await db.commit()


async def get_total_time_seconds(db: AsyncSession, user_id: str, language_id: str) -> int:
    """Sums every ActivityTime row that belongs to this language's own
    courses (Course.levelId -> Level.languageId, same chain progress uses),
    plus legacy (pre-Language/Level) lesson time when this language is
    German by name — the same convention the Главное lesson list already
    uses for showing those same legacy lessons only under Немецкий, so a
    legacy lesson's time is attributed exactly where its content already
    visibly lives, not to a new/separate bucket."""
    language = await db.get(Language, language_id)
    if not language:
        return 0
    course_ids = (await db.execute(select(Course.id).join(Level, Level.id == Course.levelId).where(Level.languageId == language_id))).scalars().all()

    conditions = []
    if course_ids:
        conditions.append(ActivityTime.courseId.in_(course_ids))
    if language.name.strip().lower() == "немецкий":
        conditions.append(ActivityTime.courseId.is_(None))
    if not conditions:
        return 0

    total = (await db.execute(select(func.sum(ActivityTime.seconds)).where(ActivityTime.userId == user_id, or_(*conditions)))).scalar_one()
    return total or 0


async def record_daily_activity(db: AsyncSession, user_id: str, activity_type: str) -> None:
    """Marks today as having a qualifying activity of this type (§ streak
    mode, 2026-08-29) — idempotent: completing three lessons today still
    leaves exactly one row, since a streak only cares whether the day had
    activity at all. Deliberately global, not language-scoped — a streak
    rewards studying at all, regardless of which language, same reasoning
    as get_week_activity_summary below."""
    today = utcnow().date()
    existing = (
        await db.execute(
            select(DailyActivity).where(DailyActivity.userId == user_id, DailyActivity.activityType == activity_type, DailyActivity.activityDate == today)
        )
    ).scalar_one_or_none()
    if existing:
        return
    db.add(DailyActivity(userId=user_id, activityType=activity_type, activityDate=today))
    await db.commit()


async def get_streak_days(db: AsyncSession, user_id: str) -> int:
    """Consecutive calendar days, ending today or yesterday, with at least
    one DailyActivity row of any type (§ streak mode, 2026-08-29) — "ending
    yesterday" gives today until it's over before breaking the streak,
    same grace every habit-streak counter gives (a day isn't missed until
    it's actually finished)."""
    dates = set((await db.execute(select(DailyActivity.activityDate).where(DailyActivity.userId == user_id).distinct())).scalars().all())
    if not dates:
        return 0
    today = utcnow().date()
    cursor = today if today in dates else today - timedelta(days=1)
    streak = 0
    while cursor in dates:
        streak += 1
        cursor -= timedelta(days=1)
    return streak


async def get_week_activity_summary(db: AsyncSession, user_id: str) -> dict:
    """The current Monday-Sunday week's per-day activity (§ streak mode,
    2026-08-29), plus the same-day-of-week average and a today-vs-yesterday
    time comparison the profile's "Активность за неделю" card needs.
    Deliberately global (every language summed together), same reasoning as
    record_daily_activity/get_streak_days: a study streak/weekly total isn't
    "for German" or "for English", it's for studying at all — switching the
    profile's selected progress language must never change these numbers."""
    today = utcnow().date()
    monday = today - timedelta(days=today.weekday())
    week_dates = [monday + timedelta(days=i) for i in range(7)]

    active_dates = set(
        (
            await db.execute(
                select(DailyActivity.activityDate).where(
                    DailyActivity.userId == user_id, DailyActivity.activityDate >= monday, DailyActivity.activityDate <= week_dates[-1]
                )
            )
        )
        .scalars()
        .all()
    )

    rows = (
        await db.execute(
            select(ActivityTime.activityDate, func.sum(ActivityTime.seconds))
            .where(ActivityTime.userId == user_id, ActivityTime.activityDate >= monday, ActivityTime.activityDate <= week_dates[-1])
            .group_by(ActivityTime.activityDate)
        )
    ).all()
    seconds_by_date = {d: s for d, s in rows}

    days = [{"date": d.isoformat(), "active": d in active_dates, "seconds": seconds_by_date.get(d, 0)} for d in week_dates]
    avg_seconds_per_day = round(sum(day["seconds"] for day in days) / 7)

    yesterday = today - timedelta(days=1)
    today_seconds = seconds_by_date.get(today, 0)
    if yesterday >= monday:
        yesterday_seconds = seconds_by_date.get(yesterday, 0)
    else:
        # Today is Monday, so yesterday (Sunday) falls in last week — outside
        # week_dates, needs its own lookup.
        yesterday_seconds = (
            await db.execute(select(func.sum(ActivityTime.seconds)).where(ActivityTime.userId == user_id, ActivityTime.activityDate == yesterday))
        ).scalar_one() or 0

    percent_change = None if yesterday_seconds == 0 else round(((today_seconds - yesterday_seconds) / yesterday_seconds) * 100)

    return {
        "days": days,
        "avgSecondsPerDay": avg_seconds_per_day,
        "todaySeconds": today_seconds,
        "yesterdaySeconds": yesterday_seconds,
        "percentChangeVsYesterday": percent_change,
    }


async def get_topic_progress(db: AsyncSession, user_id: str, topic_id: str) -> dict:
    """Cross-lesson knowledge stat (§ approved rule 8/9): the learner's
    latest answer to every Question tagged with this Topic, wherever it was
    placed. This is a statistic about topic mastery, not a claim that the
    topic itself is "complete" — deliberately reuses the global
    `_weighted_progress`, which is exactly this semantics already."""
    question_ids = (await db.execute(select(Question.id).where(Question.topicId == topic_id))).scalars().all()
    return await _weighted_progress(db, user_id, list(question_ids))

from collections import defaultdict

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.answer_log import AnswerLog
from app.models.course import Course
from app.models.course_lesson import CourseLesson
from app.models.lesson_block import LessonBlock
from app.models.lesson_state import LessonAttempt
from app.models.lesson_question import LessonQuestion
from app.models.level import Level
from app.models.material import Material
from app.models.material_block import MaterialBlock
from app.models.question import Question
from app.models.question_placement import QuestionPlacement
from app.utils import to_iso_z


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
    placement_rows = (await db.execute(select(QuestionPlacement.id, QuestionPlacement.questionId).where(or_(*conditions)))).all()

    placement_ids_by_question: dict[str, list[str]] = defaultdict(list)
    for placement_id, question_id in placement_rows:
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
    since they're not reusable to begin with)."""
    total = len(quiz_question_ids) + len(placement_ids_by_question)
    if total == 0:
        return {"correct": 0, "total": 0, "answered": 0, "percent": 0, "passed": False}

    placement_to_question = {pid: qid for qid, pids in placement_ids_by_question.items() for pid in pids}
    conditions = []
    if placement_to_question:
        conditions.append(AnswerLog.placementId.in_(list(placement_to_question)))
    if quiz_question_ids:
        conditions.append(and_(AnswerLog.questionId.in_(quiz_question_ids), AnswerLog.placementId.is_(None)))

    latest_by_question: dict[str, bool] = {}
    if conditions:
        result = await db.execute(
            select(AnswerLog).where(AnswerLog.userId == user_id, or_(*conditions)).order_by(AnswerLog.createdAt.asc())
        )
        for log in result.scalars().all():
            if log.placementId in placement_to_question:
                latest_by_question[placement_to_question[log.placementId]] = log.correct
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


async def get_topic_progress(db: AsyncSession, user_id: str, topic_id: str) -> dict:
    """Cross-lesson knowledge stat (§ approved rule 8/9): the learner's
    latest answer to every Question tagged with this Topic, wherever it was
    placed. This is a statistic about topic mastery, not a claim that the
    topic itself is "complete" — deliberately reuses the global
    `_weighted_progress`, which is exactly this semantics already."""
    question_ids = (await db.execute(select(Question.id).where(Question.topicId == topic_id))).scalars().all()
    return await _weighted_progress(db, user_id, list(question_ids))

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.answer_log import AnswerLog
from app.models.course import Course
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


async def _question_ids_for_material_blocks(db: AsyncSession, material_block_ids: list[str]) -> set[str]:
    if not material_block_ids:
        return set()
    result = await db.execute(select(QuestionPlacement.questionId).where(QuestionPlacement.materialBlockId.in_(material_block_ids)))
    return set(result.scalars().all())


async def _question_ids_for_lesson_blocks(db: AsyncSession, lesson_block_ids: list[str]) -> set[str]:
    if not lesson_block_ids:
        return set()
    result = await db.execute(select(QuestionPlacement.questionId).where(QuestionPlacement.lessonBlockId.in_(lesson_block_ids)))
    return set(result.scalars().all())


async def _question_ids_for_lesson(db: AsyncSession, lesson_id: str) -> list[str]:
    material_ids = (await db.execute(select(Material.id).where(Material.lessonId == lesson_id))).scalars().all()
    material_block_ids = (
        (await db.execute(select(MaterialBlock.id).where(MaterialBlock.materialId.in_(material_ids)))).scalars().all() if material_ids else []
    )
    lesson_block_ids = (await db.execute(select(LessonBlock.id).where(LessonBlock.lessonId == lesson_id))).scalars().all()

    q_ids = await _question_ids_for_material_blocks(db, material_block_ids)
    q_ids |= await _question_ids_for_lesson_blocks(db, lesson_block_ids)
    # Legacy pool questions have neither a MaterialBlock nor a LessonBlock —
    # the backfill recorded them via legacyLessonId directly instead.
    legacy_ids = (await db.execute(select(QuestionPlacement.questionId).where(QuestionPlacement.legacyLessonId == lesson_id))).scalars().all()
    q_ids |= set(legacy_ids)
    # Old quiz questions (minitest/practice/review) — real LessonQuestion.id
    # values, counted directly since new ones never get a QuestionPlacement.
    quiz_ids = (await db.execute(select(LessonQuestion.id).where(LessonQuestion.lessonId == lesson_id))).scalars().all()
    q_ids |= set(quiz_ids)
    return list(q_ids)


async def _question_ids_for_courses(db: AsyncSession, course_ids: list[str]) -> list[str]:
    if not course_ids:
        return []
    material_ids = (await db.execute(select(Material.id).where(Material.courseId.in_(course_ids)))).scalars().all()
    material_block_ids = (
        (await db.execute(select(MaterialBlock.id).where(MaterialBlock.materialId.in_(material_ids)))).scalars().all() if material_ids else []
    )
    lesson_block_ids = (await db.execute(select(LessonBlock.id).where(LessonBlock.courseId.in_(course_ids)))).scalars().all()

    q_ids = await _question_ids_for_material_blocks(db, material_block_ids)
    q_ids |= await _question_ids_for_lesson_blocks(db, lesson_block_ids)
    quiz_ids = (await db.execute(select(LessonQuestion.id).where(LessonQuestion.courseId.in_(course_ids)))).scalars().all()
    q_ids |= set(quiz_ids)
    return list(q_ids)


async def _weighted_progress(db: AsyncSession, user_id: str, question_ids: list[str]) -> dict:
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


async def get_lesson_progress_from_answers(db: AsyncSession, lesson_id: str, user_id: str) -> dict:
    question_ids = await _question_ids_for_lesson(db, lesson_id)
    return await _weighted_progress(db, user_id, question_ids)


async def get_level_progress(db: AsyncSession, user_id: str, level_id: str) -> dict | None:
    level = await db.get(Level, level_id)
    if not level:
        return None
    course_ids = (await db.execute(select(Course.id).where(Course.levelId == level_id))).scalars().all()
    question_ids = await _question_ids_for_courses(db, course_ids)
    return await _weighted_progress(db, user_id, question_ids)


async def get_overall_progress(db: AsyncSession, user_id: str) -> dict:
    """Only levels the user has actually started count (§22: "не учитывай
    будущие уровни, которые пользователь ещё не проходил") — a level with
    zero AnswerLog rows for the user is skipped entirely rather than
    dragging the average down with an implicit 0%."""
    levels = (await db.execute(select(Level))).scalars().all()
    total_correct = 0
    total_all = 0
    included = []
    for level in levels:
        course_ids = (await db.execute(select(Course.id).where(Course.levelId == level.id))).scalars().all()
        question_ids = await _question_ids_for_courses(db, course_ids)
        if not question_ids:
            continue
        touched = (
            await db.execute(
                select(func.count()).select_from(AnswerLog).where(AnswerLog.userId == user_id, AnswerLog.questionId.in_(question_ids))
            )
        ).scalar_one()
        if touched == 0:
            continue
        progress = await _weighted_progress(db, user_id, question_ids)
        total_correct += progress["correct"]
        total_all += progress["total"]
        included.append({"levelId": level.id, "code": level.code, "name": level.name, **progress})

    percent = round((total_correct / total_all) * 100) if total_all else 0
    return {"correct": total_correct, "total": total_all, "percent": percent, "passed": percent >= settings.pass_threshold_percent, "levels": included}

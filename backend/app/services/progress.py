from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.lesson_state import LessonAttempt
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

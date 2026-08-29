import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base
from app.utils import utcnow


class ActivityTime(Base):
    """Accumulated, already-capped seconds a user has spent on one activity
    type within one lesson (§ time tracking, 2026-08-29) — one row per
    (user, lesson, activityType), incremented on every report from the
    client rather than logged as an ever-growing event stream, since nothing
    today needs anything finer than "total seconds so far".

    `activityType` mirrors the frontend's Stage enum names minus "complete"
    (vocabulary/material/video/minitest/audio/practice/review) — no new
    taxonomy, just the stages that already exist. `courseId` is null for a
    legacy (file-based) lesson, same loose-reference convention AnswerLog
    already uses for questionId; `lessonId` alone is enough to look up a
    CourseLesson or trust as a legacy id, so it (not courseId) anchors the
    uniqueness constraint.

    Per-unit caps (2 min/material section, 10s/word, 60s/exercise, 90s/
    matching exercise) are enforced by the CLIENT before it ever reports a
    delta — this table only ever receives already-capped, already-summed
    seconds, so no cap logic exists here beyond the defensive per-request
    ceiling in ActivityTimeInput.
    """

    __tablename__ = "ActivityTime"
    __table_args__ = (UniqueConstraint("userId", "lessonId", "activityType", name="ActivityTime_userId_lessonId_activityType_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    courseId: Mapped[str | None] = mapped_column(String, nullable=True)
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    activityType: Mapped[str] = mapped_column(String, nullable=False)
    seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

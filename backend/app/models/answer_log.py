import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.user import User


class AnswerLog(Base):
    """One row per answered question — the real, per-question source of
    truth that lesson/level/overall progress and weak-spot detection are
    computed from. LessonAttempt/LessonState are left untouched and keep
    being written exactly as before for backward compatibility; nothing here
    replaces them, this is purely additive."""

    __tablename__ = "AnswerLog"
    __table_args__ = (
        Index("AnswerLog_userId_questionId_idx", "userId", "questionId"),
        Index("AnswerLog_questionId_idx", "questionId"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    # Loose reference, no FK (2026-08-26 — extended to cover quiz answers
    # too): either a Question.id (reusable pool question, attached to a
    # MaterialBlock) or a LessonQuestion.id (old quiz system — minitest/
    # practice/review). The two id spaces are disjoint UUIDs, so this is
    # safe; see submit_answer() for the validation that accepts either.
    questionId: Mapped[str] = mapped_column(String, nullable=False)
    # Which QuestionPlacement the user actually answered it through —
    # nullable since a question can in principle be answered standalone (a
    # future "review your weak spots" flow not tied to a specific lesson
    # placement). Loose reference, no FK — placements can be deleted/moved
    # independently of the historical log.
    placementId: Mapped[str | None] = mapped_column(String, nullable=True)
    answerData: Mapped[dict | list] = mapped_column(JSONB, nullable=False)
    correct: Mapped[bool] = mapped_column(Boolean, nullable=False)
    attemptNumber: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")

    user: Mapped["User"] = relationship(back_populates="answerLogs")

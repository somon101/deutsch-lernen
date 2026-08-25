import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import ARRAY, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.user import User


class LessonState(Base):
    """Live 'where the user is inside a lesson' state — server-side and
    user-scoped, so it follows the account across devices/browsers."""

    __tablename__ = "LessonState"
    __table_args__ = (UniqueConstraint("userId", "lessonId", name="LessonState_userId_lessonId_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    lessonId: Mapped[str] = mapped_column(String, nullable=False)

    completedStages: Mapped[list[str]] = mapped_column(ARRAY(String), nullable=False, default=list)
    vocabIndex: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    miniTestCorrect: Mapped[int | None] = mapped_column(Integer, nullable=True)
    miniTestTotal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    miniTestAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    practiceCorrect: Mapped[int | None] = mapped_column(Integer, nullable=True)
    practiceTotal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    practiceAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    reviewCorrect: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reviewTotal: Mapped[int | None] = mapped_column(Integer, nullable=True)
    reviewAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)

    startedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow)
    completedAt: Mapped[datetime | None] = mapped_column(DateTime(), nullable=True)
    # No DB-level default (same situation as User.updatedAt — confirmed via
    # information_schema before writing this) — must be set client-side on
    # every insert and update.
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    user: Mapped["User"] = relationship()


class LessonAttempt(Base):
    """One row per completed pass through a lesson. Best/last/attempt-count
    are always derived by querying this table (see services/progress.py),
    never stored redundantly — append-only, never updated or deleted."""

    __tablename__ = "LessonAttempt"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    userId: Mapped[str] = mapped_column(String, ForeignKey("User.id", ondelete="CASCADE"), nullable=False)
    lessonId: Mapped[str] = mapped_column(String, nullable=False)

    miniTestCorrect: Mapped[int] = mapped_column(Integer, nullable=False)
    miniTestTotal: Mapped[int] = mapped_column(Integer, nullable=False)
    practiceCorrect: Mapped[int] = mapped_column(Integer, nullable=False)
    practiceTotal: Mapped[int] = mapped_column(Integer, nullable=False)
    reviewCorrect: Mapped[int] = mapped_column(Integer, nullable=False)
    reviewTotal: Mapped[int] = mapped_column(Integer, nullable=False)
    score: Mapped[int] = mapped_column(Integer, nullable=False)

    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, server_default="now()")

    user: Mapped["User"] = relationship()

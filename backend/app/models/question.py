import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import ARRAY, DateTime, ForeignKey, Index, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.question_placement import QuestionPlacement
    from app.models.topic import Topic


class Question(Base):
    """A standalone, reusable question — a stable question_id. Unlike
    LessonQuestion (left untouched, still fully working), a Question isn't
    owned by exactly one lesson+block: QuestionPlacement rows say where it's
    used, and one Question can have several, which is what makes reuse a
    real reference instead of a copy. The existing 109 LessonQuestion rows
    are copied into this shape by the migration's backfill step, not
    deleted."""

    __tablename__ = "Question"
    __table_args__ = (Index("Question_topicId_idx", "topicId"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    # "choice" | "truefalse" | "cloze" | "scramble" | "match" — same 5 kinds
    # LessonQuestion already uses.
    kind: Mapped[str] = mapped_column(String, nullable=False, default="choice")
    prompt: Mapped[str] = mapped_column(String, nullable=False)
    options: Mapped[list[str]] = mapped_column(ARRAY(String), nullable=True)
    correctAnswer: Mapped[str] = mapped_column(String, nullable=False)
    # Only used by kind="match": [{left, right}, ...] — same convention as
    # LessonQuestion.data.
    data: Mapped[dict | list | None] = mapped_column(JSONB, nullable=True)
    topicId: Mapped[str | None] = mapped_column(String, ForeignKey("Topic.id", ondelete="SET NULL"), nullable=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    topic: Mapped["Topic | None"] = relationship(back_populates="questions")
    placements: Mapped[list["QuestionPlacement"]] = relationship(back_populates="question", cascade="all, delete-orphan")

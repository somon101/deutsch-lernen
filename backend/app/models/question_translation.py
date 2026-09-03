import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import ARRAY, DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.utils import utcnow

if TYPE_CHECKING:
    from app.models.question import Question


class QuestionTranslation(Base):
    """One instructional-language variant of a Question's text (§ course
    content language, 2026-09-04). Mirrors Question's own text-bearing
    columns (prompt/options/correctAnswer/data), but every column here is
    nullable — a given `kind` only ever fills in the subset it actually
    uses (e.g. "match" only needs `data`'s pairs, "auto_translate" needs
    none of them, config-only kinds have no translation row at all). Same
    locale-as-data pattern as CourseTranslation; see that model's docstring
    for why."""

    __tablename__ = "QuestionTranslation"
    __table_args__ = (UniqueConstraint("questionId", "locale", name="QuestionTranslation_questionId_locale_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    questionId: Mapped[str] = mapped_column(String, ForeignKey("Question.id", ondelete="CASCADE"), nullable=False)
    locale: Mapped[str] = mapped_column(String, nullable=False)
    prompt: Mapped[str | None] = mapped_column(String, nullable=True)
    options: Mapped[list[str] | None] = mapped_column(ARRAY(String), nullable=True)
    correctAnswer: Mapped[str | None] = mapped_column(String, nullable=True)
    data: Mapped[dict | list | None] = mapped_column(JSONB, nullable=True)
    createdAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, server_default="now()")
    updatedAt: Mapped[datetime] = mapped_column(DateTime(), nullable=False, default=utcnow, onupdate=utcnow)

    question: Mapped["Question"] = relationship()

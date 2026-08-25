import uuid

from sqlalchemy import ARRAY, Index, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class LessonQuestion(Base):
    __tablename__ = "LessonQuestion"
    __table_args__ = (
        Index("LessonQuestion_lessonId_setName_position_idx", "lessonId", "setName", "position"),
        Index("LessonQuestion_blockId_position_idx", "blockId", "position"),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    lessonId: Mapped[str] = mapped_column(String, nullable=False)
    # "minitest" | "practice" | "review" — free-text in the DB, not an enum.
    setName: Mapped[str] = mapped_column(String, nullable=False)
    prompt: Mapped[str] = mapped_column(String, nullable=False)
    options: Mapped[list[str]] = mapped_column(ARRAY(String), nullable=True)
    correctAnswer: Mapped[str] = mapped_column(String, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    courseId: Mapped[str] = mapped_column(String, nullable=False, default="legacy")
    # Loose reference to LessonBlock.id — no real FK/cascade (see
    # models/lesson_block.py's comment).
    blockId: Mapped[str | None] = mapped_column(String, nullable=True)
    # "choice" | "truefalse" | "cloze" | "scramble" | "match" — free-text.
    kind: Mapped[str] = mapped_column(String, nullable=False, default="choice")
    # Only used by kind="match": [{left, right}, ...].
    data: Mapped[dict | list | None] = mapped_column(JSONB, nullable=True)
